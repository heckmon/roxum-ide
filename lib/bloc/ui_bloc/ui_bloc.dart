import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:bloc/bloc.dart';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_downloader/flutter_file_downloader.dart';
import 'package:http/http.dart' as http;
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roxum/utils/constants.dart';
import '../../utils/ai.dart';
import '../../utils/agentic_tool_catalog.dart';
import '../../utils/copilot_chat.dart';
import '../../utils/copilot_lsp.dart';
import '../../utils/functions.dart';
import '../../utils/languages.dart';
import '../../utils/package_catalog.dart';
import '../../utils/themes.dart';

part 'ui_event.dart';
part 'ui_state.dart';

class StackBloc extends Bloc<StackIndexChange, StackState> {
  StackBloc() : super(const StackState(stackIndex: 0)) {
    on<StackIndexChange>((event, emit)=>emit(StackState(stackIndex: event.stackValue)));
  }
}

class ConfigBloc extends Bloc<UiEvent, ConfigState>{
  final Map<String, dynamic> codeForgeConfig;
  ConfigBloc({
    required this.codeForgeConfig
  })
    :super(
      ConfigState(
        fontSize: 15,
        codeForgeConfig: codeForgeConfig
      )
    ){
    on<SetFontSize>((event, emit)=>emit(state.copyWith(fontSize: event.fontSize)));
    on<ChangeConfigEvent>((event, emit) => emit(state.copyWith(codeForgeConfig: event.codeForgeConfig)));
  }
}

class GeneralBloc extends Bloc<GeneralEvent, GeneralState> {
  final Map<String, dynamic> generalSettings;
  GeneralBloc(this.generalSettings) : super(GeneralState(generalSettings: generalSettings)) {
    on<GeneralEvent>((event, emit) => emit(GeneralState(generalSettings: event.generalSettings)));
  }
}

class MenuSearchBloc extends Bloc<Search, MenuSearchState>{
  MenuSearchBloc():super(const MenuSearchState(searchedLangs: <Card>[])){
    on<Search>((event, emit)=>emit(MenuSearchState(searchedLangs: event.searchedLangs)));
  }
}

class FindWordBloc extends Bloc<FindWord, FindWordState>{
  FindWordBloc():super(
    const FindWordState(
      word: '',
      matchCase: false,
      matchWholeWord: false,
      isRegex: false
    )
  ){
    on<FindWord>((event, emit)=>emit(
      FindWordState(
        word: event.word,
        matchCase: event.matchCase,
        matchWholeWord: event.matchWholeWord,
        isRegex: event.isRegex
      )
    ));
  }
}

class WebViewBloc extends Bloc<UiEvent, WebViewState>{
  WebViewBloc():super(const WebViewState(isMobile: true,isConsole: true)){
    on<SetViewPort>((event, emit)=>emit(state.copyWith(isMobile: event.isMobile)));
    on<EnableConsole>((event, emit)=>emit(state.copyWith(isConsole: event.isConsole)));
  }
}

class ApiBloc extends Bloc<RestEvent, ApiState>{
  ApiBloc():super(const ApiState(method: "GET",data: null, url: null, params: {}, headers: {}, body: {})){
    on<ApiEvent>((event, emit)=>emit(state.copyWith(method: event.method)));
    on<GetParams>((event, emit)=>emit(state.copyWith(params: event.params)));
    on<GetHeaders>((event, emit)=>emit(state.copyWith(headers: event.headers)));
    on<GetBody>((event, emit)=>emit(state.copyWith(body: event.body)));
    on<GetUrl>((event, emit)=>emit(state.copyWith(url: event.url)));
    on<GotApiData>((event, emit)=>emit(state.copyWith(data: event.data)));
  }
}

class FolderBloc extends Cubit<FolderState> {
  FolderBloc() : super(FolderState({}));

  void toggleFolder(String dirPath) {
    final currentState = state.folderStates;
    final isUnfolded = currentState[dirPath] ?? false;
    final nextUnfolded = !isUnfolded;
    emit(
      state.copyWith(
        folderStates: {...currentState, dirPath: nextUnfolded},
        lastUnfoldedFolderPath: nextUnfolded
            ? dirPath
            : state.lastUnfoldedFolderPath,
      ),
    );
  }

  void setAllFoldersExpanded(List<String> dirPaths, bool expanded) {
    final currentState = state.folderStates;
    final newStates = Map<String, bool>.from(currentState);
    for (final path in dirPaths) {
      newStates[path] = expanded;
    }
    emit(
      state.copyWith(
        folderStates: newStates,
        clearLastUnfoldedFolderPath: !expanded,
      ),
    );
  }
}

class RecentBloc extends Bloc<RecentEvent, RecentState>{
  final List<dynamic> recent;
  RecentBloc({required this.recent}) : super(RecentState(recent: recent)){
    on<RecentEvent>((event, emit) => emit(RecentState(recent: event.recent)));
  }
}

class AppThemeBloc extends Bloc<AppThemeEvent, AppThemeState>{
  final AppTheme appTheme;
  AppThemeBloc({required this.appTheme}):super(AppThemeState(appTheme: appTheme)){
    on<AppThemeEvent>((event, emit) => emit(AppThemeState(appTheme: event.appTheme)));
  }
}

class ActiveEditorBloc extends Bloc<EditorEvent, ActiveEditorState>{
  final String rootDir;
  final Map<String, dynamic> config;
  static final Map<String, LspConfig?> _globalLspConfigs = {};
  static final Map<String, Future<LspConfig?>> _lspStartupFutures = {};
  final Map<String, LspConfig?> _lspConfigs = _globalLspConfigs;
  Map<String, LspConfig?> get sharedLspConfigs => _lspConfigs;

  static String buildLspCacheKey({
    required String workspacePath,
    required String languageId,
  }) {
    final canonicalWorkspace = Directory(workspacePath).absolute.path;
    return '${canonicalWorkspace.toLowerCase()}::${languageId.toLowerCase()}';
  }

  Future<LspConfig?> getOrStartSharedLspConfig({
    required String languageId,
    required String ext,
    required String? executable,
    required List<String> args,
    LspClientCapabilities? capabilities,
  }) async {
    if (!isLspServerAvailable(ext: ext, executable: executable, args: args)) {
      return null;
    }

    final key = buildLspCacheKey(
      workspacePath: rootDir,
      languageId: languageId,
    );

    final existing = _lspConfigs[key];
    if (existing != null) {
      return existing;
    }

    final pending = _lspStartupFutures[key];
    if (pending != null) {
      return pending;
    }

    final startup = startLspServer(
      ext: ext,
      executable: executable,
      args: args,
      workspacePath: rootDir,
      langId: languageId,
      capabilities: capabilities,
    ).then((config) {
      _lspConfigs[key] = config;
      return config;
    }).whenComplete(() {
      _lspStartupFutures.remove(key);
    });

    _lspStartupFutures[key] = startup;
    return startup;
  }

  ActiveEditorBloc(this.rootDir, this.config):super(ActiveEditorState([])){
    on<ActiveEditorEvent>((event, emit) => emit(ActiveEditorState(event.activeEditors)));

    on<OpenRecentActiveEditor>((event, emit) async {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString("projects");
      final Map<String, dynamic> recentEditors = jsonDecode(stored ?? "{}");
      final list = (recentEditors[rootDir] as List<dynamic>?)?.map((e) => e as Map<String, dynamic>) ?? [];
      final editors = <ActiveEditor>[];
      for (final editorJson in list) {
        final lang = languages.singleWhere((lang) => lang.name == editorJson["lang"]);
        final filePath = editorJson["file"]?.toString() ?? '';
        final isPreviewFile = filePath.isNotEmpty && isPreviewFilePath(filePath);
        LspConfig? lspConfig;
        if (!isPreviewFile) {
          final languageId = lspLanguageIdForFile(
            language: lang,
            filePath: filePath,
          );
          final key = buildLspCacheKey(
            workspacePath: rootDir,
            languageId: languageId,
          );
          if (config['enableLSP'] && _lspConfigs[key] == null) {
            _lspConfigs[key] = await getOrStartSharedLspConfig(
              languageId: languageId,
              ext: lspServerExtForFilePath(filePath),
              executable: lang.lspExecutable,
              args: lang.args ?? [],
            );
          }
          lspConfig = _lspConfigs[key];
        }
        final controller = CodeForgeController(lspConfig: lspConfig)
          ..text = isPreviewFile ? '' : editorJson["text"];
        if (isPreviewFile) {
          controller.readOnly = true;
        }

        if (!isPreviewFile) {
          final canonicalPath = File(editorJson["file"]).absolute.path;
          final pendingEdit = await PendingEditFile.getForFile(canonicalPath);
          if (pendingEdit != null && pendingEdit.editHunks.isNotEmpty) {
            pendingEdit.applyDecorations(controller);
          }
        }

        final editor = ActiveEditor(
          file: File(editorJson["file"]),
          controller: controller,
          languageDetails: lang,
          undoRedoController: UndoRedoController(),
          findController: isPreviewFile ? null : FindController(controller),
          hscroll: ScrollController(initialScrollOffset: editorJson["hscroll"] ?? 0.0),
          vscroll: ScrollController(initialScrollOffset: editorJson["vscroll"] ?? 0.0),
          isActive: editorJson["isActive"],
          customTitle: editorJson["customTitle"]
        );
        editors.add(editor);
      }
      emit(ActiveEditorState(editors));
    });

    on<CloseActiveEditor>((event, emit) async {
      final prefs = await SharedPreferences.getInstance();
      final projState = state.activeEditors.map((editor) => editor.toJsonMap()).toList();
      final newData = {
        rootDir: projState
      };
      final alreadyStored = prefs.getString("projects");
      final data = jsonDecode(alreadyStored ?? "{}") as Map<String, dynamic>;
      data.addAll(newData);
      prefs.setString("projects", jsonEncode(data));
    });
  }
}

class AIBloc extends Bloc<AIEvent, AIState> {
  final Map<String, dynamic> config, modelSelected;
  final bool isEnabled, showSuggestionOntap;
  final CopilotBloc? copilotBloc;
  AIBloc(
      this.config,
      this.isEnabled,
      Map<String, dynamic> modelSelectedInput,
      this.showSuggestionOntap,
      {this.copilotBloc}
    ) : modelSelected = (() {
          if (copilotBloc != null && copilotBloc.state.status == CopilotStatus.signedIn) {
            final ms = Map<String, dynamic>.from(modelSelectedInput);
            if (ms['code'] == null || ms['code'] == '') {
              ms['code'] = 'copilot';
            }
            return ms;
          }
          return Map<String, dynamic>.from(modelSelectedInput);
        })(),
        super(AIState(
          config,
          isEnabled,
          (() {
            final ms = Map<String, dynamic>.from(modelSelectedInput);
            if (copilotBloc != null && copilotBloc.state.status == CopilotStatus.signedIn) {
              if (ms['code'] == null || ms['code'] == '') ms['code'] = 'copilot';
            }
            return ms;
          })(),
          showSuggestionOntap,
        )) {
    on<AIConfigEvent>((event, emit) => emit(state.copyWith(config: event.config)));
    on<AIEnableEvent>((event, emit) => emit(state.copyWith(isEnabled: event.isEnabled)));
    on<ModelSelectEvent>((event, emit) => emit(state.copyWith(modelSelected: event.modelSelected)));
    on<AIModeEvent>((event, emit) => emit(state.copyWith(showSuggestionOntap: event.showSuggestionOntap)));

    copilotBloc?.stream.listen((copilotState) {
      try {
        final status = copilotState.status;
        if (status == CopilotStatus.signedIn) {
          final ms = Map<String, dynamic>.from(state.modelSelected);
          if (ms['code'] == null || ms['code'] == '') {
            ms['code'] = 'copilot';
            add(ModelSelectEvent(ms));
          }
        } else {
          final ms = Map<String, dynamic>.from(state.modelSelected);
          if (ms['code'] == 'copilot') {
            ms.remove('code');
            add(ModelSelectEvent(ms));
          }
        }
      } catch (_) {}
    });
  }
}

class DownloadProgressBloc extends Bloc<DownloadProgressEvent, DownloadProgressState>{
  DownloadProgressBloc():super(DownloadProgressState(null)){
    on<DownloadProgressEvent>((event, emit) => emit(DownloadProgressState(event.downloadProgress)));
  }
}

class AIChatBloc extends Bloc<AIChatEvent, AIChatState>{
  AIChatBloc():super(AIChatState([])){
    on<AIChatEvent>((event, emit) => emit(AIChatState(event.aiConversation)));
  }
}

class AIChatUIBloc extends Bloc<AIChatUIEvent, AIChatUIState> {
  static const String _chatModePrefsKey = 'ai_chat_mode';
  static const String _agenticToolSelectionsPrefsKey = 'ai_agentic_tool_selections';
  static const String _selectedModelIdPrefsKey = 'ai_selected_chat_model_id';

  AIChatUIBloc() : super(const AIChatUIState()) {
    on<AIChatUIEvent>((event, emit) async {
      final nextState = AIChatUIState(
        chatMode: event.chatMode,
        promptText: event.promptText,
        selectedModelId: event.selectedModelId,
        scrollOffset: event.scrollOffset,
        isGenerating: event.isGenerating,
        agenticToolSelections: event.agenticToolSelections != null
          ? normalizeAgenticToolSelections(event.agenticToolSelections)
          : state.agenticToolSelections,
      );

      if (state.chatMode != nextState.chatMode) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_chatModePrefsKey, nextState.chatMode.name);
      }

      if (state.agenticToolSelections != nextState.agenticToolSelections) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _agenticToolSelectionsPrefsKey,
          jsonEncode(nextState.agenticToolSelections),
        );
      }

      if (state.selectedModelId != nextState.selectedModelId) {
        final prefs = await SharedPreferences.getInstance();
        if (nextState.selectedModelId != null) {
          await prefs.setString(_selectedModelIdPrefsKey, nextState.selectedModelId!);
        } else {
          await prefs.remove(_selectedModelIdPrefsKey);
        }
      }

      emit(nextState);
    });

    _restoreChatModeFromPrefs();
    _restoreAgenticToolSelectionsFromPrefs();
    _restoreSelectedModelIdFromPrefs();
  }

  Future<void> _restoreSelectedModelIdFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedId = prefs.getString(_selectedModelIdPrefsKey);
      
      if (savedId == null || savedId.isEmpty) {
        final modelSelectedStr = prefs.getString('modelSelected');
        if (modelSelectedStr != null) {
          final Map<String, dynamic> modelSelected = jsonDecode(modelSelectedStr);
          savedId = modelSelected['chat'] as String?;
        }
      }
      
      if (savedId != null && savedId.isNotEmpty) {
        final aiConfigStr = prefs.getString('aiConfig');
        if (aiConfigStr != null) {
          final Map<String, dynamic> aiConfig = jsonDecode(aiConfigStr);
          if (!aiConfig.containsKey(savedId)) {
            savedId = null;
          }
        }
      }
      
      if (savedId != null && savedId.isNotEmpty && savedId != state.selectedModelId) {
        add(AIChatUIEvent(
          chatMode: state.chatMode,
          promptText: state.promptText,
          selectedModelId: savedId,
          scrollOffset: state.scrollOffset,
          isGenerating: state.isGenerating,
          agenticToolSelections: state.agenticToolSelections,
        ));
      }

    } catch (_) {}
  }

  Future<void> _restoreChatModeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_chatModePrefsKey);
      final restoredMode = switch (savedMode) {
        'agent' => ChatMode.agent,
        'ask' => ChatMode.ask,
        _ => null,
      };

      if (restoredMode != null && restoredMode != state.chatMode) {
        add(
          AIChatUIEvent(
            chatMode: restoredMode,
            promptText: state.promptText,
            selectedModelId: state.selectedModelId,
            scrollOffset: state.scrollOffset,
            isGenerating: state.isGenerating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _restoreAgenticToolSelectionsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSelections = prefs.getString(_agenticToolSelectionsPrefsKey);
      if (savedSelections == null || savedSelections.isEmpty) {
        return;
      }

      final decoded = jsonDecode(savedSelections);
      if (decoded is! Map) {
        return;
      }

      final restoredSelections = <String, bool>{};
      decoded.forEach((key, value) {
        if (key != null) {
          restoredSelections[key.toString()] = value == true;
        }
      });

      final normalizedSelections =
          normalizeAgenticToolSelections(restoredSelections);
      if (normalizedSelections != state.agenticToolSelections) {
        add(
          AIChatUIEvent(
            chatMode: state.chatMode,
            promptText: state.promptText,
            selectedModelId: state.selectedModelId,
            scrollOffset: state.scrollOffset,
            isGenerating: state.isGenerating,
            agenticToolSelections: normalizedSelections,
          ),
        );
      }
    } catch (_) {}
  }
}

class ChatSessionBloc extends Bloc<ChatSessionEvent, ChatSessionState> {
  static const String _storageKey = 'chat_sessions';

  ChatSessionBloc() : super(ChatSessionState(sessions: [])) {
    on<LoadChatSessions>(_onLoadSessions);
    on<CreateNewSession>(_onCreateNewSession);
    on<SelectSession>(_onSelectSession);
    on<UpdateCurrentSession>(_onUpdateCurrentSession);
    on<DeleteSession>(_onDeleteSession);
    on<UpdateSessionTitle>(_onUpdateSessionTitle);
  }

  Future<void> _onLoadSessions(LoadChatSessions event, Emitter<ChatSessionState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionsJson = prefs.getString(_storageKey);
      if (sessionsJson != null) {
        final List<dynamic> decoded = jsonDecode(sessionsJson);
        final sessions = decoded.map((s) => ChatSession.fromJson(s)).toList();
        sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        emit(state.copyWith(sessions: sessions, isLoading: false));
      } else {
        emit(state.copyWith(isLoading: false));
      }
    } catch (e) {
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onCreateNewSession(CreateNewSession event, Emitter<ChatSessionState> emit) async {
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New Chat',
      createdAt: DateTime.now(),
      conversations: [],
    );
    final updatedSessions = [newSession, ...state.sessions];
    emit(state.copyWith(sessions: updatedSessions, currentSession: newSession));
    await _saveSessions(updatedSessions);
  }

  Future<void> _onSelectSession(SelectSession event, Emitter<ChatSessionState> emit) async {
    final session = state.sessions.firstWhere((s) => s.id == event.sessionId);
    emit(state.copyWith(currentSession: session));
  }

  Future<void> _onUpdateCurrentSession(UpdateCurrentSession event, Emitter<ChatSessionState> emit) async {
    if (state.currentSession == null) {
      final newSession = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: event.title ?? 'New Chat',
        createdAt: DateTime.now(),
        conversations: event.conversations,
      );
      final updatedSessions = [newSession, ...state.sessions];
      emit(state.copyWith(sessions: updatedSessions, currentSession: newSession));
      await _saveSessions(updatedSessions);
      return;
    }

    final updatedSession = state.currentSession!.copyWith(
      conversations: event.conversations,
      title: event.title,
    );
    final updatedSessions = state.sessions.map((s) {
      if (s.id == updatedSession.id) return updatedSession;
      return s;
    }).toList();
    emit(state.copyWith(sessions: updatedSessions, currentSession: updatedSession));
    await _saveSessions(updatedSessions);
  }

  Future<void> _onDeleteSession(DeleteSession event, Emitter<ChatSessionState> emit) async {
    final updatedSessions = state.sessions.where((s) => s.id != event.sessionId).toList();
    final shouldClearCurrent = state.currentSession?.id == event.sessionId;
    emit(state.copyWith(
      sessions: updatedSessions,
      clearCurrentSession: shouldClearCurrent,
    ));
    await _saveSessions(updatedSessions);
  }

  Future<void> _onUpdateSessionTitle(UpdateSessionTitle event, Emitter<ChatSessionState> emit) async {
    final updatedSessions = state.sessions.map((s) {
      if (s.id == event.sessionId) {
        return s.copyWith(title: event.title);
      }
      return s;
    }).toList();
    
    ChatSession? updatedCurrentSession;
    if (state.currentSession?.id == event.sessionId) {
      updatedCurrentSession = state.currentSession!.copyWith(title: event.title);
    }
    
    emit(state.copyWith(
      sessions: updatedSessions,
      currentSession: updatedCurrentSession ?? state.currentSession,
    ));
    await _saveSessions(updatedSessions);
  }

  Future<void> _saveSessions(List<ChatSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(sessions.map((s) => s.toJson()).toList());
    await prefs.setString(_storageKey, json);
  }
}

class DownloadPortBloc extends Cubit<ReceivePort?> {
  static const String portName = 'downloader_send_port';
  late final Stream<dynamic> broadcastStream;

  DownloadPortBloc() : super(null) {
    final rp = ReceivePort();
    IsolateNameServer.registerPortWithName(rp.sendPort, portName);
    broadcastStream = rp.asBroadcastStream();
    emit(rp);
  }

  ReceivePort? get port => state;

  Stream<dynamic> get downloadStream => broadcastStream;

  @override
  Future<void> close() {
    if (state != null) {
      IsolateNameServer.removePortNameMapping(portName);
      state!.close();
    }
    return super.close();
  }
}

class GitCommitBloc extends Bloc<GitCommitEvent, GitCommitState>{
  GitCommitBloc(): super(GitCommitState(commitMessage: '')){
    on<GitCommitEvent>((event, emit) => emit(GitCommitState(commitMessage: event.commitMessage)));
  }
}

class WorkspaceSearchBloc extends Bloc<WorkspaceSearchEvent, WorkspaceSearchState> {
  WorkspaceSearchBloc() : super(WorkspaceSearchState.initial()) {
    on<UpdateSearchResults>((event, emit) => emit(state.copyWith(
      results: event.results,
      query: event.query,
      isSearching: false,
    )));
    on<SetSearching>((event, emit) => emit(state.copyWith(isSearching: event.isSearching)));
    on<UpdateSearchOptions>((event, emit) => emit(state.copyWith(
      matchCase: event.matchCase,
      matchWholeWord: event.matchWholeWord,
      isRegex: event.isRegex,
    )));
    on<ClearSearchResults>((event, emit) => emit(WorkspaceSearchState.initial()));
  }
}

class DownloadManagerBloc extends Cubit<DownloadManagerState> {
  DownloadManagerBloc() : super(DownloadManagerState(
    downloadProgress: {}, 
    extractionProgress: {},
    extractingItems: {},
    fullyCompleted: {}
  ));

  void updateProgress(int index, double progress) {
    final newProgress = Map<int, double>.from(state.downloadProgress);
    newProgress[index] = progress;
    emit(state.copyWith(downloadProgress: newProgress));
  }

  void updateExtractionProgress(int index, double progress) {
    final newProgress = Map<int, double>.from(state.extractionProgress);
    newProgress[index] = progress;
    emit(state.copyWith(extractionProgress: newProgress));
  }

  void startExtracting(int index) {
    final newExtracting = Set<int>.from(state.extractingItems);
    newExtracting.add(index);
    emit(state.copyWith(extractingItems: newExtracting));
  }

  void markFullyCompleted(int index) {
    final newExtracting = Set<int>.from(state.extractingItems);
    final newFullyCompleted = Set<int>.from(state.fullyCompleted);
    newExtracting.remove(index);
    newFullyCompleted.add(index);
    emit(state.copyWith(
      extractingItems: newExtracting,
      fullyCompleted: newFullyCompleted
    ));
  }

  void removeDownload(int index) {
    final newProgress = Map<int, double>.from(state.downloadProgress);
    final newExtractionProgress = Map<int, double>.from(state.extractionProgress);
    final newExtracting = Set<int>.from(state.extractingItems);
    final newFullyCompleted = Set<int>.from(state.fullyCompleted);
    newProgress.remove(index);
    newExtractionProgress.remove(index);
    newExtracting.remove(index);
    newFullyCompleted.remove(index);
    emit(state.copyWith(
      downloadProgress: newProgress, 
      extractionProgress: newExtractionProgress,
      extractingItems: newExtracting,
      fullyCompleted: newFullyCompleted
    ));
  }

  void clearProgress(int index) {
    final newProgress = Map<int, double>.from(state.downloadProgress);
    final newExtractionProgress = Map<int, double>.from(state.extractionProgress);
    newProgress.remove(index);
    newExtractionProgress.remove(index);
    emit(state.copyWith(
      downloadProgress: newProgress,
      extractionProgress: newExtractionProgress
    ));
  }
}

class PackageCatalogCubit extends Cubit<PackageCatalogState> {
  bool _didInitialSync = false;

  PackageCatalogCubit() : super(PackageCatalogState.initial());

  Future<void> syncOnStartup() async {
    if (_didInitialSync) return;
    _didInitialSync = true;
    await refreshCatalog();
  }

  Future<void> refreshCatalog() async {
    emit(state.copyWith(isSyncing: true, remoteFetchFailed: false));

    final result = await PackageCatalogService.syncOnStartup();
    emit(
      state.copyWith(
        runtimes: result.runtimes,
        extensions: result.extensions,
        runtimeUpdates: result.runtimeUpdates,
        extensionUpdates: result.extensionUpdates,
        isSyncing: false,
        remoteFetchFailed: result.remoteFetchFailed,
        usedRemote: result.usedRemote,
      ),
    );
  }

  Future<void> refreshInstalledStatusOnly() async {
    final result = await PackageCatalogService.refreshInstalledStatusOnly(
      runtimes: state.runtimes,
      extensions: state.extensions,
    );
    emit(
      state.copyWith(
        runtimeUpdates: result.runtimeUpdates,
        extensionUpdates: result.extensionUpdates,
      ),
    );
  }
}

class CopilotBloc extends Bloc<CopilotEvent, CopilotState> {
  CopilotLsp? _client;
  CopilotCompletionManager? _completionManager;
  StreamSubscription? _notificationSubscription;
  bool _expectingSignIn = false;
  
  static const String _storageKey = 'copilot_config';

  CopilotBloc() : super(CopilotState.initial()) {
    on<CopilotAutoInit>(_onAutoInit);
    on<CopilotInitialize>(_onInitialize);
    on<CopilotSignInInitiate>(_onSignInInitiate);
    on<CopilotSignInConfirm>(_onSignInConfirm);
    on<CopilotSignOut>(_onSignOut);
    on<CopilotCheckStatus>(_onCheckStatus);
    on<CopilotUpdateStatus>(_onUpdateStatus);
    on<CopilotSetEnabled>(_onSetEnabled);
    on<CopilotSetCompletion>(_onSetCompletion);
    on<CopilotClearCompletion>(_onClearCompletion);
    on<CopilotAcceptCompletion>(_onAcceptCompletion);
    on<CopilotRejectCompletion>(_onRejectCompletion);
    on<CopilotRequestCompletion>(_onRequestCompletion);
    on<CopilotDispose>(_onDispose);
  }

  CopilotLsp? get client => _client;
  CopilotCompletionManager? get completionManager => _completionManager;

  void _onAutoInit(CopilotAutoInit event, Emitter<CopilotState> emit) {
    final configPath = filesDir;
    final copilotPath = '$extensionDir/copilot-language-server';
    
    if (!Directory(copilotPath).existsSync()) {
      debugPrint('Copilot extension not installed, skipping auto-init');
      return;
    }
    add(CopilotInitialize(configPath: configPath));
  }

  Future<void> _onInitialize(CopilotInitialize event, Emitter<CopilotState> emit) async {
    if (state.status == CopilotStatus.initializing) return;
    
    emit(state.copyWith(status: CopilotStatus.initializing));
    
    try {
      await _loadConfig(emit);
      
      _client = await CopilotLsp.start(
        configPath: event.configPath,
        workspacePath: event.workspacePath ?? '',
      );

      await _client!.initialize();

      _client!.notificationStream.listen((response) {
        if (_expectingSignIn && (response['type'] == 'statusNotification' || response['type'] == 'didChangeStatus')) {
          _expectingSignIn = false;
          add(CopilotCheckStatus());
        }
      });
      
      _completionManager = CopilotCompletionManager(
        client: _client!,
        debounceDelay: Duration(milliseconds: event.debounceMs),
        onCompletionReady: (completion) {
          if (completion != null) {
            add(CopilotSetCompletion(
              text: completion.text,
              displayText: completion.displayText,
              uuid: completion.uuid,
            ));
          } else {
            add(CopilotClearCompletion());
          }
        },
        onCompletionCleared: () {
          add(CopilotClearCompletion());
        },
      );
      
      final statusPayload = await _client!.checkStatus();
      
      CopilotStatus newStatus;
      if (statusPayload.isOk || statusPayload.isAlreadySignedIn) {
        newStatus = CopilotStatus.signedIn;
      } else if (statusPayload.isNotAuthorized) {
        newStatus = CopilotStatus.notAuthorized;
      } else {
        newStatus = CopilotStatus.notSignedIn;
      }
      
      emit(state.copyWith(
        status: newStatus,
        user: statusPayload.user,
        isInitialized: true,
      ));

      await _saveConfig(newStatus == CopilotStatus.signedIn);
      
    } catch (e) {
      debugPrint('Copilot initialization error: $e');
      if (e is TimeoutException) {
        emit(state.copyWith(
          status: CopilotStatus.notSignedIn,
          isInitialized: true,
        ));
      } else {
        emit(state.copyWith(
          status: CopilotStatus.error,
          error: e.toString(),
        ));
      }
    }
  }

  Future<void> _onSignInInitiate(CopilotSignInInitiate event, Emitter<CopilotState> emit) async {
    if (_client == null) return;
    
    emit(state.copyWith(status: CopilotStatus.signingIn));
    
    try {
      final payload = await _client!.signIn();
      
      if (payload.isAlreadySignedIn) {
        emit(state.copyWith(
          status: CopilotStatus.signedIn,
          user: payload.user,
        ));
        await _saveConfig(true);
        return;
      }
      
      emit(state.copyWith(
        signInPayload: payload,
      ));
      
      _expectingSignIn = true;
    } catch (e) {
      emit(state.copyWith(
        status: CopilotStatus.error,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onSignInConfirm(CopilotSignInConfirm event, Emitter<CopilotState> emit) async {
    if (_client == null) return;
    
    try {
      final payload = await _client!.signInConfirm(event.userCode);
      
      if (payload.isOk || payload.isAlreadySignedIn) {
        _expectingSignIn = false;
        emit(state.copyWith(
          status: CopilotStatus.signedIn,
          user: payload.user,
          signInPayload: null,
        ));
        await _saveConfig(true);
      } else if (payload.isNotAuthorized) {
        emit(state.copyWith(
          status: CopilotStatus.notAuthorized,
          signInPayload: null,
        ));
      } else {
        _expectingSignIn = false;
        emit(state.copyWith(
          status: CopilotStatus.notSignedIn,
          signInPayload: null,
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: CopilotStatus.error,
        error: e.toString(),
        signInPayload: null,
      ));
    }
  }

  Future<void> _onSignOut(CopilotSignOut event, Emitter<CopilotState> emit) async {
    if (_client == null) return;
    
    try {
      await _client!.signOut();
      emit(state.copyWith(
        status: CopilotStatus.notSignedIn,
        user: null,
        signInPayload: null,
      ));
      await _saveConfig(false);
    } catch (e) {
      emit(state.copyWith(
        status: CopilotStatus.error,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onCheckStatus(CopilotCheckStatus event, Emitter<CopilotState> emit) async {
    if (_client == null) return;
    
    try {
      final payload = await _client!.checkStatus();
      
      CopilotStatus newStatus;
      if (payload.isOk || payload.isAlreadySignedIn) {
        newStatus = CopilotStatus.signedIn;
      } else if (payload.isNotAuthorized) {
        newStatus = CopilotStatus.notAuthorized;
      } else {
        newStatus = CopilotStatus.notSignedIn;
      }
      
      emit(state.copyWith(
        status: newStatus,
        user: payload.user,
      ));

      await _saveConfig(newStatus == CopilotStatus.signedIn);
    } catch (e) {
      debugPrint('Check status error: $e');
    }
  }

  void _onUpdateStatus(CopilotUpdateStatus event, Emitter<CopilotState> emit) {
    emit(state.copyWith(status: event.status));
  }

  Future<void> _onSetEnabled(CopilotSetEnabled event, Emitter<CopilotState> emit) async {
    emit(state.copyWith(isEnabled: event.isEnabled));

    await _saveConfig(state.status == CopilotStatus.signedIn);
    
    if (!event.isEnabled) {
      _completionManager?.cancel();
    }
  }

  void _onSetCompletion(CopilotSetCompletion event, Emitter<CopilotState> emit) {
    emit(state.copyWith(
      currentCompletion: CopilotCompletionData(
        text: event.text,
        displayText: event.displayText,
        uuid: event.uuid,
      ),
    ));
  }

  void _onClearCompletion(CopilotClearCompletion event, Emitter<CopilotState> emit) {
    emit(state.copyWith(clearCompletion: true));
  }

  Future<void> _onAcceptCompletion(CopilotAcceptCompletion event, Emitter<CopilotState> emit) async {
    await _completionManager?.acceptCompletion();
    emit(state.copyWith(clearCompletion: true));
  }

  Future<void> _onRejectCompletion(CopilotRejectCompletion event, Emitter<CopilotState> emit) async {
    await _completionManager?.rejectCompletions();
    emit(state.copyWith(clearCompletion: true));
  }

  void _onRequestCompletion(CopilotRequestCompletion event, Emitter<CopilotState> emit) {
    if (!state.isEnabled || state.status != CopilotStatus.signedIn) return;
    
    if (event.immediate) {
      _completionManager?.fetchCompletionsNow(
        filePath: event.filePath,
        content: event.content,
        line: event.line,
        character: event.character,
        languageId: event.languageId,
      );
    } else {
      _completionManager?.requestCompletions(
        filePath: event.filePath,
        content: event.content,
        line: event.line,
        character: event.character,
        languageId: event.languageId,
      );
    }
  }

  Future<void> _onDispose(CopilotDispose event, Emitter<CopilotState> emit) async {
    _notificationSubscription?.cancel();
    _completionManager?.dispose();
    _client?.dispose();
    _client = null;
    _completionManager = null;
    
    emit(CopilotState.initial());
  }

  Future<void> _saveConfig(bool isSignedIn) async {
    final prefs = await SharedPreferences.getInstance();
    final isCopilotEnabled = isSignedIn && state.isEnabled;
    await prefs.setString(_storageKey, jsonEncode({
      'isSignedIn': isSignedIn,
      'isEnabled': state.isEnabled,
    }));
    await setCopilotSignedPref(isSignedIn);
    await setCopilotEnabledPref(isCopilotEnabled);
  }

  Future<void> _loadConfig(Emitter<CopilotState> emit) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configStr = prefs.getString(_storageKey);
      if (configStr != null) {
        final config = jsonDecode(configStr) as Map<String, dynamic>;
        final wasSignedIn = config['isSignedIn'] as bool? ?? false;
        final isEnabled = config['isEnabled'] as bool? ?? true;
        
        emit(state.copyWith(
          isEnabled: isEnabled,
        ));
        
        debugPrint('Loaded Copilot config: signedIn=$wasSignedIn, enabled=$isEnabled');

        final storedSignedPref = prefs.getBool(copilotSignedPrefKey);
        if (storedSignedPref == null) {
          await setCopilotSignedPref(wasSignedIn);
        }
      }

      await ensureCopilotEnabledPrefInitialized();
      await ensureCopilotSignedPrefInitialized();
    } catch (e) {
      debugPrint('Failed to load Copilot config: $e');
    }
  }

  @override
  Future<void> close() {
    _notificationSubscription?.cancel();
    _completionManager?.dispose();
    _client?.dispose();
    return super.close();
  }
}

class CopilotChatBloc extends Bloc<CopilotChatEvent, CopilotChatState> {
  CopilotChat? _chatClient;
  StreamSubscription? _conversationSubscription;
  bool _isFetchingModels = false;

  static const Set<String> _supportedChatEndpoints = {
    '/chat/completions',
    '/responses',
    '/messages',
  };

  CopilotChatBloc() : super(CopilotChatState.initial()) {
    on<CopilotChatFetchModels>(_onChatFetchModels);
    on<_CopilotChatInternalUpdateMessages>(_onInternalUpdateMessages);

    _initializeChatClient();
  }

  CopilotChat? get chatClient => _chatClient;

  String _normalizeEndpoint(String endpoint) {
    var normalized = endpoint.trim().toLowerCase();
    if (normalized.isEmpty) return normalized;
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    if (normalized.startsWith('/v1/')) {
      normalized = normalized.substring(3);
    }
    if (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _isLikelyNonChatModel(Map<String, dynamic> model) {
    final id = (model['id']?.toString() ?? '').toLowerCase();
    final name = (model['name']?.toString() ?? '').toLowerCase();
    final text = '$id $name';

    const blockedTokens = [
      'embedding',
      'embed',
      'text-embedding',
      'ada',
      'whisper',
      'tts',
      'dall-e',
      'image',
      'audio',
      'moderation',
      'rerank',
      'transcribe',
      'speech',
    ];

    return blockedTokens.any(text.contains);
  }

  bool _isChatCapableModel(Map<String, dynamic> model) {
    final pickerEnabled = model['model_picker_enabled'];
    if (pickerEnabled == false) return false;

    if (_isLikelyNonChatModel(model)) return false;

    final endpointsRaw = model['supported_endpoints'];
    if (endpointsRaw is List) {
      final endpoints = endpointsRaw
          .map((e) => _normalizeEndpoint(e.toString()))
          .where((e) => e.isNotEmpty)
          .toSet();
      if (endpoints.isNotEmpty &&
          endpoints.intersection(_supportedChatEndpoints).isEmpty) {
        return false;
      }
    }

    return true;
  }

  Future<void> _initializeChatClient() async {
    final authContext = await CopilotChat.loadAuthContext();
    if (authContext != null) {
      _chatClient = CopilotChat(
        authToken: authContext.authToken,
        initialApiEndpoint: authContext.apiEndpoint,
      );
    }
  }

  Future<void> _onChatFetchModels(CopilotChatFetchModels event, Emitter<CopilotChatState> emit) async {
    if (_isFetchingModels || (state.hasFetchedModels && !event.forceRefresh)) {
      return;
    }

    if (_chatClient == null) {
      await _initializeChatClient();
    }

    if (_chatClient != null) {
      _isFetchingModels = true;
      emit(state.copyWith(isFetchingModels: true, error: null));
      try {
        final models = await _chatClient!.getCopilotModels();
        final data = models['data'] as List<dynamic>? ?? [];
        debugPrint('[CopilotChatBloc] Raw model payload count: ${data.length}');
        final parsedModels = data
            .whereType<Map>()
            .map((model) => Map<String, dynamic>.from(model))
            .where((model) => model['id'] != null && model['name'] != null)
            .where(_isChatCapableModel)
            .toList();

        final modelSummaries = parsedModels
            .map((m) {
              final id = m['id'];
              final picker = m['model_picker_enabled'];
              final preview = m['preview'];
              return '$id(picker=$picker,preview=$preview)';
            })
            .join(', ');
        debugPrint(
          '[CopilotChatBloc] Parsed filtered model count: ${parsedModels.length}. Models: $modelSummaries',
        );

        emit(state.copyWith(
          models: parsedModels,
          isFetchingModels: false,
          hasFetchedModels: true,
          error: null,
        ));
      } catch (e) {
        debugPrint('Failed to fetch Copilot models: $e');
        emit(state.copyWith(
          isFetchingModels: false,
          hasFetchedModels: false,
          error: e.toString(),
        ));
      } finally {
        _isFetchingModels = false;
      }
    }
  }

  void _onInternalUpdateMessages(_CopilotChatInternalUpdateMessages event, Emitter<CopilotChatState> emit) {
    emit(state.copyWith(chatMessages: event.messages));
  }

  @override
  Future<void> close() {
    _conversationSubscription?.cancel();
    _chatClient?.dispose();
    return super.close();
  }
}

class SSHServersCubit extends Cubit<SSHServersState> {
  SSHServersCubit(List<SSHInfo> serverList) : super(SSHServersState(serverList));

  Future<void> addServer(SSHInfo server) async{
    final updatedList = [...state.serverList, server];
    emit(SSHServersState(updatedList));
    await _save(updatedList);
  }

  Future<void> removeServer(int id) async{
    final List<SSHInfo> serverList = List.from(state.serverList);
    serverList.removeWhere((server) => server.id == id);
    emit(SSHServersState(serverList));
    await _save(serverList);
  }

  Future<void> updateServer(SSHInfo serverInfo) async {
    final serverList = List<SSHInfo>.from(state.serverList);
    final index = serverList.indexWhere((s) => s.id == serverInfo.id);
    if (index == -1) return;
    serverList[index] = serverInfo;
    emit(SSHServersState(serverList));
    await _save(serverList);
  }

  Future<void> _save(List<SSHInfo> servers) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'sshServerList',
      jsonEncode(
        servers.map((e) => e.toJsonMap()).toList(),
      ),
    );
  }
}

class TermuxCubit extends Cubit<TermuxState> {
  TermuxCubit(SSHPrivateKey? termuxInfo) : super(TermuxState(termuxInfo));

  Future<void> setTermuxInfo(SSHPrivateKey info) async{
    emit(TermuxState(info));
    await _save(info);
  }

  void unSetTermuxInfo() {
    emit(const TermuxState(null));
  }

  Future<void> clear() async {
    unSetTermuxInfo();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('termuxInfo');
  }

  Future<void> _save(SSHPrivateKey info) async{
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('termuxInfo', jsonEncode(info.toJsonMap()));
  }

  static Future<SSHPrivateKey?> getSavedTermuxInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final json = prefs.getString('termuxInfo');
      if (json == null) return null;


      return SSHPrivateKey.fromJsonMap(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}

class CurrentlySelectedTerminalCubit extends Cubit<SelectedTerminalState>{
  CurrentlySelectedTerminalCubit() : super(SelectedTerminalState(null));

  void updateId(int? id, bool isTermux){
    emit(SelectedTerminalState(id, isTermux: isTermux));
  }
}

class SelectedRuntimeEnvironmentCubit extends Cubit<SelectedRunEnvironmentState> {
  SelectedRuntimeEnvironmentCubit() : super(SelectedRunEnvironmentState(null));

  void updateId(int? id){
    emit(SelectedRunEnvironmentState(id));
  }
}

class LocalLlamaBloc extends Bloc<LocalLlamaEvent, LocalLlamaState> {
  LlamaController? _controller;

  LocalLlamaBloc() : super(const LocalLlamaState()) {
    on<LocalLlamaLoadModel>(_onLoadModel);
    on<LocalLlamaUnloadModel>(_onUnloadModel);
    on<LocalLlamaStopGeneration>(_onStopGeneration);
    on<LocalLlamaDetectGpu>(_onDetectGpu);
    on<LocalLlamaGenerationDone>(_onGenerationDone);
  }

  LlamaController? get controller => _controller;

  Future<void> _onLoadModel(
    LocalLlamaLoadModel event,
    Emitter<LocalLlamaState> emit,
  ) async {
    if (state.loadedModelPath == event.model.modelPath && state.status == LocalLlamaStatus.ready) return;

    await _controller?.dispose();
    _controller = null;

    emit(state.copyWith(
      status: LocalLlamaStatus.loading,
      clearError: true,
    ));

    try {
      _controller = LlamaController();

      GpuInfo? gpuInfo = state.gpuInfo;
      gpuInfo ??= await _controller!.detectGpu();

      final layers = event.model.gpuLayers == 0
        ? gpuInfo.recommendedGpuLayers
        : event.model.gpuLayers;

      await _controller!.loadModel(
        modelPath: event.model.modelPath,
        threads: event.model.threads,
        contextSize: event.model.contextSize,
        gpuLayers: layers,
      );

      emit(state.copyWith(
        status: LocalLlamaStatus.ready,
        loadedModelPath: event.model.modelPath,
        loadedModelName: event.model.displayName,
        gpuInfo: gpuInfo,
      ));
    } catch (e) {
      await _controller?.dispose();
      _controller = null;
      emit(state.copyWith(
        status: LocalLlamaStatus.error,
        error: e.toString(),
      ));
    }
  }

  Future<void> _onUnloadModel(
    LocalLlamaUnloadModel event,
    Emitter<LocalLlamaState> emit,
  ) async {
    await _controller?.dispose();
    _controller = null;
    emit(const LocalLlamaState());
  }

  Future<void> _onStopGeneration(
    LocalLlamaStopGeneration event,
    Emitter<LocalLlamaState> emit,
  ) async {
    await _controller?.stop();
  }

  Future<void> _onDetectGpu(
    LocalLlamaDetectGpu event,
    Emitter<LocalLlamaState> emit,
  ) async {
    try {
      _controller ??= LlamaController();
      final gpuInfo = await _controller!.detectGpu();
      emit(state.copyWith(gpuInfo: gpuInfo));
    } catch (_) {}
  }

  void _onGenerationDone(
    LocalLlamaGenerationDone event,
    Emitter<LocalLlamaState> emit,
  ) {
    if (state.status == LocalLlamaStatus.generating) {
      emit(state.copyWith(status: LocalLlamaStatus.ready));
    }
  }

  @override
  Future<void> close() async {
    await _controller?.dispose();
    return super.close();
  }
}

class GgufDownloadCubit extends Cubit<GgufDownloadState> {
  void Function(GgufDownloadTask task)? onTaskCompleted;

  GgufDownloadCubit({this.onTaskCompleted}) : super(GgufDownloadState.initial()) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksJson = prefs.getString('gguf_downloads');
    if (tasksJson != null) {
      final List<dynamic> decoded = jsonDecode(tasksJson);
      final tasks = decoded.map((e) => GgufDownloadTask.fromJson(e)).toList();
      for (int i = 0; i < tasks.length; i++) {
        if (tasks[i].status == GgufDownloadStatus.downloading) {
          tasks[i] = tasks[i].copyWith(status: GgufDownloadStatus.failed);
        }
      }
      emit(state.copyWith(tasks: tasks));
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(state.tasks.map((t) => t.toJson()).toList());
    await prefs.setString('gguf_downloads', json);
  }

  Future<int?> _getFileSize(String url) async {
    try {
      final response = await http.head(Uri.parse(url));
      if (response.statusCode == 200) {
        final length = response.headers['content-length'];
        if (length != null) return int.tryParse(length);
      }
    } catch (e) {
      debugPrint('HEAD request failed: $e');
    }
    return null;
  }

  void startDownload(GgufModel model) async {
    if (state.tasks.any((t) => t.url == model.url && 
        (t.status == GgufDownloadStatus.downloading || t.status == GgufDownloadStatus.completed))) {
      return;
    }

    final saveDir = '$filesDir/gguf';
    if (!Directory(saveDir).existsSync()) {
      Directory(saveDir).createSync(recursive: true);
    }
    final savePath = '$saveDir/${model.fileName}';

    final existing = File(savePath);
    if (await existing.exists()) await existing.delete();

    final totalBytes = await _getFileSize(model.url);

    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    final task = GgufDownloadTask(
      taskId: taskId,
      modelName: model.name,
      url: model.url,
      fileName: model.fileName,
      localPath: savePath,
      status: GgufDownloadStatus.downloading,
      progress: 0,
      registered: false,
      quant: model.quant,
      paramSize: model.paramSize,
      imageUrl: model.imageUrl,
    );

    final updatedTasks = [task, ...state.tasks];
    emit(state.copyWith(tasks: updatedTasks));
    _saveToPrefs();

    FileDownloader.downloadFile(
      url: model.url,
      name: model.fileName,
      downloadDestination: DownloadDestinations.appFiles,
      notificationType: NotificationType.all,
      onDownloadRequestIdReceived: (downloadId) {
        emit(state.copyWith(id: downloadId));
      },
      onProgress: (fileName, progress) {
        double realProgress;
        if (totalBytes != null && progress < 0) {
          final overflowAbs = 4294967296 - totalBytes;
          realProgress = (-progress) * overflowAbs / totalBytes;
        } else {
          realProgress = progress.clamp(0.0, 100.0);
        }
        _updateProgress(taskId, realProgress);
      },

      onDownloadCompleted: (path) async {
        final downloadedFile = File(path);
        if (await downloadedFile.exists()) {
          await downloadedFile.copy(savePath);
          await downloadedFile.delete();
        }
        _onDownloadComplete(taskId, savePath);
      },
      onDownloadError: (error) {
        _onDownloadError(taskId, error);
      },
    );
  }

  void _updateProgress(String taskId, double progress) {
    final tasks = List<GgufDownloadTask>.from(state.tasks);
    final index = tasks.indexWhere((t) => t.taskId == taskId);
    if (index != -1) {
      tasks[index] = tasks[index].copyWith(progress: progress.clamp(0.0, 100.0));
      emit(state.copyWith(tasks: tasks));
      _saveToPrefs();
    }
  }

  void _onDownloadComplete(String taskId, String path) {
    final tasks = List<GgufDownloadTask>.from(state.tasks);
    final index = tasks.indexWhere((t) => t.taskId == taskId);
    if (index == -1) return;
    tasks[index] = tasks[index].copyWith(
      status: GgufDownloadStatus.completed,
      localPath: path,
      progress: 100,
    );
    emit(state.copyWith(tasks: tasks));
    _saveToPrefs();
    onTaskCompleted?.call(tasks[index]);
  }

  void _onDownloadError(String taskId, dynamic error) {
    final tasks = List<GgufDownloadTask>.from(state.tasks);
    final index = tasks.indexWhere((t) => t.taskId == taskId);
    if (index != -1) {
      tasks[index] = tasks[index].copyWith(status: GgufDownloadStatus.failed);
      emit(state.copyWith(tasks: tasks));
      _saveToPrefs();
    }
  }

  void deleteTask(String taskId) async {
    final tasks = List<GgufDownloadTask>.from(state.tasks);
    final index = tasks.indexWhere((t) => t.taskId == taskId);
    if (index == -1) return;
    final file = File(tasks[index].localPath);
    if (await file.exists()) await file.delete();
    tasks.removeAt(index);
    emit(state.copyWith(tasks: tasks));
    _saveToPrefs();
  }

  void retryDownload(GgufDownloadTask task) {
    deleteTask(task.taskId);
    startDownload(
      GgufModel(
        name: task.modelName,
        url: task.url,
        fileName: task.fileName,
        quant: task.quant,
        paramSize: task.paramSize,
        imageUrl: task.imageUrl,
      )
    );
  }

  static Future<String> cancelGGUFDownload(int id) async{
    try {
      final canceled = await FileDownloader.cancelDownload(id);
      return "Canceled $canceled";
    } catch (_) {
      return "An error occurred";
    }
  }

  void markTaskRegistered(String taskId) {
    final tasks = List<GgufDownloadTask>.from(state.tasks);
    final index = tasks.indexWhere((t) => t.taskId == taskId);
    if (index != -1 && !tasks[index].registered) {
      tasks[index] = tasks[index].copyWith(registered: true);
      emit(state.copyWith(tasks: tasks));
      _saveToPrefs();
    }
  }
}