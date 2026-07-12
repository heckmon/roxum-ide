import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:roxum/bloc/repo_bloc/repo_bloc.dart';
import 'package:roxum/ui/mdview.dart';
import 'package:roxum/utils/constants.dart';
import 'webview.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../terminal/terminal.dart';
import '../utils/languages.dart';
import '../utils/functions.dart';
import '../utils/themes.dart';
import 'widgets.dart';

class DiagnosticsTickBloc extends Cubit<int> {
  DiagnosticsTickBloc() : super(0);

  void tick() => emit(state + 1);
}

class EditorPage extends StatefulWidget {
  final Language? languageDetails;
  final String rootDir;
  final File? file;
  final bool isProject, isCloned;
  const EditorPage({
    super.key,
    required this.languageDetails,
    required this.rootDir,
    required this.isProject,
    this.file,
    this.isCloned = false,
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with TickerProviderStateMixin, WidgetsBindingObserver {
  final createFileKey = GlobalKey<FormState>();
  final trasnformationController = TransformationController();
  final Map<CodeForgeController, String> _savedSnapshotByController = {};
  final Map<CodeForgeController, VoidCallback> _editorListeners = {};
  final Map<CodeForgeController, VoidCallback> _diagnosticListeners = {};
  final Set<CodeForgeController> _dirtyControllers = {};
  final Map<CodeForgeController, int> _lastErrorCountByController = {};
  late final TextEditingController createFileController, findWordController;
  late final TextEditingController replaceWordController, apiUrlController;
  late final TabController apiTabController, paramTabController;
  late final ActiveEditorBloc _activeEditorBloc;
  late final DiagnosticsTickBloc _diagnosticsTickBloc;
  late final List<SSHInfo> sshServerList;
  late final SSHPrivateKey? termuxInfo;
  late List<int> mruOrder;
  bool _allowImmediatePop = false, _didInitializeEditors = false;
  bool _viteUseHttps = false, _isOpeningVitePreview = false, _hasViteProject = false;
  Map<String, String> params = {}, headers = {};
  TabController? tabController;
  int _vitePort = 5173;
  Process? _vitePreviewProcess;
  AnimationStatus _terminalSelectionStatus = .dismissed, _runtimeSelectionStatus = .dismissed;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    final uiBloc = context.read<ConfigBloc>();
    _activeEditorBloc = ActiveEditorBloc(
      widget.rootDir,
      uiBloc.state.codeForgeConfig,
    );
    _diagnosticsTickBloc = DiagnosticsTickBloc();
    mruOrder = [0];
    createFileController = TextEditingController();
    findWordController = TextEditingController();
    replaceWordController = TextEditingController();
    apiUrlController = TextEditingController();
    trasnformationController.value = Matrix4.identity()..scaleByVector3(Vector3(1.45, 1.45, 1.45));
    apiTabController = TabController(length: 3, vsync: this);
    paramTabController = TabController(length: 3, vsync: this);
    sshServerList = context.read<SSHServersCubit>().state.serverList.where((server)=> server.isConnected == true).toList();
    termuxInfo = context.read<TermuxCubit>().state.termInfo;
    assert(
      !(widget.isProject && widget.languageDetails != null),
      "Cannot have both isProject and language details",
    );
    assert(
      !(!widget.isProject && widget.isCloned),
      "Cloned directory should be a project.",
    );
    _initializeCopilotForEditorIfEnabled();
    _loadVitePreviewInfo();
  }

  Future<void> _loadVitePreviewInfo() async {
    final viteTs = File(path.join(widget.rootDir, 'vite.config.ts'));
    final viteJs = File(path.join(widget.rootDir, 'vite.config.js'));
    final packageJson = File(path.join(widget.rootDir, 'package.json'));

    final hasViteConfig = await viteTs.exists() || await viteJs.exists();
    final hasPkg = await packageJson.exists();
    final hasVite = hasViteConfig && hasPkg;

    if (!hasVite) {
      if (!mounted) return;
      setState(() {
        _hasViteProject = false;
        _vitePort = 5173;
        _viteUseHttps = false;
      });
      return;
    }

    String configText = '';
    if (await viteTs.exists()) {
      configText = await viteTs.readAsString();
    } else if (await viteJs.exists()) {
      configText = await viteJs.readAsString();
    }

    String packageText = '';
    if (await packageJson.exists()) {
      packageText = await packageJson.readAsString();
    }

    final detectedPort = _extractVitePort(configText) ??
        _extractVitePort(packageText) ??
        5173;
    final useHttps = _extractViteHttps(configText) ||
        _extractViteHttps(packageText);

    if (!mounted) return;
    setState(() {
      _hasViteProject = true;
      _vitePort = detectedPort;
      _viteUseHttps = useHttps;
    });
  }

  int? _extractVitePort(String text) {
    final patterns = <RegExp>[
      RegExp(r'port\s*:\s*(\d+)', caseSensitive: false),
      RegExp(r'--port(?:\s+|=)(\d+)', caseSensitive: false),
      RegExp(r'\s-p(?:\s+|=)(\d+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return int.tryParse(match.group(1) ?? '');
      }
    }
    return null;
  }

  bool _extractViteHttps(String text) {
    final patterns = <RegExp>[
      RegExp(r'https\s*:\s*true', caseSensitive: false),
      RegExp(r'--https\b', caseSensitive: false),
    ];
    return patterns.any((pattern) => pattern.hasMatch(text));
  }

  Future<int> _resolveRunningVitePort() async {
    final candidates = <int>{
      _vitePort,
      for (int p = 5173; p <= 5190; p++) p,
    };

    for (final port in candidates) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(milliseconds: 150),
        );
        await socket.close();
        return port;
      } catch (_) {}
    }

    return _vitePort;
  }

  Future<bool> _isPortOpen(int port) async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(milliseconds: 200),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startViteServerInBackground() async {
    if (_vitePreviewProcess != null) return;

    final viteBin = File(path.join(widget.rootDir, 'node_modules/vite/bin/vite.js'));
    if (!await viteBin.exists()) {
      throw Exception('Vite binary not found. Install dependencies first.');
    }

    final sharedPath = await NativeChannel.getLibraryPath();
    final process = await Process.start(
      '$binDir/node',
      [
        'node_modules/vite/bin/vite.js',
        '--host',
        '0.0.0.0',
      ],
      workingDirectory: widget.rootDir,
      environment: {
        'PATH': '$binDir:/bin:/usr/bin',
        'HOME': homeDir,
        'ROXUM_SHARED_PATH': sharedPath,
        'LD_LIBRARY_PATH':
            '$runtimesDir/node/lib:$sharedPath:${Platform.environment['LD_LIBRARY_PATH'] ?? ''}',
      },
    );

    process.exitCode.then((_) {
      if (identical(_vitePreviewProcess, process)) {
        _vitePreviewProcess = null;
      }
    });
    _vitePreviewProcess = process;
  }

  Future<int?> _waitForVitePort({Duration timeout = const Duration(seconds: 8)}) async {
    final started = DateTime.now();
    while (DateTime.now().difference(started) < timeout) {
      final resolved = await _resolveRunningVitePort();
      if (await _isPortOpen(resolved)) {
        return resolved;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  Future<void> _openVitePreview() async {
    if (_isOpeningVitePreview || !mounted) return;
    setState(() => _isOpeningVitePreview = true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: const [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Opening web view...')),
              ],
            ),
          ),
        );
      },
    );

    try {
      int? runningPort;
      final currentPort = await _resolveRunningVitePort();
      if (await _isPortOpen(currentPort)) {
        runningPort = currentPort;
      } else {
        await _startViteServerInBackground();
        runningPort = await _waitForVitePort();
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (runningPort == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not start Vite server. Open terminal to inspect logs.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final url =
          '${_viteUseHttps ? 'https' : 'http'}://localhost:$runningPort';
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, scondaryAnimation) =>
              WebViewScreen(streamUrl: url),
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
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open preview: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningVitePreview = false);
      }
    }
  }

  Future<void> _initializeCopilotForEditorIfEnabled() async {
    final isCopilotEnabled = await isCopilotEnabledPref();
    final isCopilotSignedIn = await isCopilotSignedPref();
    if ((!isCopilotEnabled && !isCopilotSignedIn) || !mounted) {
      return;
    }

    if (!Directory('$extensionDir/copilot-language-server').existsSync()) {
      return;
    }

    final copilotBloc = context.read<CopilotBloc>();
    if (copilotBloc.state.isInitialized ||
        copilotBloc.state.status == CopilotStatus.initializing) {
      return;
    }

    copilotBloc.add(
      CopilotInitialize(configPath: filesDir, workspacePath: widget.rootDir),
    );
  }

  String _lspLanguageIdForPath(Language language, String filePath) {
    return lspLanguageIdForFile(language: language, filePath: filePath);
  }

  bool _isPreviewEditor(ActiveEditor editor) {
    return isPreviewFilePath(editor.file.path);
  }

  Widget _buildTabIconForEditor(ActiveEditor editor, AppTheme appTheme) {
    if (isImageFilePath(editor.file.path) || isSvgFilePath(editor.file.path)) {
      return Icon(
        Icons.image,
        size: 16,
        color: appTheme.isDark
            ? const Color(0xffc0c0c0)
            : const Color(0xff4b4b4b),
      );
    }

    if (isPdfFilePath(editor.file.path)) {
      return Icon(
        Icons.picture_as_pdf,
        size: 16,
        color: appTheme.isDark
            ? const Color(0xffc0c0c0)
            : const Color(0xff4b4b4b),
      );
    }

    final icon = editor.languageDetails.icon;
    if (icon is Widget) {
      return SizedBox(
        height: 16,
        width: 16,
        child: FittedBox(
          fit: BoxFit.contain,
          child: icon,
        ),
      );
    }

    return Icon(
      Icons.insert_drive_file,
      size: 16,
      color: appTheme.isDark
          ? const Color(0xffc0c0c0)
          : const Color(0xff4b4b4b),
    );
  }

  Future<ActiveEditor> _buildEditorForFile(File file) async {
    if (isPreviewFilePath(file.path)) {
      final previewController = CodeForgeController()..readOnly = true;
      return ActiveEditor(
        controller: previewController,
        undoRedoController: UndoRedoController(),
        file: file,
        isActive: true,
        languageDetails: languages[0],
        hscroll: ScrollController(),
        vscroll: ScrollController(),
      );
    }

    final lang = languages.firstWhere(
      (language) => language.extension.contains(
        path.extension(file.path).replaceFirst('.', ''),
      ),
      orElse: () => languages[0],
    );

    final activeEditorBloc = _activeEditorBloc;
    final codeForgeConfig = context.read<ConfigBloc>().state.codeForgeConfig;
    LspConfig? lspConfig;

    if (codeForgeConfig['enableLSP']) {
      lspConfig = await activeEditorBloc.getOrStartSharedLspConfig(
        languageId: _lspLanguageIdForPath(lang, file.path),
        ext: lspServerExtForFilePath(file.path),
        executable: lang.lspExecutable,
        args: lang.args ?? [],
        capabilities: _getLspCapabilities(
          codeForgeConfig,
          lang.name.toLowerCase(),
        ),
      );
    }

    final newController = CodeForgeController(lspConfig: lspConfig);
    await _applyPendingAgenticDiffForFile(newController, file.path);

    return ActiveEditor(
      controller: newController,
      undoRedoController: UndoRedoController(),
      file: file,
      isActive: true,
      languageDetails: lang,
      findController: FindController(newController),
      hscroll: ScrollController(),
      vscroll: ScrollController(),
    );
  }

  Future<void> _openFileInTabs({
    required BuildContext actionContext,
    required List<ActiveEditor> currentState,
    required File file,
    int? lineNumber,
    String searchQuery = '',
  }) async {
    final canonicalPath = file.absolute.path;
    final existingIndex = currentState.indexWhere(
      (editor) => File(editor.file.path).absolute.path == canonicalPath,
    );

    if (existingIndex >= 0) {
      for (int i = 0; i < currentState.length; i++) {
        currentState[i].isActive = i == existingIndex;
      }
      mruOrder.remove(existingIndex);
      mruOrder.insert(0, existingIndex);

      if (!actionContext.mounted) return;
      _activeEditorBloc.add(ActiveEditorEvent(currentState));

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (tabController != null && existingIndex < tabController!.length) {
          tabController!.animateTo(existingIndex);
        }
        if (searchQuery.isNotEmpty && lineNumber != null) {
          final existingEditor = currentState[existingIndex];
          if (existingEditor.findController != null) {
            _goToMatchNearLine(existingEditor, lineNumber, searchQuery);
          }
        }
        _applyWorkspaceSearchToActiveEditor();
      });
      return;
    }

    for (final editor in currentState) {
      editor.isActive = false;
    }

    final newEditor = await _buildEditorForFile(file);
    currentState.add(newEditor);
    mruOrder.insert(0, currentState.length - 1);

    if (!actionContext.mounted) return;
    _activeEditorBloc.add(ActiveEditorEvent(currentState));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final newIndex = currentState.indexWhere((item) => item.isActive == true);
      if (tabController != null && newIndex >= 0 && newIndex < tabController!.length) {
        tabController!.animateTo(newIndex);
      }

      if (searchQuery.isNotEmpty && lineNumber != null && newEditor.findController != null) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          _goToMatchNearLine(newEditor, lineNumber, searchQuery);
        });
      }

      _applyWorkspaceSearchToActiveEditor();
    });
  }

  Widget _buildImagePreviewPane(ActiveEditor editor, AppTheme appTheme) {
    return Container(
      color: appTheme.editorPageDrawerBg,
      alignment: Alignment.center,
      child: InteractiveViewer(
        minScale: 0.2,
        maxScale: 8,
        child: Image.file(
          editor.file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, size: 44),
                  const SizedBox(height: 8),
                  Text(
                    'Failed to load image preview',
                    style: TextStyle(color: appTheme.selectScreenCardTextColor),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSvgPreviewPane(ActiveEditor editor, AppTheme appTheme) {
    return _SvgPreviewPane(file: editor.file, appTheme: appTheme);
  }

  Widget _buildPreviewPane(ActiveEditor editor, AppTheme appTheme) {
    if (isImageFilePath(editor.file.path)) {
      return _buildImagePreviewPane(editor, appTheme);
    }

    if (isSvgFilePath(editor.file.path)) {
      return _buildSvgPreviewPane(editor, appTheme);
    }

    if (isPdfFilePath(editor.file.path)) {
      return _PdfPreviewPane(filePath: editor.file.path, appTheme: appTheme);
    }

    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final entry in _editorListeners.entries) {
      entry.key.removeListener(entry.value);
    }
    for (final entry in _diagnosticListeners.entries) {
      entry.key.diagnosticsNotifier.removeListener(entry.value);
    }
    _editorListeners.clear();
    _diagnosticListeners.clear();
    _savedSnapshotByController.clear();
    _dirtyControllers.clear();
    _lastErrorCountByController.clear();
    apiUrlController.dispose();
    apiTabController.dispose();
    paramTabController.dispose();
    findWordController.dispose();
    trasnformationController.dispose();
    tabController?.removeListener(_onTabChanged);
    tabController?.dispose();
    _diagnosticsTickBloc.close();
    _vitePreviewProcess?.kill(ProcessSignal.sigterm);
    _vitePreviewProcess = null;
    _activeEditorBloc.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (!_activeEditorBloc.isClosed) {
          _activeEditorBloc.add(CloseActiveEditor());
        }
        break;
      case AppLifecycleState.resumed:
        break;
    }

    super.didChangeAppLifecycleState(state);
  }

  @override
  void reassemble() {
    super.reassemble();

    for (final entry in _diagnosticListeners.entries) {
      entry.key.diagnosticsNotifier.removeListener(entry.value);
    }
    _diagnosticListeners.clear();
    _lastErrorCountByController.clear();
  }

  void _updateTabController(int tabCount) {
    if (tabController == null || tabController!.length != tabCount) {
      tabController?.removeListener(_onTabChanged);
      tabController?.dispose();
      tabController = TabController(length: tabCount, vsync: this);
      tabController!.addListener(_onTabChanged);
    }
  }

  void _syncActiveEditorWithTabIndex(int index) {
    final currentEditors = _activeEditorBloc.state.activeEditors;
    if (currentEditors.isEmpty || index < 0 || index >= currentEditors.length) {
      return;
    }

    final currentActiveIndex = currentEditors.indexWhere((e) => e.isActive);
    if (currentActiveIndex == index) return;

    final updatedEditors = List<ActiveEditor>.from(currentEditors);
    for (int i = 0; i < updatedEditors.length; i++) {
      updatedEditors[i].isActive = i == index;
    }
    _activeEditorBloc.add(ActiveEditorEvent(updatedEditors));
  }

  void _onTabChanged() {
    if (tabController == null) return;

    final currentIndex = tabController!.index;
    _syncActiveEditorWithTabIndex(currentIndex);
    mruOrder.remove(currentIndex);
    mruOrder.insert(0, currentIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyWorkspaceSearchToActiveEditor();
    });
  }

  void _applyWorkspaceSearchToActiveEditor() {
    if (!mounted) return;

    try {
      final searchState = context.read<WorkspaceSearchBloc>().state;
      final editorState = _activeEditorBloc.state;

      if (searchState.query.isEmpty) return;
      if (editorState.activeEditors.isEmpty) return;

      final activeIndex = tabController?.index ?? 0;
      if (activeIndex < 0 || activeIndex >= editorState.activeEditors.length) {
        return;
      }

      final editor = editorState.activeEditors[activeIndex];
      _applySearchHighlighting(editor, searchState.query, searchState);
    } catch (_) {}
  }

  void _applySearchHighlighting(
    ActiveEditor editor,
    String query,
    WorkspaceSearchState searchState,
  ) {
    if (editor.findController == null) return;

    final findController = editor.findController!;

    findController.caseSensitive = searchState.matchCase;
    findController.matchWholeWord = searchState.matchWholeWord;
    findController.isRegex = searchState.isRegex;

    findController.findInputController.text = query;
    findController.find(query, scrollToMatch: false);
  }

  void _clearSearchHighlighting(ActiveEditor editor) {
    if (editor.findController == null) return;
    editor.findController!.find('', scrollToMatch: false);
    editor.findController!.findInputController.clear();
  }

  Future<void> _applyPendingAgenticDiffForFile(
    CodeForgeController controller,
    String filePath,
  ) async {
    try {
      final canonicalPath = File(filePath).absolute.path;
      final pending = await PendingEditFile.getForFile(canonicalPath);
      if (!mounted) return;

      if (pending == null || pending.editHunks.isEmpty) {
        return;
      }

      pending.applyDecorations(controller);
    } catch (_) {
    }
  }

  void _goToMatchNearLine(
    ActiveEditor editor,
    int targetLine,
    String searchQuery,
  ) {
    if (editor.findController == null) return;

    final findController = editor.findController!;
    final codeController = editor.controller;
    final text = codeController.text;

    findController.findInputController.text = searchQuery;
    findController.find(searchQuery);

    if (findController.matchCount == 0) return;

    final lines = text.split('\n');
    int targetCharOffset = 0;
    for (int i = 0; i < targetLine - 1 && i < lines.length; i++) {
      targetCharOffset += lines[i].length + 1;
    }

    int targetLineEnd = targetCharOffset;
    if (targetLine - 1 < lines.length) {
      targetLineEnd += lines[targetLine - 1].length;
    }

    final lowerText = findController.caseSensitive ? text : text.toLowerCase();
    final lowerQuery = findController.caseSensitive
        ? searchQuery
        : searchQuery.toLowerCase();

    final matchPositions = <int>[];
    int pos = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, pos);
      if (index == -1) break;
      matchPositions.add(index);
      pos = index + 1;
    }

    if (matchPositions.isEmpty) return;

    int bestMatchIndex = 0;
    for (int i = 0; i < matchPositions.length; i++) {
      final matchStart = matchPositions[i];

      if (matchStart >= targetCharOffset && matchStart <= targetLineEnd) {
        bestMatchIndex = i;
        break;
      }
    }

    final currentIdx = findController.currentMatchIndex;
    final diff = bestMatchIndex - currentIdx;

    if (diff > 0) {
      for (int i = 0; i < diff; i++) {
        findController.next();
      }
    } else if (diff < 0) {
      for (int i = 0; i < -diff; i++) {
        findController.previous();
      }
    }
  }

  LspClientCapabilities? _getLspCapabilities(
    Map<String, dynamic> config,
    String langKey,
  ) {
    final Map<String, dynamic> featureToggle = Map<String, dynamic>.from(
      config["LSPFeatureToggle"] ?? {},
    );
    final List<String> disabledFeatures = List<String>.from(
      featureToggle[langKey] ?? [],
    );

    if (disabledFeatures.isEmpty) {
      return null;
    }

    return LspClientCapabilities(
      semanticHighlighting: !disabledFeatures.contains('semanticHighlighting'),
      codeCompletion: !disabledFeatures.contains('codeCompletion'),
      hoverInfo: !disabledFeatures.contains('hoverInfo'),
      codeAction: !disabledFeatures.contains('codeAction'),
      signatureHelp: !disabledFeatures.contains('signatureHelp'),
      documentColor: !disabledFeatures.contains('documentColor'),
      documentHighlight: !disabledFeatures.contains('documentHighlight'),
      codeFolding: !disabledFeatures.contains('codeFolding'),
      inlayHint: !disabledFeatures.contains('inlayHint'),
      goToDefinition: !disabledFeatures.contains('goToDefinition'),
      rename: !disabledFeatures.contains('rename'),
    );
  }

  bool _isTrackableEditor(ActiveEditor editor) {
    if (_isPreviewEditor(editor)) {
      return false;
    }
    if (editor.customTitle?.contains('(Working Tree)') == true) {
      return false;
    }
    return !editor.controller.readOnly;
  }

  bool _isEditorDirty(ActiveEditor editor) {
    final autoSaveEnabled =
        context.read<GeneralBloc>().state.generalSettings['autoSave'] ?? true;
    if (autoSaveEnabled) return false;
    return _dirtyControllers.contains(editor.controller);
  }

  String _displayFileName(ActiveEditor editor) {
    final baseName = editor.customTitle ?? path.basename(editor.file.path);
    return _isEditorDirty(editor) ? '$baseName*' : baseName;
  }

  bool _hasUnsavedEditors(List<ActiveEditor> editors) {
    for (final editor in editors) {
      if (_isEditorDirty(editor)) return true;
    }
    return false;
  }

  void _attachDirtyListener(ActiveEditor editor) {
    final controller = editor.controller;
    if (_editorListeners.containsKey(controller) ||
        !_isTrackableEditor(editor)) {
      return;
    }

    String initialSnapshot = controller.text;
    try {
      if (editor.file.existsSync()) {
        initialSnapshot = editor.file.readAsStringSync();
      }
    } catch (_) {
      initialSnapshot = controller.text;
    }
    _savedSnapshotByController[controller] = initialSnapshot;

    void listener() {
      final savedSnapshot = _savedSnapshotByController[controller] ?? '';
      final isDirty = controller.text != savedSnapshot;
      final hasChanged = isDirty
          ? _dirtyControllers.add(controller)
          : _dirtyControllers.remove(controller);

      if (hasChanged && mounted) {
        setState(() {});
      }
    }

    controller.addListener(listener);
    _editorListeners[controller] = listener;
  }

  void _syncDirtyTracking(List<ActiveEditor> editors) {
    final currentControllers = editors.map((e) => e.controller).toSet();

    final removedControllers = _editorListeners.keys
        .where((controller) => !currentControllers.contains(controller))
        .toList();

    for (final controller in removedControllers) {
      final listener = _editorListeners.remove(controller);
      if (listener != null) {
        controller.removeListener(listener);
      }
      _dirtyControllers.remove(controller);
      _savedSnapshotByController.remove(controller);
    }

    final removedDiagnosticControllers = _diagnosticListeners.keys
        .where((controller) => !currentControllers.contains(controller))
        .toList();
    for (final controller in removedDiagnosticControllers) {
      final listener = _diagnosticListeners.remove(controller);
      if (listener != null) {
        controller.diagnosticsNotifier.removeListener(listener);
      }
      _lastErrorCountByController.remove(controller);
    }

    for (final editor in editors) {
      _attachDirtyListener(editor);
      _attachDiagnosticListener(editor);
    }
  }

  ActiveEditor? _resolveActiveEditor(List<ActiveEditor> editors) {
    if (editors.isEmpty) return null;

    if (tabController != null && tabController!.index < editors.length) {
      return editors[tabController!.index];
    }

    final activeIndex = editors.indexWhere((item) => item.isActive == true);
    if (activeIndex >= 0) {
      return editors[activeIndex];
    }

    return editors.first;
  }

  int _diagnosticErrorCount(List<LspErrors> diagnostics) {
    return diagnostics.where((diag) => diag.severity == 1).length;
  }

  int _openEditorsErrorCount(List<ActiveEditor> editors) {
    var total = 0;
    for (final editor in editors) {
      total += _diagnosticErrorCount(editor.controller.diagnostics);
    }
    return total;
  }

  String _diagnosticSeverityLabel(int severity) {
    switch (severity) {
      case 1:
        return 'Error';
      case 2:
        return 'Warning';
      case 3:
        return 'Info';
      case 4:
        return 'Hint';
      default:
        return 'Issue';
    }
  }

  Color _diagnosticSeverityColor(int severity, AppTheme appTheme) {
    switch (severity) {
      case 1:
        return const Color(0xffe45757);
      case 2:
        return const Color(0xfff3a73f);
      case 3:
      case 4:
        return appTheme.isDark
            ? const Color(0xff58a6ff)
            : const Color(0xff1267c4);
      default:
        return appTheme.editorPageToolColor;
    }
  }

  IconData _diagnosticSeverityIcon(int severity) {
    switch (severity) {
      case 1:
        return Icons.error_rounded;
      case 2:
        return Icons.warning_amber_rounded;
      case 3:
      case 4:
        return Icons.info_outline_rounded;
      default:
        return Icons.bug_report_outlined;
    }
  }

  int _offsetFromLineAndCharacter(
    String text,
    int zeroBasedLine,
    int zeroBasedCharacter,
  ) {
    if (text.isEmpty) return 0;

    final safeLine = zeroBasedLine < 0 ? 0 : zeroBasedLine;
    final safeChar = zeroBasedCharacter < 0 ? 0 : zeroBasedCharacter;
    final lines = text.split('\n');
    if (safeLine >= lines.length) {
      return text.length;
    }

    var offset = 0;
    for (var index = 0; index < safeLine; index++) {
      offset += lines[index].length + 1;
    }

    final lineLength = lines[safeLine].length;
    offset += safeChar > lineLength ? lineLength : safeChar;
    return offset > text.length ? text.length : offset;
  }

  void _attachDiagnosticListener(ActiveEditor editor) {
    final controller = editor.controller;
    final existingListener = _diagnosticListeners.remove(controller);
    if (existingListener != null) {
      controller.diagnosticsNotifier.removeListener(existingListener);
    }

    _lastErrorCountByController[controller] = _diagnosticErrorCount(
      controller.diagnostics,
    );

    void listener() {
      _lastErrorCountByController[controller] = _diagnosticErrorCount(
        controller.diagnostics,
      );

      if (mounted && !_diagnosticsTickBloc.isClosed) {
        _diagnosticsTickBloc.tick();
      }
    }

    controller.diagnosticsNotifier.addListener(listener);
    _diagnosticListeners[controller] = listener;
  }

  Widget _buildBadgedIcon({
    required Widget icon,
    required int count,
    required AppTheme appTheme,
    Color? badgeColor,
  }) {
    if (count <= 0) return icon;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -5,
          top: -6,
          child: Container(
            decoration: BoxDecoration(
              color: badgeColor ?? const Color(0xffd9534f),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: appTheme.editorPageToolbarBg,
                width: 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showDiagnosticDetailsSheet(
    BuildContext actionContext,
    ActiveEditor editor,
    LspErrors diagnostic,
    AppTheme appTheme,
  ) {
    final start = Map<String, dynamic>.from(diagnostic.range['start'] ?? {});
    final end = Map<String, dynamic>.from(diagnostic.range['end'] ?? {});
    final startLine = ((start['line'] as num?) ?? 0).toInt() + 1;
    final startChar = ((start['character'] as num?) ?? 0).toInt() + 1;
    final endLine = ((end['line'] as num?) ?? 0).toInt() + 1;
    final endChar = ((end['character'] as num?) ?? 0).toInt() + 1;
    final severityColor = _diagnosticSeverityColor(diagnostic.severity, appTheme);

    showModalBottomSheet<void>(
      context: actionContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: appTheme.isDark
                ? const Color(0xff1f1f1f)
                : const Color(0xfff4f6f8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: appTheme.editorPageToolColor.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: severityColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _diagnosticSeverityIcon(diagnostic.severity),
                          color: severityColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _diagnosticSeverityLabel(diagnostic.severity),
                              style: TextStyle(
                                color: severityColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              diagnostic.message,
                              style: TextStyle(
                                color: appTheme.selectScreenCardTextColor,
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: appTheme.editorPageDrawerBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          path.basename(editor.file.path),
                          style: TextStyle(
                            color: appTheme.selectScreenCardTextColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Line $startLine:$startChar  ->  $endLine:$endChar',
                          style: TextStyle(
                            color: appTheme.editorPageToolColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDiagnosticSummaryCard({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    required AppTheme appTheme,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: appTheme.editorPageDrawerBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(
              '$count',
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: appTheme.editorPageToolColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticSection({
    required String title,
    required List<LspErrors> diagnostics,
    required ActiveEditor editor,
    required AppTheme appTheme,
  }) {
    if (diagnostics.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: appTheme.selectScreenCardTextColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        ...diagnostics.map((diag) {
          final severityColor = _diagnosticSeverityColor(diag.severity, appTheme);
          final start = Map<String, dynamic>.from(diag.range['start'] ?? {});
          final line = ((start['line'] as num?) ?? 0).toInt() + 1;
          final character = ((start['character'] as num?) ?? 0).toInt() + 1;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  final offset = _offsetFromLineAndCharacter(
                    editor.controller.text,
                    line - 1,
                    character - 1,
                  );
                  editor.controller.selection = TextSelection.collapsed(
                    offset: offset,
                  );
                  _showDiagnosticDetailsSheet(
                    context,
                    editor,
                    diag,
                    appTheme,
                  );
                },
                child: Ink(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: appTheme.editorPageDrawerBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: severityColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          _diagnosticSeverityIcon(diag.severity),
                          color: severityColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              diag.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: appTheme.selectScreenCardTextColor,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Line $line:$character',
                              style: TextStyle(
                                color: appTheme.editorPageToolColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDiagnosticsPane(
    AppTheme appTheme,
    ActiveEditorState editorState,
  ) {
    final activeEditor = _resolveActiveEditor(editorState.activeEditors);
    if (activeEditor == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Open a file to view diagnostics.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: appTheme.editorPageToolColor,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    if (_isPreviewEditor(activeEditor)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Diagnostics are not available for image/SVG/PDF preview tabs.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: appTheme.editorPageToolColor,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    final diagnostics = activeEditor.controller.diagnostics;
    final errors = diagnostics.where((diag) => diag.severity == 1).toList();
    final warnings = diagnostics.where((diag) => diag.severity == 2).toList();
    final infos = diagnostics
      .where((diag) => diag.severity == 3 || diag.severity == 4)
      .toList();

    if (diagnostics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.task_alt_rounded,
                color: appTheme.editorPageToolColor,
                size: 34,
              ),
              const SizedBox(height: 10),
              Text(
                'No diagnostics in this file',
                style: TextStyle(
                  color: appTheme.selectScreenCardTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'LSP issues will appear here when available.',
                textAlign: TextAlign.center,
                style: TextStyle(color: appTheme.editorPageToolColor),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      children: [
        Text(
          'DIAGNOSTICS',
          style: TextStyle(
            color: appTheme.selectScreenCardTextColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildDiagnosticSummaryCard(
              label: 'Errors',
              count: errors.length,
              color: _diagnosticSeverityColor(1, appTheme),
              icon: _diagnosticSeverityIcon(1),
              appTheme: appTheme,
            ),
            const SizedBox(width: 8),
            _buildDiagnosticSummaryCard(
              label: 'Warnings',
              count: warnings.length,
              color: _diagnosticSeverityColor(2, appTheme),
              icon: _diagnosticSeverityIcon(2),
              appTheme: appTheme,
            ),
            const SizedBox(width: 8),
            _buildDiagnosticSummaryCard(
              label: 'Info',
              count: infos.length,
              color: _diagnosticSeverityColor(3, appTheme),
              icon: _diagnosticSeverityIcon(3),
              appTheme: appTheme,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildDiagnosticSection(
          title: 'Errors',
          diagnostics: errors,
          editor: activeEditor,
          appTheme: appTheme,
        ),
        if (errors.isNotEmpty) const SizedBox(height: 8),
        _buildDiagnosticSection(
          title: 'Warnings',
          diagnostics: warnings,
          editor: activeEditor,
          appTheme: appTheme,
        ),
        if (warnings.isNotEmpty) const SizedBox(height: 8),
        _buildDiagnosticSection(
          title: 'Info & Hints',
          diagnostics: infos,
          editor: activeEditor,
          appTheme: appTheme,
        ),
      ],
    );
  }

  Future<void> _saveEditor(
    BuildContext actionContext,
    ActiveEditor editor,
  ) async {
    if (!_isTrackableEditor(editor)) return;

    try {
      editor.controller.saveFile();
      _savedSnapshotByController[editor.controller] = editor.controller.text;
      _dirtyControllers.remove(editor.controller);
      if (mounted) {
        try {
          actionContext.read<RepoStatusBloc>().add(
            LoadRepoStatus(widget.rootDir),
          );
        } catch (_) {}
        setState(() {});
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _saveActiveEditor(
    BuildContext actionContext,
    List<ActiveEditor> editors,
  ) async {
    if (editors.isEmpty) return;

    final activeIndex =
        tabController != null && tabController!.index < editors.length
        ? tabController!.index
        : editors.indexWhere((item) => item.isActive);
    final safeIndex = activeIndex < 0 ? 0 : activeIndex;
    await _saveEditor(actionContext, editors[safeIndex]);
  }

  Future<bool> _handleExitWithUnsavedPrompt(
    BuildContext actionContext,
    List<ActiveEditor> editors,
  ) async {
    final unsavedEditors = editors.where(_isEditorDirty).toList();
    if (unsavedEditors.isEmpty) {
      return true;
    }
    final appTheme = actionContext.read<AppThemeBloc>().state.appTheme;

    final action = await showDialog<String>(
      context: actionContext,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: appTheme.isDark
              ? const Color(0xff2b2b2b)
              : const Color.fromARGB(255, 240, 240, 240),
          icon: const Icon(Icons.warning_amber_rounded, size: 34),
          iconColor: Colors.orange[700],
          title: Text(
            'Unsaved Changes',
            style: TextStyle(
              color: appTheme.selectScreenCardTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          content: Text(
            unsavedEditors.length == 1
                ? 'Save changes to ${path.basename(unsavedEditors.first.file.path)} before exiting?'
                : 'Save changes to ${unsavedEditors.length} files before exiting?',
            style: TextStyle(color: Colors.grey[appTheme.isDark ? 400 : 700]),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: appTheme.editorPageToolColor,
              ),
              onPressed: () => Navigator.of(dialogContext).pop('cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red[400]),
              onPressed: () => Navigator.of(dialogContext).pop('discard'),
              child: const Text("Don't Save"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: appTheme.editorPageToolSelectedBgColor,
                foregroundColor: appTheme.editorPageToolSelectedColor,
              ),
              onPressed: () => Navigator.of(dialogContext).pop('save'),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (action == 'cancel' || action == null) {
      return false;
    }

    if (action == 'save' && context.mounted) {
      for (final editor in unsavedEditors) {
        await _saveEditor(actionContext, editor);
      }
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme appTheme = context.read<AppThemeBloc>().state.appTheme;
    final ConfigBloc uiBloc = BlocProvider.of<ConfigBloc>(context);
    final autoSaveEnabled = context.watch<GeneralBloc>().state.generalSettings['autoSave'] ?? true;
    return FutureBuilder(
      future: Future.wait([
        widget.file == null && !widget.isProject
            ? setTempFile(widget.languageDetails!.extension[0])
            : Future.value(widget.file),
        (() async {
          final prefs = await SharedPreferences.getInstance();
          List<dynamic> storedData = jsonDecode(await getRecent());
          final Map<String, dynamic> dataToInsert;
          if (widget.isProject) {
            dataToInsert = {
              'type': 'project',
              'path': widget.rootDir,
              'rootDir': widget.rootDir,
            };
          } else {
            final File file =
                widget.file ??
                await setTempFile(widget.languageDetails!.extension[0]);
            dataToInsert = {
              'type': 'file',
              'path': file.path,
              'rootDir': widget.rootDir,
            };
          }
          final Set<String> uniquePaths = {};
          storedData.insert(0, dataToInsert);
          final List<dynamic> uniqueData = [];
          Map<String, dynamic>? normalizeRecentEntry(dynamic rawEntry) {
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

          for (final data in storedData) {
            final normalized = normalizeRecentEntry(data);
            if (normalized == null) {
              continue;
            }

            final uniqueKey = '${normalized['type']}:${normalized['path']}';
            if (!uniquePaths.contains(uniqueKey)) {
              uniquePaths.add(uniqueKey);
              uniqueData.add(normalized);
            }
          }
          if (uniqueData.length > 3) {
            uniqueData.removeRange(3, uniqueData.length);
          }
          if (context.mounted) {
            context.read<RecentBloc>().add(RecentEvent(recent: uniqueData));
          }
          prefs.setString('recent', jsonEncode(uniqueData));
        })(),
        uiBloc.state.codeForgeConfig['enableLSP'] &&
            !widget.isProject &&
            !(widget.file != null && isPreviewFilePath(widget.file!.path))
            ? (() async {
                final initialPath =
                    widget.file?.path ??
                    '${widget.rootDir}/temp.${widget.languageDetails!.extension[0]}';
                final languageId = _lspLanguageIdForPath(
                  widget.languageDetails!,
                  initialPath,
                );
                return _activeEditorBloc.getOrStartSharedLspConfig(
                  languageId: languageId,
                  ext: lspServerExtForFilePath(initialPath),
                  executable: widget.languageDetails!.lspExecutable,
                  args: widget.languageDetails!.args ?? [],
                  capabilities: _getLspCapabilities(
                    uiBloc.state.codeForgeConfig,
                    widget.languageDetails!.name.toLowerCase(),
                  ),
                );
              })()
            : Future.value(null),
      ]),
      builder: (context, snapshot) {
        if (snapshot.hasError && !widget.isProject) {
          return Scaffold(
            resizeToAvoidBottomInset: true,
            appBar: AppBar(title: const Text('Error')),
            body: SingleChildScrollView(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to initialize editor',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if ((!snapshot.hasData ||
                snapshot.data == null ||
                snapshot.data!.isEmpty) &&
            !widget.isProject) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 48,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No data received',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          );
        }

        final target = !widget.isProject ? snapshot.data![0] as File? : null;
        final lspConfig = !widget.isProject
            ? snapshot.data!.length > 2
                  ? snapshot.data![2] as LspConfig?
                  : null
            : null;

        if ((target == null || !target.existsSync()) && !widget.isProject) {
          return Scaffold(
            appBar: AppBar(title: const Text('Error')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 48,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to create or access file',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    target?.path ?? 'Unknown path',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          );
        }

        final isRepoThere = Directory(
          path.join(widget.rootDir, ".git"),
        ).existsSync();

        if (!_didInitializeEditors) {
          _didInitializeEditors = true;
          if (widget.isProject) {
            _activeEditorBloc.add(OpenRecentActiveEditor());
          } else {
            final isPreviewInitial = isPreviewFilePath(target!.path);
            final initialController = CodeForgeController(lspConfig: lspConfig);
            if (isPreviewInitial) {
              initialController.readOnly = true;
            } else {
              _applyPendingAgenticDiffForFile(initialController, target.path);
            }
            final initialUndoController = UndoRedoController();
            _activeEditorBloc.add(
              ActiveEditorEvent([
                ActiveEditor(
                  file: target,
                  controller: initialController,
                  languageDetails: widget.languageDetails ?? languages[0],
                  undoRedoController: initialUndoController,
                  isActive: true,
                  findController: isPreviewInitial
                      ? null
                      : FindController(initialController),
                  hscroll: ScrollController(),
                  vscroll: ScrollController(),
                ),
              ]),
            );
          }
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: _activeEditorBloc),
            BlocProvider.value(value: _diagnosticsTickBloc),
            BlocProvider(create: (_) => StackBloc()),
            BlocProvider(create: (_) => FindWordBloc()),
            BlocProvider(create: (_) => ApiBloc()),
            BlocProvider(create: (_) => FolderBloc()),
            BlocProvider(create: (_) => AIChatBloc()),
            BlocProvider(create: (_) => AIChatUIBloc()),
            BlocProvider(create: (_) => WorkspaceSearchBloc()),
            BlocProvider(
              create: (_) =>
                  RepoStatusBloc()..add(LoadRepoStatus(widget.rootDir)),
            ),
          ],
          child: BlocListener<WorkspaceSearchBloc, WorkspaceSearchState>(
            listenWhen: (previous, current) =>
                previous.query != current.query ||
                previous.matchCase != current.matchCase ||
                previous.matchWholeWord != current.matchWholeWord ||
                previous.isRegex != current.isRegex,
            listener: (context, searchState) {
              final editorState = context.read<ActiveEditorBloc>().state;
              for (final editor in editorState.activeEditors) {
                if (searchState.query.isEmpty) {
                  _clearSearchHighlighting(editor);
                } else {
                  _applySearchHighlighting(
                    editor,
                    searchState.query,
                    searchState,
                  );
                }
              }
            },
            child: BlocBuilder<ActiveEditorBloc, ActiveEditorState>(
              buildWhen: (previous, current) =>
                  previous.activeEditors.length != current.activeEditors.length,
              builder: (context, editorState) {
                _syncDirtyTracking(editorState.activeEditors);
                final hasDirtyFiles = _hasUnsavedEditors(
                  editorState.activeEditors,
                );
                _updateTabController(editorState.activeEditors.length);
                final activeIndex = editorState.activeEditors.indexWhere(
                  (e) => e.isActive,
                );
                if (activeIndex >= 0 &&
                    tabController != null &&
                    tabController!.index != activeIndex) {
                  tabController!.index = activeIndex;
                  mruOrder.remove(activeIndex);
                  mruOrder.insert(0, activeIndex);
                }
                return PopScope(
                  canPop:
                      _allowImmediatePop ||
                      !_hasUnsavedEditors(editorState.activeEditors),
                  onPopInvokedWithResult: (didPop, result) async {
                    if (didPop) {
                      context.read<ActiveEditorBloc>().add(CloseActiveEditor());
                      return;
                    }

                    final shouldExit = await _handleExitWithUnsavedPrompt(
                      context,
                      editorState.activeEditors,
                    );
                    if (!shouldExit || !context.mounted) {
                      return;
                    }

                    _allowImmediatePop = true;
                    context.read<ActiveEditorBloc>().add(CloseActiveEditor());
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Scaffold(
                    resizeToAvoidBottomInset: true,
                    drawer: BlocBuilder<StackBloc, StackState>(
                      buildWhen: (previous, current) => current != previous,
                      builder: (context, state) {
                        return Drawer(
                          width: 350,
                          backgroundColor: appTheme.editorPageDrawerBg,
                          child: Row(
                            children: [
                              Container(
                                color: appTheme.editorPageToolbarBg,
                                child: Column(
                                  children: [
                                    const SizedBox(height: 25),
                                    drawerButtons(
                                      () => context.read<StackBloc>().add(
                                        StackIndexChange(stackValue: 0),
                                      ),
                                      Icons.file_copy_outlined,
                                      color: state.stackIndex == 0
                                        ? appTheme.editorPageToolSelectedColor
                                        : appTheme.editorPageToolColor,
                                      bgColor: state.stackIndex == 0
                                        ? appTheme.editorPageToolSelectedBgColor
                                        : Colors.transparent,
                                    ),
                                    drawerButtons(
                                      () => context.read<StackBloc>().add(
                                        StackIndexChange(stackValue: 1),
                                      ),
                                      Icons.search,
                                      color: state.stackIndex == 1
                                        ? appTheme.editorPageToolSelectedColor
                                        : appTheme.editorPageToolColor,
                                      bgColor: state.stackIndex == 1
                                        ? appTheme.editorPageToolSelectedBgColor
                                        : Colors.transparent,
                                    ),
                                    drawerButtons(
                                      () => context.read<StackBloc>().add(
                                        StackIndexChange(stackValue: 2),
                                      ),
                                      BlocBuilder<DiagnosticsTickBloc, int>(
                                        builder: (context, _) {
                                          final openErrorCount = _openEditorsErrorCount(editorState.activeEditors);
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 3),
                                            child: _buildBadgedIcon(
                                              icon: Icon(
                                                Icons.rule_rounded,
                                                size: 31,
                                                color: state.stackIndex == 2
                                                  ? appTheme.editorPageToolSelectedColor
                                                  : appTheme.editorPageToolColor,
                                              ),
                                              count: openErrorCount,
                                              appTheme: appTheme,
                                            ),
                                          );
                                        },
                                      ),
                                      bgColor: state.stackIndex == 2
                                        ? appTheme.editorPageToolSelectedBgColor
                                        : Colors.transparent,
                                    ),
                                    drawerButtons(
                                      () => context.read<StackBloc>().add(
                                        StackIndexChange(stackValue: 3),
                                      ),
                                      FontAwesomeIcons.codeBranch,
                                      color: state.stackIndex == 3
                                        ? appTheme.editorPageToolSelectedColor
                                        : appTheme.editorPageToolColor,
                                      bgColor: state.stackIndex == 3
                                        ? appTheme.editorPageToolSelectedBgColor
                                        : Colors.transparent,
                                    ),
                                    drawerButtons(
                                      () => context.read<StackBloc>().add(
                                        StackIndexChange(stackValue: 4),
                                      ),
                                      SvgPicture.asset(
                                        'assets/icons/rest-api-icon.svg',
                                        height: 34,
                                        width: 34,
                                        colorFilter: ColorFilter.mode(
                                          state.stackIndex == 4
                                            ? appTheme.editorPageToolSelectedColor
                                            : appTheme.editorPageToolColor,
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                      bgColor: state.stackIndex == 4
                                        ? appTheme.editorPageToolSelectedBgColor
                                        : Colors.transparent,
                                    ),
                                    drawerButtons(
                                      () => context.read<StackBloc>().add(
                                        StackIndexChange(stackValue: 5),
                                      ),
                                      SvgPicture.asset(
                                        'assets/icons/ai.svg',
                                        height: 34,
                                        width: 34,
                                      ),
                                      bgColor: state.stackIndex == 5
                                        ? appTheme.editorPageToolSelectedBgColor
                                        : Colors.transparent,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5.5,
                                        vertical: 5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: IndexedStack(
                                  index: state.stackIndex,
                                  children: [
                                    Align(
                                      alignment: Alignment.topCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 20,
                                        ),
                                        child: ListView(
                                          children: [
                                            if (editorState.activeEditors.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 10),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'OPEN EDITORS',
                                                      style: TextStyle(
                                                        fontWeight:
                                                          appTheme.isDark
                                                          ? FontWeight.w300
                                                          : FontWeight.w500,
                                                        color: appTheme.selectScreenCardTextColor,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    ...List.generate(
                                                      editorState.activeEditors.length,
                                                      (index) {
                                                        final editor = editorState.activeEditors[index];
                                                        return InkWell(
                                                          onTap: () {
                                                            final List<ActiveEditor>
                                                            currentState = List.from(editorState.activeEditors);
                                                            for (int i = 0; i <currentState.length; i++) {
                                                              currentState[i].isActive = i == index;
                                                            }
                                                            context.read<ActiveEditorBloc>().add(ActiveEditorEvent(currentState));
                                                            if (tabController != null && tabController!.length > index) {
                                                              tabController!.animateTo(index);
                                                            }
                                                          },
                                                          child: Padding(
                                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                                            child: Text(
                                                              _displayFileName(editor),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: TextStyle(
                                                                color: appTheme.selectScreenCardTextColor,
                                                                fontWeight: editor.isActive
                                                                  ? FontWeight.w600
                                                                  : FontWeight.w400,
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                    const SizedBox(height: 14),
                                                  ],
                                                ),
                                              ),
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 15,
                                                ),
                                                child: Text(
                                                  "EXPLORER",
                                                  style: TextStyle(
                                                    fontWeight: appTheme.isDark
                                                        ? FontWeight.w300
                                                        : FontWeight.w500,
                                                    color: appTheme
                                                        .selectScreenCardTextColor,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            DirectoryTreeViewerCustom(
                                              appTheme: appTheme,
                                              activeEditorState: editorState,
                                              isUnfoldedFirst: false,
                                              rootPath: widget.rootDir,
                                              enableCreateFileOption: true,
                                              enableDeleteFileOption: true,
                                              enableDeleteFolderOption: true,
                                              enableCreateFolderOption: true,
                                              enableRenameFileOption: true,
                                              enableRenameFolderOption: true,
                                              enableGitFeatures: true,
                                              editingFieldStyle: EditingFieldStyle(
                                                textFieldWidth: MediaQuery.of(
                                                  context,
                                                ).size.width,
                                                textStyle: const TextStyle(
                                                  color: Colors.grey,
                                                ),
                                                cursorColor: Colors.grey,
                                                cursorHeight: 19,
                                                verticalTextAlign: TextAlignVertical.top,
                                                textfieldDecoration: const InputDecoration(
                                                  isDense: true,
                                                  contentPadding: EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 1.0),
                                                  focusedBorder:
                                                    OutlineInputBorder(
                                                      borderRadius: BorderRadius.all(Radius.circular(2)),
                                                      borderSide: BorderSide(color: Colors.grey),
                                                    ),
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                      BorderRadius.all(
                                                        Radius.circular(2),
                                                      ),
                                                    borderSide: BorderSide(
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ),
                                                folderIcon: const Icon(
                                                  Icons.folder,
                                                  color: Colors.grey,
                                                  size: 20,
                                                ),
                                                fileIcon: const Icon(
                                                  Icons.edit_document,
                                                  color: Colors.grey,
                                                  size: 20,
                                                ),
                                                doneIcon: const Icon(
                                                  Icons.check,
                                                  color: Colors.grey,
                                                  size: 20,
                                                ),
                                                cancelIcon: const Icon(
                                                  Icons.close,
                                                  color: Colors.grey,
                                                  size: 20,
                                                ),
                                              ),
                                              fileIconBuilder: (ext) {
                                                final normalizedExt = ext.toLowerCase().startsWith('.')
                                                  ? ext.toLowerCase()
                                                  : '.${ext.toLowerCase()}';
                                                if (isImageFilePath('preview$normalizedExt') || isSvgFilePath('preview$normalizedExt')) {
                                                  return const Icon(
                                                    Icons.image,
                                                    color: Colors.green,
                                                    size: 20,
                                                  );
                                                }
                                                if (normalizedExt == '.pdf') {
                                                  return const Icon(
                                                    Icons.picture_as_pdf,
                                                    color: Colors.red,
                                                    size: 20,
                                                  );
                                                }
                                                return SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child:languages.firstWhere(
                                                    (lang) => lang.extension.contains(normalizedExt.replaceFirst('.', '')),
                                                    orElse: () => languages[0]).icon ?? langtxt.icon,
                                                );
                                              },
                                              folderStyle: FolderStyle(
                                                iconForCreateFolder: Icon(
                                                  Icons.create_new_folder,
                                                  color: appTheme.isDark
                                                    ? Colors.grey
                                                    : const Color(0xff2b2b2b),
                                                ),
                                                iconForCreateFile: FaIcon(
                                                  FontAwesomeIcons.fileCirclePlus,
                                                  size: 20,
                                                  color: appTheme.isDark
                                                    ? Colors.grey
                                                    : const Color(0xff2b2b2b),
                                                ),
                                                rootFolderClosedIcon:
                                                  const Icon(
                                                    Icons.chevron_right_sharp,
                                                    color: Colors.grey,
                                                  ),
                                                rootFolderOpenedIcon: const Icon(
                                                  Icons.keyboard_arrow_down_sharp,
                                                  color: Colors.grey,
                                                ),
                                                folderClosedicon:SvgPicture.asset(
                                                    'assets/icons/folder.svg',
                                                    height: 23,
                                                    width: 23,
                                                  ),
                                                folderOpenedicon: SvgPicture.asset(
                                                  'assets/icons/open-file-folder.svg',
                                                  height: 23,
                                                  width: 23,
                                                ),
                                                folderNameStyle: TextStyle(
                                                  color: appTheme.selectScreenCardTextColor,
                                                  fontSize: 19,
                                                  fontWeight: appTheme.isDark
                                                    ? FontWeight.w400
                                                    : FontWeight.w500,
                                                ),
                                              ),
                                              fileStyle: FileStyle(
                                                iconForDeleteFile: Icon(
                                                  Icons.delete,
                                                  size: 25,
                                                  color: Colors.red[300],
                                                ),
                                                fileNameStyle: TextStyle(
                                                  color: appTheme.selectScreenCardTextColor,
                                                  fontSize: 18.5,
                                                  fontWeight: appTheme.isDark
                                                    ? FontWeight.w400
                                                    : FontWeight.w400,
                                                  height: 2,
                                                ),
                                              ),
                                              onFileTap: (f) async {
                                                final currentState = List<ActiveEditor>.from(editorState.activeEditors);
                                                await _openFileInTabs(
                                                  actionContext: context,
                                                  currentState: currentState,
                                                  file: f,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    FindWordWidget(
                                      appTheme: appTheme,
                                      findWordController: findWordController,
                                      editorState: editorState,
                                      replaceWordController: replaceWordController,
                                      tabController: tabController,
                                      workspacePath: widget.rootDir,
                                      onFileOpen: (file, lineNumber, searchQuery) async {
                                        final currentState = List<ActiveEditor>.from(editorState.activeEditors);
                                        await _openFileInTabs(
                                          actionContext: context,
                                          currentState: currentState,
                                          file: file,
                                          lineNumber: lineNumber,
                                          searchQuery: searchQuery,
                                        );
                                      },
                                    ),
                                    BlocBuilder<DiagnosticsTickBloc, int>(
                                      builder: (context, _) {
                                        return _buildDiagnosticsPane(
                                          appTheme,
                                          editorState,
                                        );
                                      },
                                    ),
                                    SourceControl(
                                      appTheme: appTheme,
                                      workSpace: widget.rootDir,
                                      isRepoThere: isRepoThere,
                                      activeEditorsBloc:
                                        BlocProvider.of<ActiveEditorBloc>(
                                          context,
                                          listen: false,
                                        ),
                                      onOpenDiffView:(fileName, workspacePath, bloc) async {
                                        try {
                                          final diffResult = await getGitDiff(fileName, workspacePath);
                                          final file = File(path.join(workspacePath,fileName),
                                          );
                                          if (!await file.exists()) return;

                                          final lang = languages.firstWhere(
                                            (language) =>
                                              language.extension.contains(
                                                path.extension(file.path).replaceFirst(".", ""),
                                              ),
                                            orElse: () => languages[0],
                                          );

                                          final tempFile = File(
                                            "$tempDir/(Working Tree)${path.basename(fileName)}",
                                          );
                                          if (!(await tempFile.exists())) {
                                            await tempFile.create(
                                              recursive: true,
                                            );
                                          }
                                          await tempFile.writeAsString(
                                            diffResult.diffText,
                                          );

                                          final currentState = List<ActiveEditor>.from(editorState.activeEditors);
                                          final canonicalDiffPath = tempFile.absolute.path;
                                          final existingIndex = currentState
                                              .indexWhere((editor) => File(editor.file.path).absolute.path == canonicalDiffPath);

                                          if (existingIndex >= 0) {
                                            for (int i = 0; i < currentState.length; i++) {
                                              currentState[i].isActive = i == existingIndex;
                                            }

                                            final existingEditor = currentState[existingIndex];
                                            existingEditor.controller.readOnly = true;
                                            existingEditor.controller.setGitDiffDecorations(
                                              addedRanges:diffResult.addedRanges,
                                              removedRanges: diffResult.removedRanges,
                                              addedColor: const Color.fromARGB(255, 0, 255, 8),
                                              removedColor: const Color.fromARGB(255, 255, 0, 0),
                                              modifiedColor: const Color(0xFF2196F3),
                                            );
                                            existingEditor.controller.text = diffResult.diffText;

                                            if (context.mounted) {
                                              bloc.add(ActiveEditorEvent(currentState));
                                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                                if (
                                                  tabController != null &&
                                                  existingIndex >= 0 &&
                                                  existingIndex < tabController!.length
                                                ) {
                                                  tabController!.animateTo(existingIndex);
                                                }
                                                existingEditor.controller.notifyListeners();
                                              });
                                            }
                                            return;
                                          }

                                          final newController = CodeForgeController();
                                          newController.readOnly = true;

                                          newController.setGitDiffDecorations(
                                            addedRanges: diffResult.addedRanges,
                                            removedRanges: diffResult.removedRanges,
                                            addedColor: const Color.fromARGB(255, 0, 255, 8),
                                            removedColor:const Color.fromARGB( 255, 255, 0, 0),
                                            modifiedColor: const Color(0xFF2196F3),
                                          );

                                          final newEditor = ActiveEditor(
                                            controller: newController,
                                            undoRedoController: UndoRedoController(),
                                            file: tempFile,
                                            isActive: true,
                                            languageDetails: lang,
                                            findController: FindController(newController),
                                            customTitle: '${path.basename(fileName)}(Working Tree)',
                                            hscroll: ScrollController(),
                                            vscroll: ScrollController(),
                                          );

                                          for (final editor in currentState) {
                                            editor.isActive = false;
                                          }
                                          currentState.add(newEditor);

                                          if (context.mounted) {
                                            mruOrder.insert(0, currentState.length - 1);
                                            bloc.add(ActiveEditorEvent(currentState),
                                            );
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              newEditor.controller.notifyListeners();
                                              final newIndex = currentState.length - 1;
                                              if (tabController != null && newIndex >= 0) {
                                                tabController!.animateTo(newIndex);
                                              }
                                            });
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Failed to open diff view: $e',
                                                ),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                    APITesting(
                                      params: params,
                                      headers: headers,
                                      apiUrlController: apiUrlController,
                                      appTheme: appTheme,
                                      paramTabController: paramTabController,
                                      apiTabController: apiTabController,
                                    ),
                                    AIChat(
                                      filePath:
                                        editorState.activeEditors.isNotEmpty
                                        ? editorState
                                            .activeEditors[(tabController != null
                                              ? tabController!.index
                                              : editorState.activeEditors.indexWhere((item) => item.isActive == true))]
                                            .file.path
                                        : '',
                                      workspacePath: widget.rootDir,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    appBar: AppBar(
                      leading: Builder(
                        builder: (leadingContext) {
                          return IconButton(
                            onPressed: () => Scaffold.of(leadingContext).openDrawer(),
                            icon: BlocBuilder<DiagnosticsTickBloc, int>(
                              builder: (context, _) {
                                final openErrorCount = _openEditorsErrorCount(
                                  editorState.activeEditors,
                                );
                                return _buildBadgedIcon(
                                  icon: Icon(
                                    Icons.menu_rounded,
                                    color: appTheme.editorPageToolColor,
                                  ),
                                  count: openErrorCount,
                                  appTheme: appTheme,
                                );
                              },
                            ),
                            tooltip: 'Open tools',
                          );
                        },
                      ),
                      title: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: tabController == null
                            ? Text(
                                editorState.activeEditors.isNotEmpty
                                    ? _displayFileName(
                                        editorState.activeEditors[0],
                                      )
                                    : '',
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor,
                                ),
                              )
                            : AnimatedBuilder(
                                animation: tabController!,
                                builder: (context, _) {
                                  int idx = tabController!.index;
                                  if (idx < 0 || idx >= editorState.activeEditors.length) {
                                    idx = 0;
                                  }
                                  final fileName =
                                      editorState.activeEditors.isNotEmpty
                                      ? _displayFileName(
                                          editorState.activeEditors[idx],
                                        )
                                      : '';
                                  return Text(
                                    fileName,
                                    style: TextStyle(
                                      color: appTheme.selectScreenCardTextColor,
                                    ),
                                  );
                                },
                              ),
                      ),
                      bottom: editorState.activeEditors.isNotEmpty
                          ? TabBar(
                              labelPadding: EdgeInsets.zero,
                              padding: EdgeInsets.zero,
                              indicator: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: Color(0xff157dcc),
                                    width: 2,
                                  ),
                                  left: BorderSide(
                                    color: appTheme.isDark
                                        ? Colors.grey
                                        : Colors.blueGrey[600]!,
                                    width: 0.2,
                                  ),
                                  right: BorderSide(
                                    color: appTheme.isDark
                                        ? Colors.grey
                                        : Colors.blueGrey[600]!,
                                    width: 0.2,
                                  ),
                                ),
                              ),
                              labelColor: appTheme.selectScreenCardTextColor,
                              unselectedLabelColor: appTheme.isDark
                                  ? null
                                  : Colors.grey[400],
                              dividerColor: Colors.transparent,
                              controller: tabController,
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              onTap: (value) {
                                _syncActiveEditorWithTabIndex(value);
                                mruOrder.remove(value);
                                mruOrder.insert(0, value);
                                if (tabController != null &&
                                    tabController!.index != value) {
                                  tabController!.animateTo(value);
                                }
                              },
                              tabs: List.generate(
                                editorState.activeEditors.length,
                                (index) {
                                  return Tab(
                                    height: 32,
                                    child: Row(
                                      children: [
                                        _buildTabIconForEditor(
                                          editorState.activeEditors[index],
                                          appTheme,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 8,
                                          ),
                                          child: Text(
                                            _displayFileName(
                                              editorState.activeEditors[index],
                                            ),
                                            softWrap: false,
                                            maxLines: 1,
                                          ),
                                        ),
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          onPressed: () async {
                                            final List<ActiveEditor>
                                            currentState = List.from(
                                              editorState.activeEditors,
                                            );
                                            if (currentState.length <= 1) {
                                              context.read<ActiveEditorBloc>().add(ActiveEditorEvent([]));
                                              context.read<ActiveEditorBloc>().add(CloseActiveEditor());
                                              return;
                                            }

                                            try {
                                              await currentState[index].dispose();
                                            } catch (e) {
                                              debugPrint('Error disposing editor: $e');
                                            }

                                            if (currentState[index].customTitle?.contains("(Working Tree)",) == true) {
                                              try {
                                                await currentState[index].file.delete();
                                              } catch (e) {
                                                debugPrint(e.toString());
                                              }
                                            }

                                            final wasActive = currentState[index].isActive;
                                            currentState.removeAt(index);
                                            mruOrder.remove(index);
                                            mruOrder = mruOrder
                                                .map(
                                                  (i) => i > index ? i - 1 : i,
                                                )
                                                .toList();
                                            if (currentState.isNotEmpty &&
                                                wasActive) {
                                              int newActive =
                                                  mruOrder.isNotEmpty
                                                  ? mruOrder[0]
                                                  : 0;
                                              for (
                                                int i = 0;
                                                i < currentState.length;
                                                i++
                                              ) {
                                                currentState[i].isActive =
                                                    i == newActive;
                                              }
                                            }
                                            if (context.mounted) {
                                              context.read<ActiveEditorBloc>().add(ActiveEditorEvent(currentState));
                                            }

                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              final newIndex = currentState.indexWhere(
                                                (item) => item.isActive == true);
                                              if (tabController != null && newIndex >= 0 && newIndex < tabController!.length) {
                                                tabController!.animateTo(newIndex,);
                                              }
                                            });
                                          },
                                          icon: Icon(Icons.close, size: 20),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            )
                          : null,
                      actions: [
                        if (!autoSaveEnabled)
                          OutlinedButton.icon(
                            onPressed: hasDirtyFiles
                              ? () => _saveActiveEditor(context, editorState.activeEditors)
                              : null,
                            icon: Icon(
                              Icons.save_outlined,
                              size: 17,
                              color: hasDirtyFiles
                                ? appTheme.editorPageToolSelectedColor
                                : appTheme.editorPageToolColor.withValues(alpha: 0.6),
                            ),
                            label: Text(
                              'Save',
                              style: TextStyle(
                                color: hasDirtyFiles
                                  ? appTheme.editorPageToolSelectedColor
                                  : appTheme.editorPageToolColor.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              backgroundColor: hasDirtyFiles
                                ? appTheme.editorPageToolSelectedBgColor.withValues(alpha: 0.35)
                                : appTheme.editorPageDrawerBg,
                              side: BorderSide(
                                color: hasDirtyFiles
                                  ? appTheme.editorPageToolColor.withValues(alpha: 0.45)
                                  : appTheme.editorPageToolColor.withValues(alpha: 0.25),
                                width: 1,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        if (_hasViteProject)
                          IconButton(
                            tooltip: 'Open Vite Preview',
                            onPressed: _isOpeningVitePreview
                              ? null
                              : () => _openVitePreview(),
                            icon: _isOpeningVitePreview
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.slideshow),
                          ),
                        BlocBuilder<SelectedRuntimeEnvironmentCubit, SelectedRunEnvironmentState>(
                          builder: (context, runtimeState) {
                            final cubitState = context.read<SelectedRuntimeEnvironmentCubit>();
                            final currentlyRuntimeID = runtimeState.currentlyRuntimeID;
                          return Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: Row(
                              children: [
                                InkWell(
                                  onTap: () async {
                                    if (editorState.activeEditors.isEmpty) return;
                                    if (currentlyRuntimeID != null) {
                                      final activeEditorForRun = tabController != null && tabController!.index < editorState.activeEditors.length
                                      ? editorState.activeEditors[tabController!.index]
                                      : editorState.activeEditors.firstWhere(
                                          (item) => item.isActive == true,
                                          orElse: () => editorState.activeEditors.first,
                                        );
                                      final filePath = activeEditorForRun.file;
                                      final lang = languages.firstWhere(
                                          (language) => language.extension.contains(path.extension(filePath.path).replaceFirst(".", "")),
                                          orElse: () => languages[0],
                                        );
                                      final String command = lang.command ?? '';

                                      final String extension = path.extension(
                                        filePath.path,
                                      );

                                      switch (extension) {
                                        case ".c":
                                        case ".c++":
                                        case ".cpp":
                                        case ".cc":
                                          runCodeInTermux(
                                            context,
                                            "$command ${filePath.path} -o \$HOME/rox-bin.out && \$HOME/rox-bin.out",
                                            widget.rootDir,
                                            termuxInfo?.id
                                          );
                                          break;
                                        case '.java':
                                          final String compileCommand = "javac ${filePath.path} -d .";
                                          final String runCommand = "java ${path.basenameWithoutExtension(filePath.path)}";
                                          runCodeInTermux(context, "$compileCommand && $runCommand", widget.rootDir, termuxInfo?.id);
                                          break;
                                        case '.kts':
                                          final String compileCommand = 'echo Compiling... && kotlinc ${filePath.path} -include-runtime -d ./temp.jar';
                                          final String runCommand = 'java -jar ./temp.jar';
                                          runCodeInTermux(context, "$compileCommand && $runCommand", widget.rootDir, termuxInfo?.id);
                                          break;
                                        case '.ts':
                                          final String compileCommand = "tsc ${filePath.path} --outDir .";
                                          final String runCommand = "node ./${path.basenameWithoutExtension(filePath.path)}.js";
                                          runCodeInTermux(context, "$compileCommand && $runCommand", widget.rootDir, termuxInfo?.id);
                                          break;
                                        case ".rs":
                                          final cargoFile = File("${widget.rootDir}/Cargo.toml");
                                
                                          if (cargoFile.existsSync()) {
                                            final mainRs = File("${widget.rootDir}/src/main.rs");
                                            final libRs = File("${widget.rootDir}/src/lib.rs");
                                
                                            final hasLibTarget = libRs.existsSync();
                                
                                            if (!hasLibTarget && !mainRs.existsSync()) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text("No src/main.rs or src/lib.rs found in this Cargo project."),
                                                ),
                                              );
                                              return;
                                            }
                                            runCodeInTermux(context, "cargo run", widget.rootDir, termuxInfo?.id);
                                            break;
                                          }

                                          runCodeInTermux(
                                            context,
                                            "rustc ${filePath.path} -o \$HOME/rox-bin.out && \$HOME/rox-bin.out",
                                            widget.rootDir,
                                            termuxInfo?.id
                                          );
                                          break;
                                        default: 
                                          Navigator.of(context).push(
                                            PageRouteBuilder(
                                              pageBuilder:(context, animation, scondaryAnimation) => SetupTerminal(
                                                projectDir: widget.rootDir,
                                                termuxId: termuxInfo?.id,
                                                commandToExecuteInSSH: "$command ${filePath.path}",
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
                                      return;
                                    }

                                    final temp = Directory(tempDir);
                                    if (!temp.existsSync()) {
                                      temp.createSync(recursive: true);
                                    }
                                    final activeEditorForRun = tabController != null && tabController!.index < editorState.activeEditors.length
                                      ? editorState.activeEditors[tabController!.index]
                                      : editorState.activeEditors.firstWhere(
                                          (item) => item.isActive == true,
                                          orElse: () => editorState.activeEditors.first,
                                        );
                                    final filePath = activeEditorForRun.file;
                                    final viteTs = File(
                                      path.join(widget.rootDir, 'vite.config.ts'),
                                    );
                                    final viteJs = File(
                                      path.join(widget.rootDir, 'vite.config.js'),
                                    );
                                    final nextTs = File(
                                      path.join(widget.rootDir, 'next.config.ts'),
                                    );
                                    final nextJs = File(
                                      path.join(widget.rootDir, 'next.config.js'),
                                    );
                                
                                    final packageJson = File(
                                      path.join(widget.rootDir, 'package.json'),
                                    );
                                
                                    final hasVite = await viteTs.exists() || await viteJs.exists();
                                    final hasNext = await nextTs.exists() || await nextJs.exists();
                                    final hasPkg = await packageJson.exists();
                                
                                    if (hasVite && hasPkg && context.mounted) {
                                      runCode(
                                        context,
                                        "node node_modules/vite/bin/vite.js",
                                        widget.rootDir,
                                      );
                                      return;
                                    }
                                
                                    if (hasNext && hasPkg && context.mounted) {
                                      runCode(
                                        context,
                                        "npm install --ignore-scripts && npm uninstall lightningcss && node node_modules/next/dist/bin/next dev --webpack",
                                        widget.rootDir,
                                      );
                                      return;
                                    }
                                
                                    if (isPreviewFilePath(filePath.path) && context.mounted) {
                                      final message = isPdfFilePath(filePath.path)
                                        ? 'PDF files can be previewed but are not executable.'
                                        : 'Image/SVG files can be previewed but are not executable.';
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(message)),
                                      );
                                      return;
                                    }
                                
                                    final String extension = path.extension(
                                      filePath.path,
                                    );

                                    if (!context.mounted) return;
                                    switch (extension) {
                                      case '.html':
                                        if (context.mounted) {
                                          Navigator.of(context).push(
                                            PageRouteBuilder(
                                              pageBuilder: (context, animation, scondaryAnimation) => WebViewScreen(htmlFile: filePath),
                                              transitionsBuilder:(context, animation, secondaryAnimation, child,) {
                                                return SizeTransition(
                                                  sizeFactor: animation,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          );
                                        }
                                        break;
                                      case '.c':
                                        final String compileCommand = "clang -fPIC -shared ${filePath.path} -o ${temp.path}/libtemp.so";
                                        final String runCommand = 'clangloader ${temp.path}/libtemp.so';
                                        runCode(context, "$compileCommand && $runCommand", widget.rootDir);
                                        break;
                                      case '.cpp':
                                      case '.c++':
                                      case '.cc':
                                        final String compileCommand = "clang++ -fPIC -shared ${filePath.path} -o ${temp.path}/libtemp.so";
                                        final String runCommand = 'clangloader ${temp.path}/libtemp.so';
                                        runCode(context, "$compileCommand && $runCommand", widget.rootDir);
                                        break;
                                      case '.java':
                                        final String compileCommand = "javac ${filePath.path} -d ${temp.path}";
                                        final String runCommand = "cd ${temp.path} && java ${path.basenameWithoutExtension(filePath.path)}";
                                        runCode(context, "$compileCommand && $runCommand", widget.rootDir);
                                        break;
                                      case '.kt':
                                      case '.kts':
                                        final String compileCommand = 'echo Compiling... && kotlinc ${filePath.path} -include-runtime -d ${temp.path}/temp.jar';
                                        final String runCommand = 'java -jar ${temp.path}/temp.jar';
                                        runCode(context, "$compileCommand && $runCommand", widget.rootDir);
                                        break;
                                      case '.ts':
                                        final String compileCommand = "tsc ${filePath.path} --outDir ${temp.path}";
                                        final String runCommand = "node ${temp.path}/${path.basenameWithoutExtension(filePath.path)}.js";
                                        runCode(context, "$compileCommand && $runCommand", widget.rootDir);
                                        break;
                                      case '.go':
                                        try {
                                          final soPath = path.join(widget.rootDir, '.roxum-go-run.so');
                                
                                          final command =
                                              'export GOROOT="$runtimesDir/go" '
                                              '&& export PATH="\$GOROOT/bin:\$PATH" '
                                              '&& export CC="clang" '
                                              '&& export GOOS="android" '
                                              '&& export GOARCH="arm64" '
                                              '&& echo "Compiling..." '
                                              '&& go_bak="\$(mktemp)" '
                                              '&& cp "${filePath.path}" "\$go_bak" '
                                              '&& cleanup(){ '
                                              'cp "\$go_bak" "${filePath.path}"; '
                                                'rm -f "\$go_bak" "$soPath" "${filePath.path}.roxum.tmp"; '
                                              '}; '
                                              'trap cleanup EXIT '
                                
                                              '&& if ! grep -q \'import "C"\' "${filePath.path}"; then '
                                                  'tmp_go="${filePath.path}.roxum.tmp"; '
                                                  'if grep -q "^import (" "${filePath.path}"; then '
                                                    "awk 'BEGIN{done=0} {print} !done && /^import \\(\$/ {print \"    \\\"C\\\"\"; done=1}' \"${filePath.path}\" > \"\$tmp_go\" && mv \"\$tmp_go\" \"${filePath.path}\"; "
                                                  'elif grep -q "^import " "${filePath.path}"; then '
                                                    "awk 'BEGIN{done=0} !done && /^import / {print \"import \\\"C\\\"\"; done=1} {print}' \"${filePath.path}\" > \"\$tmp_go\" && mv \"\$tmp_go\" \"${filePath.path}\"; "
                                                  'else '
                                                    "awk 'BEGIN{done=0} !done && /^package / {print; print \"\"; print \"import \\\"C\\\"\"; done=1; next} {print}' \"${filePath.path}\" > \"\$tmp_go\" && mv \"\$tmp_go\" \"${filePath.path}\"; "
                                                  'fi; '
                                              'fi '
                                
                                              '&& if ! grep -q "__entry" "${filePath.path}"; then '
                                                  "printf '\\n//export __entry\\nfunc __entry() {\\n    main()\\n}\\n' >> \"${filePath.path}\"; "
                                              'fi '
                                
                                                '&& rm -f "$soPath" '
                                              '&& GOOS=android GOARCH=arm64 CGO_ENABLED=1 '
                                              'go build -buildmode=c-shared -o "$soPath" "${filePath.path}" '
                                              '&& rustloader "$soPath"';
                                
                                          runCode(context, command, widget.rootDir);
                                
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text("Go run failed: ${e.toString()}")),
                                          );
                                        }
                                        break;
                                      case '.rs':
                                        try {
                                          final cargoFile = File("${widget.rootDir}/Cargo.toml");
                                          String command = "";
                                
                                          if (cargoFile.existsSync()) {
                                            final mainRs = File("${widget.rootDir}/src/main.rs");
                                            final libRs = File("${widget.rootDir}/src/lib.rs");
                                
                                            final hasLibTarget = libRs.existsSync();
                                
                                            if (!hasLibTarget && !mainRs.existsSync()) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text("No src/main.rs or src/lib.rs found in this Cargo project."),
                                                ),
                                              );
                                              return;
                                            }
                                
                                            final targetPath = hasLibTarget ? libRs.path : mainRs.path;
                                
                                            command =
'''
set -e
cargo_bak="\$(mktemp)"
target_bak="\$(mktemp)"
cargo_cfg_bak="\$(mktemp)"
generated_lib=""
cp "${cargoFile.path}" "\$cargo_bak"
cp "$targetPath" "\$target_bak"
if [ -f .cargo/config.toml ]; then cp .cargo/config.toml "\$cargo_cfg_bak"; else : > "\$cargo_cfg_bak"; fi
cleanup(){
cp "\$target_bak" "$targetPath";
cp "\$cargo_bak" "${cargoFile.path}";
if [ -s "\$cargo_cfg_bak" ]; then
  mkdir -p .cargo;
  cp "\$cargo_cfg_bak" .cargo/config.toml;
else
  rm -f .cargo/config.toml;
  rmdir .cargo 2>/dev/null || true;
fi;
if [ -n "\$generated_lib" ]; then
  rm -f "\$generated_lib";
fi;
rm -f "\$target_bak" "\$cargo_bak" "\$cargo_cfg_bak";
};
trap cleanup EXIT
mkdir -p .cargo
printf '[target.aarch64-linux-android]\nlinker = "clang"\n' > .cargo/config.toml
if [ ${hasLibTarget ? 1 : 0} -eq 1 ]; then
if ! grep -q "fn __entry" "$targetPath"; then
  if grep -Eq 'fn[[:space:]]+main' "$targetPath"; then
    printf '\n#[unsafe(no_mangle)]\npub extern "C" fn __entry() {\n    let _ = std::panic::catch_unwind(|| {\n        let _ = main();\n    });\n}\n' >> "$targetPath";
  else
    echo "Error: src/lib.rs needs either __entry() or main() for Roxum run.";
    exit 1;
  fi
fi
else
if ! grep -Eq 'fn[[:space:]]+main' "$targetPath"; then
  echo "Error: main() not found in src/main.rs.";
  exit 1;
fi
generated_lib="${widget.rootDir}/src/.roxum_entry_lib.rs"
cat > "\$generated_lib" <<'EOF'
include!("main.rs");

#[unsafe(no_mangle)]
pub extern "C" fn __entry() {
  let _ = std::panic::catch_unwind(|| {
      let _ = main();
  });
}
EOF
if ! grep -Eq '^[[:space:]]*[lib][[:space:]]*\$' "${cargoFile.path}"; then
  printf '\n[lib]\npath = "src/.roxum_entry_lib.rs"\ncrate-type = ["cdylib"]\n' >> "${cargoFile.path}";
fi
fi
cargo rustc --release --lib -- --crate-type=cdylib
so_file="\$(find target -type f -name 'lib*.so' | head -n 1)"
[ -n "\$so_file" ]
rustloader "\$so_file"
''';
                                
                                          } else {
                                            final soPath = path.join(tempDir, '.roxum-rust-run.so');
                                
                                            command =
'''
set -e
rust_bak="\$(mktemp)"
cp "${filePath.path}" "\$rust_bak"
cleanup(){
cp "\$rust_bak" "${filePath.path}";
rm -f "\$rust_bak" "$soPath";
};
trap cleanup EXIT
if ! grep -Eq 'fn[[:space:]]+main' "${filePath.path}"; then
echo "Error: main() not found. This runner requires a main function.";
exit 1;
fi
if ! grep -q "fn __entry" "${filePath.path}"; then
printf '\n#[unsafe(no_mangle)]\npub extern "C" fn __entry() {\n    let _ = std::panic::catch_unwind(|| {\n        let _ = main();\n    });\n}\n' >> "${filePath.path}";
fi
rustc --crate-type=cdylib "${filePath.path}" -o "$soPath" -C linker=clang --sysroot "$runtimesDir/rust"
rustloader "$soPath"
''';
                                          }
                                
                                          runCode(context, command, widget.rootDir);
                                
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text("Rust run failed: ${e.toString()}")),
                                          );
                                        }
                                
                                        break;
                                      case '.md':
                                        Navigator.of(context).push(
                                          PageRouteBuilder(
                                            pageBuilder:(context, animation, scondaryAnimation) => MdView(
                                              data: filePath.readAsStringSync(),
                                              appTheme: appTheme,
                                              theme: context.read<ConfigBloc>().state,
                                            ),
                                            transitionsBuilder:(context, animation, secondaryAnimation, child) {
                                              return SizeTransition(
                                                sizeFactor: animation,
                                                child: child,
                                              );
                                            },
                                          ),
                                        );
                                        break;
                                      default:
                                        final lang = languages.firstWhere(
                                          (language) => language.extension.contains(path.extension(filePath.path).replaceFirst(".", "")),
                                          orElse: () => languages[0],
                                        );
                                        final String command = lang.command ?? '';
                                        Navigator.of(context).push(
                                          PageRouteBuilder(
                                            pageBuilder:(context, animation, scondaryAnimation) => SetupTerminal(
                                              projectDir: widget.rootDir,
                                              args: ["-c", "$command ${filePath.path}"],
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
                                  },
                                  child: runtimeState.currentlyRuntimeID == null
                                    ? Icon(Icons.play_arrow)
                                    : Stack(
                                      children: [
                                        Icon(Icons.play_arrow),
                                        Positioned(
                                          bottom: 2,
                                          right: 0,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: BoxBorder.all(
                                                color: appTheme.selectScreenCardTextColor,
                                              )
                                            ),
                                            child: SvgPicture.asset(
                                              "assets/icons/Termux.svg",
                                              height: 11,
                                              width: 11
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ),
                                if (termuxInfo != null && termuxInfo!.isConnected) 
                                  MenuAnchor(
                                    style: MenuStyle(
                                      backgroundColor: WidgetStatePropertyAll(appTheme.selectScreenCardsBg),
                                      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: .circular(6)))
                                    ),
                                    animated: true,
                                    onAnimationStatusChanged: (status) {
                                      _runtimeSelectionStatus = status;
                                    },
                                    menuChildren: [
                                      MenuItemButton(
                                        onPressed: () => cubitState.updateId(null),
                                        leadingIcon: Icon(
                                          Icons.phone_android_outlined,
                                          color: appTheme.selectScreenCardTextColor,
                                        ),
                                        trailingIcon: currentlyRuntimeID == null ? Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 16
                                          )
                                          : null,
                                        child: Text(
                                          "Roxum",
                                          style: TextStyle(
                                            color: appTheme.selectScreenCardTextColor
                                          )
                                        ),
                                      ),
                                      
                                      MenuItemButton(
                                        onPressed: () => cubitState.updateId(termuxInfo!.id),
                                        leadingIcon: SvgPicture.asset(
                                          "assets/icons/Termux.svg",
                                          height: 20,
                                          width: 20
                                        ),
                                        trailingIcon: currentlyRuntimeID == termuxInfo!.id ? Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 16
                                          )
                                          : null,
                                        child: Text(
                                          termuxInfo!.name,
                                          style: TextStyle(
                                            color: appTheme.selectScreenCardTextColor
                                          )
                                        ),
                                      ),

                                      //TODO
                                      Opacity(
                                        opacity: 0.45,
                                        child: MenuItemButton(
                                          onPressed: null,

                                          leadingIcon: Padding(
                                            padding: const EdgeInsets.only(left: 3),
                                            child: FaIcon(
                                              FontAwesomeIcons.server,
                                              color: appTheme.selectScreenCardTextColor,
                                              size: 20,
                                            ),
                                          ),

                                          child: Row(
                                            children: [
                                              Text(
                                                "Remote server",
                                                style: TextStyle(
                                                  color: appTheme.selectScreenCardTextColor,
                                                ),
                                              ),

                                              const SizedBox(width: 8),

                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.withAlpha(40),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  "Coming Soon",
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              )
                                            ],
                                          ),
                                        ),
                                      )
                                    ],
                                    builder: (context, controller, child) => InkWell(
                                      onTap: () {
                                        if(_runtimeSelectionStatus.isForwardOrCompleted){
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
                                  )
                                ],
                              ),
                          );
                          }
                        ),
                        BlocBuilder<CurrentlySelectedTerminalCubit, SelectedTerminalState>(
                          builder: (context, selectedTerminalState) {
                            int? currentlySelectedTerminalID = selectedTerminalState.currentlySelectedID;
                            bool isTermux = selectedTerminalState.isTermux;
                            final cubitState = context.read<CurrentlySelectedTerminalCubit>();
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Row(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        PageRouteBuilder(
                                          pageBuilder: (context, animation, scondaryAnimation) =>
                                            SetupTerminal(
                                              projectDir: widget.rootDir,
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
                                      ? Icon(Icons.terminal)
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
                                              size: 32,
                                            ),
                                            Positioned(
                                              bottom: 2,
                                              child: Icon(
                                                Icons.terminal,
                                                size: 22,
                                                color: appTheme.appBarTheme.backgroundColor
                                              ),
                                            ),
                                          ],
                                        )
                                  ),
                                  if(sshServerList.isNotEmpty || (termuxInfo != null && termuxInfo!.isConnected)) MenuAnchor(
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
                                            size: 16
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
                              
                                      if(termuxInfo != null && termuxInfo!.isConnected)
                                      MenuItemButton(
                                        onPressed: () => cubitState.updateId(termuxInfo!.id, true),
                                        leadingIcon: SvgPicture.asset(
                                          "assets/icons/Termux.svg",
                                          height: 20,
                                          width: 20
                                        ),
                                        trailingIcon: currentlySelectedTerminalID == termuxInfo!.id ? Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 16
                                          )
                                          : null,
                                        child: Text(
                                          termuxInfo!.name,
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
                              ),
                            );
                          },
                        )
                      ],
                    ),
                    body: editorState.activeEditors.isNotEmpty
                  ? TabBarView(
                      controller: tabController,
                      children: editorState.activeEditors.map((editor) {
                        if (_isPreviewEditor(editor)) {
                          return _buildPreviewPane(editor, appTheme);
                        }
                        return EditorArea(
                          key: ValueKey(editor.file.path),
                          editor: editor,
                          appTheme: appTheme,
                          workspacePath: widget.rootDir,
                          tabController: tabController,
                        );
                      }).toList(),
                    )
                  : SingleChildScrollView(
                      child: Center(
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            Text(
                              "Open a file to Edit",
                              style: TextStyle(
                                color: appTheme.selectScreenCardTextColor,
                                fontSize: 20,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 15),
                              child: Column(
                                children: [
                                  Text(
                                    isRepoThere
                                      ? "Version control (.git) found \u2713"
                                      : "No version control (.git) found on this folder/project",
                                    style: TextStyle(
                                      color: Colors.grey[appTheme.isDark ? 500 : 600],
                                    ),
                                  ),
                                  if (!widget.isCloned)
                                    Card(
                                      child: Wrap(
                                        children: [
                                          Padding(
                                            padding:
                                              const EdgeInsets.only(left: 15,top: 8, bottom: 8),
                                            child: Text(
                                              "Note: This is a clone of the selected folder in Roxum's private directory. Modifications here will not affect the original folder.",
                                              style: TextStyle(
                                                color: Colors.grey[appTheme.isDark ? 500 : 600],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _PdfPreviewPane extends StatefulWidget {
  final String filePath;
  final AppTheme appTheme;

  const _PdfPreviewPane({
    required this.filePath,
    required this.appTheme,
  });

  @override
  State<_PdfPreviewPane> createState() => _PdfPreviewPaneState();
}

class _SvgPreviewPane extends StatefulWidget {
  final File file;
  final AppTheme appTheme;

  const _SvgPreviewPane({
    required this.file,
    required this.appTheme,
  });

  @override
  State<_SvgPreviewPane> createState() => _SvgPreviewPaneState();
}

class _SvgPreviewPaneState extends State<_SvgPreviewPane> {
  late Future<String> _svgTextFuture;

  @override
  void initState() {
    super.initState();
    _svgTextFuture = _loadSvgText();
  }

  @override
  void didUpdateWidget(covariant _SvgPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _svgTextFuture = _loadSvgText();
    }
  }

  bool _isGzipData(Uint8List data) {
    return data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b;
  }

  Future<String> _loadSvgText() async {
    if (!await widget.file.exists()) {
      throw Exception('SVG file not found.');
    }

    final bytes = await widget.file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('SVG file is empty.');
    }

    final ext = path.extension(widget.file.path).toLowerCase();
    final shouldDecompress = ext == '.svgz' || _isGzipData(bytes);

    final rawBytes = shouldDecompress
        ? Uint8List.fromList(gzip.decode(bytes))
        : bytes;

    final svgText = utf8.decode(rawBytes, allowMalformed: true);
    if (svgText.trim().isEmpty) {
      throw Exception('SVG content is empty.');
    }
    return svgText;
  }

  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 44),
          const SizedBox(height: 10),
          Text(
            'Failed to load SVG preview',
            style: TextStyle(
              color: widget.appTheme.selectScreenCardTextColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.appTheme.editorPageDrawerBg,
      alignment: Alignment.center,
      child: FutureBuilder<String>(
        future: _svgTextFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            );
          }

          if (snapshot.hasError) {
            return _buildError(snapshot.error.toString());
          }

          final svgText = snapshot.data;
          if (svgText == null || svgText.trim().isEmpty) {
            return _buildError('No SVG data available.');
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 480.0;
              final maxHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : 640.0;

              final viewWidth = maxWidth > 240 ? maxWidth * 0.92 : maxWidth;
              final viewHeight =
                  maxHeight > 240 ? maxHeight * 0.92 : maxHeight;

              return InteractiveViewer(
                minScale: 0.2,
                maxScale: 8,
                child: SizedBox(
                  width: viewWidth > 0 ? viewWidth : 320,
                  height: viewHeight > 0 ? viewHeight : 320,
                  child: SvgPicture.string(
                    svgText,
                    fit: BoxFit.contain,
                    allowDrawingOutsideViewBox: true,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PdfPreviewPaneState extends State<_PdfPreviewPane> {
  bool _isReady = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    if (!File(widget.filePath).existsSync()) {
      return Center(
        child: Text(
          'PDF file not found.',
          style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 44),
              const SizedBox(height: 8),
              Text(
                'Failed to load PDF preview',
                style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
              ),
              const SizedBox(height: 4),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        PDFView(
          key: ValueKey(widget.filePath),
          filePath: widget.filePath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          fitPolicy: FitPolicy.BOTH,
          onRender: (_) {
            if (!mounted) return;
            setState(() {
              _isReady = true;
            });
          },
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _errorMessage = error.toString();
              _isReady = true;
            });
          },
          onPageError: (page, error) {
            if (!mounted) return;
            setState(() {
              _errorMessage = 'Page $page: $error';
              _isReady = true;
            });
          },
        ),
        if (!_isReady)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}