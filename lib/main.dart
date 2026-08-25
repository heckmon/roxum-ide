import 'dart:convert';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
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

class MainApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ConfigBloc(codeForgeConfig: jsonDecode(codeForgeConfig))),
        BlocProvider(create: (_) => FolderBloc()),
        BlocProvider(create: (_) => GitCommitBloc()),
        BlocProvider(create: (_) => RecentBloc(recent: jsonDecode(recent))),
        BlocProvider(create: (_) => AppThemeBloc(appTheme: themeMap[appTheme]!)),
        BlocProvider(create: (_) => WebViewBloc()),
        BlocProvider(create: (_) => MenuSearchBloc()),
        BlocProvider(create: (_) => DownloadManagerBloc()),
        BlocProvider(create: (_) => PackageCatalogCubit()),
        BlocProvider(create: (_) => GithubAuthCubit()),
        BlocProvider(create: (_) => ChatSessionBloc()..add(LoadChatSessions())),
        BlocProvider(create: (_) => GeneralBloc({"autoSave": jsonDecode(codeForgeConfig)['autoSave'] as bool})),
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
          jsonDecode(aiConfig),
          jsonDecode(codeForgeConfig)['isAIEnabled'] as bool,
          jsonDecode(modelSelected),
          jsonDecode(codeForgeConfig)['manualCompletion'] as bool,
          copilotBloc: context.read<CopilotBloc>(),
        )),
        BlocProvider(create: (_) => CopilotChatBloc()),
        BlocProvider(create: (_) => LocalLlamaBloc()),
        BlocProvider(create: (_) => GgufDownloadCubit()),
        BlocProvider(create: (_) => SSHServersCubit(sshSServerList)),
        BlocProvider(create: (_) => TermuxCubit(termuxInfo)),
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
