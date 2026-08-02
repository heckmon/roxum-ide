import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:roxum/utils/constants.dart';
import 'package:roxum/utils/functions.dart';

enum CopilotAccountStatus {
  notSignedIn,
  signingIn,
  signedIn,
  notAuthorized,
}

class CopilotSignInPayload {
  final String status;
  final String? userCode;
  final String? verificationUri;
  final int? expiresIn;
  final int? interval;
  final String? user;
  final Map<String, dynamic>? command;

  CopilotSignInPayload({
    required this.status,
    this.userCode,
    this.verificationUri,
    this.expiresIn,
    this.interval,
    this.user,
    this.command,
  });

  factory CopilotSignInPayload.fromJson(Map<String, dynamic> json) {
    return CopilotSignInPayload(
      status: json['status'] ?? 'NotSignedIn',
      userCode: json['userCode'],
      verificationUri: json['verificationUri'],
      expiresIn: json['expiresIn'],
      interval: json['interval'],
      user: json['user'],
      command: json['command'] as Map<String, dynamic>?,
    );
  }

  bool get isAlreadySignedIn => status == 'AlreadySignedIn' || status == 'OK';
  bool get isOk => status == 'OK';
  bool get isNotAuthorized => status == 'NotAuthorized';
  bool get hasCommand => command != null && command!['command'] != null;
}

class CopilotCompletion {
  final String uuid;
  final String text;
  final String displayText;
  final Map<String, dynamic> position;
  final Map<String, dynamic> range;

  CopilotCompletion({
    required this.uuid,
    required this.text,
    required this.displayText,
    required this.position,
    required this.range,
  });

  factory CopilotCompletion.fromJson(Map<String, dynamic> json) {
    return CopilotCompletion(
      uuid: json['uuid'] ?? '',
      text: json['text'] ?? '',
      displayText: json['displayText'] ?? json['text'] ?? '',
      position: json['position'] ?? {'line': 0, 'character': 0},
      range: json['range'] ?? {},
    );
  }
}

class CopilotConversationEntry {
  final String kind;
  final String conversationId;
  final String turnId;
  final String reply;
  final List<dynamic> references;
  final bool hideText;

  CopilotConversationEntry({
    required this.kind,
    required this.conversationId,
    required this.turnId,
    required this.reply,
    this.references = const [],
    this.hideText = false,
  });

  factory CopilotConversationEntry.fromJson(Map<String, dynamic> json) {
    return CopilotConversationEntry(
      kind: json['kind'] ?? '',
      conversationId: json['conversationId'] ?? '',
      turnId: json['turnId'] ?? '',
      reply: json['reply'] ?? '',
      references: json['references'] ?? [],
      hideText: json['hideText'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'conversationId': conversationId,
      'turnId': turnId,
      'reply': reply,
      'references': references,
      'hideText': hideText,
    };
  }
}

class CopilotLsp {
  final String? workspacePath;
  final String configPath;
  final StreamController<Map<String, dynamic>> _responseController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _notificationController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _progressController = StreamController<Map<String, dynamic>>.broadcast();
  late Process _process;
  final List<int> _buffer = [];
  final Map<String, int> _openDocuments = {};
  int _nextId = 0;
  bool _isSending = false;
  bool _isInitialized = false;
  bool _isDisposed = false;
  CopilotAccountStatus _accountStatus = CopilotAccountStatus.notSignedIn;
  String? _currentUser;
  String? _conversationId;
  List<String> _serverCommands = const [];

  bool get isInitialized => _isInitialized;
  bool get isDisposed => _isDisposed;
  CopilotAccountStatus get accountStatus => _accountStatus;
  String? get currentUser => _currentUser;
  String? get conversationId => _conversationId;
  List<String> get serverCommands => List<String>.unmodifiable(_serverCommands);
  
  Stream<Map<String, dynamic>> get responseStream => _responseController.stream;
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;
  Stream<Map<String, dynamic>> get progressStream => _progressController.stream;

  CopilotLsp._({
    this.workspacePath,
    required this.configPath,
  });

  static Future<CopilotLsp> start({
    required String configPath,
    String? workspacePath,
  }) async {
    final client = CopilotLsp._(
      workspacePath: workspacePath,
      configPath: configPath,
    );
    await client._startServer();
    return client;
  }

  Future<void> _startServer() async {
    final sharedPath = await NativeChannel.getLibraryPath();
    _process = await Process.start(
      '$binDir/node',
      ['$extensionDir/copilot-language-server/language-server.js', '--stdio'],
      environment: {
        'HOME': configPath,
        'XDG_CONFIG_HOME': configPath,
        'ROXUM_SHARED_PATH': sharedPath
      },
    );

    _process.stdout.listen(
      _handleStdoutData,
      onError: (error) => debugPrint('Copilot stdout error: $error'),
    );
    
    _process.stderr.listen(
      (data) => debugPrint('Copilot stderr: ${utf8.decode(data)}'),
      onError: (error) => debugPrint('Copilot stderr error: $error'),
    );
    
    _process.exitCode.then((code) {
      debugPrint('Copilot process exited with code: $code');
      if (!_isDisposed) {
        _isInitialized = false;
      }
    });
  }

  void _handleStdoutData(List<int> data) {
    _buffer.addAll(data);
    
    while (_buffer.isNotEmpty) {
      final headerEnd = _findHeaderEnd();
      if (headerEnd == -1) return;
      
      final header = utf8.decode(_buffer.sublist(0, headerEnd));
      final contentLengthMatch = RegExp(r'Content-Length: (\d+)').firstMatch(header);
      if (contentLengthMatch == null) return;
      
      final contentLength = int.parse(contentLengthMatch.group(1)!);
      final messageStart = headerEnd + 4;
      
      if (_buffer.length < messageStart + contentLength) return;
      
      final messageBytes = _buffer.sublist(messageStart, messageStart + contentLength);
      _buffer.removeRange(0, messageStart + contentLength);
      
      try {
        final json = jsonDecode(utf8.decode(messageBytes)) as Map<String, dynamic>;
        _handleMessage(json);
      } catch (e) {
        debugPrint('Error parsing LSP message: $e');
      }
    }
  }

  int _findHeaderEnd() {
    const endSequence = [13, 10, 13, 10];
    for (var i = 0; i <= _buffer.length - endSequence.length; i++) {
      bool match = true;
      for (var j = 0; j < endSequence.length; j++) {
        if (_buffer[i + j] != endSequence[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (message.containsKey('id') && !message.containsKey('method')) {
      _responseController.add(message);
      return;
    }
    
    if (message.containsKey('method')) {
      final method = message['method'] as String;
      final params = message['params'];
      
      if (method == r'$/progress') {
        _progressController.add(params as Map<String, dynamic>);
      }
      
      else if (method == 'featureFlagsNotification') {
        _notificationController.add({'type': 'featureFlags', 'data': params});
      }
      
      else if (method == 'window/logMessage') {
        _notificationController.add({'type': 'log', 'data': params});
      }
      
      else if (method == 'statusNotification') {
        _notificationController.add({'type': 'status', 'data': params});
      }
      
      else {
        _notificationController.add({'type': method, 'data': params});
      }
    }
  }

  Future<Map<String, dynamic>> _sendRequest({
    required String method,
    required Map<String, dynamic> params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final id = _nextId++;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };
    
    await _sendLspMessage(request);
    
    return await _responseController.stream
        .firstWhere(
          (response) => response['id'] == id,
          orElse: () => throw TimeoutException('No response for request $id'),
        )
        .timeout(timeout);
  }

  Future<void> _sendNotification({
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final notification = {
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    };
    await _sendLspMessage(notification);
  }

  Future<void> _sendLspMessage(Map<String, dynamic> message) async {
    while (_isSending) {
      await Future.delayed(const Duration(microseconds: 100));
    }
    
    _isSending = true;
    try {
      final body = utf8.encode(jsonEncode(message));
      final header = utf8.encode('Content-Length: ${body.length}\r\n\r\n');
      _process.stdin.add([...header, ...body]);
      await _process.stdin.flush();
    } finally {
      _isSending = false;
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
  
    final effectivePath = workspacePath ?? configPath;
    final workspaceUri = Uri.directory(effectivePath).toString();
    
    final response = await _sendRequest(
      method: 'initialize',
      params: {
        'processId': _process.pid,
        'rootUri': workspaceUri,
        'workspaceFolders': workspacePath != null ? [
          {'uri': workspaceUri, 'name': 'workspace'},
        ] : [],
        'capabilities': {
          'workspace': {
            'workspaceFolders': true,
            'didChangeConfiguration': {
              'dynamicRegistration': true,
            },
            'executeCommand': {
              'dynamicRegistration': true,
            },
          },
          'textDocument': {
            'synchronization': {
              'dynamicRegistration': true,
              'didSave': true,
            },
          },
          'window': {
            'showDocument': {
              'support': true,
            },
          },
        },
        'initializationOptions': {
          'editorInfo': {
            'name': 'Roxum',
            'version': '2.3.2',
          },
          'editorPluginInfo': {
            'name': 'GitHub Copilot for Roxum',
            'version': '1.0.0',
          },
        },
      },
    );

    if (response['error'] != null) {
      throw Exception('Initialization failed: ${response['error']}');
    }

    final result = response['result'] as Map<String, dynamic>? ?? const {};
    final capabilities = result['capabilities'] as Map<String, dynamic>? ?? const {};
    final executeCommandProvider = capabilities['executeCommandProvider'] as Map<String, dynamic>?;
    final commands = executeCommandProvider?['commands'] as List<dynamic>?;
    _serverCommands = commands?.whereType<String>().toList() ?? const [];
    debugPrint('[CopilotLsp] Server execute commands: ${_serverCommands.join(', ')}');

    await _sendNotification(method: 'initialized', params: {});
    _isInitialized = true;
    
    await setEditorInfo();
    await checkStatus();
  }

  Future<void> setEditorInfo() async {
    await _sendRequest(
      method: 'setEditorInfo',
      params: {
        'editorInfo': {
          'name': 'Roxum',
          'version': '2.3.2',
        },
        'editorPluginInfo': {
          'name': 'GitHub Copilot for Roxum',
          'version': '1.0.0',
        },
      },
    );
  }

  Future<CopilotSignInPayload> checkStatus() async {
    final response = await _sendRequest(
      method: 'checkStatus',
      params: {},
    );
    
    final result = response['result'] as Map<String, dynamic>? ?? {};
    debugPrint(
      '[CopilotLsp] checkStatus keys: ${result.keys.join(', ')}, status=${result['status']}, hasCommand=${result['command'] != null}',
    );
    final payload = CopilotSignInPayload.fromJson(result);
    
    if (payload.isOk) {
      _accountStatus = CopilotAccountStatus.signedIn;
      _currentUser = payload.user;
    } else if (payload.isAlreadySignedIn) {
      _accountStatus = CopilotAccountStatus.signedIn;
    } else if (payload.isNotAuthorized) {
      _accountStatus = CopilotAccountStatus.notAuthorized;
    } else {
      _accountStatus = CopilotAccountStatus.notSignedIn;
    }
    
    return payload;
  }

  Future<void> didChangeConfiguration() async {
    await _sendNotification(
      method: 'workspace/didChangeConfiguration',
      params: {
        "settings": {
          'telementary': {
            'telementaryLevel': "all"
          },
        },
      }
    );
  }

  Future<CopilotSignInPayload> signIn() async {
    _accountStatus = CopilotAccountStatus.signingIn;
    
    final response = await _sendRequest(
      method: 'signIn',
      params: {},
    );
    
    final result = response['result'] as Map<String, dynamic>? ?? {};
    return CopilotSignInPayload.fromJson(result);
  }

  Future<void> executeCommand(Map<String, dynamic> command) async {
    final commandName = command['command'] as String?;
    final arguments = command['arguments'] as List<dynamic>? ?? [];
    
    if (commandName == null) {
      throw ArgumentError('Command must have a "command" field');
    }
    
    await _sendRequest(
      method: 'workspace/executeCommand',
      params: {
        'command': commandName,
        'arguments': arguments,
      },
      timeout: const Duration(minutes: 5),
    );
  }

  Future<dynamic> executeCommandRaw({
    required String command,
    List<dynamic> arguments = const [],
  }) async {
    final response = await _sendRequest(
      method: 'workspace/executeCommand',
      params: {
        'command': command,
        'arguments': arguments,
      },
      timeout: const Duration(minutes: 5),
    );

    if (response['error'] != null) {
      throw Exception('Command failed: ${response['error']}');
    }

    return response['result'];
  }

  Future<CopilotSignInPayload> signInConfirm(String userCode) async {
    final response = await _sendRequest(
      method: 'signInConfirm',
      params: {'userCode': userCode},
      timeout: const Duration(minutes: 5),
    );
    
    final result = response['result'] as Map<String, dynamic>? ?? {};
    final payload = CopilotSignInPayload.fromJson(result);
    
    if (payload.isOk || payload.isAlreadySignedIn) {
      _accountStatus = CopilotAccountStatus.signedIn;
      _currentUser = payload.user;
    } else if (payload.isNotAuthorized) {
      _accountStatus = CopilotAccountStatus.notAuthorized;
    } else {
      _accountStatus = CopilotAccountStatus.notSignedIn;
    }
    
    return payload;
  }

  Future<void> signOut() async {
    await _sendRequest(
      method: 'signOut',
      params: {},
    );
    
    _accountStatus = CopilotAccountStatus.notSignedIn;
    _currentUser = null;
    _conversationId = null;
  }

  Future<String> getVersion() async {
    final response = await _sendRequest(
      method: 'getVersion',
      params: {},
    );
    
    final result = response['result'] as Map<String, dynamic>? ?? {};
    return result['version'] ?? 'unknown';
  }

  Future<void> openDocument({
    required String filePath,
    required String content,
    required String languageId,
  }) async {
    final version = (_openDocuments[filePath] ?? 0) + 1;
    _openDocuments[filePath] = version;
    
    await _sendNotification(
      method: 'textDocument/didOpen',
      params: {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'languageId': languageId,
          'version': version,
          'text': content,
        },
      },
    );
  }

  Future<void> updateDocument({
    required String filePath,
    required String content,
  }) async {
    if (!_openDocuments.containsKey(filePath)) return;
    
    final version = _openDocuments[filePath]! + 1;
    _openDocuments[filePath] = version;
    
    await _sendNotification(
      method: 'textDocument/didChange',
      params: {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'version': version,
        },
        'contentChanges': [
          {'text': content},
        ],
      },
    );
  }

  Future<void> closeDocument(String filePath) async {
    if (!_openDocuments.containsKey(filePath)) return;
    
    await _sendNotification(
      method: 'textDocument/didClose',
      params: {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
        },
      },
    );
    
    _openDocuments.remove(filePath);
  }

  Future<List<CopilotCompletion>> getCompletions({
    required String filePath,
    required String content,
    required int line,
    required int character,
    required String languageId,
    int tabSize = 2,
    bool insertSpaces = true,
  }) async {
    if (_accountStatus != CopilotAccountStatus.signedIn) {
      return [];
    }
    
    if (!_openDocuments.containsKey(filePath)) {
      await openDocument(
        filePath: filePath,
        content: content,
        languageId: languageId,
      );
    } else {
      await updateDocument(filePath: filePath, content: content);
    }
    
    final uri = Uri.file(filePath).toString();
    final relativePath = filePath.split('/').last;
    
    final response = await _sendRequest(
      method: 'getCompletions',
      params: {
        'doc': {
          'source': content,
          'tabSize': tabSize,
          'indentSize': 1,
          'insertSpaces': insertSpaces,
          'path': filePath,
          'uri': uri,
          'relativePath': relativePath,
          'languageId': languageId,
          'position': {
            'line': line,
            'character': character,
          },
          'version': _openDocuments[filePath] ?? 1,
        },
      },
    );
    
    final result = response['result'] as Map<String, dynamic>? ?? {};
    final completions = result['completions'] as List<dynamic>? ?? [];
    
    return completions
        .map((c) => CopilotCompletion.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<void> notifyAccepted(String uuid) async {
    await _sendRequest(
      method: 'notifyAccepted',
      params: {'uuid': uuid},
    );
  }

  Future<void> notifyRejected(List<String> uuids) async {
    await _sendRequest(
      method: 'notifyRejected',
      params: {'uuids': uuids},
    );
  }

  Future<Map<String, dynamic>> getInLineCompletions(String filePath, int line, int character) async {
    if (!_openDocuments.containsKey(filePath)) return {};
    final version = _openDocuments[filePath]!;
    final data = await _sendRequest(
      method: 'textDocument/inlineCompletion',
      params: {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'version': version
        },
        'position': {'line': line, 'character': character},
        'context': {'triggerKind': 1},
        "formattingOptions": {
          "tabSize": 4,
          "insertSpaces": true
        }
      },
    );
    return data;
  }

  Future<Map<String, dynamic>> getInLineEdits(String filePath, int line, int character) async {
    if (!_openDocuments.containsKey(filePath)) return {};
    final version = _openDocuments[filePath]!;
    final data = await _sendRequest(
      method: 'textDocument/copilotInlineEdit',
      params: {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'version': version
        },
        'position': {'line': line, 'character': character},
      },
    );
    return data;
  }

  Future<Map<String, dynamic>> getPanelCompletions(String filePath, int line, int character) async {
    if (!_openDocuments.containsKey(filePath)) return {};
    final version = _openDocuments[filePath]!;
    final data = await _sendRequest(
      method: 'textDocument/copilotPanelCompletion',
      params: {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'version': version
        },
        'position': {'line': line, 'character': character},
      },
    );
    return data;
  }

  Future<void> updateCompletionStatus(Map<String, dynamic> item) async {
    await _sendNotification(
      method: 'textDocument/didShowCompletion',
      params: {
        'item': item
      },
    );
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _isInitialized = false;
    _process.kill();
    _responseController.close();
    _notificationController.close();
    _progressController.close();
    _buffer.clear();
    _openDocuments.clear();
  }
}

class CopilotCompletionCacheEntry {
  final List<CopilotCompletion> completions;
  final DateTime timestamp;
  final String contentHash;
  final int line;
  final int character;

  CopilotCompletionCacheEntry({
    required this.completions,
    required this.timestamp,
    required this.contentHash,
    required this.line,
    required this.character,
  });

  bool isValid({Duration maxAge = const Duration(seconds: 10)}) {
    return DateTime.now().difference(timestamp) < maxAge;
  }
}

class CopilotCompletionManager {
  final CopilotLsp client;
  Timer? _debounceTimer;
  final Duration debounceDelay;
  final Map<String, CopilotCompletionCacheEntry> _cache = {};
  final int maxCacheSize;
  List<CopilotCompletion>? _currentCompletions;
  int _currentCompletionIndex = 0;
  void Function(CopilotCompletion? completion)? onCompletionReady;
  void Function()? onCompletionCleared;
  
  CopilotCompletionManager({
    required this.client,
    this.debounceDelay = const Duration(milliseconds: 500),
    this.maxCacheSize = 50,
    this.onCompletionReady,
    this.onCompletionCleared,
  });

  void requestCompletions({
    required String filePath,
    required String content,
    required int line,
    required int character,
    required String languageId,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () async {
      await _fetchCompletions(
        filePath: filePath,
        content: content,
        line: line,
        character: character,
        languageId: languageId,
      );
    });
  }

  Future<void> fetchCompletionsNow({
    required String filePath,
    required String content,
    required int line,
    required int character,
    required String languageId,
  }) async {
    _debounceTimer?.cancel();
    await _fetchCompletions(
      filePath: filePath,
      content: content,
      line: line,
      character: character,
      languageId: languageId,
    );
  }

  Future<void> _fetchCompletions({
    required String filePath,
    required String content,
    required int line,
    required int character,
    required String languageId,
  }) async {
    final contentHash = content.hashCode.toString();
    final cacheKey = '$filePath:$line:$character:$contentHash';
    final cached = _cache[cacheKey];
    if (cached != null && cached.isValid()) {
      _currentCompletions = cached.completions;
      _currentCompletionIndex = 0;
      onCompletionReady?.call(_currentCompletion);
      return;
    }
    
    try {
      final completions = await client.getCompletions(
        filePath: filePath,
        content: content,
        line: line,
        character: character,
        languageId: languageId,
      );
      
      _cache[cacheKey] = CopilotCompletionCacheEntry(
        completions: completions,
        timestamp: DateTime.now(),
        contentHash: contentHash,
        line: line,
        character: character,
      );
      
      if (_cache.length > maxCacheSize) {
        final sortedKeys = _cache.keys.toList()
          ..sort((a, b) => _cache[a]!.timestamp.compareTo(_cache[b]!.timestamp));
        for (var i = 0; i < _cache.length - maxCacheSize; i++) {
          _cache.remove(sortedKeys[i]);
        }
      }
      
      _currentCompletions = completions;
      _currentCompletionIndex = 0;
      onCompletionReady?.call(_currentCompletion);
    } catch (e) {
      debugPrint('Error fetching completions: $e');
      _currentCompletions = null;
      onCompletionReady?.call(null);
    }
  }

  CopilotCompletion? get _currentCompletion {
    if (_currentCompletions == null || _currentCompletions!.isEmpty) {
      return null;
    }
    return _currentCompletions![_currentCompletionIndex];
  }

  String? get currentDisplayText => _currentCompletion?.displayText;
  String? get currentText => _currentCompletion?.text;

  void nextCompletion() {
    if (_currentCompletions == null || _currentCompletions!.isEmpty) return;
    
    _currentCompletionIndex = (_currentCompletionIndex + 1) % _currentCompletions!.length;
    onCompletionReady?.call(_currentCompletion);
  }

  void previousCompletion() {
    if (_currentCompletions == null || _currentCompletions!.isEmpty) return;
    
    _currentCompletionIndex = (_currentCompletionIndex - 1 + _currentCompletions!.length) % _currentCompletions!.length;
    onCompletionReady?.call(_currentCompletion);
  }

  Future<void> acceptCompletion() async {
    final completion = _currentCompletion;
    if (completion == null) return;
    
    await client.notifyAccepted(completion.uuid);
    clearCompletions();
  }

  Future<void> rejectCompletions() async {
    if (_currentCompletions == null || _currentCompletions!.isEmpty) return;
    
    final uuids = _currentCompletions!.map((c) => c.uuid).toList();
    await client.notifyRejected(uuids);
    clearCompletions();
  }

  void clearCompletions() {
    _currentCompletions = null;
    _currentCompletionIndex = 0;
    onCompletionCleared?.call();
  }

  void cancel() {
    _debounceTimer?.cancel();
    clearCompletions();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _cache.clear();
    _currentCompletions = null;
  }
}
