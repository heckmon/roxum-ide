part of 'ui_bloc.dart';

@immutable
sealed class UiEvent {}

@immutable
sealed class RestEvent extends UiEvent {}

@immutable
sealed class AIEvent extends UiEvent{}

class StackIndexChange extends UiEvent {
  final int stackValue;
  StackIndexChange({required this.stackValue});
}

class SetFontSize extends UiEvent{
  final double fontSize;
  SetFontSize({required this.fontSize});
}

class ChangeConfigEvent extends UiEvent{
  final Map<String, dynamic> codeForgeConfig;
  ChangeConfigEvent(this.codeForgeConfig);
}

class Search extends UiEvent {
  final List<Card> searchedLangs;
  Search({required this.searchedLangs});
}

class FindWord extends UiEvent {
  final String word;
  final bool matchCase, matchWholeWord, isRegex;
  FindWord({
    required this.word,
    required this.matchCase,
    required this.matchWholeWord,
    required this.isRegex
  });
}

class SetViewPort extends UiEvent{
  final bool isMobile;
  SetViewPort({required this.isMobile});
}

class EnableConsole extends UiEvent{
  final bool isConsole;
  EnableConsole({required this.isConsole});
}


class ApiEvent extends RestEvent{
  final String method;
  ApiEvent({required this.method});
}

class GetParams extends RestEvent{
  final Map<String,String> params;
  GetParams({required this.params});
}

class GetHeaders extends RestEvent{
  final Map<String,String> headers;
  GetHeaders({required this.headers});
}

class GetBody extends RestEvent{
  final Map<String,String> body;
  GetBody({required this.body});
}

class GetUrl extends RestEvent{
  final String url;
  GetUrl({required this.url});
}

class GotApiData extends RestEvent{
  final Map<String,dynamic> data;
  GotApiData({required this.data});
}

class FileTreeEvent extends UiEvent{
  final Map<String, bool> folderStates;
  FileTreeEvent({required this.folderStates});
}

class AppThemeEvent extends UiEvent{
  final AppTheme appTheme;
  AppThemeEvent({required this.appTheme});
}

class EditorEvent {}

class ActiveEditorEvent extends EditorEvent{
  final List<ActiveEditor> activeEditors;

  ActiveEditorEvent(this.activeEditors);
}

class OpenRecentActiveEditor extends EditorEvent {}

class CloseActiveEditor extends EditorEvent {}

class AIConfigEvent extends AIEvent{
  final Map<String, dynamic> config;

  AIConfigEvent(this.config);
}

class AIEnableEvent extends AIEvent {
  final bool isEnabled;

  AIEnableEvent(this.isEnabled);
}

class ModelSelectEvent extends AIEvent {
  final Map<String, dynamic> modelSelected;

  ModelSelectEvent(this.modelSelected);
}

class AIModeEvent extends AIEvent {
  final bool showSuggestionOntap;

  AIModeEvent(this.showSuggestionOntap);
}

class DownloadProgressEvent extends UiEvent{
  final Map<String, double>? downloadProgress;

  DownloadProgressEvent(this.downloadProgress);
}

class GeneralEvent extends UiEvent {
  final Map<String, dynamic> generalSettings; 

  GeneralEvent({required this.generalSettings});
}

class AIChatEvent extends UiEvent {
  final List<AIConversation> aiConversation;

  AIChatEvent(this.aiConversation);
}

class AIChatUIEvent extends UiEvent {
  final ChatMode chatMode;
  final String promptText;
  final String? selectedModelId;
  final double scrollOffset;
  final bool isGenerating;
  final Map<String, bool>? agenticToolSelections;

  AIChatUIEvent({
    required this.chatMode,
    required this.promptText,
    this.selectedModelId,
    required this.scrollOffset,
    required this.isGenerating,
    this.agenticToolSelections,
  });
}

sealed class ChatSessionEvent extends UiEvent {}

class LoadChatSessions extends ChatSessionEvent {}

class CreateNewSession extends ChatSessionEvent {}

class SelectSession extends ChatSessionEvent {
  final String sessionId;
  SelectSession(this.sessionId);
}

class UpdateCurrentSession extends ChatSessionEvent {
  final List<AIConversation> conversations;
  final String? title;
  UpdateCurrentSession({required this.conversations, this.title});
}

class DeleteSession extends ChatSessionEvent {
  final String sessionId;
  DeleteSession(this.sessionId);
}

class UpdateSessionTitle extends ChatSessionEvent {
  final String sessionId;
  final String title;
  UpdateSessionTitle({required this.sessionId, required this.title});
}

class GitCommitEvent extends UiEvent {
  final String commitMessage;

  GitCommitEvent({required this.commitMessage});
}

sealed class WorkspaceSearchEvent extends UiEvent {}

class UpdateSearchResults extends WorkspaceSearchEvent {
  final List<SearchResultData> results;
  final String query;

  UpdateSearchResults({required this.results, required this.query});
}

class SetSearching extends WorkspaceSearchEvent {
  final bool isSearching;

  SetSearching({required this.isSearching});
}

class UpdateSearchOptions extends WorkspaceSearchEvent {
  final bool matchCase;
  final bool matchWholeWord;
  final bool isRegex;

  UpdateSearchOptions({
    required this.matchCase,
    required this.matchWholeWord,
    required this.isRegex,
  });
}

class ClearSearchResults extends WorkspaceSearchEvent {}

sealed class CopilotEvent extends UiEvent {}

class CopilotAutoInit extends CopilotEvent {}

class CopilotInitialize extends CopilotEvent {
  final String configPath;
  final String? workspacePath;
  final int debounceMs;

  CopilotInitialize({
    required this.configPath,
    this.workspacePath,
    this.debounceMs = 500,
  });
}

class CopilotSignInInitiate extends CopilotEvent {}

class CopilotExecuteSignIn extends CopilotEvent {
  final Map<String, dynamic> command;

  CopilotExecuteSignIn(this.command);
}

class CopilotSignInConfirm extends CopilotEvent {
  final String userCode;

  CopilotSignInConfirm(this.userCode);
}

class CopilotSignOut extends CopilotEvent {}

class CopilotCheckStatus extends CopilotEvent {}

class CopilotUpdateStatus extends CopilotEvent {
  final CopilotStatus status;

  CopilotUpdateStatus(this.status);
}

class CopilotSetEnabled extends CopilotEvent {
  final bool isEnabled;

  CopilotSetEnabled(this.isEnabled);
}

class CopilotSetCompletion extends CopilotEvent {
  final String text;
  final String displayText;
  final String uuid;

  CopilotSetCompletion({
    required this.text,
    required this.displayText,
    required this.uuid,
  });
}

class CopilotClearCompletion extends CopilotEvent {}

class CopilotAcceptCompletion extends CopilotEvent {}

class CopilotRejectCompletion extends CopilotEvent {}

class CopilotRequestCompletion extends CopilotEvent {
  final String filePath;
  final String content;
  final int line;
  final int character;
  final String languageId;
  final bool immediate;

  CopilotRequestCompletion({
    required this.filePath,
    required this.content,
    required this.line,
    required this.character,
    required this.languageId,
    this.immediate = false,
  });
}

class CopilotDispose extends CopilotEvent {}

sealed class CopilotChatEvent extends UiEvent {}

class CopilotChatFetchModels extends CopilotChatEvent {
  final bool forceRefresh;
  CopilotChatFetchModels({this.forceRefresh = false});
}

class _CopilotChatInternalUpdateMessages extends CopilotChatEvent {
  final List<CopilotChatMessage> messages;

  _CopilotChatInternalUpdateMessages(this.messages);
}

sealed class LocalLlamaEvent {}
class LocalLlamaLoadModel extends LocalLlamaEvent {
  final LocalLlama model;
  LocalLlamaLoadModel(this.model);
}

class LocalLlamaUnloadModel extends LocalLlamaEvent {}

class LocalLlamaStopGeneration extends LocalLlamaEvent {}

class LocalLlamaDetectGpu extends LocalLlamaEvent {}

class LocalLlamaGenerationDone extends LocalLlamaEvent {}