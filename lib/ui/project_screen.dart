import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:roxum/l10n/app_localizations.dart';
import 'package:path/path.dart' as path;
import 'package:roxum/ui/editor_page.dart';
import 'package:roxum/utils/proj_temps.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/themes.dart';
import 'downloads.dart';
import 'widgets.dart';

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  final TextEditingController _projectNameController = TextEditingController();
  bool _yourProjectsExpanded = false;
  bool _templatesExpanded = false, _generating = true;
  Future<List<Directory>>? _existingProjectsFuture;
  late final Future<Directory> _projectDirFuture;
  StreamSubscription<FileSystemEvent>? _projectDirWatcher;

  @override
  void initState() {
    super.initState();
    _projectDirFuture = setupProjectDir();
    _projectDirFuture.then((_) {
      _startProjectDirWatcher();
      _refreshProjectList();
    });
  }

  @override
  void dispose() {
    _projectDirWatcher?.cancel();
    _projectNameController.dispose();
    super.dispose();
  }

  void _refreshProjectList() {
    setState(() {
      _existingProjectsFuture = _getExistingProjects(Directory(projectDir));
    });
  }

  void _startProjectDirWatcher() {
    try {
      _projectDirWatcher = Directory(projectDir).watch().listen((event) {
        if (event.type == FileSystemEvent.create ||
            event.type == FileSystemEvent.delete ||
            event.type == FileSystemEvent.move) {
          _refreshProjectList();
        }
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  static Future<List<Directory>> _getExistingProjects(Directory projectDir) async {
    try {
      if (!await projectDir.exists()) {
        return [];
      }
      final entities = await projectDir.list().toList();
      final directories = entities.whereType<Directory>().toList();
      directories.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      return directories;
    } catch (e) {
      return [];
    }
  }

  List<TemplateRequirement> _missingTemplateRequirements(CLITemplates template) {
    return template.requirements
        .where((requirement) => !File(requirement.binaryPath).existsSync())
        .toList();
  }

  Future<void> _showTemplatePrerequisiteDialog(
    BuildContext context,
    AppTheme appTheme,
    List<TemplateRequirement> missing,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final missingNames = missing.map((item) => item.title).join(' and ');

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: appTheme.isDark
              ? const Color(0xff2b2b2b)
              : const Color.fromARGB(255, 240, 240, 240),
          title: Text(
            l10n.runtimeSetupRequired,
            style: TextStyle(color: appTheme.selectScreenCardTextColor),
          ),
          content: Text(
            '${l10n.beforeCreatingTemplateInstall(missingNames)}\n\n${l10n.openDownloadsToInstallFirst}',
            style: TextStyle(color: appTheme.selectScreenCardTextColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const DownloadManager(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      return SizeTransition(sizeFactor: animation, child: child);
                    },
                  ),
                );
              },
              child: Text(l10n.openDownloads),
            ),
          ],
        );
      },
    );
  }

  void _showNewProjectDialog(BuildContext context, AppTheme appTheme) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: appTheme.isDark ? const Color(0xff2b2b2b) : const Color.fromARGB(255, 240, 240, 240),
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xffffc928).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.folder_special_rounded,
                      color: Color(0xffffc928),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      l10n.newProject,
                      style: TextStyle(
                        color: appTheme.selectScreenCardTextColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _projectNameController,
                style: TextStyle(
                  color: appTheme.selectScreenCardTextColor,
                ),
                cursorColor: const Color(0xff5090c8),
                decoration: InputDecoration(
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  hintText: l10n.projectName,
                  filled: true,
                  fillColor: appTheme.isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: Color(0xff5090c8), width: 2),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      l10n.cancel,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      if (_projectNameController.text.trim().isNotEmpty) {
                        final actualProjectDir = Directory("$projectDir/${_projectNameController.text.trim()}");
                        if (!actualProjectDir.existsSync()) {
                          await actualProjectDir.create(recursive: true);
                        }
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) =>
                                EditorPage(rootDir: actualProjectDir.path, isCloned: true, isProject: true, languageDetails: null),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return SizeTransition(sizeFactor: animation, child: child);
                              },
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff5090c8),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      l10n.create,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsibleSection({
    required String title,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
    required AppTheme appTheme,
    int? itemCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    color: appTheme.selectScreenCardTextColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor,
                    fontSize: 18,
                    fontWeight: appTheme.isDark ? FontWeight.w400 : FontWeight.w500,
                  ),
                ),
                if (itemCount != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: appTheme.isDark 
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$itemCount',
                      style: TextStyle(
                        color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: child,
            );
          },
          child: isExpanded
              ? Padding(
                  key: const ValueKey('expanded'),
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('collapsed')),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return BlocBuilder<AppThemeBloc, AppThemeState>(
      builder: (context, appThemestate) {
        final appTheme = appThemestate.appTheme;
        return Scaffold(
          body: FutureBuilder<Directory>(
            future: _projectDirFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return AlertDialog(
                  title: Text(l10n.permissionDenied, style: TextStyle(color: Colors.grey[400], fontSize: 20)),
                  backgroundColor: const Color(0xff2b2b2b),
                  icon: const Icon(Icons.error_outline, size: 35),
                  iconColor: Colors.red[600],
                  actionsAlignment: MainAxisAlignment.center,
                  actions: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      child: Text(l10n.ok),
                    ),
                  ],
                );
              }

              _existingProjectsFuture ??= _getExistingProjects(snapshot.data!);

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 75),
                    projectTile(
                      l10n.newProject,
                      l10n.createNewProject,
                      const Icon(Icons.folder_special_rounded, color: Color(0xffffc928), size: 28),
                      appTheme.selectScreenCardsBg,
                      () => _showNewProjectDialog(context, appTheme),
                    ),
                    const SizedBox(height: 20),
                    
                    FutureBuilder<List<Directory>>(
                      future: _existingProjectsFuture,
                      builder: (context, projectsSnapshot) {
                        if (projectsSnapshot.connectionState == ConnectionState.waiting) {
                          return const SizedBox.shrink();
                        }
                        if (projectsSnapshot.hasError || !projectsSnapshot.hasData || projectsSnapshot.data!.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        
                        final projects = projectsSnapshot.data!;
                        return _buildCollapsibleSection(
                          title: l10n.yourProjects,
                          isExpanded: _yourProjectsExpanded,
                          onToggle: () => setState(() => _yourProjectsExpanded = !_yourProjectsExpanded),
                          itemCount: projects.length,
                          appTheme: appTheme,
                          children: projects.map((dir) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: projectTile(
                              path.basename(dir.path),
                              l10n.openExistingProject,
                              const Icon(Icons.folder, color: Color(0xff5090c8), size: 28),
                              appTheme.selectScreenCardsBg,
                              () {
                                Navigator.of(context).push(
                                  PageRouteBuilder(
                                    pageBuilder: (context, animation, secondaryAnimation) =>
                                      EditorPage(rootDir: dir.path, isCloned: true, isProject: true, languageDetails: null),
                                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                      return SizeTransition(sizeFactor: animation, child: child);
                                    },
                                  ),
                                );
                              },
                              trailing: IconButton.filledTonal(
                                visualDensity: VisualDensity(horizontal: 1, vertical: 1),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      backgroundColor: appTheme.isDark
                                        ? const Color(0xff2b2b2b)
                                        : const Color.fromARGB(255, 250, 250, 250),
                                      title: Text(
                                        l10n.areYouSureDeleteProject,
                                        style: TextStyle(
                                          color: appTheme.selectScreenCardTextColor,
                                          fontSize: 20
                                        ),
                                      ),
                                      content: Text(
                                        l10n.actionCannotBeUndone,
                                        style: TextStyle(
                                          color: appTheme.selectScreenCardTextColor.withAlpha(150),
                                          fontSize: 16
                                        ),
                                      ),
                                      actions: [
                                        ElevatedButton(
                                          onPressed: ()=> Navigator.of(context).pop(),
                                          style: ElevatedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            elevation: 2,
                                          ),
                                          child: Text(l10n.cancel)
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            dir.deleteSync(recursive: true);
                                            setState(() {
                                              _existingProjectsFuture = null;
                                            });
                                            Navigator.of(context).pop(true);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            elevation: 2,
                                          ),
                                          child: Text(l10n.delete, style: const TextStyle(color: Colors.white))
                                        )
                                      ],
                                    )
                                  );
                                },
                                icon: Icon(
                                  Icons.delete,
                                    color: Colors.red.withAlpha(180)
                                ),
                                style: ButtonStyle(
                                  backgroundColor: WidgetStatePropertyAll(appTheme.editorPageToolSelectedBgColor.withAlpha(170)),
                                  shape: WidgetStatePropertyAll(
                                    RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(10)),
                                      side: BorderSide(
                                        color: appTheme.selectScreenCardTextColor.withAlpha(100),
                                        width: 0.45
                                      )
                                    )
                                  ),
                                  elevation: WidgetStatePropertyAll(15),

                                ),
                              )
                            ),
                          )).toList(),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 10),
                    
                    (() {
                      final pts = projTemps(context);
                      return _buildCollapsibleSection(
                        title: l10n.projectTemplates,
                        isExpanded: _templatesExpanded,
                        onToggle: () => setState(() => _templatesExpanded = !_templatesExpanded),
                        itemCount: pts.length,
                        appTheme: appTheme,
                        children: pts.map(
                          (item) => projectTile(
                            item.title,
                            item.subtitle,
                            item.icon,
                            appTheme.selectScreenCardsBg,
                            (){
                              showDialog(
                                context: context,
                                builder: (ctx) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  child: Container(
                                    width: 320,
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: appTheme.isDark ? const Color(0xff2b2b2b) : const Color.fromARGB(255, 240, 240, 240),
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
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xffffc928).withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: item.icon,
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Text(
                                                "New Project",
                                                style: TextStyle(
                                                  color: appTheme.selectScreenCardTextColor,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 24),
                                        TextFormField(
                                          controller: _projectNameController,
                                          style: TextStyle(
                                            color: appTheme.selectScreenCardTextColor,
                                          ),
                                          cursorColor: const Color(0xff5090c8),
                                          decoration: InputDecoration(
                                            hintStyle: TextStyle(color: Colors.grey[500]),
                                            hintText: "Project name",
                                            filled: true,
                                            fillColor: appTheme.isDark
                                              ? Colors.white.withValues(alpha: 0.05)
                                              : Colors.black.withValues(alpha: 0.05),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(15),
                                              borderSide: const BorderSide(color: Color(0xff5090c8), width: 2),
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(15),
                                            ),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pop(),
                                              style: TextButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                              child: Text(
                                                "Cancel",
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            ElevatedButton(
                                              onPressed: () async {
                                                if(item is PlainTemplates){
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text(_generating ? l10n.generate : l10n.generated),
                                                      persist: true,
                                                      elevation: 50,
                                                    )
                                                  );
                                                  await item.generateContent(_projectNameController.text.trim());
                                                  setState(() {
                                                    _generating = false;
                                                    Future.delayed(
                                                      Duration(milliseconds: 500),
                                                      (){
                                                        if(context.mounted){
                                                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                                        } 
                                                      }
                                                    );
                                                  });
                                                  if(context.mounted){
                                                    final dir = Directory("$projectDir/${_projectNameController.text}");
                                                    Navigator.pop(context);
                                                    Navigator.of(context).push(
                                                      PageRouteBuilder(
                                                        pageBuilder: (context, animation, secondaryAnimation) =>
                                                          EditorPage(rootDir: dir.path, isCloned: true, isProject: true, languageDetails: null),
                                                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                                          return SizeTransition(sizeFactor: animation, child: child);
                                                        },
                                                      ),
                                                    );
                                                  }

                                                } else if(item is CLITemplates) {
                                                  final missing = _missingTemplateRequirements(item);
                                                  if (missing.isNotEmpty) {
                                                    await _showTemplatePrerequisiteDialog(context, appTheme, missing);
                                                    return;
                                                  }

                                                  Navigator.pop(context);
                                                  item.name = _projectNameController.text.trim();
                                                  await showDialog(
                                                    context: context,
                                                    builder: (ctx) => item.runCommand(),
                                                  );

                                                  if (item.openAfterCreate && context.mounted) {
                                                    final newDir = Directory("$projectDir/${_projectNameController.text.trim()}");
                                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                                      if (!context.mounted) return;
                                                      try {
                                                        Navigator.of(context).push(
                                                          PageRouteBuilder(
                                                            pageBuilder: (context, animation, secondaryAnimation) =>
                                                              EditorPage(rootDir: newDir.path, isCloned: true, isProject: true, languageDetails: null),
                                                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                                              return SizeTransition(sizeFactor: animation, child: child);
                                                            },
                                                          ),
                                                        );
                                                      } catch (e) {
                                                        if (!context.mounted) return;
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(content: Text(l10n.failedToOpenTheProject(e.toString()))),
                                                        );
                                                        debugPrint(e.toString());
                                                      }
                                                    });
                                                  }
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xff5090c8),
                                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                              child: const Text(
                                                "Create",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }
                          )
                        ).toList()
                      );
                    })(),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
