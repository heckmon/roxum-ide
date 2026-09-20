import 'dart:async';
import 'dart:convert';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:roxum/l10n/app_localizations.dart';
import 'bloc/repo_bloc/repo_bloc.dart';
import 'bloc/ui_bloc/ui_bloc.dart';
import 'ui/start_screen.dart';
import 'utils/functions.dart';
import 'utils/themes.dart';
import 'terminal/terminal.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await migrateSharedStorageRoots();
  final recent = await getRecent();
  final appTheme = await getAppTheme();
  final codeForgeConfig = await getCodeForgeConfig();
  final aiConfig = await getAiConfig();
  final modelSelected = await getModelSelected();
  final sshServerList = await SSHInfo.getSavedSSHServers();
  final termuxInfo = await TermuxCubit.getSavedTermuxInfo();

  runApp(
    MainApp(
      recent: recent,
      appTheme: appTheme,
      codeForgeConfig: codeForgeConfig,
      aiConfig: aiConfig,
      modelSelected: modelSelected,
      sshSServerList: sshServerList,
      termuxInfo: termuxInfo,
    )
  );
}

class MainApp extends StatefulWidget {
  final String recent, appTheme, codeForgeConfig, aiConfig, modelSelected;
  final List<SSHInfo> sshSServerList;
  final SSHPrivateKey? termuxInfo;
  const MainApp({
      super.key,
      required this.recent,
      required this.appTheme,
      required this.codeForgeConfig,
      required this.aiConfig,
      required this.modelSelected,
      required this.sshSServerList,
      required this.termuxInfo
    });

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  Timer? _navBarHideTimer;
  
  @override
  void initState() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );

    SystemChrome.setSystemUIChangeCallback((systemOverlaysAreVisible) async {
      if (systemOverlaysAreVisible) {
        _navBarHideTimer?.cancel();
        _navBarHideTimer = Timer(const Duration(seconds: 3), () {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: [SystemUiOverlay.top],
          );
        });
      }
    });
    
    super.initState();
  }

  @override
  void dispose() {
    _navBarHideTimer?.cancel();
    SystemChrome.setSystemUIChangeCallback(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ConfigBloc(codeForgeConfig: jsonDecode(widget.codeForgeConfig))),
        BlocProvider(create: (_) => FolderBloc()),
        BlocProvider(create: (_) => GitCommitBloc()),
        BlocProvider(create: (_) => RecentBloc(recent: jsonDecode(widget.recent))),
        BlocProvider(create: (_) => AppThemeBloc(appTheme: themeMap[widget.appTheme]!)),
        BlocProvider(create: (_) => WebViewBloc()),
        BlocProvider(create: (_) => MenuSearchBloc()),
        BlocProvider(create: (_) => DownloadManagerBloc()),
        BlocProvider(create: (_) => PackageCatalogCubit()),
        BlocProvider(create: (_) => GithubAuthCubit()),
        BlocProvider(create: (_) => ChatSessionBloc()..add(LoadChatSessions())),
        BlocProvider(create: (_) => GeneralBloc({"autoSave": jsonDecode(widget.codeForgeConfig)['autoSave'] as bool})),
        BlocProvider(create: (_) => CopilotBloc()),
        BlocProvider(create: (_) => TerminalSessionBloc(
          initialFontSize: ((){
            try {
              final raw = context.read<ConfigBloc>().state.codeForgeConfig['terminalFontSize'];
              if (raw is num) return raw.toDouble();
              if (raw is String) return double.tryParse(raw) ?? 14.0;
            } catch (_) {}
            return 14.0;
          })()
        )),
        BlocProvider(create: (context) => AIBloc(
          jsonDecode(widget.aiConfig),
          jsonDecode(widget.codeForgeConfig)['isAIEnabled'] as bool,
          jsonDecode(widget.modelSelected),
          jsonDecode(widget.codeForgeConfig)['manualCompletion'] as bool,
          copilotBloc: context.read<CopilotBloc>(),
        )),
        BlocProvider(create: (_) => CopilotChatBloc()),
        BlocProvider(create: (_) => LocalLlamaBloc()),
        BlocProvider(create: (_) => GgufDownloadCubit()),
        BlocProvider(create: (_) => SSHServersCubit(widget.sshSServerList)),
        BlocProvider(create: (_) => TermuxCubit(widget.termuxInfo)),
        BlocProvider(create: (_) => CurrentlySelectedTerminalCubit()),
        BlocProvider(create: (_) => SelectedRuntimeEnvironmentCubit()),
      ],
      child: BlocBuilder<AppThemeBloc, AppThemeState>(
        builder: (context, appThemeState) {
          context.read<GgufDownloadCubit>().onTaskCompleted = (task) async {
            final result = await GgufModel.registerGgufModelWithAI(task);
            if (context.mounted) {
              context.read<AIBloc>().add(AIConfigEvent(result.aiConfig));
              context.read<AIBloc>().add(ModelSelectEvent(result.modelSelected));
              context.read<GgufDownloadCubit>().markTaskRegistered(task.taskId);
            }
          };
          return MaterialApp(
            onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
            theme: ThemeData(
              progressIndicatorTheme: progressTheme,
              popupMenuTheme: appThemeState.appTheme.popupBtnTheme,
              scaffoldBackgroundColor: appThemeState.appTheme.scaffoldBg,
              appBarTheme: appThemeState.appTheme.appBarTheme,
              listTileTheme: appThemeState.appTheme.tileTheme,
              cardTheme: appThemeState.appTheme.cardTheme.data,
              textSelectionTheme: const TextSelectionThemeData(
                selectionHandleColor: Colors.blue,
              ),
            ),

            localizationsDelegates: AppLocalizations.localizationsDelegates,

            supportedLocales: AppLocalizations.supportedLocales,
            
            home: SafeArea(
              top: false,
              child: const StartScreen()
            ),
          );
        },
      ),
    );
  }
}
