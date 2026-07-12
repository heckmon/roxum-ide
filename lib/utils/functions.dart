import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:code_forge/code_forge.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:roxum/utils/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../terminal/terminal.dart';
import '../utils/constants.dart';
import '../utils/languages.dart';

const Set<String> supportedImageExtensions = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.wbmp',
  '.ico',
  '.tif',
  '.tiff',
  '.heic',
  '.heif',
  '.avif',
};

const Set<String> supportedSvgExtensions = {
  '.svg',
  '.svgz',
};

bool isImageFilePath(String filePath) {
  return supportedImageExtensions.contains(
    path.extension(filePath).toLowerCase(),
  );
}

bool isPdfFilePath(String filePath) {
  return path.extension(filePath).toLowerCase() == '.pdf';
}

bool isSvgFilePath(String filePath) {
  return supportedSvgExtensions.contains(
    path.extension(filePath).toLowerCase(),
  );
}

bool isPreviewFilePath(String filePath) {
  return
    isImageFilePath(filePath) ||
    isSvgFilePath(filePath) ||
    isPdfFilePath(filePath);
}

const String _legacyProjectDir = '/data/data/com.roxum/Roxum/Projects';
const String _legacyTemplateDir = '/data/data/com.roxum/Roxum/Templates';
const String _legacyFilesDir = '/data/data/com.roxum/Roxum/Files';
const String sharedStorageMigrationNoticeKey = 'roxum_shared_storage_migration_notice';
const String sharedStorageMigrationDoneKey = 'roxum_shared_storage_migration_done_v1';

Future<void> _copyEntityRecursive(FileSystemEntity source, Directory targetRoot) async {
  if (source is Directory) {
    final target = Directory(path.join(targetRoot.path, path.basename(source.path)));
    if (!target.existsSync()) {
      await target.create(recursive: true);
    }
    await for (final child in source.list(recursive: false, followLinks: false)) {
      await _copyEntityRecursive(child, target);
    }
    return;
  }

  if (source is File) {
    final target = File(path.join(targetRoot.path, path.basename(source.path)));
    await target.parent.create(recursive: true);
    await source.copy(target.path);
  }
}

Future<bool> _migrateDirectoryRoot(String sourcePath, String targetPath) async {
  final source = Directory(sourcePath);
  if (!await source.exists()) {
    return false;
  }

  final target = Directory(targetPath);
  if (!await target.exists()) {
    await target.create(recursive: true);
  }

  final entities = await source.list(followLinks: false).toList();
  for (final entity in entities) {
    final destination = path.join(target.path, path.basename(entity.path));
    if (entity is Directory) {
      await Directory(destination).create(recursive: true);
      await for (final child in entity.list(followLinks: false)) {
        await _copyEntityRecursive(child, Directory(destination));
      }
    } else if (entity is File) {
      await File(destination).parent.create(recursive: true);
      await entity.copy(destination);
    }
  }

  await source.delete(recursive: true);
  return true;
}

Map<String, dynamic>? _normalizeRecentMap(dynamic rawEntry) {
  if (rawEntry is Map && rawEntry['type'] is String && rawEntry['path'] is String) {
    return {
      'type': rawEntry['type'],
      'path': rawEntry['path'],
      'rootDir': rawEntry['rootDir'] ?? rawEntry['path'],
    };
  }

  if (rawEntry is Map && rawEntry.length == 1) {
    final dynamic key = rawEntry.keys.first;
    if (key is String) {
      return {'type': 'file', 'path': key, 'rootDir': rawEntry[key]};
    }
  }

  return null;
}

String _remapLegacyPath(String value) {
  if (value.startsWith(_legacyProjectDir)) {
    return value.replaceFirst(_legacyProjectDir, projectDir);
  }
  if (value.startsWith(_legacyTemplateDir)) {
    return value.replaceFirst(_legacyTemplateDir, templateDir);
  }
  if (value.startsWith(_legacyFilesDir)) {
    return value.replaceFirst(_legacyFilesDir, filesDir);
  }
  return value;
}

Future<void> _remapRecentEntriesToSharedStorage() async {
  final prefs = await SharedPreferences.getInstance();
  final rawRecent = prefs.getString('recent');
  if (rawRecent == null || rawRecent.trim().isEmpty) {
    return;
  }

  try {
    final decoded = jsonDecode(rawRecent);
    if (decoded is! List) return;

    var changed = false;
    final remapped = <dynamic>[];

    for (final rawEntry in decoded) {
      final normalized = _normalizeRecentMap(rawEntry);
      if (normalized == null) {
        continue;
      }

      final nextPath = _remapLegacyPath(normalized['path'] as String);
      final nextRootDir = _remapLegacyPath(normalized['rootDir'] as String);
      if (nextPath != normalized['path'] || nextRootDir != normalized['rootDir']) {
        changed = true;
      }

      remapped.add({
        'type': normalized['type'],
        'path': nextPath,
        'rootDir': nextRootDir,
      });
    }

    if (changed) {
      await prefs.setString('recent', jsonEncode(remapped));
    }
  } catch (_) {}
}

Future<bool> migrateSharedStorageRoots() async {
  var migrated = false;
  migrated = await _migrateDirectoryRoot(_legacyProjectDir, projectDir) || migrated;
  migrated = await _migrateDirectoryRoot(_legacyTemplateDir, templateDir) || migrated;
  migrated = await _migrateDirectoryRoot(_legacyFilesDir, filesDir) || migrated;

  await _remapRecentEntriesToSharedStorage();

  if (migrated) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(sharedStorageMigrationNoticeKey, true);
    await prefs.setBool(sharedStorageMigrationDoneKey, true);
  }

  return migrated;
}

Future<Directory> setupProjectDir() async {
  final target = Directory(projectDir);
  if (!target.existsSync()) {
    await target.create(recursive: true);
  }
  return target;
}

Future<Directory> setupTempDir() async {
  final target = Directory(tempDir);
  if (!target.existsSync()) {
    await target.create(recursive: true);
  }
  return target;
}

Future<Directory> setupFilesDir() async {
  final target = Directory(filesDir);
  if (!target.existsSync()) {
    await target.create(recursive: true);
  }
  final ggufDir = Directory('${target.path}/gguf');
  if (!ggufDir.existsSync()) await ggufDir.create(recursive: true);

  final currentFiles = File('${target.path}/.current_files.json');

  if (!await currentFiles.exists()) {
    await currentFiles.writeAsString(jsonEncode({}));
    return target;
  }

  try {
    final raw = await currentFiles.readAsString();
    if (raw.trim().isEmpty) {
      await currentFiles.writeAsString(jsonEncode({}));
      return target;
    }

    final Map<String, dynamic> data = jsonDecode(raw);
    final Map<String, String> cleaned = {};

    for (final entry in data.entries) {
      final filePath = '${target.path}/${entry.key}';
      if (await File(filePath).exists()) {
        cleaned[entry.key] = entry.value.toString();
      }
    }

    await currentFiles.writeAsString(jsonEncode(cleaned), flush: true);
  } catch (e) {
    await currentFiles.writeAsString(jsonEncode({}), flush: true);
  }

  return target;
}

Future<Directory> setupTemplateDir() async {
  final target = Directory(templateDir);
  if (!target.existsSync()) {
    await target.create(recursive: true);
  }
  return target;
}

Future<File> setTempFile(String extension) async {
  final dir = await setupTemplateDir();

  File target;
  if (extension == 'html') {
    target = File('${dir.path}/index.html');
  } else if (extension == 'css') {
    target = File('${dir.path}/style.css');
  } else if (extension == 'js') {
    target = File('${dir.path}/script.js');
  } else {
    target = File('${dir.path}/tempCode.$extension');
  }

  if (!target.existsSync() || target.readAsStringSync().isEmpty) {
    await target.create(recursive: true);
    await target.writeAsString(
      languages.firstWhere(
        (lang) => lang.extension.contains(path.extension(target.path).replaceFirst(".", "")),
        orElse: () => languages[0],
      ).helloWorld,
    );
  }

  return target;
}

Map<String, String> gitEnvs(String sharedPath) => {
  'PATH': '$binDir:/bin:/usr/bin',
  'HOME': homeDir,
  'GIT_EXEC_PATH': '$binDir/git-core',
  'GIT_SSL_CAINFO': '$certDir/cacert.pem',
  'LD_LIBRARY_PATH': "$sharedPath:$libDir",
  'ROXUM_SHARED_PATH': sharedPath,
};

Future<void> cloneRepo(
  String location,
  String url,
  void Function(double progress) onProgress,
) async {
  final sharedPath = await NativeChannel.getLibraryPath();

  final process = await Process.start(
    '$binDir/git',
    ['clone', '--progress', url],
    workingDirectory: location,
    environment: gitEnvs(sharedPath),
  );

  final progressRegex = RegExp(
    r'(Receiving objects|Resolving deltas|Compressing objects):\s+(\d+)%',
  );

  process.stderr.listen((data) {
    final text = String.fromCharCodes(data);

    final match = progressRegex.firstMatch(text);
    if (match != null) {
      final percent = double.parse(match.group(2)!);
      onProgress(percent / 100);
    }
  });

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw Exception('git clone failed with exit code $exitCode');
  }
}

Future<void> initRepo(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  await Process.run(
    "$binDir/git",
    ["init"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  await Process.run(
    "$binDir/git",
    ["config", "--local", "user.name", "Roxum user"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  await Process.run(
    "$binDir/git",
    ["config", "--local", "user.email", "roxum@local"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  await createGitignoreIfNeeded(workspacePath);
}

Future<void> createGitignoreIfNeeded(String workspacePath) async {
  final gitignoreFile = File('$workspacePath/.gitignore');
  final patterns = _getGitignorePatterns();

  if (await gitignoreFile.exists()) {
    final existingContent = await gitignoreFile.readAsString();
    final existingLines = existingContent
      .split('\n')
      .map((e) => e.trim())
      .toSet();

    final patternsToAdd = <String>[];
    for (final pattern in patterns) {
      final trimmedPattern = pattern.trim();
      if (trimmedPattern.isNotEmpty &&
          !trimmedPattern.startsWith('#') &&
          !existingLines.contains(trimmedPattern)) {
        patternsToAdd.add(pattern);
      }
    }

    if (patternsToAdd.isNotEmpty) {
      await gitignoreFile.writeAsString(
        '$existingContent\n\n# Auto-added by Roxum\n${patternsToAdd.join('\n')}\n',
        mode: FileMode.append,
      );
    }
  } else {
    await gitignoreFile.writeAsString('${patterns.join('\n')}\n');
  }
}

List<String> _getGitignorePatterns() {
  return [
    '# Roxum and Editor files',
    '.vscode/',
    '.idea/',
    '*.swp',
    '*.swo',
    '*~',
    '.DS_Store',
    '',
    '# Language Server Protocol (LSP) cache directories',
    '.ccls-cache/',
    'jdt.ls-java-project',
    '.clangd/',
    '.cache/',
    'compile_commands.json',
    '__pycache__/',
    '*.pyc',
    '.mypy_cache/',
    '.ruff_cache/',
    '.pytest_cache/',
    'pyrightconfig.json',
    '*.jdt.ls/',
    '.settings/',
    '',
    '# Dependencies',
    'node_modules/',
    '.pnpm-store/',
    '.npm/',
    '.yarn/',
    '.venv/',
    'venv/',
    'env/',
    'ENV/',
    '',
    '# Flutter / Dart',
    '.dart_tool/',
    '.packages',
    'pubspec.lock',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
    '.metadata',
    '',
    '# Java / Android',
    'bin/',
    '.classpath',
    '.project',
    '.factorypath',
    '*.class',
    '.gradle/',
    'local.properties',
    '.externalNativeBuild/',
    '.cxx/',
    '',
    '# Node / TypeScript',
    'tsconfig.tsbuildinfo',
    '.eslintcache',
    '*.tsbuildinfo',
    '',
    '# Build outputs',
    'build/',
    'dist/',
    'out/',
    'target/',
    '*.o',
    '*.a',
    '*.so',
    '*.dylib',
    '*.dll',
    '*.exe',
    '*.app',
    '*.apk',
    '*.aab',
    '*.ipa',
    '*.so.*',
    '*.dylib.*',
    '',
    '# Logs and databases',
    '*.log',
    '*.sql',
    '*.sqlite',
    '*.db',
    '',
    '# Environment files',
    '.env',
    '.env.*',
    '',
    '# Temporary files',
    '*.tmp',
    '*.temp',
    '*.bak',
    '*.backup',
    '',
    '# Coverage reports',
    'coverage/',
    '.coverage',
    'htmlcov/',
    '',
    '# Package files',
    '*.tar.gz',
    '*.zip',
    '*.rar',
    '*.7z',
    '',
    '# OS files',
    '*.iml',
    'Thumbs.db',
    'Desktop.ini',
    '.Spotlight-V100',
    '.Trashes',
    '',
    '# Shell configuration',
    '.bashrc',
  ];
}

Future<ProcessResult> getRepoStatus(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["status", "--porcelain=v1", "-uall"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<void> stageChange(String fileName, String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  await Process.run(
    "$binDir/git",
    ["add", fileName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<void> stageAll(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  await Process.run(
    "$binDir/git",
    ["add", "--all"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<void> unstageChange(String fileName, String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final env = gitEnvs(sharedPath);

  final hasHead = await _hasInitialCommit(workspacePath, env);

  final args = hasHead
      ? ["restore", "--staged", fileName]
      : ["reset", fileName];

  await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: env,
  );
}

Future<void> unstageAll(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final env = gitEnvs(sharedPath);

  final hasHead = await _hasInitialCommit(workspacePath, env);

  final args = hasHead ? ["restore", "--staged", "."] : ["reset", "."];

  await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: env,
  );
}

Future<bool> _hasInitialCommit(
  String workspacePath,
  Map<String, String> env,
) async {
  final result = await Process.run(
    "$binDir/git",
    ["rev-parse", "--verify", "HEAD"],
    workingDirectory: workspacePath,
    environment: env,
  );

  return result.exitCode == 0;
}

Future<ProcessResult> gitCommit(
  String workspacePath,
  String message, {
  bool all = false,
  bool amend = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['commit'];
  if (amend) args.add('--amend');
  if (all) args.add('-a');
  args.addAll(['-m', message]);

  final result = await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  return result;
}

Future<List<CommitNode>> getGraph(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["log", "--all", "--pretty=format:%H%x01%P%x01%an%x01%s"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  String? headHash;
  String? upstreamHash;

  final headResult = await Process.run(
    "$binDir/git",
    ["rev-parse", "HEAD"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (headResult.exitCode == 0) {
    headHash = (headResult.stdout as String).trim();
  }

  final upstreamResult = await Process.run(
    "$binDir/git",
    ["rev-parse", "--verify", "@{u}"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (upstreamResult.exitCode == 0) {
    upstreamHash = (upstreamResult.stdout as String).trim();
  }

  final List<CommitNode> commits = [];
  final lines = result.stdout.toString().split('\n');

  for (final line in lines) {
    if (line.trim().isEmpty) continue;

    final parts = line.split('\x01');
    if (parts.length >= 4) {
      final hash = parts[0];
      final parentHashes = parts[1].isEmpty ? <String>[] : parts[1].split(' ');
      final author = parts[2];
      final message = parts[3];

      commits.add(
        CommitNode(
          hash: hash,
          parents: parentHashes,
          author: author,
          message: message,
          isHead: hash == headHash,
          isRemoteHead: upstreamHash != null && hash == upstreamHash,
        ),
      );
    }
  }

  return commits;
}

Future<void> gitRestoreFile(String fileName, String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  await Process.run(
    "$binDir/git",
    ["restore", fileName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

class GitDiffResult {
  final String diffText;
  final List<(int startLine, int endLine)> addedRanges;
  final List<({int afterLine, String content})> removedRanges;

  GitDiffResult({
    required this.diffText,
    required this.addedRanges,
    required this.removedRanges,
  });
}

Future<GitDiffResult> getGitDiff(String fileName, String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["diff", "--function-context", fileName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );

  final diffTextOriginal = result.stdout as String;
  final addedRanges = <(int, int)>[];
  final removedRanges = <({int afterLine, String content})>[];

  final lines = diffTextOriginal.split('\n');
  final filteredLines = lines
    .where(
      (line) =>
        !line.startsWith('diff --git') &&
        !line.startsWith('index ') &&
        !line.startsWith('--- ') &&
        !line.startsWith('+++ '),
    )
    .toList();

  final visibleLines = <String>[];

  int? currentAddedStart;
  int? currentRemovedAfterLine;
  final removedContent = StringBuffer();

  void flushAdded(int endExclusive) {
    if (currentAddedStart == null) return;
    addedRanges.add((currentAddedStart!, endExclusive - 1));
    currentAddedStart = null;
  }

  void flushRemoved() {
    if (currentRemovedAfterLine == null) return;
    removedRanges.add((
      afterLine: currentRemovedAfterLine!,
      content: removedContent.toString(),
    ));
    currentRemovedAfterLine = null;
    removedContent.clear();
  }

  for (final line in filteredLines) {
    final isAdded = line.startsWith('+');
    final isRemoved = line.startsWith('-');

    if (isRemoved) {
      flushAdded(visibleLines.length);
      currentRemovedAfterLine ??= visibleLines.isEmpty
          ? 0
          : visibleLines.length - 1;
      if (removedContent.isNotEmpty) {
        removedContent.write('\n');
      }
      removedContent.write(line.length > 1 ? line.substring(1) : '');
      continue;
    }

    flushRemoved();

    if (isAdded) {
      currentAddedStart ??= visibleLines.length;
      visibleLines.add(line);
      continue;
    }

    flushAdded(visibleLines.length);
    visibleLines.add(line);
  }

  flushAdded(visibleLines.length);
  flushRemoved();

  final diffText = visibleLines.join('\n');

  return GitDiffResult(
    diffText: diffText,
    addedRanges: addedRanges,
    removedRanges: removedRanges,
  );
}

Future<ProcessResult> gitPush(
  String workspacePath, {
  String? remote,
  String? branch,
  bool setUpstream = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['push'];
  if (setUpstream) args.add('-u');
  if (remote != null) args.add(remote);
  if (branch != null) args.add(branch);
  final result = await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return result;
}

Future<ProcessResult> gitPull(
  String workspacePath, {
  String? remote,
  String? branch,
  bool rebase = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['pull'];
  if (rebase) args.add('--rebase');
  if (remote != null) args.add(remote);
  if (branch != null) args.add(branch);
  final result = await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return result;
}

Future<ProcessResult> gitFetch(
  String workspacePath, {
  String? remote,
  bool all = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['fetch'];
  if (all) args.add('--all');
  if (remote != null && !all) args.add(remote);
  final result = await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return result;
}

Future<ProcessResult> gitSync(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final pullResult = await Process.run(
    "$binDir/git",
    ["pull", "--rebase"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (pullResult.exitCode != 0) return pullResult;

  final pushResult = await Process.run(
    "$binDir/git",
    ["push"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return pushResult;
}

Future<List<String>> gitListBranches(
  String workspacePath, {
  bool remote = false,
  bool all = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['branch'];
  if (all) {
    args.add('-a');
  } else if (remote) {
    args.add('-r');
  }
  final result = await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return [];
  return (result.stdout as String)
      .split('\n')
      .map((b) => b.replaceFirst('*', '').trim())
      .where((b) => b.isNotEmpty)
      .toList();
}

Future<String?> gitCurrentBranch(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["branch", "--show-current"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return null;
  final branch = (result.stdout as String).trim();

  if (branch.isEmpty) {
    final descResult = await Process.run(
      "$binDir/git",
      ["describe", "--tags", "--exact-match", "HEAD"],
      workingDirectory: workspacePath,
      environment: gitEnvs(sharedPath),
    );
    if (descResult.exitCode == 0) {
      return (descResult.stdout as String).trim();
    }

    final refResult = await Process.run(
      "$binDir/git",
      ["rev-parse", "--short", "HEAD"],
      workingDirectory: workspacePath,
      environment: gitEnvs(sharedPath),
    );
    if (refResult.exitCode == 0) {
      return (refResult.stdout as String).trim();
    }
    return "HEAD";
  }

  return branch;
}

Future<ProcessResult> gitCreateBranch(
  String workspacePath,
  String branchName, {
  String? fromRef,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['checkout', '-b', branchName];
  if (fromRef != null) args.add(fromRef);
  return await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitCheckoutBranch(
  String workspacePath,
  String branchName,
) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["checkout", branchName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitRenameBranch(
  String workspacePath,
  String oldName,
  String newName,
) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["branch", "-m", oldName, newName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitDeleteBranch(
  String workspacePath,
  String branchName, {
  bool force = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["branch", force ? "-D" : "-d", branchName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitDeleteRemoteBranch(
  String workspacePath,
  String branchName, {
  String remote = 'origin',
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["push", remote, "--delete", branchName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitMergeBranch(
  String workspacePath,
  String branchName, {
  bool noFf = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['merge'];
  if (noFf) args.add('--no-ff');
  args.add(branchName);
  return await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitRebaseBranch(
  String workspacePath,
  String branchName,
) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["rebase", branchName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitPublishBranch(
  String workspacePath,
  String branchName, {
  String remote = 'origin',
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["push", "-u", remote, branchName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<List<Map<String, String>>> gitListStashes(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["stash", "list", "--format=%gd%x01%s"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return [];
  final lines = (result.stdout as String)
      .split('\n')
      .where((l) => l.isNotEmpty);
  return lines.map((line) {
    final parts = line.split('\x01');
    return {
      'ref': parts.isNotEmpty ? parts[0] : '',
      'message': parts.length > 1 ? parts[1] : '',
    };
  }).toList();
}

Future<ProcessResult> gitStash(
  String workspacePath, {
  String? message,
  bool includeUntracked = false,
  bool stagedOnly = false,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['stash', 'push'];
  if (includeUntracked) args.add('--include-untracked');
  if (stagedOnly) args.add('--staged');
  if (message != null && message.isNotEmpty) {
    args.addAll(['-m', message]);
  }
  return await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitStashApply(
  String workspacePath, {
  String? stashRef,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['stash', 'apply'];
  if (stashRef != null) args.add(stashRef);
  return await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitStashPop(
  String workspacePath, {
  String? stashRef,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['stash', 'pop'];
  if (stashRef != null) args.add(stashRef);
  return await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitStashDrop(
  String workspacePath, {
  String? stashRef,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['stash', 'drop'];
  if (stashRef != null) args.add(stashRef);
  return await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitStashClear(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["stash", "clear"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<String> gitStashShow(String workspacePath, String stashRef) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["stash", "show", "-p", stashRef],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return result.stdout as String;
}

Future<List<String>> gitListTags(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["tag", "-l"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return [];
  return (result.stdout as String)
    .split('\n')
    .where((t) => t.isNotEmpty)
    .toList();
}

Future<ProcessResult> gitCreateTag(
  String workspacePath,
  String tagName, {
  String? message,
  String? ref,
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final args = <String>['tag'];
  if (message != null && message.isNotEmpty) {
    args.addAll(['-a', tagName, '-m', message]);
  } else {
    args.add(tagName);
  }
  if (ref != null) args.add(ref);
  return await Process.run(
    "$binDir/git",
    args,
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitDeleteTag(String workspacePath, String tagName) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["tag", "-d", tagName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitDeleteRemoteTag(
  String workspacePath,
  String tagName, {
  String remote = 'origin',
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["push", remote, "--delete", "refs/tags/$tagName"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<ProcessResult> gitPushTag(
  String workspacePath,
  String tagName, {
  String remote = 'origin',
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["push", remote, tagName],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<List<String>> gitListRemotes(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["remote"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return [];
  return (result.stdout as String)
      .split('\n')
      .where((r) => r.isNotEmpty)
      .toList();
}

Future<String?> gitGetRemoteUrl(
  String workspacePath, {
  String remote = 'origin',
}) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["remote", "get-url", remote],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return null;
  return (result.stdout as String).trim();
}

Future<ProcessResult> gitAddRemote(
  String workspacePath,
  String name,
  String url,
) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  return await Process.run(
    "$binDir/git",
    ["remote", "add", name, url],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
}

Future<bool> hasRemote(String workspacePath) async {
  final remotes = await gitListRemotes(workspacePath);
  return remotes.isNotEmpty;
}

Future<int> getUnpushedCommitCount(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["rev-list", "--count", "@{u}..HEAD"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return 0;
  return int.tryParse((result.stdout as String).trim()) ?? 0;
}

Future<int> getUnpulledCommitCount(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  await gitFetch(workspacePath);
  final result = await Process.run(
    "$binDir/git",
    ["rev-list", "--count", "HEAD..@{u}"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  if (result.exitCode != 0) return 0;
  return int.tryParse((result.stdout as String).trim()) ?? 0;
}

Future<bool> hasUpstream(String workspacePath) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final result = await Process.run(
    "$binDir/git",
    ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
    workingDirectory: workspacePath,
    environment: gitEnvs(sharedPath),
  );
  return result.exitCode == 0;
}

Future<String> gitHubSignIn() async {
  final secureStorage = const FlutterSecureStorage();
  const clientId = "Ov23liYO7I8tsbftzDKc";
  const backEndHandler = "https://gihub-auth-handler.vercel.app";

  final authUrl = Uri.https('github.com', '/login/oauth/authorize', {
    'client_id': clientId,
    'scope': 'repo read:user',
    'redirect_uri': 'roxum://oauth',
  });

  try {
    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: 'roxum',
      options: const FlutterWebAuth2Options(),
    );

    final code = Uri.parse(result).queryParameters['code'];

    if (code == null || code.isEmpty) {
      return 'No authorization code received';
    }

    final response = await http
      .post(
        Uri.parse('$backEndHandler/github/oauth'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'code': code}),
      )
      .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          return http.Response('Backend connection timeout', 408);
        },
      );

    if (response.statusCode != 200) {
      return ('${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final accessToken = data['access_token'];

    if (accessToken == null || accessToken.isEmpty) {
      return 'No access token in backend response';
    }

    await secureStorage.write(key: 'github_access_token', value: accessToken);

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      await _configureGitIdentity(jsonDecode(response.body));
      await _configureGitCredentialHelper();
      await _approveGithubCredentials(accessToken);
    } catch (e) {
      debugPrint('Failed to load user info: $e');
    }

    return "success";
  } catch (e) {
    final err = e.toString();
    if (err.contains('PlatformException(CANCELED') ||
        err.toLowerCase().contains('user canceled')) {
      return 'Sign in was canceled';
    }
    return e.toString();
  }
}

String resolveGitEmail(Map<String, dynamic> user) {
  final email = user['email'];
  final login = user['login'];
  if (email != null && email.toString().isNotEmpty) {
    return email;
  }
  return '$login@users.noreply.github.com';
}

Future<void> _configureGitIdentity(Map<String, dynamic> user) async {
  final sharedPath = await NativeChannel.getLibraryPath();
  final name = user['name'] ?? user['login'];
  final email = resolveGitEmail(user);

  await Process.run("$binDir/git", [
    "config",
    "--global",
    "user.name",
    name,
  ], environment: gitEnvs(sharedPath));

  await Process.run("$binDir/git", [
    "config",
    "--global",
    "user.email",
    email,
  ], environment: gitEnvs(sharedPath));
}

Future<void> _configureGitCredentialHelper() async {
  final sharedPath = await NativeChannel.getLibraryPath();

  await Process.run("$binDir/git", [
    "config",
    "--global",
    "credential.helper",
    "store",
  ], environment: gitEnvs(sharedPath));
}

Future<void> _approveGithubCredentials(String token) async {
  final sharedPath = await NativeChannel.getLibraryPath();

  final process = await Process.start("$binDir/git", [
    "credential-store",
    "store",
  ], environment: gitEnvs(sharedPath));

  process.stdin.write(
    "protocol=https\n"
    "host=github.com\n"
    "username=oauth2\n"
    "password=$token\n\n",
  );

  await process.stdin.close();
  await process.exitCode;
}

Future<void> clearGitCredentials() async {
  final sharedPath = await NativeChannel.getLibraryPath();

  await Process.run(
    "$binDir/git",
    ["credential", "reject"],
    environment: gitEnvs(sharedPath),
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  final home = Directory(homeDir);
  final credsFile = File('${home.path}/.git-credentials');
  if (credsFile.existsSync()) {
    credsFile.deleteSync();
  }
}

String extractRepoName(String url) {
  url = url.replaceFirst(RegExp(r'^(https?://|git@)'), '');
  final parts = url.split(RegExp(r'[:/]'));
  if (parts.isEmpty) return '';
  String repoName = parts.last;
  if (repoName.endsWith('.git')) {
    repoName = repoName.substring(0, repoName.length - 4);
  }

  return repoName;
}

Future<File?> pickFile() async {
  final result = await FilePicker.pickFiles(
    allowMultiple: false,
    type: FileType.custom,
  );

  if (result == null || result.files.isEmpty) return null;

  final picked = result.files.first;

  if (picked.path == null && picked.bytes == null) {
    return null;
  }

  final projectDir = await setupFilesDir();
  final currentFiles = File('${projectDir.path}/.current_files.json');

  Map<String, String> fileMap = {};

  if (currentFiles.existsSync() && currentFiles.lengthSync() > 0) {
    fileMap = Map<String, String>.from(
      jsonDecode(currentFiles.readAsStringSync()),
    );
  }

  if (picked.identifier != null) {
    fileMap[picked.name] = picked.identifier!;
  }

  await currentFiles.writeAsString(jsonEncode(fileMap), flush: true);

  final targetFile = File('${projectDir.path}/${picked.name}');

  if (picked.bytes != null) {
    await targetFile.writeAsBytes(picked.bytes!, flush: true);
  } else {
    final tempFile = File(picked.path!);
    await tempFile.copy(targetFile.path);
  }

  return targetFile;
}

Future<Directory?> pickDir() async {
  const MethodChannel saf = MethodChannel('roxum/saf');
  final String? treeUri = await saf.invokeMethod<String>('pickSafDir');

  if (treeUri == null) return null;

  final projectPath = await saf.invokeMethod<String>('cloneSafDir', {
    'uri': treeUri,
  });
  if (projectPath == null) return null;
  return Directory(projectPath);
}

Future<String?> selectDir({
  String? dialogeTitle,
  String? initialDirectory,
  String? fileName,
  Uint8List? bytes,
}) async {
  return await FilePicker.saveFile(
    dialogTitle: dialogeTitle,
    fileName: fileName,
    initialDirectory: initialDirectory,
    bytes: bytes,
  );
}

Future<File?> createFile(
  String filename,
  String dirPath,
  BuildContext context,
) async {
  final fileDir = Directory(dirPath);
  if (!fileDir.existsSync()) {
    await fileDir.create(recursive: true);
  }
  final file = File("$dirPath/$filename");
  if (!file.existsSync()) {
    try {
      await file.create(recursive: true);
      return file;
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(e.toString()),
            title: const Text(
              "Failed to open file",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w300),
            ),
            backgroundColor: const Color(0xff2b2b2b),
            icon: const Icon(Icons.error_outline),
            iconColor: Colors.red[600],
          ),
        );
      }
    }
  }
  return file;
}

Future<HttpServer?> startServer() async {
  try {
    final server = await HttpServer.bind('127.0.0.1', 49258);
    return server;
  } catch (e) {
    return null;
  }
}

Future<String> getRecent() async {
  final prefs = await SharedPreferences.getInstance();
  final recent = prefs.getString('recent');
  return recent ?? '[]';
}

const String copilotEnabledPrefKey = 'isCopilotEnabled';
const String copilotSignedPrefKey = 'isSignedCopilot';

Future<bool> ensureCopilotEnabledPrefInitialized() async {
  final prefs = await SharedPreferences.getInstance();
  final currentValue = prefs.getBool(copilotEnabledPrefKey);
  if (currentValue == null) {
    await prefs.setBool(copilotEnabledPrefKey, false);
    return false;
  }
  return currentValue;
}

Future<bool> ensureCopilotSignedPrefInitialized() async {
  final prefs = await SharedPreferences.getInstance();
  final currentValue = prefs.getBool(copilotSignedPrefKey);
  if (currentValue == null) {
    await prefs.setBool(copilotSignedPrefKey, false);
    return false;
  }
  return currentValue;
}

Future<bool> isCopilotSignedPref() async {
  final prefs = await SharedPreferences.getInstance();
  final currentValue = prefs.getBool(copilotSignedPrefKey);
  if (currentValue == null) {
    await prefs.setBool(copilotSignedPrefKey, false);
    return false;
  }
  return currentValue;
}

Future<void> setCopilotSignedPref(bool isSignedIn) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(copilotSignedPrefKey, isSignedIn);
}

Future<bool> isCopilotEnabledPref() async {
  final prefs = await SharedPreferences.getInstance();
  final currentValue = prefs.getBool(copilotEnabledPrefKey);
  if (currentValue == null) {
    await prefs.setBool(copilotEnabledPrefKey, false);
    return false;
  }
  return currentValue;
}

Future<void> setCopilotEnabledPref(bool isEnabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(copilotEnabledPrefKey, isEnabled);
}

Future<String> getAppTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final savedAppTheme = prefs.getString("savedAppTheme");
  return savedAppTheme ?? "dark";
}

Future<String> getCodeForgeConfig() async {
  final prefs = await SharedPreferences.getInstance();
  final defaultConfig = {
    "indentLineStatus": true,
    "lineWrap": false,
    "enableFolding": true,
    "theme": "vs2015",
    "terminalTheme": "classic-green",
    "fontFamily": "jetBrainsMono",
    "terminalFontSize": 14.0,
    "isAIEnabled": true,
    "manualCompletion": true,
    "autoSave": true,
    "enableLSP": true,
    "LSPFeatureToggle": {},
    "customEditorThemes": {},
  };
  final configString = prefs.getString('codeForgeConfig');
  if (configString == null) {
    return jsonEncode(defaultConfig);
  }
  try {
    final Map<String, dynamic> storedConfig = jsonDecode(configString);
    final mergedConfig = Map<String, dynamic>.from(defaultConfig)
      ..addAll(storedConfig);
    return jsonEncode(mergedConfig);
  } catch (e) {
    return jsonEncode(defaultConfig);
  }
}

Map<String, CustomEditorTheme> getCustomEditorThemes(Map<String, dynamic> codeForgeConfig) {
  final rawThemes = codeForgeConfig['customEditorThemes'];
  if (rawThemes is! Map) {
    return {};
  }

  final themes = <String, CustomEditorTheme>{};
  rawThemes.forEach((key, value) {
    if (key == null || value == null) {
      return;
    }

    final themeName = key.toString();
    if (value is Map<String, dynamic>) {
      themes[themeName] = CustomEditorTheme.fromJson(value);
    } else if (value is Map) {
      themes[themeName] = CustomEditorTheme.fromJson(
        Map<String, dynamic>.from(value),
      );
    }
  });

  return themes;
}

Map<String, Map<String, TextStyle>> getMergedHighlightThemes(Map<String, dynamic> codeForgeConfig) {
  final mergedThemes = Map<String, Map<String, TextStyle>>.from(highlightThemes);
  getCustomEditorThemes(codeForgeConfig).forEach((themeName, theme) {
    mergedThemes[themeName] = theme.toMap();
  });
  return mergedThemes;
}

Future<String> getAiConfig() async {
  final prefs = await SharedPreferences.getInstance();
  final defaultConfig = {};
  final configString = prefs.getString('aiConfig');
  if (configString == null) {
    return jsonEncode(defaultConfig);
  }
  try {
    final Map<String, dynamic> storedConfig = jsonDecode(configString);
    final mergedConfig = Map<String, dynamic>.from(defaultConfig)
      ..addAll(storedConfig);
    return jsonEncode(mergedConfig);
  } catch (e) {
    return jsonEncode(defaultConfig);
  }
}

Future<String> getModelSelected() async {
  final prefs = await SharedPreferences.getInstance();
  final defaultConfig = {"code": "", "chat": ""};
  final configString = prefs.getString('modelSelected');
  if (configString == null) {
    return jsonEncode(defaultConfig);
  }
  try {
    final Map<String, dynamic> storedConfig = jsonDecode(configString);
    final mergedConfig = Map<String, dynamic>.from(defaultConfig)
      ..addAll(storedConfig);
    return jsonEncode(mergedConfig);
  } catch (e) {
    return jsonEncode(defaultConfig);
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

Future<Map<String, dynamic>> sendRequest({
  required String url,
  required String method,
  Map<String, String>? headers,
  Object? body,
}) async {
  final uri = Uri.parse(url);
  http.Response response;

  try {
    switch (method.toUpperCase()) {
      case 'GET':
        response = await http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(uri, headers: headers, body: body);
        break;
      case 'PUT':
        response = await http.put(uri, headers: headers, body: body);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      default:
        throw Exception('Unsupported HTTP method: $method');
    }

    return {
      'statusCode': response.statusCode,
      'headers': response.headers,
      'body': response.body,
    };
  } catch (e) {
    return {'error': e.toString()};
  }
}

void runCode(BuildContext context, String command, String rootDir) {
  try {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, scondaryAnimation) => SetupTerminal(projectDir: rootDir, args: ["-c", command]),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SizeTransition(sizeFactor: animation, child: child);
        },
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Execution failed: ${e.toString()}")),
    );
    debugPrint(e.toString());
  }
}

void runCodeInTermux(BuildContext context, String command, String rootDir, int? id) {
  try {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, scondaryAnimation) => SetupTerminal(
          projectDir: rootDir,
          termuxId: id,
          commandToExecuteInSSH: command,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SizeTransition(sizeFactor: animation, child: child);
        },
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Execution failed: ${e.toString()}")),
    );
    debugPrint(e.toString());
  }
}

String _resolveLspServerPath(String serverPath) {
  final normalized = serverPath
      .replaceAll('\$extensionDir', extensionDir)
      .replaceAll('\${extensionDir}', extensionDir);
  if (path.isAbsolute(normalized)) return normalized;
  return path.join(extensionDir, normalized);
}

String lspLanguageIdForExtension({
  required String ext,
  required String fallbackLanguageName,
}) {
  final normalizedExt = ext.toLowerCase().replaceFirst('.', '');

  switch (normalizedExt) {
    case 'c':
      return 'c';
    case 'cc':
    case 'cpp':
    case 'cxx':
    case 'c++':
    case 'h':
    case 'hh':
    case 'hpp':
    case 'hxx':
    case 'h++':
      return 'cpp';
    case 'js':
    case 'mjs':
    case 'cjs':
      return 'javascript';
    case 'jsx':
      return 'jsx';
    case 'ts':
      return 'typescript';
    case 'tsx':
      return 'tsx';
    case 'py':
    case 'pyi':
      return 'python';
    case 'sh':
    case 'bash':
    case 'zsh':
      return 'shellscript';
    default:
      break;
  }

  return fallbackLanguageName.trim().toLowerCase();
}

String lspLanguageIdForFile({
  required Language language,
  required String filePath,
}) {
  final ext = path.extension(filePath);
  return lspLanguageIdForExtension(
    ext: ext,
    fallbackLanguageName: language.name,
  );
}

String lspServerExtForExtension({required String ext}) {
  final normalizedExt = ext.toLowerCase().replaceFirst('.', '');
  switch (normalizedExt) {
    case 'jsx':
      return 'js';
    case 'tsx':
      return 'ts';
    default:
      return normalizedExt;
  }
}

String lspServerExtForFilePath(String filePath) {
  return lspServerExtForExtension(ext: path.extension(filePath));
}

bool isLspServerAvailable({
  required String ext,
  required String? executable,
  required List<String> args,
}) {
  if (executable == null || executable.isEmpty) return false;
  final executableExists = File(executable).existsSync();
  if (!executableExists) return false;
  final normalizedExt = ext.toLowerCase();

  if (normalizedExt == 'dart') {
    return File('$runtimesDir/dart/bin/dartaotruntime').existsSync() &&
      File('$runtimesDir/dart/bin/snapshots/analysis_server_aot.dart.snapshot')
        .existsSync();
  }

  if (normalizedExt == 'js' || normalizedExt == 'ts') {
    return File(
      '$runtimesDir/node/lib/node_modules/typescript-language-server/lib/cli.mjs',
    ).existsSync();
  }

  if (normalizedExt == 'c' ||
      normalizedExt == 'cpp' ||
      normalizedExt == 'cc' ||
      normalizedExt == 'c++') {
    return true;
  }

  String? serverFile;

  if (['py', 'sh', 'bash', 'zsh'].contains(normalizedExt)) {
    final matched = extensions.where(
      (item) => item.fileExtension.contains(normalizedExt),
    );
    if (matched.isNotEmpty && matched.first.serverFile.isNotEmpty) {
      serverFile = matched.first.serverFile.first;
    }
  } else if (normalizedExt == 'html') {
    final matched = extensions.where(
      (item) => item.fileExtension.any((ex) => ex == 'html'),
    );
    if (matched.isNotEmpty && matched.first.serverFile.isNotEmpty) {
      serverFile = matched.first.serverFile[0];
    }
  } else if (normalizedExt == 'css') {
    final matched = extensions.where(
      (item) => item.fileExtension.any((ex) => ex == 'css'),
    );
    if (matched.isNotEmpty && matched.first.serverFile.length > 1) {
      serverFile = matched.first.serverFile[1];
    }
  } else if (normalizedExt == 'json') {
    final matched = extensions.where(
      (item) => item.fileExtension.any((ex) => ex == 'json'),
    );
    if (matched.isNotEmpty && matched.first.serverFile.length > 2) {
      serverFile = matched.first.serverFile[2];
    }
  }

  if (serverFile != null && serverFile.isNotEmpty) {
    final resolved = _resolveLspServerPath(serverFile);
    return File(resolved).existsSync();
  }

  return true;
}

Future<LspConfig?> startLspServer({
  required String ext,
  required String? executable,
  required List<String> args,
  required String workspacePath,
  required String langId,
  Map<String, String>? environment,
  LspClientCapabilities? capabilities,
}) async {
  if (executable == null) return null;
  try {
    final String sharedPath = await NativeChannel.getLibraryPath();
    final String runtimeDir = runtimesDir;
    final String normalizedExt = ext.toLowerCase();
    final String dartRuntimeDir = '$runtimeDir/dart';
    final String dartRuntimeExecutable = '$dartRuntimeDir/bin/dart';
    final String dartAotRuntimeExecutable = '$dartRuntimeDir/bin/dartaotruntime';
    final String dartAnalysisServerSnapshot = '$dartRuntimeDir/bin/snapshots/analysis_server_aot.dart.snapshot';
    final String resolvedExecutable = normalizedExt == 'dart'
      ? dartAotRuntimeExecutable
      : executable;
    List<String> resolveServerArgs(String ext, List<String> args) {
      final normalizedExt = ext.toLowerCase();

      if (['sh', 'bash', 'zsh'].contains(normalizedExt)) {
        final matched = extensions.where(
          (item) => item.fileExtension.contains(normalizedExt),
        );
        if (matched.isNotEmpty && matched.first.serverFile.isNotEmpty) {
          return [matched.first.serverFile.first, ...args];
        }
      }

      if (normalizedExt == 'html') {
        final matched = extensions.where(
          (item) => item.fileExtension.any((ex) => ex == 'html'),
        );
        if (matched.isNotEmpty && matched.first.serverFile.isNotEmpty) {
          return [matched.first.serverFile[0], ...args];
        }
      }

      if (normalizedExt == 'css') {
        final matched = extensions.where(
          (item) => item.fileExtension.any((ex) => ex == 'css'),
        );
        if (matched.isNotEmpty && matched.first.serverFile.length > 1) {
          return [matched.first.serverFile[1], ...args];
        }
      }

      if (normalizedExt == 'json') {
        final matched = extensions.where(
          (item) => item.fileExtension.any((ex) => ex == 'json'),
        );
        if (matched.isNotEmpty && matched.first.serverFile.length > 2) {
          return [matched.first.serverFile[2], ...args];
        }
      }

      return args;
    }

    final resolvedArgs = (() {
      if (normalizedExt == 'ts' || normalizedExt == 'js') {
        return [
          "$runtimeDir/node/lib/node_modules/typescript-language-server/lib/cli.mjs",
          ...args,
        ];
      } else if (normalizedExt == 'py' || normalizedExt == 'pyi') {
        return ["server"];
      } else if (normalizedExt == 'c' ||
          normalizedExt == 'cpp' ||
          normalizedExt == 'cc' ||
          normalizedExt == 'c++' ||
          normalizedExt == 'h' ||
          normalizedExt == 'hpp' ||
          normalizedExt == 'hh' ||
          normalizedExt == 'hxx') {
        return [
          '--init={"cache":{"directory":"$tempDir/.ccls-cache"}, "clang":{"extraArgs":["-isystem","$runtimeDir/clang/sysroot/usr/include/c++/v1","-isystem","$runtimeDir/clang/sysroot/usr/include","-isystem","$runtimeDir/clang/lib/clang/21/include"],"resourceDir":"$runtimeDir/clang/lib/clang/21"}}',
        ];
      } else if (normalizedExt == 'dart') {
        return [
          dartAnalysisServerSnapshot,
          "--protocol=lsp",
          "--dart-sdk=$dartRuntimeDir",
        ];
      }
      return resolveServerArgs(ext, args);
    })();

    final resolvedEnvironment = {
      ...environment ?? {},
      'PATH': '$binDir:$runtimeDir/dart/bin:/bin:/usr/bin:${Platform.environment['PATH'] ?? ''}',
      'ROXUM_SHARED_PATH': sharedPath,
      'LD_LIBRARY_PATH': '${normalizedExt == 'dart' ? '$sharedPath:$libDir' : '$libDir:$runtimeDir/clang:$runtimeDir/node/lib:$sharedPath'}:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
      if (normalizedExt == 'dart') 'DART_ROOT': dartRuntimeDir,
      'JAVA_HOME': '$runtimeDir/java-21-openjdk',
    };

    if (normalizedExt == 'dart') {
      try {
        final config = await LspStdioConfig.start(
          executable: resolvedExecutable,
          capabilities: capabilities ?? const LspClientCapabilities(),
          args: resolvedArgs,
          environment: resolvedEnvironment,
          workspacePath: workspacePath,
          languageId: langId.toLowerCase(),
        );
        debugPrint('Dart LSP started with AOT runtime executable: $resolvedExecutable');
        return config;
      } catch (primaryError) {
        debugPrint(
          'Primary Dart LSP startup failed with $resolvedExecutable: $primaryError',
        );
        final fallbackExecutable = dartRuntimeExecutable;
        final fallbackConfig = await LspStdioConfig.start(
          executable: fallbackExecutable,
          capabilities: capabilities ?? const LspClientCapabilities(),
          args: [
            'language-server',
            '--protocol=lsp',
            '--sdk=$dartRuntimeDir',
          ],
          environment: resolvedEnvironment,
          workspacePath: workspacePath,
          languageId: langId.toLowerCase(),
        );
        debugPrint('Dart LSP started with fallback executable: $fallbackExecutable');
        return fallbackConfig;
      }
    }

    final config = await LspStdioConfig.start(
      executable: resolvedExecutable,
      capabilities: capabilities ?? const LspClientCapabilities(),
      args: resolvedArgs,
      environment: resolvedEnvironment,
      workspacePath: workspacePath,
      languageId: langId.toLowerCase(),
    );
    return config;
  } catch (e) {
    debugPrint('LSP Initialization failed: $e');
  }
  return null;
}

class Extractor {
  static Future<void> extractZip(
    BuildContext context,
    String inputPath,
    String outputDir, {
    String? archiveName,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier = ValueNotifier<double>(0.0);

    final snackbar = SnackBar(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(days: 1),
      content: ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Extracting${archiveName == null ? "" : " "}${archiveName ?? "..."}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 6),
            LinearPercentIndicator(
              percent: value.clamp(0.0, 1.0),
              progressColor: Colors.greenAccent,
              backgroundColor: Colors.white24,
              barRadius: const Radius.circular(20),
              lineHeight: 8,
              trailing: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  "${(value * 100).toStringAsFixed(1)}%",
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );

    messenger.showSnackBar(snackbar);

    try {
      await ZipFile.extractToDirectory(
        zipFile: File(inputPath),
        destinationDir: Directory(outputDir),
        onExtracting: (entry, rawProgress) {
          progressNotifier.value = rawProgress / 100.0;
          return ZipFileOperation.includeItem;
        },
      );

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('🎉 Extraction complete!')),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('❌ Extraction failed')),
      );
      debugPrint('Extraction error: $e');
    }
  }

  static Future<void> extractZipBackground(
    String inputPath,
    String outputDir, {
    String? archiveName,
    Function(double)? onProgress,
  }) async {
    try {
      await ZipFile.extractToDirectory(
        zipFile: File(inputPath),
        destinationDir: Directory(outputDir),
        onExtracting: (entry, rawProgress) {
          onProgress?.call(rawProgress);
          return ZipFileOperation.includeItem;
        },
      );
    } catch (e) {
      debugPrint('Extraction error for $archiveName: $e');
    }
  }
}

class NativeChannel {
  static const MethodChannel _channel = MethodChannel('com.roxum');
  static const MethodChannel _pfdMethodChannel = MethodChannel('roxum/pfd');
  static const EventChannel _pfdEventChannel = EventChannel('roxum/pfd_events');

  static Future<String> getLibraryPath() async {
    try {
      final String result = await _channel.invokeMethod('getLibraryPath');
      return result;
    } on PlatformException catch (e) {
      return "Failed to load library: ${e.message}";
    }
  }

  static Future<String> getExternalMediaDir() async {
    try {
      final String result = await _channel.invokeMethod('getExtMediaPath');
      return result;
    } catch (e) {
      return "Error $e";
    }
  }

  static Future<List<String>> consumePendingOpenFiles() async {
    try {
      final List<dynamic>? raw = await _channel.invokeMethod<List<dynamic>>(
        'consumePendingOpenFiles',
      );
      if (raw == null) return const [];
      return raw.map((item) => item.toString()).toList();
    } on PlatformException catch (e) {
      debugPrint('Failed to read pending open files: ${e.message}');
      return const [];
    }
  }

  static Future<bool> isModuleInstalled(String moduleName) async {
    try {
      final bool? installed = await _pfdMethodChannel.invokeMethod<bool>(
        'isModuleInstalled',
        {'moduleName': moduleName},
      );
      return installed ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to check module install state: ${e.message}');
      return false;
    }
  }

  static Future<void> installModule(String moduleName) async {
    await _pfdMethodChannel.invokeMethod(
      'installModule',
      {'moduleName': moduleName},
    );
  }

  static Future<void> uninstallModule(String moduleName) async {
    await _pfdMethodChannel.invokeMethod(
      'uninstallModule',
      {'moduleName': moduleName},
    );
  }

  static Future<void> copyModuleAssetToPath({
    required String moduleName,
    required String assetName,
    required String targetPath,
  }) async {
    await _pfdMethodChannel.invokeMethod(
      'copyModuleAssetToPath',
      {
        'moduleName': moduleName,
        'assetName': assetName,
        'targetPath': targetPath,
      },
    );
  }

  static Future<bool> syncImportedItem({
    required String sourceUri,
    required String localPath,
    required bool isDirectory,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'syncImportedItem',
        {
          'sourceUri': sourceUri,
          'localPath': localPath,
          'isDirectory': isDirectory,
        },
      );
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to sync imported item: ${e.message}');
      return false;
    }
  }

  static Stream<Map<String, dynamic>> moduleInstallEvents() {
    return _pfdEventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{};
    }).where((event) => event.isNotEmpty);
  }
}

class ActiveEditor {
  final File file;
  final CodeForgeController controller;
  final Language languageDetails;
  final UndoRedoController undoRedoController;
  final ScrollController hscroll, vscroll;
  bool isActive;
  FindController? findController;
  String? customTitle;

  ActiveEditor({
    required this.file,
    required this.controller,
    required this.languageDetails,
    required this.undoRedoController,
    required this.hscroll,
    required this.vscroll,
    required this.isActive,
    this.findController,
    this.customTitle,
  });

  Map<String, dynamic> toJsonMap() {
    final json = {
      "file": file.path,
      "text": controller.text,
      "extentOffset": controller.selection.extentOffset,
      "baseOffset": controller.selection.baseOffset,
      "customTitle": customTitle,
      "isActive": isActive,
      "lang": languageDetails.name,
    };

    return json;
  }

  @override
  String toString() => toJsonMap().toString();

  Future<void> dispose() async {
    try {
      final lspConfig = controller.lspConfig;
      if (lspConfig != null) {
        await lspConfig.closeDocument(file.path);
      }
    } catch (e) {
      debugPrint('Error closing LSP document: $e');
    }
  }
}

class CodeForgeDemoKey {
  final bool indentLineStatus, lineWrap, enableFolding, isDark;
  final String theme, fontFamily;

  CodeForgeDemoKey({
    required this.indentLineStatus,
    required this.lineWrap,
    required this.enableFolding,
    required this.theme,
    required this.fontFamily,
    required this.isDark,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
      other is CodeForgeDemoKey &&
        runtimeType == other.runtimeType &&
        indentLineStatus == other.indentLineStatus &&
        lineWrap == other.lineWrap &&
        enableFolding == other.enableFolding &&
        theme == other.theme &&
        fontFamily == other.fontFamily &&
        isDark == other.isDark;
  }

  @override
  int get hashCode => Object.hash(
    indentLineStatus,
    lineWrap,
    enableFolding,
    theme,
    fontFamily,
    isDark,
  );
}

class AIConversation {
  final String userRequest;
  String? modelResponse;

  AIConversation(this.userRequest, this.modelResponse);

  AIConversation copyWith({String? modelResponse}) =>
      AIConversation(userRequest, modelResponse);

  Map<String, dynamic> toJson() => {
    'userRequest': userRequest,
    'modelResponse': modelResponse,
  };

  factory AIConversation.fromJson(Map<String, dynamic> json) => AIConversation(
    json['userRequest'] as String,
    json['modelResponse'] as String?,
  );
}

class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final List<AIConversation> conversations;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.conversations,
  });

  ChatSession copyWith({String? title, List<AIConversation>? conversations}) =>
      ChatSession(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        conversations: conversations ?? this.conversations,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'conversations': conversations.map((c) => c.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
    id: json['id'] as String,
    title: json['title'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    conversations: (json['conversations'] as List)
        .map((c) => AIConversation.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}

class CommitNode {
  final String hash;
  final List<String> parents;
  final String author;
  final String message;
  int lane;
  int? childLane;
  bool isMerge;
  bool isBranchStart;
  bool isHead;
  bool isRemoteHead;

  CommitNode({
    required this.hash,
    required this.parents,
    required this.author,
    required this.message,
    this.lane = -1,
    this.childLane,
    this.isMerge = false,
    this.isBranchStart = false,
    this.isHead = false,
    this.isRemoteHead = false,
  });
}

class GraphLine {
  final int fromLane;
  final int toLane;
  final int colorIndex;
  final bool isPassThrough;

  GraphLine({
    required this.fromLane,
    required this.toLane,
    required this.colorIndex,
    this.isPassThrough = false,
  });
}

class CommitRowInfo {
  final CommitNode commit;
  final List<GraphLine> lines;
  final int commitLane;
  final int colorIndex;

  CommitRowInfo({
    required this.commit,
    required this.lines,
    required this.commitLane,
    required this.colorIndex,
  });
}

List<CommitRowInfo> assignVSCodeLanes(List<CommitNode> commits) {
  if (commits.isEmpty) return [];

  final List<CommitRowInfo> rowInfos = [];

  final Map<String, int> hashToIndex = {};
  for (int i = 0; i < commits.length; i++) {
    hashToIndex[commits[i].hash] = i;
  }

  final Map<int, (String, int)> activeLanes = {};
  final Map<String, int> hashToLane = {};
  final Map<String, int> hashToColor = {};
  int nextColorIndex = 0;

  int findAvailableLane(int preferredLane) {
    if (!activeLanes.containsKey(preferredLane)) {
      return preferredLane;
    }
    int lane = 0;
    while (activeLanes.containsKey(lane)) {
      lane++;
    }
    return lane;
  }

  for (int i = 0; i < commits.length; i++) {
    final commit = commits[i];
    commit.isMerge = commit.parents.length > 1;

    final List<GraphLine> lines = [];
    int commitLane;
    int colorIndex;

    int? expectedLane;
    int? expectedColor;
    for (final entry in activeLanes.entries) {
      if (entry.value.$1 == commit.hash) {
        expectedLane = entry.key;
        expectedColor = entry.value.$2;
        break;
      }
    }

    if (expectedLane != null) {
      commitLane = expectedLane;
      colorIndex = expectedColor!;
      activeLanes.remove(expectedLane);
    } else {
      commitLane = findAvailableLane(0);
      colorIndex = nextColorIndex++;
      commit.isBranchStart = i > 0;
    }

    commit.lane = commitLane;
    hashToLane[commit.hash] = commitLane;
    hashToColor[commit.hash] = colorIndex;

    for (final entry in activeLanes.entries) {
      lines.add(
        GraphLine(
          fromLane: entry.key,
          toLane: entry.key,
          colorIndex: entry.value.$2,
          isPassThrough: true,
        ),
      );
    }

    for (int p = 0; p < commit.parents.length; p++) {
      final parentHash = commit.parents[p];
      int? existingParentLane;
      int? existingParentColor;
      for (final entry in activeLanes.entries) {
        if (entry.value.$1 == parentHash) {
          existingParentLane = entry.key;
          existingParentColor = entry.value.$2;
          break;
        }
      }

      int parentLane;
      int parentColor;

      if (existingParentLane != null) {
        parentLane = existingParentLane;
        parentColor = existingParentColor!;
        final hasDiagonal = parentLane != commitLane;
        final edgeColor = hasDiagonal
            ? (commit.isMerge && p > 0 ? parentColor : colorIndex)
            : parentColor;
        lines.add(
          GraphLine(
            fromLane: commitLane,
            toLane: parentLane,
            colorIndex: edgeColor,
          ),
        );
      } else {
        if (p == 0) {
          parentLane = commitLane;
          parentColor = colorIndex;
        } else {
          parentLane = findAvailableLane(commitLane + 1);
          parentColor = nextColorIndex++;
        }

        activeLanes[parentLane] = (parentHash, parentColor);
        hashToColor[parentHash] = parentColor;

        lines.add(
          GraphLine(
            fromLane: commitLane,
            toLane: parentLane,
            colorIndex: parentColor,
          ),
        );
      }
    }

    rowInfos.add(
      CommitRowInfo(
        commit: commit,
        lines: lines,
        commitLane: commitLane,
        colorIndex: colorIndex,
      ),
    );
  }

  return rowInfos;
}

Map<String, (String, Color)> gitFileStatus = {
  "M": ('M', Color(0xffaf9672)),
  "D": ('D', Colors.red[300]!),
  "UU": ('C', Colors.red[300]!),
  "??": ('U', Colors.green[700]!),
  "A": ('U', Colors.green[700]!),
};

class EditHunk {
  final String id;
  final String type;
  final int startLine, endLine;
  final int sourceStartLine, sourceEndLine;
  final int? afterLine;
  final String oldText;
  final String newText;
  final String? addedText;
  final String? removedText;

  const EditHunk({
    required this.id,
    required this.type,
    required this.startLine,
    required this.endLine,
    required this.sourceStartLine,
    required this.sourceEndLine,
    required this.oldText,
    required this.newText,
    this.afterLine,
    this.addedText,
    this.removedText,
  });

  factory EditHunk.fromJson(Map<String, dynamic> json) {
    return EditHunk(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'modified',
      startLine: (json['startLine'] as num?)?.toInt() ?? 0,
      endLine: (json['endLine'] as num?)?.toInt() ?? 0,
      sourceStartLine:
          (json['sourceStartLine'] as num?)?.toInt() ??
          (json['startLine'] as num?)?.toInt() ??
          0,
      sourceEndLine:
          (json['sourceEndLine'] as num?)?.toInt() ??
          (json['endLine'] as num?)?.toInt() ??
          0,
      oldText: json['oldText']?.toString() ?? '',
      newText: json['newText']?.toString() ?? '',
      afterLine: (json['afterLine'] as num?)?.toInt(),
      addedText: json['addedText']?.toString(),
      removedText: json['removedText']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      "startLine": startLine,
      "endLine": endLine,
      "sourceStartLine": sourceStartLine,
      "sourceEndLine": sourceEndLine,
      "oldText": oldText,
      "newText": newText,
      "afterLine": afterLine,
      "addedText": addedText,
      "removedText": removedText,
    };
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

class PendingEditFile {
  static const String _prefsKey = 'pendingAgenticEdits';

  final String filePath;
  final String oldText;
  final List<EditHunk> editHunks;

  const PendingEditFile({
    required this.filePath,
    required this.oldText,
    required this.editHunks,
  });

  factory PendingEditFile.fromJson(Map<String, dynamic> json) {
    final hunksRaw = json['editHunks'];
    final hunks = <EditHunk>[];
    if (hunksRaw is List) {
      for (final item in hunksRaw) {
        if (item is Map<String, dynamic>) {
          hunks.add(EditHunk.fromJson(item));
        } else if (item is Map) {
          hunks.add(EditHunk.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return PendingEditFile(
      filePath: json['filePath']?.toString() ?? '',
      oldText: json['oldText']?.toString() ?? '',
      editHunks: hunks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'oldText': oldText,
      'editHunks': editHunks.map((h) => h.toJson()).toList(),
    };
  }

  PendingEditFile copyWith({
    String? filePath,
    String? oldText,
    List<EditHunk>? editHunks,
  }) {
    return PendingEditFile(
      filePath: filePath ?? this.filePath,
      oldText: oldText ?? this.oldText,
      editHunks: editHunks ?? this.editHunks,
    );
  }

  static int _safeLineAtOffset(CodeForgeController controller, int offset) {
    final text = controller.text;
    if (text.isEmpty) return 0;
    final maxOffset = text.length - 1;
    final safeOffset = offset.clamp(0, maxOffset);
    return controller.getLineAtOffset(safeOffset);
  }

  static List<EditHunk> patchesToHunks(
    List<Patch> patches,
    CodeForgeController newController,
    CodeForgeController oldController,
  ) {
    final List<EditHunk> hunks = [];
    final ts = DateTime.now().microsecondsSinceEpoch;
    var idx = 0;

    for (final patch in patches) {
      var newCursor = patch.start2;
      var oldCursor = patch.start1;
      int? changedStartOffset;
      int? changedEndOffset;
      int? changedSourceStartOffset;
      int? changedSourceEndOffset;
      final newText = StringBuffer();
      final oldText = StringBuffer();
      final addedOnlyText = StringBuffer();
      final removedOnlyText = StringBuffer();
      var hasInsert = false;
      var hasDelete = false;

      for (final diff in patch.diffs) {
        if (diff.operation == 0 || diff.operation == -1) {
          oldText.write(diff.text);
        }

        if (diff.operation == 0 || diff.operation == 1) {
          newText.write(diff.text);
        }

        if (diff.operation == -1) {
          hasDelete = true;
          removedOnlyText.write(diff.text);
          changedSourceStartOffset ??= oldCursor;
          changedSourceEndOffset = (oldCursor + diff.text.length) - 1;
        } else if (diff.operation == 1) {
          hasInsert = true;
          addedOnlyText.write(diff.text);
          changedStartOffset ??= newCursor;
          changedEndOffset = (newCursor + diff.text.length) - 1;
        }

        if (diff.operation == 0 || diff.operation == 1) {
          newCursor += diff.text.length;
        }
        if (diff.operation == 0 || diff.operation == -1) {
          oldCursor += diff.text.length;
        }
      }

      final type = hasInsert && hasDelete
          ? 'modified'
          : hasInsert
          ? 'added'
          : 'removed';
      final rangeStartOffset = changedStartOffset ?? patch.start2;
      final rangeEndOffset = changedEndOffset ?? rangeStartOffset;
      final sourceRangeStartOffset = changedSourceStartOffset ?? patch.start1;
      final sourceRangeEndOffset =
          changedSourceEndOffset ?? sourceRangeStartOffset;
      final startLine = _safeLineAtOffset(newController, rangeStartOffset);
      final endLine = _safeLineAtOffset(newController, rangeEndOffset);
      final sourceStartLine = _safeLineAtOffset(
        oldController,
        sourceRangeStartOffset,
      );
      final sourceEndLine = _safeLineAtOffset(
        oldController,
        sourceRangeEndOffset,
      );
      final afterLine = hasDelete ? (startLine > 0 ? startLine - 1 : 0) : null;

      hunks.add(
        EditHunk(
          id: 'hunk-$ts-${idx++}',
          type: type,
          startLine: startLine,
          endLine: endLine,
          sourceStartLine: sourceStartLine,
          sourceEndLine: sourceEndLine,
          oldText: oldText.toString(),
          newText: newText.toString(),
          afterLine: afterLine,
          addedText: addedOnlyText.isEmpty ? null : addedOnlyText.toString(),
          removedText: removedOnlyText.isEmpty
              ? null
              : removedOnlyText.toString(),
        ),
      );
    }

    return hunks;
  }

  ({
    List<(int startLine, int endLine)> addedRanges,
    List<(int startLine, int endLine)> modifiedRanges,
    List<({int afterLine, String content})> removedRanges,
  })
  toDecorationRanges() {
    final addedRanges = <(int, int)>[];
    final modifiedRanges = <(int, int)>[];
    final removedRanges = <({int afterLine, String content})>[];

    String extractOldLines(EditHunk hunk) {
      if (oldText.isEmpty) return '';
      final lines = oldText.split('\n');
      if (lines.isEmpty) return '';
      final safeStart = hunk.sourceStartLine.clamp(0, lines.length - 1);
      final safeEnd = hunk.sourceEndLine.clamp(safeStart, lines.length - 1);
      return lines.sublist(safeStart, safeEnd + 1).join('\n');
    }

    for (final hunk in editHunks) {
      if (hunk.type == 'added') {
        addedRanges.add((hunk.startLine, hunk.endLine));
        continue;
      }

      if (hunk.type == 'modified') {
        modifiedRanges.add((hunk.startLine, hunk.endLine));
        final removed = extractOldLines(hunk);
        if (removed.isNotEmpty) {
          removedRanges.add((
            afterLine:
                hunk.afterLine ?? (hunk.startLine > 0 ? hunk.startLine - 1 : 0),
            content: removed,
          ));
        }
        continue;
      }

      if (hunk.type == 'removed') {
        final removed = extractOldLines(hunk);
        removedRanges.add((
          afterLine:
              hunk.afterLine ?? (hunk.startLine > 0 ? hunk.startLine - 1 : 0),
          content: removed.isNotEmpty
              ? removed
              : (hunk.removedText ?? hunk.oldText),
        ));
      }
    }

    return (
      addedRanges: addedRanges,
      modifiedRanges: modifiedRanges,
      removedRanges: removedRanges,
    );
  }

  void applyDecorations(
    CodeForgeController controller, {
    Color addedColor = const Color(0xFF4CAF50),
    Color removedColor = const Color(0xFFE53935),
    Color modifiedColor = const Color(0xFF4CAF50),
  }) {
    final ranges = toDecorationRanges();
    if (editHunks.isEmpty) {
      controller.clearGitDiffDecorations();
      return;
    }
    controller.setGitDiffDecorations(
      addedRanges: ranges.addedRanges,
      modifiedRanges: ranges.modifiedRanges,
      removedRanges: ranges.removedRanges,
      addedColor: addedColor,
      removedColor: removedColor,
      modifiedColor: modifiedColor,
    );
  }

  static Map<String, dynamic> _decodePrefs(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return {};
    }
    return {};
  }

  static PendingEditFile? _parseFileEntry(dynamic rawEntry) {
    try {
      if (rawEntry is Map<String, dynamic>) {
        return PendingEditFile.fromJson(rawEntry);
      }
      if (rawEntry is Map) {
        return PendingEditFile.fromJson(Map<String, dynamic>.from(rawEntry));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedContent = _decodePrefs(prefs.getString(_prefsKey));
    final existing = _parseFileEntry(savedContent[filePath]);
    final merged = existing == null
        ? this
        : PendingEditFile(
            filePath: filePath,
            oldText: existing.oldText,
            editHunks: [...existing.editHunks, ...editHunks],
          );
    savedContent[filePath] = merged.toJson();
    await prefs.setString(_prefsKey, jsonEncode(savedContent));
  }

  static Future<void> upsert(PendingEditFile pendingEditFile) async {
    final prefs = await SharedPreferences.getInstance();
    final savedContent = _decodePrefs(prefs.getString(_prefsKey));
    savedContent[pendingEditFile.filePath] = pendingEditFile.toJson();
    await prefs.setString(_prefsKey, jsonEncode(savedContent));
  }

  static Future<PendingEditFile?> getForFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final savedContent = _decodePrefs(prefs.getString(_prefsKey));
    return _parseFileEntry(savedContent[filePath]);
  }

  static Future<Map<String, PendingEditFile>> getAllFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedContent = _decodePrefs(prefs.getString(_prefsKey));
    final result = <String, PendingEditFile>{};
    for (final entry in savedContent.entries) {
      final parsed = _parseFileEntry(entry.value);
      if (parsed != null) {
        result[entry.key] = parsed;
      }
    }
    return result;
  }

  static Future<void> removeFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final savedContent = _decodePrefs(prefs.getString(_prefsKey));
    savedContent.remove(filePath);
    await prefs.setString(_prefsKey, jsonEncode(savedContent));
  }

  static Future<void> removeHunk(String filePath, String hunkId) async {
    final pending = await getForFile(filePath);
    if (pending == null) return;

    final updated = pending.editHunks.where((h) => h.id != hunkId).toList();
    if (updated.isEmpty) {
      await removeFile(filePath);
      return;
    }

    await upsert(pending.copyWith(editHunks: updated));
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode({}));
  }

  static Future<Map<String, dynamic>> getFromPref() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodePrefs(prefs.getString(_prefsKey));
  }
}

sealed class SSHInfo {
  final String url, name;
  final int id;

  SSHInfo({
    required this.id,
    required this.url,
    required this.name
  });

  SSHClient? get client;
  bool get isConnected;

  Uri get uri => Uri.parse(url);
  String get username => uri.userInfo.split(':').first;
  String get host => uri.host;
  int get port => uri.port == 0 ? 22 : uri.port;

  factory SSHInfo.fromJsonMap(Map<String, dynamic> jsonMap){
    switch (jsonMap["login"]) {
      case true: return SSHLogin.fromJsonMap(jsonMap);
      case false: return SSHPrivateKey.fromJsonMap(jsonMap);
      default: throw Exception('Invalid SSH type');
    }
  }

  Map<String, dynamic> toJsonMap();

  Future<(bool, String)> connect();
  void disconnect();

  static Future<List<SSHInfo>> getSavedSSHServers() async{
    final prefs = await SharedPreferences.getInstance();
    final serverList = (jsonDecode(prefs.getString('sshServerList') ?? '[]') as List).cast<Map<String, dynamic>>();
    return serverList.map(SSHInfo.fromJsonMap).toList();
  }

  @override
  bool operator ==(Object other) {
    return other is SSHInfo && other.id == id;
  }
  
  @override int get hashCode => id;
}

class SSHLogin extends SSHInfo{
  final String password;

  SSHLogin({
    required super.name,
    required super.id,
    required super.url,
    required this.password,
  });
  
  @override
  Map<String, dynamic> toJsonMap() => {
    "name": name,
    "id": id,
    "url": url,
    "username": username,
    "password": password,
    "login": true
  };

  @override
  String toString() => toJsonMap().toString();
  
  
  static SSHLogin fromJsonMap(Map<String, dynamic> jsonMap) => SSHLogin(
    name: jsonMap["name"],
    id: jsonMap["id"],
    url: jsonMap["url"],
    password: jsonMap["password"],
  );
  
  SSHClient? _client;
  bool _isConnected = false;

  @override
  SSHClient? get client => _client;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<(bool, String)> connect() async{
    try {
      _client = SSHClient(
        await SSHSocket.connect(host, port),
        username: username,
        onPasswordRequest: () => password,
      );
      await _client!.authenticated;
      _isConnected = true;
      return (true, "Successfully connected to $host as $username");
    } on SocketException catch(e) {
      return (false, "Server unreachable: $e");
    } on TimeoutException catch(e) {
      return (false, "Connection timed out: $e");
    } catch (e) {
      return (false, "An error occurred: $e");
    }
  }

  @override
  void disconnect() {
    _isConnected = false;
    _client?.close();
  }
}

class SSHPrivateKey extends SSHInfo{
  final File? termuxKeyLoc;

  SSHPrivateKey({
    required super.name,
    required super.id,
    required super.url,
    this.termuxKeyLoc
  });
  
  @override
  Map<String, dynamic> toJsonMap() => {
    "name": name,
    "id": id,
    "url": url,
    "login": false,
    "termuxKeyLoc": termuxKeyLoc?.path
  };

  static SSHPrivateKey fromJsonMap(Map<String, dynamic> jsonMap) => SSHPrivateKey(
    name: jsonMap["name"],
    id: jsonMap["id"],
    url: jsonMap["url"],
    termuxKeyLoc: File("$appDir/.termux/.ssh/id_ed25519"),
  );

  SSHClient? _client;
  bool _isConnected = false;

  @override
  String toString() => toJsonMap().toString();

  @override
  SSHClient? get client => _client;

  @override
  bool get isConnected => _isConnected;
  
  @override
  Future<(bool, String)> connect() async{
    try {
      _client = SSHClient(
        await SSHSocket.connect(host, port),
        username: username,
        identities: [
          ...SSHKeyPair.fromPem(await (termuxKeyLoc ?? SshKeygen.privateKeyFilelocation).readAsString())
        ]
      );
      await _client!.authenticated;
      _isConnected = true;
      return (true, "Successfully connected to $host as $username");
    } on SocketException catch(e) {
      return (false, "Server unreachable: $e");
    } on TimeoutException catch(e) {
      return (false, "Connection timed out: $e");
    } catch (e) {
      return (false, "An error occurred: $e");
    }
  }

  @override
  void disconnect() {
    _isConnected = false;
    _client?.close();
  }
}

class SshKeygen {
  final String? comment;
  final File? termPubKey;
  final File? termPrivKey;

  static final publicKeyFilelocation = File("$appDir/.ssh/id_ed25519.pub");
  static final privateKeyFilelocation = File("$appDir/.ssh/id_ed25519");

  SshKeygen({
    this.comment,
    this.termPubKey,
    this.termPrivKey,
  });

  Future<void> generate() async{
    final algo = Ed25519();
    final keyPair = await algo.newKeyPair();
    final pubKey = await keyPair.extractPublicKey();
    final privSeed = await keyPair.extractPrivateKeyBytes();
    final pubBytes = Uint8List.fromList(pubKey.bytes);
    final seedBytes = Uint8List.fromList(privSeed);
    final publicKeyFile = buildPublicKeyFile(pubBytes, comment: comment ?? 'user@host');
    final privateKeyFile = buildPrivateKeyFile(pubBytes, seedBytes, comment: comment ?? 'user@host');
    if(!(await (termPrivKey ?? privateKeyFilelocation).exists())){
      await (termPrivKey ?? privateKeyFilelocation).create(recursive: true);
    }

    if(!(await (termPubKey ?? publicKeyFilelocation).exists())){
      await (termPubKey ?? publicKeyFilelocation).create(recursive: true);
    }
    
    await (termPrivKey ?? privateKeyFilelocation).writeAsString(privateKeyFile);
    await (termPubKey ?? publicKeyFilelocation).writeAsString(publicKeyFile);
  }

  String buildPublicKeyFile(Uint8List pubBytes, {String comment = ''}) {
    final buf = BytesBuilder();
    _writeString(buf, 'ssh-ed25519');
    _writeBytes(buf, pubBytes);
    final b64 = base64.encode(buf.toBytes());
    return 'ssh-ed25519 $b64 $comment'.trim();
  }

  String buildPrivateKeyFile(Uint8List pubBytes, Uint8List seedBytes, {String comment = ''}) {
    final privBytes = Uint8List(64)
      ..setRange(0, 32, seedBytes)
      ..setRange(32, 64, pubBytes);

    final pubBlob = _buildPubBlob(pubBytes);
    final privBlob = _buildPrivBlob(pubBytes, privBytes, comment);

    final outer = BytesBuilder();
    outer.add(utf8.encode('openssh-key-v1\x00'));
    _writeString(outer, 'none');
    _writeString(outer, 'none');
    _writeString(outer, '');
    _writeUint32(outer, 1);
    _writeBytes(outer, pubBlob);
    _writeBytes(outer, privBlob);

    final b64 = base64.encode(outer.toBytes());
    final lines = RegExp('.{1,70}').allMatches(b64).map((m) => m.group(0)!).join('\n');
    return '-----BEGIN OPENSSH PRIVATE KEY-----\n$lines\n-----END OPENSSH PRIVATE KEY-----\n';
  }

  Uint8List _buildPubBlob(Uint8List pubBytes) {
    final b = BytesBuilder();
    _writeString(b, 'ssh-ed25519');
    _writeBytes(b, pubBytes);
    return b.toBytes();
  }

  Uint8List _buildPrivBlob(Uint8List pubBytes, Uint8List privBytes, String comment) {
    final checkInt = Random.secure().nextInt(0xFFFFFFFF);
    final b = BytesBuilder();
    _writeUint32(b, checkInt);
    _writeUint32(b, checkInt);
    _writeString(b, 'ssh-ed25519');
    _writeBytes(b, pubBytes);
    _writeBytes(b, privBytes);
    _writeString(b, comment); 
    int pad = 1;
    while (b.length % 8 != 0) {
      b.addByte(pad++);
    }
    return b.toBytes();
  }

  void _writeUint32(BytesBuilder b, int value) {
    b.addByte((value >> 24) & 0xFF);
    b.addByte((value >> 16) & 0xFF);
    b.addByte((value >> 8) & 0xFF);
    b.addByte(value & 0xFF);
  }

  void _writeString(BytesBuilder b, String s) {
    final bytes = utf8.encode(s);
    _writeUint32(b, bytes.length);
    b.add(bytes);
  }

  void _writeBytes(BytesBuilder b, Uint8List bytes) {
    _writeUint32(b, bytes.length);
    b.add(bytes);
  }
}

enum GgufDownloadStatus { downloading, completed, failed }

class GgufDownloadTask {
  final String taskId, modelName, url, fileName, localPath, quant, imageUrl;
  final GgufDownloadStatus status;
  final double progress, paramSize;
  final bool registered;

  GgufDownloadTask({
    required this.taskId,
    required this.modelName,
    required this.url,
    required this.fileName,
    required this.localPath,
    required this.status,
    required this.progress,
    required this.registered,
    required this.quant,
    required this.paramSize,
    required this.imageUrl
  });

  GgufDownloadTask copyWith({
    String? taskId,
    String? modelName,
    String? url,
    String? fileName,
    String? localPath,
    String? quant,
    String? imageUrl,
    GgufDownloadStatus? status,
    double? progress,
    double? paramSize,
    bool? registered,
  }) {
    return GgufDownloadTask(
      taskId: taskId ?? this.taskId,
      modelName: modelName ?? this.modelName,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      registered: registered ?? this.registered,
      quant: quant ?? this.quant,
      paramSize: paramSize ?? this.paramSize,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'modelName': modelName,
    'url': url,
    'fileName': fileName,
    'localPath': localPath,
    'status': status.index,
    'progress': progress,
    'registered': registered,
    'quant': quant,
    'paramSize': paramSize,
    'imageUrl': imageUrl
  };

  factory GgufDownloadTask.fromJson(Map<String, dynamic> json) => GgufDownloadTask(
    taskId: json['taskId'] as String? ?? '',
    modelName: json['modelName'] as String? ?? '',
    url: json['url'] as String? ?? '',
    fileName: json['fileName'] as String? ?? '',
    localPath: json['localPath'] as String? ?? '',
    status: GgufDownloadStatus.values[json['status'] as int? ?? 0],
    progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
    registered: json['registered'] as bool? ?? false,
    quant: json['quant'] as String? ?? '',
    paramSize: (json['paramSize'] as num?)?.toDouble() ?? 0.0,
    imageUrl: json['imageUrl'] ?? '',
  );
}

class GgufModel {
  final String name, url, fileName, quant, imageUrl;
  final double paramSize;

  GgufModel({
    required this.name,
    required this.url,
    required this.fileName,
    required this.quant,
    required this.paramSize,
    required this.imageUrl
  });

  static Future<({String modelId, Map<String, dynamic> aiConfig, Map<String, dynamic> modelSelected})> registerGgufModelWithAI(GgufDownloadTask task) async {
    final prefs = await SharedPreferences.getInstance();
    final aiConfigStr = await getAiConfig();
    final Map<String, dynamic> aiConfig = jsonDecode(aiConfigStr);

    final alreadyExists = aiConfig.values.any((v) =>
      v is Map<String, dynamic> &&
      v['provider'] == 'LocalLlama' &&
      v['modelPath'] == task.localPath
    );
    if (alreadyExists) {
      final existingKey = aiConfig.entries.firstWhere((e) =>
        e.value is Map<String, dynamic> &&
        (e.value as Map)['modelPath'] == task.localPath
      ).key;
      final modelSelectedStr = await getModelSelected();
      return (
        modelId: existingKey,
        aiConfig: aiConfig,
        modelSelected: jsonDecode(modelSelectedStr) as Map<String, dynamic>,
      );
    }

    final modelId = 'LocalLlama-${DateTime.now().millisecondsSinceEpoch}';
    aiConfig[modelId] = {
      'provider': 'LocalLlama',
      'apiProvider': 'LocalLlama',
      'modelName': task.modelName,
      'model': task.modelName,
      'modelPath': task.localPath,
      'threads': 4,
      'contextSize': 4096,
      'gpuLayers': 0,
    };
    await prefs.setString('aiConfig', jsonEncode(aiConfig));

    final modelSelectedStr = await getModelSelected();
    final Map<String, dynamic> modelSelected = jsonDecode(modelSelectedStr);
    if ((modelSelected['chat'] as String? ?? '').isEmpty) {
      modelSelected['chat'] = modelId;
      await prefs.setString('modelSelected', jsonEncode(modelSelected));
    }

    return (modelId: modelId, aiConfig: aiConfig, modelSelected: modelSelected);
  }
}

class BoyerMooreSearch {
  final String pattern;
  final bool caseSensitive;

  late final String _pat;
  late final List<int> _skip;

  BoyerMooreSearch(this.pattern, {this.caseSensitive = true}) {
    _pat = caseSensitive ? pattern : pattern.toLowerCase();
    _skip = List<int>.filled(256, _pat.length);
    for (int i = 0; i < _pat.length - 1; i++) {
      final c = _pat.codeUnitAt(i);
      if (c < 256) _skip[c] = _pat.length - 1 - i;
    }
  }

  bool containsIn(String text) => _firstMatch(
    caseSensitive ? text : text.toLowerCase(),
  ) != -1;

  int firstMatch(String text) => _firstMatch(caseSensitive ? text : text.toLowerCase());

  List<int> findAll(String text) {
    final src = caseSensitive ? text : text.toLowerCase();
    final m = _pat.length;
    if (m == 0) return [];
    final hits = <int>[];
    int base = 0;
    while (base <= src.length - m) {
      final idx = _firstMatch(src.substring(base));
      if (idx == -1) break;
      hits.add(base + idx);
      base += idx + m;
    }
    return hits;
  }

  bool isWholeWordMatch(String text, int offset) {
    final end = offset + _pat.length;
    final before = offset == 0 || !_isWordChar(text.codeUnitAt(offset - 1));
    final after  = end >= text.length || !_isWordChar(text.codeUnitAt(end));
    return before && after;
  }

  int _firstMatch(String src) {
    final m = _pat.length;
    final n = src.length;
    if (m == 0) return 0;
    if (m > n)  return -1;

    int i = m - 1;
    while (i < n) {
      int j = m - 1, k = i;
      while (j >= 0 && src.codeUnitAt(k) == _pat.codeUnitAt(j)) {
        k--;
        j--;
      }
      if (j < 0) return k + 1;
      final c = src.codeUnitAt(i);
      i += (c < 256) ? _skip[c] : m;
    }
    return -1;
  }

  static bool _isWordChar(int c) =>
      (c >= 65 && c <= 90)  ||
      (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57)  ||
      c == 95;
}

String? _regexLiteralPrefix(String regexPattern) {
  final sb = StringBuffer();
  for (int i = 0; i < regexPattern.length; i++) {
    final c = regexPattern[i];
    if (r'\^$.|?*+()[]{}'.contains(c)) break;
    sb.write(c);
  }
  final p = sb.toString();
  return p.length >= 2 ? p : null;
}

Future<bool> _isBinaryFile(File file, {int sampleBytes = 4096}) async {
  try {
    final raf = await file.open();
    try {
      final buf = await raf.read(sampleBytes);
      return buf.contains(0);
    } finally {
      await raf.close();
    }
  } catch (_) {
    return true;
  }
}

class SearchParams {
  final String workspacePath;
  final String query;
  final bool matchCase;
  final bool matchWholeWord;
  final bool isRegex;
  final int maxFileSizeBytes;

  const SearchParams({
    required this.workspacePath,
    required this.query,
    required this.matchCase,
    required this.matchWholeWord,
    required this.isRegex,
    this.maxFileSizeBytes = 5 * 1024 * 1024,
  });
}

class RawResult {
  final String filePath;
  final String relativePath;
  final int lineNumber;
  final String lineContent;

  const RawResult({
    required this.filePath,
    required this.relativePath,
    required this.lineNumber,
    required this.lineContent,
  });
}

const _kTextExtensions = {
  '.dart', '.js',   '.ts',   '.json', '.xml',   '.html',  '.css',
  '.md',   '.txt',  '.yaml', '.yml',  '.java',  '.kt',    '.py',
  '.c',    '.cpp',  '.h',    '.hpp',  '.sh',    '.gradle',
  '.properties',   '.swift', '.m',    '.go',    '.rs',    '.rb',
  '.php',  '.sql',  '.vue',  '.jsx',  '.tsx',   '.toml',  '.lock',
};

Future<List<RawResult>> searchIsolate(SearchParams p) async {
  final results = <RawResult>[];
  final dir = Directory(p.workspacePath);

  BoyerMooreSearch? bm;
  RegExp? regex;
  BoyerMooreSearch? prefixBm;

  if (p.isRegex) {
    try {
      regex = RegExp(p.query, caseSensitive: p.matchCase);
    } catch (_) {
      return results;
    }
    final prefix = _regexLiteralPrefix(p.query);
    if (prefix != null) {
      prefixBm = BoyerMooreSearch(prefix, caseSensitive: p.matchCase);
    }
  } else {
    bm = BoyerMooreSearch(p.query, caseSensitive: p.matchCase);
  }

  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;

    final relativePath = entity.path.replaceFirst('${p.workspacePath}/', '');

    if (relativePath.startsWith('.') ||
        relativePath.contains('/.') ||
        relativePath.contains('/build/') ||
        relativePath.contains('/.git/') ||
        relativePath.contains('/node_modules/') ||
        relativePath.contains('/.dart_tool/') ||
        relativePath.contains('/.gradle/')) {
      continue;
    }

    final ext = path.extension(entity.path).toLowerCase();
    if (ext.isNotEmpty && !_kTextExtensions.contains(ext)) continue;

    try {
      final stat = await entity.stat();
      if (stat.size == 0 || stat.size > p.maxFileSizeBytes) continue;
    } catch (_) {
      continue;
    }

    if (await _isBinaryFile(entity)) continue;

    try {
      int lineNumber = 0;

      await for (final line in entity
          .openRead()
          .transform(utf8.decoder) 
          .transform(const LineSplitter())) {
        lineNumber++;

        bool hasMatch;

        if (p.isRegex) {
          if (prefixBm != null && !prefixBm.containsIn(line)) {
            hasMatch = false;
          } else {
            hasMatch = regex!.hasMatch(line);
          }
        } else if (p.matchWholeWord) {
          final offsets = bm!.findAll(line);
          hasMatch = offsets.any((o) => bm!.isWholeWordMatch(line, o));
        } else {
          hasMatch = bm!.containsIn(line);
        }

        if (hasMatch) {
          results.add(RawResult(
            filePath:     entity.path,
            relativePath: relativePath,
            lineNumber:   lineNumber,
            lineContent:  line.trim(),
          ));
        }
      }
    } on FormatException {
      continue;
    } catch (_) {
      continue;
    }
  }

  return results;
}

class InvertedIndex {
  final Map<String, Map<String, List<int>>> _index = {};
  bool _ready = false;

  bool get isReady => _ready;

  static final _wordRe = RegExp(r'\b[A-Za-z_]\w{2,}\b');
  static const _maxFileSizeForIndex = 2 * 1024 * 1024;   // 2 MB

  Future<void> build(String workspacePath) async {
    _index.clear();
    _ready = false;
    await _scan(workspacePath);
    _ready = true;
  }

  Future<void> _scan(String workspacePath) async {
    final dir = Directory(workspacePath);

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      final relativePath = entity.path.replaceFirst('$workspacePath/', '');
      if (relativePath.startsWith('.') ||
          relativePath.contains('/.') ||
          relativePath.contains('/build/') ||
          relativePath.contains('/.git/') ||
          relativePath.contains('/node_modules/')) {
        continue;
      }

      final ext = path.extension(entity.path).toLowerCase();
      if (ext.isNotEmpty && !_kTextExtensions.contains(ext)) continue;

      try {
        final stat = await entity.stat();
        if (stat.size == 0 || stat.size > _maxFileSizeForIndex) continue;
      } catch (_) {
        continue;
      }

      if (await _isBinaryFile(entity)) continue;

      try {
        int lineNo = 0;
        await for (final line in entity
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          lineNo++;
          for (final m in _wordRe.allMatches(line.toLowerCase())) {
            final word = m.group(0)!;
            (_index[word] ??= {})[entity.path] ??= [];
            _index[word]![entity.path]!.add(lineNo);
          }
        }
      } catch (_) {
        continue;
      }
    }
  }

  Map<String, List<int>>? lookup(String word) {
    if (!_ready || word.length < 3) return null;
    return _index[word.toLowerCase()];
  }

  Future<void> updateFile(File file) async {
    for (final v in _index.values) {
      v.remove(file.path);
    }
    try {
      int lineNo = 0;
      await for (final line in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        lineNo++;
        for (final m in _wordRe.allMatches(line.toLowerCase())) {
          final word = m.group(0)!;
          (_index[word] ??= {})[file.path] ??= [];
          _index[word]![file.path]!.add(lineNo);
        }
      }
    } catch (_) {}
  }

  void clear() {
    _index.clear();
    _ready = false;
  }
}

class CustomEditorTheme {
  final Color bg, fg;
  final TextStyle keyword, literal, symbol, name, link, builtIn;
  final TextStyle type, number, class_, string, metaString, regexp;
  final TextStyle templateTag, subst, function, title, params;
  final TextStyle formula, comment, quote, doctag, meta, metaKeyword;
  final TextStyle tag, variable, templateVariable, attr, attribute;
  final TextStyle section, emphasis, strong, bullet, selectorTag;
  final TextStyle selectorId, selectorClass, selectorAttr, selectorPseudo;
  final TextStyle addition, deletion;

  const CustomEditorTheme({
    this.bg = const Color(0xff000000),
    this.fg = const Color(0xffffffff),
    this.keyword = const TextStyle(color: Colors.white),
    this.literal = const TextStyle(color: Colors.white),
    this.symbol = const TextStyle(color: Colors.white),
    this.name = const TextStyle(color: Colors.white),
    this.link = const TextStyle(color: Colors.white),
    this.builtIn = const TextStyle(color: Colors.white),
    this.type = const TextStyle(color: Colors.white),
    this.number = const TextStyle(color: Colors.white),
    this.class_ = const TextStyle(color: Colors.white),
    this.string = const TextStyle(color: Color(0xffD69D85)),
    this.metaString = const TextStyle(color: Color(0xffD69D85)),
    this.regexp = const TextStyle(color: Colors.white),
    this.templateTag = const TextStyle(color: Colors.white),
    this.subst = const TextStyle(color: Colors.white),
    this.function = const TextStyle(color: Colors.white),
    this.title = const TextStyle(color: Colors.white),
    this.params = const TextStyle(color: Colors.white),
    this.formula = const TextStyle(color: Colors.white),
    this.comment = const TextStyle(color: Colors.green),
    this.quote = const TextStyle(color: Color(0xffD69D85)),
    this.doctag = const TextStyle(color: Colors.white),
    this.meta = const TextStyle(color: Colors.white),
    this.metaKeyword = const TextStyle(color: Colors.white),
    this.tag = const TextStyle(color: Colors.white),
    this.variable = const TextStyle(color: Colors.white),
    this.templateVariable = const TextStyle(color: Colors.white),
    this.attr = const TextStyle(color: Colors.white),
    this.attribute = const TextStyle(color: Colors.white),
    this.section = const TextStyle(color: Colors.white),
    this.emphasis = const TextStyle(color: Colors.white),
    this.strong = const TextStyle(color: Colors.white),
    this.bullet = const TextStyle(color: Colors.white),
    this.selectorTag = const TextStyle(color: Colors.white),
    this.selectorId = const TextStyle(color: Colors.white),
    this.selectorClass = const TextStyle(color: Colors.white),
    this.selectorAttr = const TextStyle(color: Colors.white),
    this.selectorPseudo = const TextStyle(color: Colors.white),
    this.addition = const TextStyle(color: Colors.white),
    this.deletion = const TextStyle(color: Colors.white),
  });

  Map<String, TextStyle> toMap() => {
    'root': TextStyle(
      color: fg,
      backgroundColor: bg,
    ),
    'keyword': keyword,
    'literal': literal,
    'symbol': symbol,
    'name': name,
    'link': link,
    'built_in': builtIn,
    'type': type,
    'number': number,
    'class': class_,
    'string': string,
    'meta-string': metaString,
    'regexp': regexp,
    'template-tag': templateTag,
    'subst': subst,
    'function': function,
    'title': title,
    'params': params,
    'formula': formula,
    'comment': comment,
    'quote': quote,
    'doctag': doctag,
    'meta': meta,
    'meta-keyword': metaKeyword,
    'tag': tag,
    'variable': variable,
    'template-variable': templateVariable,
    'attr': attr,
    'attribute': attribute,
    'section': section,
    'emphasis': emphasis,
    'strong': strong,
    'bullet': bullet,
    'selector-tag': selectorTag,
    'selector-id': selectorId,
    'selector-class': selectorClass,
    'selector-attr': selectorAttr,
    'selector-pseudo': selectorPseudo,
    'addition': addition,
    'deletion': deletion,
  };

  Map<String, dynamic> toJson() => {
    "bg": bg.toARGB32(),
    "fg": fg.toARGB32(),
    "styles": {
      "keyword": _styleToJson(keyword),
      "literal": _styleToJson(literal),
      "symbol": _styleToJson(symbol),
      "name": _styleToJson(name),
      "link": _styleToJson(link),
      "built_in": _styleToJson(builtIn),
      "type": _styleToJson(type),
      "number": _styleToJson(number),
      "class": _styleToJson(class_),
      "string": _styleToJson(string),
      "meta-string": _styleToJson(metaString),
      "regexp": _styleToJson(regexp),
      "template-tag": _styleToJson(templateTag),
      "subst": _styleToJson(subst),
      "function": _styleToJson(function),
      "title": _styleToJson(title),
      "params": _styleToJson(params),
      "formula": _styleToJson(formula),
      "comment": _styleToJson(comment),
      "quote": _styleToJson(quote),
      "doctag": _styleToJson(doctag),
      "meta": _styleToJson(meta),
      "meta-keyword": _styleToJson(metaKeyword),
      "tag": _styleToJson(tag),
      "variable": _styleToJson(variable),
      "template-variable": _styleToJson(templateVariable),
      "attr": _styleToJson(attr),
      "attribute": _styleToJson(attribute),
      "section": _styleToJson(section),
      "emphasis": _styleToJson(emphasis),
      "strong": _styleToJson(strong),
      "bullet": _styleToJson(bullet),
      "selector-tag": _styleToJson(selectorTag),
      "selector-id": _styleToJson(selectorId),
      "selector-class": _styleToJson(selectorClass),
      "selector-attr": _styleToJson(selectorAttr),
      "selector-pseudo": _styleToJson(selectorPseudo),
      "addition": _styleToJson(addition),
      "deletion": _styleToJson(deletion),
    }
  };

  static CustomEditorTheme fromMap(Map<String, TextStyle> map) {
    final root = map['root'] ?? const TextStyle();

    return CustomEditorTheme(
      bg: root.backgroundColor ?? const Color(0xff000000),
      fg: root.color ?? const Color(0xffffffff),
      keyword: map['keyword'] ?? const TextStyle(color: Colors.white),
      literal: map['literal'] ?? const TextStyle(color: Colors.white),
      symbol: map['symbol'] ?? const TextStyle(color: Colors.white),
      name: map['name'] ?? const TextStyle(color: Colors.white),
      link: map['link'] ?? const TextStyle(color: Colors.white),
      builtIn: map['built_in'] ?? const TextStyle(color: Colors.white),
      type: map['type'] ?? const TextStyle(color: Colors.white),
      number: map['number'] ?? const TextStyle(color: Colors.white),
      class_: map['class'] ?? const TextStyle(color: Colors.white),
      string: map['string'] ?? const TextStyle(color: Colors.white),
      metaString: map['meta-string'] ?? const TextStyle(color: Colors.white),
      regexp: map['regexp'] ?? const TextStyle(color: Colors.white),
      templateTag: map['template-tag'] ?? const TextStyle(color: Colors.white),
      subst: map['subst'] ?? const TextStyle(color: Colors.white),
      function: map['function'] ?? const TextStyle(color: Colors.white),
      title: map['title'] ?? const TextStyle(color: Colors.white),
      params: map['params'] ?? const TextStyle(color: Colors.white),
      formula: map['formula'] ?? const TextStyle(color: Colors.white),
      comment: map['comment'] ?? const TextStyle(color: Colors.white),
      quote: map['quote'] ?? const TextStyle(color: Colors.white),
      doctag: map['doctag'] ?? const TextStyle(color: Colors.white),
      meta: map['meta'] ?? const TextStyle(color: Colors.white),
      metaKeyword: map['meta-keyword'] ?? const TextStyle(color: Colors.white),
      tag: map['tag'] ?? const TextStyle(color: Colors.white),
      variable: map['variable'] ?? const TextStyle(color: Colors.white),
      templateVariable: map['template-variable'] ?? const TextStyle(color: Colors.white),
      attr: map['attr'] ?? const TextStyle(color: Colors.white),
      attribute: map['attribute'] ?? const TextStyle(color: Colors.white),
      section: map['section'] ?? const TextStyle(color: Colors.white),
      emphasis: map['emphasis'] ?? const TextStyle(color: Colors.white),
      strong: map['strong'] ?? const TextStyle(color: Colors.white),
      bullet: map['bullet'] ?? const TextStyle(color: Colors.white),
      selectorTag: map['selector-tag'] ?? const TextStyle(color: Colors.white),
      selectorId: map['selector-id'] ?? const TextStyle(color: Colors.white),
      selectorClass: map['selector-class'] ?? const TextStyle(color: Colors.white),
      selectorAttr: map['selector-attr'] ?? const TextStyle(color: Colors.white),
      selectorPseudo: map['selector-pseudo'] ?? const TextStyle(color: Colors.white),
      addition: map['addition'] ?? const TextStyle(color: Colors.white),
      deletion: map['deletion'] ?? const TextStyle(color: Colors.white),
    );
  }

  factory CustomEditorTheme.fromJson(Map<String, dynamic> json) {
    final styles = json["styles"] as Map<String, dynamic>;

    TextStyle style(String key) => _styleFromJson(styles[key] as Map<String, dynamic>);

    return CustomEditorTheme(
      bg: Color(json["bg"]),
      fg: Color(json["fg"]),
      keyword: style("keyword"),
      literal: style("literal"),
      symbol: style("symbol"),
      name: style("name"),
      link: style("link"),
      builtIn: style("built_in"),
      type: style("type"),
      number: style("number"),
      class_: style("class"),
      string: style("string"),
      metaString: style("meta-string"),
      regexp: style("regexp"),
      templateTag: style("template-tag"),
      subst: style("subst"),
      function: style("function"),
      title: style("title"),
      params: style("params"),
      formula: style("formula"),
      comment: style("comment"),
      quote: style("quote"),
      doctag: style("doctag"),
      meta: style("meta"),
      metaKeyword: style("meta-keyword"),
      tag: style("tag"),
      variable: style("variable"),
      templateVariable: style("template-variable"),
      attr: style("attr"),
      attribute: style("attribute"),
      section: style("section"),
      emphasis: style("emphasis"),
      strong: style("strong"),
      bullet: style("bullet"),
      selectorTag: style("selector-tag"),
      selectorId: style("selector-id"),
      selectorClass: style("selector-class"),
      selectorAttr: style("selector-attr"),
      selectorPseudo: style("selector-pseudo"),
      addition: style("addition"),
      deletion: style("deletion"),
    );
  }

  Map<String, dynamic> _styleToJson(TextStyle style) => {
    "color": style.color?.toARGB32(),
    "backgroundColor": style.backgroundColor?.toARGB32(),
    "fontStyle": style.fontStyle?.name,
    "fontWeight": style.fontWeight?.value,
  };

  static TextStyle _styleFromJson(Map<String, dynamic> json) {
    return TextStyle(
      color: json["color"] != null ? Color(json["color"]) : null,
      backgroundColor: json["backgroundColor"] != null
        ? Color(json["backgroundColor"])
        : null,
      fontStyle: switch (json["fontStyle"]) {
        "italic" => FontStyle.italic,
        "normal" => FontStyle.normal,
        _ => null,
      },
      fontWeight: json["fontWeight"] != null
        ? FontWeight.values.firstWhere(
            (w) => w.value == json["fontWeight"],
          )
        : null,
    );
  }
}