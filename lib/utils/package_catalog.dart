import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'constants.dart';
import 'languages.dart';

class PackageCatalogSyncResult {
  final List<RunTime> runtimes;
  final List<Extension> extensions;
  final Set<String> runtimeUpdates;
  final Set<String> extensionUpdates;
  final bool usedRemote;
  final bool remoteFetchFailed;

  const PackageCatalogSyncResult({
    required this.runtimes,
    required this.extensions,
    required this.runtimeUpdates,
    required this.extensionUpdates,
    required this.usedRemote,
    required this.remoteFetchFailed,
  });
}

class PackageCatalogService {
  static final List<RunTime> _pfdRuntimes = [
    RunTime(
      name: 'Python',
      version: '3.13.5',
      details: 'The python interpreter.\nDownload the ty extension for LSP support.',
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/v0.0.1/python.zip',
      archiveName: 'python.zip',
      archiveSize: 78,
      parentName: 'python',
      iconUrl: 'assets/material_icons/python.svg',
    ),
    RunTime(
      name: 'Node JS',
      version: '24.4.1',
      details: 'The node js runtime.\nTypescript runtime and LSP server are included with this bundle.',
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/v0.0.1/node.zip',
      archiveName: 'node.zip',
      archiveSize: 51,
      parentName: 'node',
      iconUrl: 'https://raw.githubusercontent.com/material-extensions/vscode-material-icon-theme/f7de1c3273aab253098a717a662f2c0b9482d06e/icons/nodejs.svg',
    ),
    RunTime(
      name: 'Clang',
      version: '21.1.8',
      details: 'The clang compiler for C/C++. CCLS Language server is included with this bundle',
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/v0.0.1/clang.zip',
      archiveName: 'clang.zip',
      archiveSize: 86,
      parentName: 'clang',
      iconUrl: 'https://icon.icepanel.io/Technology/svg/LLVM.svg',
    ),
    RunTime(
      name: 'OpenJDK',
      version: '21',
      details: 'The Java Virtual Machine.',
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/v0.0.1/java-21-openjdk.zip',
      archiveName: 'java-21-openjdk.zip',
      archiveSize: 135,
      parentName: 'java-21-openjdk',
      iconUrl: 'https://icon.icepanel.io/Technology/svg/Java.svg',
    ),
    RunTime(
      name: 'Kotlin',
      version: '2.2.0',
      details: 'The Kotlin runtime.\nNote: OpenJDK installation is required',
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/v0.0.1/kotlin.zip',
      archiveName: 'kotlin.zip',
      archiveSize: 74,
      parentName: 'kotlin',
      iconUrl: 'assets/material_icons/kotlin.svg',
    ),
    RunTime(
      name: 'Dart',
      version: '3.11.4',
      details: 'The Dart SDK runtime.\nIncludes dart, dartvm, and dartaotruntime.',
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/v0.0.1/dart.zip',
      archiveName: 'dart.zip',
      archiveSize: 112,
      parentName: 'dart',
      iconUrl: 'assets/material_icons/dart.svg',
    ),
    RunTime(
      name: 'Ruby',
      version: '3.4.1',
      details: 'The Ruby interpreter.',
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/v0.0.1/ruby.zip',
      archiveName: 'ruby.zip',
      archiveSize: 12,
      parentName: 'ruby',
      iconUrl: 'assets/material_icons/ruby.svg',
    ),

    RunTime(
      name: 'Rust',
      version: '1.83.0',
      details: 'The rust compiler and runtime.\nNote: Clang runtime is required.',
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/v0.0.1/rust.zip',
      archiveName: 'rust.zip',
      archiveSize: 180,
      parentName: 'rust',
      iconUrl: 'assets/material_icons/rust.svg',
    ),

    RunTime(
      name: 'Zig',
      version: '0.16.0',
      details: 'The zig compiler and runtime.',
      url: '',
      archiveName: 'zig.zip',
      archiveSize: 199,
      parentName: 'zig',
      iconUrl: 'assets/material_icons/zig.svg',
    ),

    RunTime(
      name: 'Go',
      version: '1.26.1',
      details: 'Known for simplicity and performance, ideal for concurrent programming.\nNote: Clang runtime is required',
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/v0.0.1/go.zip',
      archiveName: 'go.zip',
      archiveSize: 51,
      parentName: 'go',
      iconUrl: 'assets/material_icons/go_gopher.svg',
    ),

    RunTime(
      name: 'Lua',
      version: '5.5',
      details: 'Lightweight embeddable scripting language runtime.',
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/v0.0.1/lua.zip',
      archiveName: 'lua.zip',
      archiveSize: 1,
      parentName: 'lua',
      iconUrl: 'assets/material_icons/lua.svg',
    ),
  ];

  static final List<Extension> _pfdExtensions = [
    Extension(
      name: 'Github Copilot',
      details: 'Enable github copilot in the editor.\nNote: Nodejs runtime is required',
      archiveName: 'copilot-language-server.zip',
      parentName: 'copilot-language-server',
      archiveSize: 12,
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/extensions/copilot-language-server.zip',
      fileExtension: const [],
      serverFile: const [
        '\$extensionDir/copilot-language-server/language-server.js',
      ],
      iconUrl: 'assets/icons/github-copilot-icon.svg',
      githubUrl: 'https://github.com/orgs/github/packages/npm/package/copilot-language-server',
    ),
    Extension(
      name: 'Ty',
      details: 'Language server for Python.',
      archiveName: 'libty.so',
      parentName: 'ty',
      archiveSize: 21,
      url: '',
      fileExtension: const ['py'],
      serverFile: const [],
      iconUrl: 'assets/icons/ty.svg',
      githubUrl: 'https://github.com/astral-sh/ty',
    ),
    Extension(
      name: 'rust-analyzer',
      details: 'Language server for Rust.',
      archiveName: 'librust-analyzer.so',
      parentName: 'rust-analyzer',
      archiveSize: 36,
      url: '',
      fileExtension: const ['rs'],
      serverFile: const [],
      iconUrl: 'assets/icons/rust-analyzer.svg',
      githubUrl: 'https://github.com/rust-lang/rust-analyzer',
      iconSize: 15
    ),
    Extension(
      name: 'gopls',
      details: 'Language server for Go.',
      archiveName: 'libgopls.so',
      parentName: 'gopls',
      archiveSize: 30,
      url: '',
      fileExtension: const ['go'],
      serverFile: const [],
      iconUrl: 'assets/material_icons/go_gopher.svg',
      githubUrl: 'https://github.com/golang/tools/tree/master/gopls',
    ),
    Extension(
      name: 'EmmyLuaLs',
      details: 'Language server for Lua.',
      archiveName: 'libemmy.so',
      parentName: 'emmyluals',
      archiveSize: 28,
      url: '',
      fileExtension: const ['lua'],
      serverFile: const [],
      iconUrl: 'assets/icons/emmy_lua.png',
      githubUrl: 'https://github.com/EmmyLuaLs/emmylua-analyzer-rust',
    ),
    Extension(
      name: 'bash-language-server',
      details: 'Language server for bash/shell-script.\nNote: Nodejs runtime is required',
      archiveName: 'bash-language-server.zip',
      parentName: 'bash-language-server',
      archiveSize: 4,
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/extensions/bash-language-server.zip',
      fileExtension: const ['sh', 'bash', 'zsh'],
      serverFile: const [
        '/data/data/com.roxum/extensions/bash-language-server/node_modules/bash-language-server/out/cli.js',
      ],
      iconUrl: 'assets/icons/bash.png',
      githubUrl: 'https://github.com/bash-lsp/bash-language-server',
    ),
    Extension(
      name: 'Kmp LSP',
      details: 'Language server for java, kotlin and swift',
      archiveName: 'libkmplsp.so',
      parentName: 'kmp-lsp',
      archiveSize: 14,
      url: '',
      fileExtension: const ['java'],
      serverFile: const [],
      iconUrl: 'assets/icons/kmp-logo.png',
      githubUrl: 'https://github.com/Hessesian/kmp-lsp',
    ),
    Extension(
      name: 'ZLS',
      details: 'Language server for java, kotlin and swift',
      archiveName: 'libkmplsp.so',
      parentName: 'zls',
      archiveSize: 19,
      url: '',
      fileExtension: const ['zig'],
      serverFile: const [],
      iconUrl: 'assets/icons/zls-opt.svg',
      iconSize: 15,
      githubUrl: 'https://github.com/zigtools/zls',
    ),
    Extension(
      name: 'VScode-extracted LSP Servers',
      details: 'Language servers extracted from VSCode. Contains HTML, CSS, Markdown, JSON and ESLint servers.\nNote: Node JS runtime is required.',
      archiveName: 'vscode-langservers-extracted.zip',
      parentName: 'vscode-langservers-extracted',
      archiveSize: 14,
      url: 'https://github.com/heckmon/android-arm64-shared-libraries/releases/download/extensions/vscode-langservers-extracted.zip',
      fileExtension: const ['html', 'css', 'md', 'json'],
      serverFile: const [
        '/data/data/com.roxum/extensions/vscode-langservers-extracted/node_modules/vscode-langservers-extracted/lib/html-language-server/node/htmlServerMain.js',
        '/data/data/com.roxum/extensions/vscode-langservers-extracted/node_modules/vscode-langservers-extracted/lib/css-language-server/node/cssServerMain.js',
        '/data/data/com.roxum/extensions/vscode-langservers-extracted/node_modules/vscode-langservers-extracted/lib/json-language-server/node/jsonServerMain.js',
        '/data/data/com.roxum/extensions/vscode-langservers-extracted/node_modules/vscode-langservers-extracted/lib/markdown-language-server/node/main.js',
        '/data/data/com.roxum/extensions/vscode-langservers-extracted/node_modules/vscode-langservers-extracted/lib/eslint-language-server/eslintServer.js',
      ],
      iconUrl: 'assets/icons/html-css.png',
      githubUrl: 'https://github.com/hrsh7th/vscode-langservers-extracted',
    ),
  ];

  static Future<PackageCatalogSyncResult> syncOnStartup() async {
    final installed = await _loadInstalledCatalog();

    final effectiveRuntimes = _mergeCatalogWithInstalled(
      catalogRuntimes: _pfdRuntimes,
      installedRuntimes: installed.runtimes,
    );
    final effectiveExtensions = _mergeExtensionCatalogWithInstalled(
      catalogExtensions: _pfdExtensions,
      installedExtensions: installed.extensions,
    );

    updatePackageCatalog(
      fetchedRuntimes: effectiveRuntimes,
      fetchedExtensions: effectiveExtensions,
    );

    final updates = _buildUpdateSets(
      catalogRuntimes: _pfdRuntimes,
      catalogExtensions: _pfdExtensions,
      installedRuntimes: installed.runtimes,
      installedExtensions: installed.extensions,
    );

    return PackageCatalogSyncResult(
      runtimes: effectiveRuntimes,
      extensions: effectiveExtensions,
      runtimeUpdates: updates.runtimeUpdates,
      extensionUpdates: updates.extensionUpdates,
      usedRemote: false,
      remoteFetchFailed: false,
    );
  }

  static Future<PackageCatalogSyncResult> refreshInstalledStatusOnly({
    required List<RunTime> runtimes,
    required List<Extension> extensions,
  }) async {
    final installed = await _loadInstalledCatalog();

    final effectiveRuntimes = _mergeCatalogWithInstalled(
      catalogRuntimes: _pfdRuntimes,
      installedRuntimes: installed.runtimes,
    );
    final effectiveExtensions = _mergeExtensionCatalogWithInstalled(
      catalogExtensions: _pfdExtensions,
      installedExtensions: installed.extensions,
    );

    updatePackageCatalog(
      fetchedRuntimes: effectiveRuntimes,
      fetchedExtensions: effectiveExtensions,
    );

    final updates = _buildUpdateSets(
      catalogRuntimes: _pfdRuntimes,
      catalogExtensions: _pfdExtensions,
      installedRuntimes: installed.runtimes,
      installedExtensions: installed.extensions,
    );

    return PackageCatalogSyncResult(
      runtimes: effectiveRuntimes,
      extensions: effectiveExtensions,
      runtimeUpdates: updates.runtimeUpdates,
      extensionUpdates: updates.extensionUpdates,
      usedRemote: false,
      remoteFetchFailed: false,
    );
  }

  static List<RunTime> _mergeCatalogWithInstalled({
    required List<RunTime> catalogRuntimes,
    required List<RunTime> installedRuntimes,
  }) {
    final merged = <RunTime>[];
    final seenParents = <String>{};

    for (final runtime in catalogRuntimes) {
      merged.add(runtime);
      seenParents.add(runtime.parentName);
    }

    for (final runtime in installedRuntimes) {
      if (seenParents.contains(runtime.parentName)) continue;
      merged.add(runtime);
      seenParents.add(runtime.parentName);
    }

    return merged;
  }

  static List<Extension> _mergeExtensionCatalogWithInstalled({
    required List<Extension> catalogExtensions,
    required List<Extension> installedExtensions,
  }) {
    final merged = <Extension>[];
    final seenParents = <String>{};

    for (final extension in catalogExtensions) {
      merged.add(extension);
      seenParents.add(extension.parentName);
    }

    for (final extension in installedExtensions) {
      if (seenParents.contains(extension.parentName)) continue;
      merged.add(extension);
      seenParents.add(extension.parentName);
    }

    return merged;
  }

  static Future<({List<RunTime> runtimes, List<Extension> extensions})> _loadInstalledCatalog() async {
    final runtimeDir = Directory(runtimesDir);
    final extensionDirPath = Directory(extensionDir);
    final installedRuntimes = <RunTime>[];
    final installedExtensions = <Extension>[];

    if (runtimeDir.existsSync()) {
      final runtimeEntries = runtimeDir
          .listSync(followLinks: false)
          .whereType<Directory>()
          .toList();
      for (final dir in runtimeEntries) {
        final packageFile = File('${dir.path}/rsx-package.json');
        if (!packageFile.existsSync()) continue;
        try {
          final parsed = jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
          installedRuntimes.add(RunTime.fromJson(parsed));
        } catch (e) {
          debugPrint('Failed to parse runtime metadata at ${dir.path}: $e');
        }
      }
    }

    if (extensionDirPath.existsSync()) {
      final extensionEntries = extensionDirPath
          .listSync(followLinks: false)
          .whereType<Directory>()
          .toList();
      for (final dir in extensionEntries) {
        final packageFile = File('${dir.path}/rsx-package.json');
        if (!packageFile.existsSync()) continue;
        try {
          final parsed = jsonDecode(await packageFile.readAsString())
              as Map<String, dynamic>;
          installedExtensions.add(Extension.fromJson(parsed));
        } catch (e) {
          debugPrint('Failed to parse extension metadata at ${dir.path}: $e');
        }
      }
    }

    return (runtimes: installedRuntimes, extensions: installedExtensions);
  }

  static ({Set<String> runtimeUpdates, Set<String> extensionUpdates}) _buildUpdateSets({
    required List<RunTime> catalogRuntimes,
    required List<Extension> catalogExtensions,
    required List<RunTime> installedRuntimes,
    required List<Extension> installedExtensions,
  }) {
    final runtimeUpdates = <String>{};
    final extensionUpdates = <String>{};

    final installedRuntimeByParent = {
      for (final item in installedRuntimes) item.parentName: item,
    };
    final installedExtensionByParent = {
      for (final item in installedExtensions) item.parentName: item,
    };

    for (final item in catalogRuntimes) {
      final installed = installedRuntimeByParent[item.parentName];
      if (installed == null) continue;

      if (_isRuntimeUpdateAvailable(item, installed)) {
        runtimeUpdates.add(item.parentName);
      }
    }

    for (final item in catalogExtensions) {
      final installed = installedExtensionByParent[item.parentName];
      if (installed == null) continue;

      if (_isExtensionUpdateAvailable(item, installed)) {
        extensionUpdates.add(item.parentName);
      }
    }

    return (
      runtimeUpdates: runtimeUpdates,
      extensionUpdates: extensionUpdates,
    );
  }

  static bool _isRuntimeUpdateAvailable(RunTime catalog, RunTime installed) {
    final catalogVersion = catalog.version?.trim();
    final installedVersion = installed.version?.trim();

    if ((catalogVersion ?? '').isNotEmpty &&
        (installedVersion ?? '').isNotEmpty) {
      return catalogVersion != installedVersion;
    }

    final catalogArchive = catalog.archiveName.trim();
    final installedArchive = installed.archiveName.trim();
    if (catalogArchive.isNotEmpty && installedArchive.isNotEmpty) {
      return catalogArchive != installedArchive;
    }

    return false;
  }

  static bool _isExtensionUpdateAvailable(
    Extension catalog,
    Extension installed,
  ) {
    final catalogArchive = catalog.archiveName.trim();
    final installedArchive = installed.archiveName.trim();
    if (catalogArchive.isNotEmpty && installedArchive.isNotEmpty) {
      return catalogArchive != installedArchive;
    }

    return false;
  }
}
