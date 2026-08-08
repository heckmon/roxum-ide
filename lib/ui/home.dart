import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:roxum/l10n/app_localizations.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:roxum/bloc/repo_bloc/repo_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'about.dart';
import 'donation_page.dart';
import 'file_manager.dart';
import 'editor_page.dart';
import 'menu_screen.dart';
import 'project_screen.dart';
import 'downloads.dart';
import 'settings.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../terminal/terminal.dart';
import '../ui/contribute.dart';
import '../ui/github_page.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';
import '../utils/themes.dart';
import 'widgets.dart';

class SelectType extends StatefulWidget {
  const SelectType({super.key});
  @override
  State<SelectType> createState() => _SelectTypeState();
}

class _SelectTypeState extends State<SelectType> with WidgetsBindingObserver {
  final createFileController = TextEditingController();
  final _createFileKey = GlobalKey<FormState>();
  final _cloneRepoKey = GlobalKey<FormState>();
  AnimationStatus _terminalSelectionStatus = .dismissed;
  bool _didShowPackageUpdateToast = false;
  bool _didShowStorageMigrationToast = false;
  bool _checkingPendingSharedFile = false;
  int _pendingSharedFileRetryCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openPendingSharedFile();
      _maybeShowStorageMigrationNotice();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_openPendingSharedFile());
    }
  }

  Future<void> _openPendingSharedFile() async {
    if (_checkingPendingSharedFile) return;
    _checkingPendingSharedFile = true;

    try {
      final pendingFiles = await NativeChannel.consumePendingOpenFiles();
      if (!mounted) return;
      if (pendingFiles.isEmpty) {
        if (_pendingSharedFileRetryCount < 30) {
          _pendingSharedFileRetryCount++;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              unawaited(_openPendingSharedFile());
            }
          });
        } else {
          _pendingSharedFileRetryCount = 0;
        }
        return;
      }

      _pendingSharedFileRetryCount = 0;

      final imported = File(pendingFiles.first);
      if (!imported.existsSync()) return;

      final language = languages.firstWhere(
        (item) => item.extension.contains(
          path.extension(imported.path).replaceFirst('.', ''),
        ),
        orElse: () => languages[0],
      );

      if (!mounted) return;
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => EditorPage(
            languageDetails: language,
            rootDir: imported.parent.path,
            file: imported,
            isProject: false,
          ),
          transitionsBuilder: (
            context,
            animation,
            secondaryAnimation,
            child,
          ) {
            return SizeTransition(sizeFactor: animation, child: child);
          },
        ),
      );
    } finally {
      _checkingPendingSharedFile = false;
    }
  }

  Future<void> _maybeShowStorageMigrationNotice() async {
    if (_didShowStorageMigrationToast) return;
    _didShowStorageMigrationToast = true;
    final l10n = AppLocalizations.of(context)!;

    final prefs = await SharedPreferences.getInstance();
    final shouldShow = prefs.getBool(sharedStorageMigrationNoticeKey) ?? false;
    if (!mounted || !shouldShow) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.projectsFilesTemplatesSharedStorage),
        duration: const Duration(seconds: 4),
      ),
    );
    await prefs.setBool(sharedStorageMigrationNoticeKey, false);
  }

  Map<String, dynamic>? _normalizeRecentEntry(dynamic rawEntry) {
    if (rawEntry is Map &&
        rawEntry['type'] is String &&
        rawEntry['path'] is String) {
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    createFileController.dispose();
    super.dispose();
  }

  Future<void> _performClone(
    String projectDir,
    String repoUrl,
    String repoName,
    BuildContext context,
    StreamController<double> progressController,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final targetDir = Directory("$projectDir/$repoName");

    if (targetDir.existsSync()) {
      if (context.mounted) {
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.directoryAlreadyExists(repoName)),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 500));
        if (context.mounted) {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                EditorPage(
                  rootDir: targetDir.path,
                  isCloned: true,
                  isProject: true,
                  languageDetails: null,
                ),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SizeTransition(sizeFactor: animation, child: child);
              },
            ),
          );
        }
      }
      return;
    }

    try {
      await cloneRepo(projectDir, repoUrl, (progress) {
        progressController.add(progress);
      });

      if (context.mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => EditorPage(
              rootDir: Directory("$projectDir/$repoName").path,
              isCloned: true,
              isProject: true,
              languageDetails: null,
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return SizeTransition(sizeFactor: animation, child: child);
                },
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: context.read<AppThemeBloc>().state.appTheme.isDark
              ? const Color(0xff2b2b2b)
              : const Color.fromARGB(255, 240, 240, 240),
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    l10n.failedToCloneRepo,
                    style: TextStyle(
                      color: context
                        .read<AppThemeBloc>()
                        .state
                        .appTheme
                        .selectScreenCardTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.toString(),
                    style: TextStyle(
                      color: context
                        .read<AppThemeBloc>()
                        .state
                        .appTheme
                        .selectScreenCardTextColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(l10n.ok),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        progressController.close();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    context.read<GithubAuthCubit>().refresh();
    return BlocBuilder<AppThemeBloc, AppThemeState>(
      builder: (context, appThemestate) {
        return BlocListener<PackageCatalogCubit, PackageCatalogState>(
          listenWhen: (previous, current) =>
            !_didShowPackageUpdateToast &&
            !previous.hasUpdates &&
            current.hasUpdates,
          listener: (context, state) {
            _didShowPackageUpdateToast = true;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.packageUpdatesAvailable(state.totalUpdateCount)),
              ),
            );
          },
          child: Scaffold(
          resizeToAvoidBottomInset: false,
          drawer: Drawer(
            backgroundColor: appThemestate.appTheme.selectScreenDrawerBg,
            child: ListView(
              children: [
                drawerTile(
                  () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const Settings(),
                        transitionsBuilder: (context, animation, _, child) =>
                          SizeTransition(sizeFactor: animation, child: child),
                      ),
                    );
                  },
                  l10n.settings,
                  const Icon(
                    Icons.settings,
                    color: Colors.blueGrey,
                    size: 31.5,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 1.5),
                  child: drawerTile(
                    () {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => const ContributePage(),
                          transitionsBuilder: (context, animation, _, child) =>
                            SizeTransition(
                              sizeFactor: animation,
                              child: child,
                            ),
                        ),
                      );
                    },
                    l10n.contributeSourceCode,
                    FaIcon(
                      FontAwesomeIcons.githubAlt,
                      color: appThemestate.appTheme.isDark
                        ? Colors.grey
                        : const Color.fromARGB(255, 36, 36, 36),
                      size: 26.5,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: drawerTile(
                    () {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => const AboutPage(),
                          transitionsBuilder: (context, animation, _, child) =>
                            SizeTransition(
                              sizeFactor: animation,
                              child: child,
                            ),
                        ),
                      );
                    },
                    l10n.aboutRoxum,
                    Image.asset(
                      'assets/icons/about-512.png',
                      height: 25.5,
                      width: 25.5,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: drawerTile(
                    () => Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondAnimation) => const BuyMeCoffee(),
                        transitionsBuilder: (context, animation, _, child) => SizeTransition(sizeFactor: animation, child: child),
                      ),
                    ),
                    l10n.buyMeACoffee,
                    SvgPicture.asset(
                      width: 29,
                      height: 29,
                      'assets/icons/bmc-logo.svg',
                      colorFilter: const ColorFilter.mode(
                        Color(0xff4783b7),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 1.5),
                  child: drawerTile(
                    () async => await launchUrl(Uri.parse("https://heckmon.github.io/roxum-privacy-policy/")),
                    l10n.privacyPolicy,
                    Icon(
                      Icons.shield,
                      size: 26,
                      color: Colors.grey
                    )
                  ),
                )
              ],
            ),
          ),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: l10n.fileManager,
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => const FileManagerPage(),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return SizeTransition(
                          sizeFactor: animation,
                          child: child,
                        );
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.folder_copy_outlined, size: 30),
              ),
              Transform.scale(
                scale: 0.8,
                child: BlocBuilder<PackageCatalogCubit, PackageCatalogState>(
                  builder: (context, packageState) {
                    return IconButton(
                      tooltip: l10n.runtimes,
                      onPressed: () {
                        Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => DownloadManager(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SizeTransition(
                                sizeFactor: animation,
                                child: child,
                              );
                            },
                          ),
                        );
                      },
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.download, size: 35),
                          if (packageState.hasUpdates)
                            Positioned(
                              right: -2,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                constraints: const BoxConstraints(minWidth: 16),
                                child: Text(
                                  '${packageState.totalUpdateCount}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              BlocBuilder<SSHServersCubit, SSHServersState>(
                builder: (context, sshState) {
                  final sshServerList = sshState.serverList.where((server) => server.isConnected).toList();
                  return BlocBuilder<TermuxCubit, TermuxState>(
                    builder: (context, termuxState) {
                      final termuxInfo = termuxState.termInfo;
                      return BlocBuilder<CurrentlySelectedTerminalCubit, SelectedTerminalState>(
                        builder: (context, selectedTerminalState) {
                          int? currentlySelectedTerminalID = selectedTerminalState.currentlySelectedID;
                          bool isTermux = selectedTerminalState.isTermux;
                          final home = Directory(homeDir);
                          final appTheme = appThemestate.appTheme;
                          final cubitState = context.read<CurrentlySelectedTerminalCubit>();
                          return Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    PageRouteBuilder(
                                      pageBuilder: (context, animation, scondaryAnimation) =>
                                        SetupTerminal(
                                          projectDir: home.path,
                                          sshId: !isTermux ? currentlySelectedTerminalID : null,
                                          termuxId: isTermux ? currentlySelectedTerminalID : null,
                                        ),
                                      transitionsBuilder:(context, animation, secondaryAnimation, child,) {
                                        return SizeTransition(
                                          sizeFactor: animation,
                                          child: child,
                                        );
                                      },
                                    ),
                                  );
                                },
                                child: currentlySelectedTerminalID == null
                                  ? Padding(
                                    padding: const EdgeInsets.only(right: 2.5),
                                    child: Icon(Icons.terminal, size: 34),
                                  )
                                  : isTermux
                                    ? SvgPicture.asset(
                                      "assets/icons/Termux.svg",
                                      height: 30,
                                      width: 30
                                    )
                                    : Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Icon(
                                          Icons.cloud,
                                          size: 34,
                                        ),
                                        Positioned(
                                          bottom: 2,
                                          child: Icon(
                                            Icons.terminal,
                                            size: 23,
                                            color: appTheme.appBarTheme.backgroundColor
                                          ),
                                        ),
                                      ],
                                    )
                              ),
                              if(sshServerList.isNotEmpty || (termuxInfo != null && termuxInfo.isConnected)) MenuAnchor(
                                style: MenuStyle(
                                  backgroundColor: WidgetStatePropertyAll(appTheme.selectScreenCardsBg),
                                  shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: .circular(6)))
                                ),
                                animated: true,
                                onAnimationStatusChanged: (status) {
                                  _terminalSelectionStatus = status;
                                },
                                menuChildren: [
                                  MenuItemButton(
                                    onPressed: () => cubitState.updateId(null, false),
                                    leadingIcon: Icon(
                                      Icons.terminal,
                                      color: appTheme.selectScreenCardTextColor
                                    ),
                                    trailingIcon: currentlySelectedTerminalID == null ? Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 16,
                                      )
                                      : null,
                                    child: Text(
                                      "Built-in terminal",
                                      style: TextStyle(
                                        color: appTheme.selectScreenCardTextColor
                                      )
                                    ),
                                  ),
                                  ...sshServerList.map((server) {
                                    return MenuItemButton(
                                      onPressed: () => cubitState.updateId(server.id, false),
                                      leadingIcon: Padding(
                                        padding: const EdgeInsets.only(left: 3),
                                        child: FaIcon(
                                          FontAwesomeIcons.server,
                                          color: appTheme.selectScreenCardTextColor,
                                          size: 20
                                        ),
                                      ),
                                      trailingIcon: currentlySelectedTerminalID == server.id
                                        ? Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 16
                                        )
                                        : null,
                                      child: Text(
                                        server.name,
                                        style: TextStyle(
                                          color: appTheme.selectScreenCardTextColor
                                        )
                                      ),
                                    );
                                  }),
                          
                                  if(termuxInfo != null && termuxInfo.isConnected)
                                  MenuItemButton(
                                    onPressed: () => cubitState.updateId(termuxInfo.id, true),
                                    leadingIcon: SvgPicture.asset(
                                      "assets/icons/Termux.svg",
                                      height: 20,
                                      width: 20
                                    ),
                                    trailingIcon: currentlySelectedTerminalID == termuxInfo.id ? Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 16
                                      )
                                      : null,
                                    child: Text(
                                      termuxInfo.name,
                                      style: TextStyle(
                                        color: appTheme.selectScreenCardTextColor
                                      )
                                    ),
                                  )
                                ],
                                builder: (context, controller, child) => InkWell(
                                  onTap: () {
                                    if(_terminalSelectionStatus.isForwardOrCompleted){
                                      controller.close();
                                    } else {
                                      controller.open();
                                    }
                                  },
                                  child: Icon(
                                    Icons.arrow_drop_down_rounded,
                                    color: appTheme.selectScreenCardTextColor
                                  )
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
              IconButton(
                tooltip: l10n.appTheme,
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  final String? current = prefs.getString("savedAppTheme");
                  if (current == "dark") {
                    if (context.mounted) {
                      context.read<AppThemeBloc>().add(
                        AppThemeEvent(appTheme: LightTheme()),
                      );
                    }
                    prefs.setString("savedAppTheme", "light");
                  } else {
                    if (context.mounted) {
                      context.read<AppThemeBloc>().add(
                        AppThemeEvent(appTheme: DarkTheme()),
                      );
                    }
                    prefs.setString("savedAppTheme", "dark");
                  }
                },
                icon: appThemestate.appTheme.appThemeIcon,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  tooltip: l10n.github,
                  onPressed: () => Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => GithubPage(),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return SizeTransition(
                          sizeFactor: animation,
                          child: child,
                        );
                      },
                    ),
                  ),
                  icon: BlocBuilder<GithubAuthCubit, GithubAuthState>(
                    builder: (context, authState) {
                      final loggedIn = authState.isSignedIn;
                      final user = authState.user;

                      if (loggedIn && user != null) {
                        return Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: appThemestate.appTheme.scaffoldBg,
                              width: 1.5,
                            ),
                          ),
                          child: ClipOval(
                            child: Image.network(
                              user.avatarUrl,
                              width: 34,
                              height: 34,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 34,
                                  height: 34,
                                  color: const Color(0xff238636),
                                  child: const Icon(
                                    Icons.person,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      } else {
                        return const FaIcon(FontAwesomeIcons.github);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 30, top: 18),
                  child: Text(
                    l10n.start,
                    style: TextStyle(
                      color: appThemestate.appTheme.selectScreenCardTextColor,
                      fontSize: 35,
                      fontWeight: appThemestate.appTheme.isDark
                          ? FontWeight.w300
                          : FontWeight.w400,
                    ),
                  ),
                ),
                fileTiles(
                  () {
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        backgroundColor: Colors.transparent,
                        child: Container(
                          width: 350,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: appThemestate.appTheme.isDark
                                ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                                : [const Color.fromARGB(255, 250, 250, 250), const Color.fromARGB(255, 240, 240, 240)],
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
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xff5090c8,
                                      ).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const FaIcon(
                                      FontAwesomeIcons.fileCirclePlus,
                                      color: Color(0xff5090c8),
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      l10n.createNewFile,
                                      style: TextStyle(
                                        color: appThemestate.appTheme.selectScreenCardTextColor,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Form(
                                key: _createFileKey,
                                child: TextFormField(
                                  style: TextStyle(
                                    color: appThemestate.appTheme.selectScreenCardTextColor,
                                  ),
                                  cursorColor: const Color(0xff5090c8),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return l10n.validFilenameRequired;
                                    }
                                    return null;
                                  },
                                  controller: createFileController,
                                  decoration: InputDecoration(
                                    hintStyle: TextStyle(
                                      color: Colors.grey[500],
                                    ),
                                    hintText: l10n.filenamePlaceholder,
                                    filled: true,
                                    fillColor: appThemestate.appTheme.isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.black.withValues(alpha: 0.05),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(15),
                                      borderSide: const BorderSide(
                                        color: Color(0xff5090c8),
                                        width: 2,
                                      ),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
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
                                      _createFileKey.currentState!.validate();
                                      if (createFileController
                                          .text
                                          .isNotEmpty) {
                                        final file = await createFile(
                                          createFileController.text,
                                          filesDir,
                                          context,
                                        );
                                        if (context.mounted && file != null) {
                                          Navigator.of(context).pop();
                                          Navigator.of(context).push(
                                            PageRouteBuilder(
                                              pageBuilder:
                                                (context, animation, secondaryAnimation,) => EditorPage(
                                                  rootDir: file.parent.path,
                                                  isProject: false,
                                                  file: file,
                                                  languageDetails: languages.firstWhere(
                                                    (language) => language.extension.contains(
                                                      path.extension(file.path,).replaceFirst(".","")),
                                                      orElse: () => languages[0]),
                                                ),
                                              transitionsBuilder:(context, animation, secondaryAnimation, child) {
                                                return SizeTransition(
                                                  sizeFactor: animation,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xff5090c8),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: Text(
                                      l10n.create,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
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
                  },
                  l10n.newFileTitle,
                  const FaIcon(FontAwesomeIcons.fileCirclePlus),
                  appThemestate.appTheme.isDark,
                ),
                fileTiles(
                  () async {
                    if (context.mounted) {
                      final file = await pickFile();
                      if (file != null) {
                        final language = languages.firstWhere(
                          (language) => language.extension.contains(
                            path.extension(file.path).replaceFirst(".", ""),
                          ),
                          orElse: () => languages[0],
                        );
                        if (context.mounted) {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) =>
                                EditorPage(
                                  languageDetails: language,
                                  rootDir: file.parent.path,
                                  file: file,
                                  isProject: false,
                                ),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return SizeTransition(
                                  sizeFactor: animation,
                                  child: child,
                                );
                              },
                            ),
                          );
                        }
                    } else {
                      if(context.mounted) {
                        showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          backgroundColor: Colors.transparent,
                          child: Container(
                            width: 350,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: appThemestate.appTheme.isDark
                                  ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                                  : [const Color.fromARGB(255, 250, 250, 250), const Color.fromARGB(255, 240, 240, 240)],
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
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                  child: const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  l10n.failedToOpenFile,
                                  style: TextStyle(
                                    color: appThemestate.appTheme.selectScreenCardTextColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.selectedFileCouldNotBeOpened,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
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
                                  child: const Text(
                                    'OK',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      }
                    }
                  }
                  }, l10n.openFile,
                  const FaIcon(FontAwesomeIcons.fileImport),
                  appThemestate.appTheme.isDark,
                ),
                fileTiles(
                  () async {
                    final dir = await pickDir();
                    if (dir != null) {
                      if (dir.existsSync()) {
                        if (context.mounted) {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                  EditorPage(
                                    rootDir: dir.path,
                                    isCloned: false,
                                    isProject: true,
                                    languageDetails: null,
                                  ),
                              transitionsBuilder:(context, animation, secondaryAnimation, child,) {
                                return SizeTransition(
                                  sizeFactor: animation,
                                  child: child,
                                );
                              },
                            ),
                          );
                        }
                      }
                    } else {
                      if (context.mounted) {
                        showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          backgroundColor: Colors.transparent,
                          child: Container(
                            width: 350,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: appThemestate.appTheme.isDark
                                  ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                                  : [const Color.fromARGB(255, 250, 250, 250), const Color.fromARGB(255, 240, 240, 240)],
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
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                  child: const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  l10n.failedToOpenFolder,
                                  style: TextStyle(
                                    color: appThemestate.appTheme.selectScreenCardTextColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.selectedFolderCouldNotBeOpened,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
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
                                  child: const Text(
                                    "OK",
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  }},
                  l10n.openFolder,
                  const FaIcon(FontAwesomeIcons.solidFolderOpen),
                  appThemestate.appTheme.isDark,
                ),
                fileTiles(
                  () {
                    showDialog(
                      context: context,
                      builder: (_) {
                        final cloneController = TextEditingController();
                        return Dialog(
                          backgroundColor: Colors.transparent,
                          child: Container(
                            width: 400,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: appThemestate.appTheme.isDark
                                  ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                                  : [const Color.fromARGB(255, 250, 250, 250), const Color.fromARGB(255, 240, 240, 240)],
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
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xff5090c8).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.file_download_outlined,
                                        color: Color(0xff5090c8),
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        l10n.cloneRepo,
                                        style: TextStyle(
                                          color: appThemestate.appTheme.selectScreenCardTextColor,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.enterRepositoryUrl,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Form(
                                  key: _cloneRepoKey,
                                  child: TextFormField(
                                    style: TextStyle(
                                      color: appThemestate.appTheme.selectScreenCardTextColor,
                                    ),
                                    cursorColor: const Color(0xff5090c8),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return l10n.validRepositoryUrlRequired;
                                      }
                                      return null;
                                    },
                                    decoration: InputDecoration(
                                      hintStyle: TextStyle(
                                        color: Colors.grey[500],
                                      ),
                                      hintText: l10n.repositoryUrlPlaceholder,
                                      filled: true,
                                      fillColor: appThemestate.appTheme.isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black.withValues(alpha: 0.05),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(15),
                                        borderSide: const BorderSide(
                                          color: Color(0xff5090c8),
                                          width: 2,
                                        ),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 16,
                                          ),
                                    ),
                                    controller: cloneController,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                                        if (!_cloneRepoKey.currentState!.validate()) return;
                                        final repoUrl = cloneController.text.trim();
                                        final repoName = extractRepoName(repoUrl,);
                                        Navigator.of(context).pop();
                                        final progressController = StreamController<double>.broadcast();
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (_) => Dialog(
                                            backgroundColor: Colors.transparent,
                                            child: Container(
                                              width: 350,
                                              padding: const EdgeInsets.all(24),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: appThemestate.appTheme.isDark
                                                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                                                    : [const Color.fromARGB(255, 250, 250, 250), const Color.fromARGB(255, 240, 240, 240)],
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
                                              child: StreamBuilder<double>(
                                                stream: progressController.stream,
                                                initialData: 0.0,
                                                builder: (context, snapshot) {
                                                  final progress = snapshot.data ?? 0.0;
                                                  return Column(
                                                    mainAxisSize:MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.all(16),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xff5090c8).withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(50),
                                                        ),
                                                        child: const Icon(
                                                          Icons.file_download_outlined,
                                                          color: Color(0xff5090c8),
                                                          size: 32,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 20,
                                                      ),
                                                      Text(
                                                        l10n.cloningRepository,
                                                        style: TextStyle(
                                                          color: appThemestate.appTheme.selectScreenCardTextColor,
                                                          fontSize: 18,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        l10n.cloningMayTakeTime,
                                                        style: TextStyle(
                                                          color: Colors.grey[600],
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 24,
                                                      ),
                                                      LinearPercentIndicator(
                                                        percent: progress,
                                                        progressColor: const Color(0xff5090c8),
                                                        backgroundColor: appThemestate.appTheme.isDark
                                                          ? Colors.white.withValues(alpha: 0.1)
                                                          : Colors.black.withValues(alpha: 0.1),
                                                        barRadius: const Radius.circular(20),
                                                        lineHeight: 8,
                                                        trailing: Padding(
                                                          padding: const EdgeInsets.only(left: 10),
                                                          child: Text(
                                                            "${(progress * 100).toStringAsFixed(1)}%",
                                                            style: TextStyle(
                                                              color: appThemestate.appTheme.selectScreenCardTextColor,
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        );

                                        progressController.add(0.0);

                                        await _performClone(
                                          projectDir,
                                          repoUrl,
                                          repoName,
                                          context,
                                          progressController,
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xff5090c8),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        elevation: 2,
                                      ),
                                      child: const Text(
                                        'Clone',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                  val: 4,
                  l10n.openRepository,
                  SvgPicture.asset(
                    'assets/icons/code-branch-solid.svg',
                    height: 28,
                    width: 28,
                    colorFilter: const ColorFilter.mode(
                      Color.fromARGB(255, 29, 107, 176),
                      BlendMode.srcIn,
                    ),
                  ),
                  appThemestate.appTheme.isDark,
                ),
                const SizedBox(height: 30),
                Align(
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      InkWell(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(15),
                        ),
                        radius: 5,
                        onTap: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      const ProjectScreen(),
                              transitionsBuilder:
                                  (
                                    context,
                                    animation,
                                    secondaryAnimation,
                                    child,
                                  ) {
                                    return SizeTransition(
                                      sizeFactor: animation,
                                      child: child,
                                    );
                                  },
                            ),
                          );
                        },
                        child: SizedBox(
                          height: 60,
                          width: 320,
                          child: Card(
                            color: appThemestate.appTheme.selectScreenCardsBg,
                            child: Align(
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FaIcon(
                                    FontAwesomeIcons.folderTree,
                                    color: appThemestate
                                      .appTheme
                                      .selectScreenCardTextColor,
                                  ),
                                  const SizedBox(width: 12.5),
                                  Text(
                                    l10n.projects,
                                    style: TextStyle(
                                      fontSize: 16.5,
                                      color: appThemestate
                                        .appTheme
                                        .selectScreenCardTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      InkWell(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(15),
                        ),
                        radius: 5,
                        onTap: () {
                          Navigator.of(context).push(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => const MenuScreen(),
                              transitionsBuilder:(context, animation, secondaryAnimation, child) {
                                return SizeTransition(
                                  sizeFactor: animation,
                                  child: child,
                                );
                              },
                            ),
                          );
                        },
                        child: SizedBox(
                          height: 60,
                          width: 320,
                          child: Card(
                            color: appThemestate.appTheme.selectScreenCardsBg,
                            child: Align(
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FaIcon(
                                    FontAwesomeIcons.fileCode,
                                    color: appThemestate.appTheme.selectScreenCardTextColor,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    l10n.openTemplate,
                                    style: TextStyle(
                                      color: appThemestate.appTheme.selectScreenCardTextColor,
                                      fontSize: 16.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.recent,
                        style: TextStyle(
                          color: appThemestate.appTheme.selectScreenCardTextColor,
                          fontWeight: appThemestate.appTheme.isDark
                            ? FontWeight.w300
                            : FontWeight.w400,
                          fontSize: 35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      BlocBuilder<RecentBloc, RecentState>(
                        builder: (context, recentState) {
                          final List<Map<String, dynamic>> recentData =
                            recentState.recent
                              .map(_normalizeRecentEntry)
                              .whereType<Map<String, dynamic>>()
                              .toList();
                          return recentData.isEmpty
                            ? Text(
                              l10n.noRecentActivity,
                                style: TextStyle(
                                  color: appThemestate.appTheme.selectScreenCardTextColor,
                                  fontWeight: appThemestate.appTheme.isDark
                                    ? FontWeight.w300
                                    : FontWeight.w500,
                                  fontSize: 18,
                                ),
                              )
                            : SizedBox(
                                width: 350,
                                child: Center(
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: recentData.length,
                                    itemBuilder: (context, index) {
                                      final currentEntry = recentData[index];
                                      final String entryType = currentEntry['type'] as String? ?? 'file';
                                      final String entryPath = currentEntry['path'] as String? ?? '';
                                      final String rootDir = currentEntry['rootDir'] as String?
                                        ?? (entryType == 'project' ? entryPath : path.dirname(entryPath));
                                      final bool isProject = entryType == 'project';
                                      final bool exists = isProject
                                        ? Directory(entryPath).existsSync()
                                        : File(entryPath).existsSync();
                                      return Card(
                                        child: ListTile(
                                          textColor: appThemestate.appTheme.selectScreenCardTextColor,
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(15),
                                            ),
                                          ),
                                          onTap: () {
                                            if (!exists) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    isProject
                                                      ? l10n.projectNotFound
                                                      : l10n.fileNotFound,
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                  
                                            if (isProject) {
                                              Navigator.of(context).push(
                                                PageRouteBuilder(
                                                  pageBuilder:(context, animation, secondaryAnimation) => EditorPage(
                                                    rootDir: entryPath,
                                                    isCloned: true,
                                                    isProject: true,
                                                    languageDetails: null,
                                                  ),
                                                  transitionsBuilder:(context, animation, secondaryAnimation, child,) {
                                                    return SizeTransition(
                                                      sizeFactor:
                                                          animation,
                                                      child: child,
                                                    );
                                                  },
                                                ),
                                              );
                                              return;
                                            }
                                  
                                            Navigator.of(context).push(
                                              PageRouteBuilder(
                                                pageBuilder: (context, animation, secondaryAnimation) => EditorPage(
                                                  file: File(entryPath),
                                                  rootDir: rootDir,
                                                  languageDetails: (() {
                                                    final matchingLang = languages.where(
                                                      (lang) => lang.extension.contains(
                                                        path.extension(entryPath).toLowerCase().replaceFirst(".",""))).toList();
                                                    if (matchingLang.isNotEmpty) return matchingLang[0];
                                                    return Language(
                                                      name: "Unknown",
                                                      extension: ["null"],
                                                      details: "Unknown language",
                                                      language: unknown,
                                                      helloWorld: "Unknown type of file",
                                                      icon: null
                                                    );
                                                  })(),
                                                  isProject: false,
                                                ),
                                                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                                  return SizeTransition(
                                                    sizeFactor: animation,
                                                    child: child,
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                          title: Text(
                                            exists
                                              ? path.basename(entryPath)
                                              : "${path.basename(entryPath)} - ${isProject ? l10n.projectNotFound : l10n.fileNotFound}",
                                            style: const TextStyle(
                                              fontSize: 17,
                                            ),
                                          ),
                                          subtitle: Text(
                                            rootDir,
                                            style: TextStyle(
                                              color:
                                                appThemestate.appTheme.isDark
                                                ? Colors.grey
                                                : Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                          leading: (() {
                                            if (isProject) {
                                              return const Icon(
                                                Icons.folder_open_rounded,
                                                color: Color(0xff5090c8),
                                              );
                                            }
                                            final matchingLang = languages.where(
                                              (lang) =>lang.extension.contains(
                                                path.extension(entryPath,).toLowerCase().replaceFirst(".",""))).toList();
                                            if (matchingLang.isNotEmpty) return matchingLang[0].icon;
                                            return langtxt.icon;
                                          })(),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
      },
    );
  }
}
