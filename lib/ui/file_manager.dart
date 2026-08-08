import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:roxum/l10n/app_localizations.dart';
import 'package:path/path.dart' as path;

import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';
import '../utils/themes.dart';
import 'editor_page.dart';

class FileManagerPage extends StatefulWidget {
  final String rootPath;

  const FileManagerPage({
    super.key,
    this.rootPath = '/storage/emulated/0/Android/media/com.roxum',
  });

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  late Directory _currentDir;
  bool _loading = true;
  List<FileSystemEntity> _entries = [];

  File _localMetadataFileForPath(String entityPath) {
    final metadataDir = Directory(path.join(tempDir, '.roxum_metadata'));
    final encodedPath = base64Url.encode(utf8.encode(entityPath)).replaceAll('=', '');
    return File(path.join(metadataDir.path, '$encodedPath.json'));
  }

  @override
  void initState() {
    super.initState();
    _currentDir = Directory(widget.rootPath);
    _initialize();
  }

  Future<void> _initialize() async {
    await _ensureBaseDirs();
    await _loadEntries();
  }

  Future<void> _ensureBaseDirs() async {
    final root = Directory(widget.rootPath);
    await root.create(recursive: true);
    await Directory(projectDir).create(recursive: true);
    await Directory(templateDir).create(recursive: true);
    await Directory(filesDir).create(recursive: true);
    if (!mounted) return;
    _currentDir = root;
  }

  Future<void> _loadEntries() async {
    if (!await _currentDir.exists()) {
      await _currentDir.create(recursive: true);
    }

    final items = await _currentDir
        .list(followLinks: false)
        .where((entity) {
          final name = path.basename(entity.path);
          return !name.startsWith('.roxum_') && !name.startsWith('.');
        })
        .toList();

    items.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir != bIsDir) {
        return aIsDir ? -1 : 1;
      }
      return path.basename(a.path).toLowerCase().compareTo(path.basename(b.path).toLowerCase());
    });

    if (!mounted) return;
    setState(() {
      _entries = items;
      _loading = false;
    });
  }

  bool _isAtRoot() {
    return path.equals(_currentDir.path, Directory(widget.rootPath).path);
  }

  Future<String?> _promptForName({required String title}) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _NamePromptDialog(title: title),
    );
    return result;
  }

  Future<void> _writeLocalMetadata(FileSystemEntity entity, {String? sourceUri, String type = 'local'}) async {
    final metadataPath = type == 'local'
      ? _localMetadataFileForPath(entity.path)
      : entity is Directory
        ? File(path.join(entity.path, '.roxum_source.json'))
        : File('${entity.path}.roxum_source.json');
    final payload = <String, dynamic>{
      'type': type,
      'sourceUri': sourceUri,
      'path': entity.path,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await metadataPath.parent.create(recursive: true);
    await metadataPath.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<Map<String, dynamic>?> _readSourceMetadata(FileSystemEntity entity) async {
    Future<Map<String, dynamic>?> readMetadataAtPath(
      String candidatePath, {
      required bool isDirectory,
    }) async {
      final metadataPath = isDirectory
          ? File(path.join(candidatePath, '.roxum_source.json'))
          : File('$candidatePath.roxum_source.json');
      if (!await metadataPath.exists()) return null;
      try {
        final raw = await metadataPath.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
      return null;
    }

    if (entity is File) {
      final direct = await readMetadataAtPath(entity.path, isDirectory: false);
      if (direct != null) return direct;
    }

    var current = entity is Directory ? entity : entity.parent;
    while (true) {
      final metadata = await readMetadataAtPath(current.path, isDirectory: true);
      if (metadata != null) {
        return metadata;
      }

      final parent = current.parent;
      if (path.equals(parent.path, current.path)) {
        break;
      }
      current = parent;
    }

    return null;
  }

  bool _hasExternalSourceMetadataSync(FileSystemEntity entity) {
    Map<String, dynamic>? readMetadataAtPath(String candidatePath, {required bool isDirectory}) {
      if (isDirectory) {
        final localMetadata = _localMetadataFileForPath(candidatePath);
        if (localMetadata.existsSync()) {
          return null;
        }
      } else {
        final localMetadata = _localMetadataFileForPath(candidatePath);
        if (localMetadata.existsSync()) {
          return null;
        }
      }

      final metadataPath = isDirectory
          ? File(path.join(candidatePath, '.roxum_source.json'))
          : File('$candidatePath.roxum_source.json');
      if (!metadataPath.existsSync()) return null;
      try {
        final raw = metadataPath.readAsStringSync();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
      return null;
    }

    bool isSourceBacked(Map<String, dynamic>? metadata) {
      final sourceUri = metadata?['sourceUri'];
      final type = metadata?['type'];
      return sourceUri is String && sourceUri.isNotEmpty && type != 'local';
    }

    if (entity is File) {
      final direct = readMetadataAtPath(entity.path, isDirectory: false);
      if (direct != null) {
        return isSourceBacked(direct);
      }
    }

    bool hasDirectoryMetadata(String candidatePath) {
      return isSourceBacked(readMetadataAtPath(candidatePath, isDirectory: true));
    }

    var current = entity is Directory ? entity : entity.parent;
    while (true) {
      if (hasDirectoryMetadata(current.path)) {
        return true;
      }

      final parent = current.parent;
      if (path.equals(parent.path, current.path)) {
        break;
      }
      current = parent;
    }

    return false;
  }

  Future<bool> _confirmOverwriteExternalTarget(FileSystemEntity entity) async {
    final appTheme = context.read<AppThemeBloc>().state.appTheme;
    final itemName = path.basename(entity.path);

    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: 380,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: appTheme.isDark
                        ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                        : [
                            const Color.fromARGB(255, 250, 250, 250),
                            const Color.fromARGB(255, 240, 240, 240),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Sync back to source?',
                      style: TextStyle(
                        color: appTheme.selectScreenCardTextColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'The existing folder in the external folder will be overwritten.\n\nItem: $itemName',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.85),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff0e639c),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Okay',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;
  }

  Language _languageForPath(String filePath) {
    final ext = path.extension(filePath).replaceFirst('.', '').toLowerCase();
    return languages.firstWhere(
      (lang) => lang.extension.contains(ext),
      orElse: () => languages[0],
    );
  }

  void _openFolder(String dirPath){
    Navigator.of(context).push(PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
          EditorPage(
            rootDir: dirPath,
            isProject: true,
            isCloned: true,
            languageDetails: null,
          ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SizeTransition(sizeFactor: animation, child: child);
        },
      )
    );
  }

  Future<void> _openFile(File file) async {
    if (!await file.exists()) return;
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => EditorPage(
          file: file,
          rootDir: file.parent.path,
          languageDetails: _languageForPath(file.path),
          isProject: false,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SizeTransition(sizeFactor: animation, child: child);
        },
      ),
    );
  }

  Future<void> _downloadToStorage(FileSystemEntity entity) async {
    final l10n = AppLocalizations.of(context)!;
    final metadata = await _readSourceMetadata(entity);
    if (metadata != null && metadata['sourceUri'] is String && (metadata['sourceUri'] as String).isNotEmpty) {
      final shouldSync = await _confirmOverwriteExternalTarget(entity);
      if (!shouldSync) return;

      final syncTarget = metadata['localRootPath'] as String? ?? entity.path;
      final syncIsDirectory = metadata['type'] == 'directory' || entity is Directory;

      final success = await NativeChannel.syncImportedItem(
        sourceUri: metadata['sourceUri'] as String,
        localPath: syncTarget,
        isDirectory: syncIsDirectory,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? l10n.syncedBackToSourceFolder : l10n.syncBackFailed),
        ),
      );
      return;
    }

    try {
      if (entity is File) {
        final savePath = await selectDir(
          dialogeTitle: l10n.saveFile,
          fileName: path.basename(entity.path),
          initialDirectory: entity.parent.path,
          bytes: await entity.readAsBytes(),
        );
        if (savePath == null) return;
      } else {
        final tempZip = File(path.join(
          tempDir,
          '${path.basename(entity.path)}.zip',
        ));
        if (await tempZip.exists()) {
          await tempZip.delete();
        }
        await ZipFile.createFromDirectory(
          sourceDir: Directory(entity.path),
          zipFile: tempZip,
          includeBaseDirectory: true,
          recurseSubDirs: true,
        );
        final savePath = await selectDir(
          dialogeTitle: l10n.exportFolder,
          fileName: path.basename(tempZip.path),
          initialDirectory: entity.parent.path,
          bytes: await tempZip.readAsBytes(),
        );
        if (savePath == null) {
          try {
            await tempZip.delete();
          } catch (_) {}
          return;
        }
        try {
          await tempZip.delete();
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.exportComplete)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.exportFailed(e.toString()))),
      );
    }
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _promptForName(title: l10n.createFolder);
    if (name == null) return;
    final folder = Directory(path.join(_currentDir.path, name));
    if (await folder.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.folderAlreadyExists)));
      return;
    }
    await folder.create(recursive: true);
    await _writeLocalMetadata(folder);
    await _loadEntries();
  }

  Future<void> _createFile() async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _promptForName(title: l10n.createFile);
    if (name == null) return;
    final file = File(path.join(_currentDir.path, name));
    if (await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File already exists.')),
      );
      return;
    }
    await file.parent.create(recursive: true);
    await file.create(recursive: true);
    await _writeLocalMetadata(file);
    await _loadEntries();
  }

  Future<void> _openEntity(FileSystemEntity entity) async {
    if (entity is Directory) {
      setState(() {
        _currentDir = entity;
        _loading = true;
      });
      await _loadEntries();
      return;
    }

    await _openFile(File(entity.path));
  }

  /*Future<void> _showEntityActions(FileSystemEntity entity) async {
    final metadata = await _readSourceMetadata(entity);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.read<AppThemeBloc>().state.appTheme.isDark
          ? const Color(0xff1f1f1f)
          : Colors.white,
      builder: (sheetContext) {
        final canSyncBack = metadata != null && metadata['sourceUri'] is String && (metadata['sourceUri'] as String).isNotEmpty;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(entity is Directory ? Icons.folder_open : Icons.open_in_new),
                title: Text(entity is Directory ? 'Open folder' : 'Open file'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openEntity(entity);
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: Text(canSyncBack ? 'Sync back to source' : 'Download to storage'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _downloadToStorage(entity);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    if (entity is Directory) {
                      await entity.delete(recursive: true);
                    } else {
                      await entity.delete();
                    }
                    await _loadEntries();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Delete failed: $e')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }*/

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    try {
      if (entity is Directory) {
        await entity.delete(recursive: true);
      } else {
        await entity.delete();
      }
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Widget _buildBreadcrumbs(AppTheme appTheme) {
    final root = Directory(widget.rootPath).absolute.path;
    final current = _currentDir.absolute.path;
    final segments = path.relative(current, from: root).split(path.separator).where((segment) => segment.isNotEmpty).toList();

    final crumbs = <Widget>[
      InkWell(
        onTap: () async {
          setState(() {
            _currentDir = Directory(root);
            _loading = true;
          });
          await _loadEntries();
        },
        child: Text(
          'com.roxum',
          style: TextStyle(
            color: appTheme.selectScreenCardTextColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ];

    var accumulated = root;
    for (final segment in segments) {
      final nextPath = path.join(accumulated, segment);
      crumbs.add(Text(
        ' / ',
        style: TextStyle(
          color: appTheme.selectScreenCardTextColor
        ),
      ));
      crumbs.add(
        InkWell(
          onTap: () async {
            setState(() {
              _currentDir = Directory(nextPath);
              _loading = true;
            });
            await _loadEntries();
          },
          child: Text(
            segment,
            style: TextStyle(
              color: appTheme.selectScreenCardTextColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: crumbs),
    );
  }

  Widget  _buildQuickRoots(AppTheme appTheme) {
    final roots = [
      (label: 'Projects', dir: Directory(projectDir), icon: Icons.workspaces_outline),
      (label: 'Files', dir: Directory(filesDir), icon: Icons.description_outlined),
      (label: 'Templates', dir: Directory(templateDir), icon: Icons.devices_fold_outlined),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: roots.map((root) {
        return OutlinedButton.icon(
          onPressed: () async {
            setState(() {
              _currentDir = root.dir;
              _loading = true;
            });
            await _loadEntries();
          },
          icon: Icon(root.icon, size: 18),
          label: Text(root.label),
          style: OutlinedButton.styleFrom(
            foregroundColor: appTheme.selectScreenCardTextColor,
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.35)),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppThemeBloc>().state.appTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mini File Manager'),
        titleTextStyle: TextStyle(
          color: appTheme.selectScreenCardTextColor,
          fontSize: 20
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Create file',
            onPressed: _createFile,
            icon: const Icon(Icons.note_add_outlined),
          ),
          IconButton(
            tooltip: 'Create folder',
            onPressed: _createFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBreadcrumbs(appTheme),
            const SizedBox(height: 14),
            _buildQuickRoots(appTheme),
            const SizedBox(height: 18),
            Text(
              _currentDir.path,
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? Center(
                        child: Text(
                          'This folder is empty.',
                          style: TextStyle(color: appTheme.selectScreenCardTextColor),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final isDir = entry is Directory;
                          final title = path.basename(entry.path);
                          return Material(
                            color: appTheme.isDark
                              ? const Color(0xff232323)
                              : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: Icon(
                                isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                                color: isDir ? const Color(0xff5090c8) : appTheme.selectScreenCardTextColor,
                              ),
                              title: Text(
                                title,
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                entry.path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () => _openEntity(entry),
                              trailing: PopupMenuButton<String>(
                                color: appTheme.scaffoldBg,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: appTheme.selectScreenCardTextColor,
                                    width: 0.2
                                  )
                                ),
                                style: IconButton.styleFrom(
                                  foregroundColor: appTheme.selectScreenCardTextColor
                                ),
                                onSelected: (value) async {
                                  switch (value) {
                                    case 'export':
                                      await _downloadToStorage(entry);  
                                      break;
                                    case 'delete':
                                      await _deleteEntity(entry);
                                      break;
                                    case 'open':
                                      _openFolder(entry.path);
                                      break;
                                    default:
                                  }
                                },
                                itemBuilder: (_) {
                                  final syncable = _hasExternalSourceMetadataSync(entry);
                                  return [
                                  PopupMenuItem(
                                    value: 'export',
                                    child: ListTile(
                                      title: Text(
                                        syncable ? 'Sync to storage' : 'Download to storage',
                                      ),
                                      leading: Icon(
                                        syncable ? Icons.sync : Icons.file_download_outlined,
                                        color: Colors.blue,
                                      ),
                                      titleTextStyle: TextStyle(
                                        color: appTheme.selectScreenCardTextColor
                                      )
                                    ),
                                  ),
                                  if (entry is Directory) PopupMenuItem(
                                    value: 'open',
                                    child: ListTile(
                                      title: Text('Open in editor'),
                                      leading: Icon(
                                        Icons.open_in_new,
                                        color: Colors.blue
                                      ),
                                      titleTextStyle: TextStyle(
                                        color: appTheme.selectScreenCardTextColor
                                      )
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      title: Text('Delete'),
                                      leading: Icon(
                                        Icons.delete,
                                        color: Colors.red
                                      ),
                                      titleTextStyle: TextStyle(
                                        color: appTheme.selectScreenCardTextColor
                                      )
                                    ),
                                  ),
                                ];
                                },
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isAtRoot()
          ? null
          : FloatingActionButton.small(
              backgroundColor: Colors.blue,
              onPressed: () async {
                setState(() {
                  _currentDir = _currentDir.parent;
                  _loading = true;
                });
                await _loadEntries();
              },
              child: const Icon(
                Icons.arrow_upward,
                color: Colors.white
              ),
            ),
    );
  }
}

class _NamePromptDialog extends StatefulWidget {
  final String title;

  const _NamePromptDialog({required this.title});

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.read<AppThemeBloc>().state.appTheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: appTheme.isDark
                ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                : [
                    const Color.fromARGB(255, 250, 250, 250),
                    const Color.fromARGB(255, 240, 240, 240),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                Icons.drive_file_rename_outline,
                color: appTheme.selectScreenCardTextColor,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.title,
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(color: appTheme.selectScreenCardTextColor),
              decoration: InputDecoration(
                hintText: 'Name',
                hintStyle: TextStyle(
                  color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.55),
                ),
                filled: true,
                fillColor: appTheme.isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.03),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isEmpty) return;
                Navigator.of(context).pop(trimmed);
              },
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    final value = _controller.text.trim();
                    if (value.isEmpty) return;
                    Navigator.of(context).pop(value);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff0e639c),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Create',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
