import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:roxum/utils/constants.dart';
import 'agentic_tools.dart';

class CopilotAuthContext {
  final String authToken;
  final String? apiEndpoint;

  const CopilotAuthContext({
    required this.authToken,
    this.apiEndpoint,
  });
}

class CopilotChat {
  final String authToken;
  static const String _preferredCopilotApiEndpoint = 'https://api.githubcopilot.com';
  static const String _defaultCopilotApiEndpoint = 'https://api.individual.githubcopilot.com';
  static const String _graphqlEndpoint = 'https://api.github.com/graphql';

  AgenticTools? _agenticTools;
  http.Client? _currentClient;
  String? _apiEndpoint;
  List<Map<String, dynamic>>? _cachedModels;

  static const String _copilotTokenEndpoint = 'https://api.github.com/copilot_internal/v2/token';

  set agenticTools(AgenticTools tools) => _agenticTools = tools;
  final StreamController<Map<String, dynamic>> _conversationController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get conversationStream => _conversationController.stream;

  void cancelCurrentRequest() {
    _currentClient?.close();
    _currentClient = null;
  }

  static Future<CopilotAuthContext?> loadAuthContext({
    bool preferGithubToken = true,
  }) async {
    try {
      const FlutterSecureStorage storage = FlutterSecureStorage();
      final all = await storage.readAll();

      final tokenFromCopilotConfig = await _loadCopilotOauthTokenFromConfigFiles(
        domain: 'github.com',
      );
      if (tokenFromCopilotConfig != null && tokenFromCopilotConfig.isNotEmpty) {
        final exchanged = await _exchangeGithubTokenForCopilotContext(
          tokenFromCopilotConfig,
        );
        if (exchanged != null) {
          return exchanged;
        }
        return CopilotAuthContext(authToken: tokenFromCopilotConfig);
      }

      final explicitCopilotToken = all['copilot_chat_auth_token'];
      if (explicitCopilotToken != null && explicitCopilotToken.isNotEmpty) {
        final exchanged = await _exchangeGithubTokenForCopilotContext(
          explicitCopilotToken,
        );
        if (exchanged != null) {
          return exchanged;
        }
        return CopilotAuthContext(authToken: explicitCopilotToken);
      }

      final copilotEntry = all.entries.cast<MapEntry<String, String?>>().firstWhere(
        (entry) {
          final key = entry.key.toLowerCase();
          final value = entry.value;
          return key.contains('copilot') && value != null && value.isNotEmpty;
        },
        orElse: () => const MapEntry<String, String?>('', null),
      );

      if (copilotEntry.value != null && copilotEntry.value!.isNotEmpty) {
        final exchanged = await _exchangeGithubTokenForCopilotContext(
          copilotEntry.value!,
        );
        if (exchanged != null) {
          return exchanged;
        }
        return CopilotAuthContext(authToken: copilotEntry.value!);
      }

      final githubToken = all['github_access_token'];
      if (githubToken != null && githubToken.isNotEmpty) {
        final exchanged = await _exchangeGithubTokenForCopilotContext(githubToken);
        if (exchanged != null) {
          return exchanged;
        }
        return CopilotAuthContext(authToken: githubToken);
      }
    } catch (e) {
      return null;
    }

    return null;
  }

  static Future<String?> loadAuthToken({bool preferGithubToken = true}) async {
    final authContext = await loadAuthContext(
      preferGithubToken: preferGithubToken,
    );
    return authContext?.authToken;
  }

  static Future<CopilotAuthContext?> _exchangeGithubTokenForCopilotContext(
    String githubToken,
  ) async {
    Future<http.Response> requestWithAuth(String authHeader) {
      return http.get(
        Uri.parse(_copilotTokenEndpoint),
        headers: {
          'Authorization': authHeader,
          'Accept': 'application/json',
          'X-GitHub-Api-Version': '2025-04-01',
        },
      );
    }

    try {
      var response = await requestWithAuth('token $githubToken');
      if (response.statusCode != 200) {
        response = await requestWithAuth('Bearer $githubToken');
      }

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final token = decoded['token'] as String?;
      if (token == null || token.isEmpty) {
        return null;
      }

      final endpoints = decoded['endpoints'] as Map<String, dynamic>?;
      final apiEndpoint = endpoints?['api'] as String?;

      return CopilotAuthContext(
        authToken: token,
        apiEndpoint: (apiEndpoint != null && apiEndpoint.isNotEmpty)
            ? apiEndpoint
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _loadCopilotOauthTokenFromConfigFiles({
    required String domain,
  }) async {
    final candidates = <String>[
      '$filesDir/github-copilot/hosts.json',
      '$filesDir/github-copilot/apps.json',
      '$filesDir/.config/github-copilot/hosts.json',
      '$filesDir/.config/github-copilot/apps.json',
      '$homeDir/.config/github-copilot/hosts.json',
      '$homeDir/.config/github-copilot/apps.json',
    ];

    for (final filePath in candidates) {
      try {
        final file = File(filePath);
        if (!await file.exists()) continue;

        final content = await file.readAsString();
        final parsed = jsonDecode(content);
        if (parsed is! Map<String, dynamic>) continue;

        for (final entry in parsed.entries) {
          final key = entry.key.toLowerCase();
          final value = entry.value;
          if (value is! Map<String, dynamic>) continue;

          final oauthToken = value['oauth_token'] as String?;
          if (oauthToken == null || oauthToken.isEmpty) continue;

          if (key.startsWith(domain.toLowerCase()) || key.contains(domain.toLowerCase())) {
            return oauthToken;
          }
        }
      } catch (e) {
        continue;
      }
    }

    return null;
  }

  CopilotChat({
    required this.authToken,
    String? initialApiEndpoint,
  }) : _apiEndpoint = initialApiEndpoint;

  Map<String, String> _commonHeaders({
    bool isJsonBody = false,
    ChatMode? chatMode,
  }) {
    String? initiator;
    if (chatMode != null) {
      initiator = chatMode == ChatMode.agent ? 'agent' : 'user';
    }

    return {
      'Authorization': 'Bearer $authToken',
      'Accept': 'application/json',
      'Copilot-Integration-Id': 'vscode-chat',
      'User-Agent': 'Roxum/2.3.0',
      'Editor-Version': 'Roxum/2.3.0',
      'X-GitHub-Api-Version': '2025-10-01',
      'X-Initiator': ?initiator,
      if (initiator != null) 'X-Interaction-Type': 'conversation-panel',
      if (initiator != null) 'OpenAI-Intent': 'conversation-panel',
      if (isJsonBody) 'Content-Type': 'application/json; charset=utf-8',
    };
  }

  Future<String> _resolveApiEndpoint() async {
    if (_apiEndpoint != null && _apiEndpoint!.isNotEmpty) {
      return _apiEndpoint!;
    }

    try {
      final response = await http.post(
        Uri.parse(_graphqlEndpoint),
        headers: _commonHeaders(isJsonBody: true),
        body: jsonEncode({
          'query': 'query { viewer { copilotEndpoints { api } } }',
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final api =
            ((decoded['data'] as Map<String, dynamic>?)?['viewer']
                as Map<String, dynamic>?)?['copilotEndpoints'];
        final endpoint = (api as Map<String, dynamic>?)?['api'] as String?;
        if (endpoint != null && endpoint.isNotEmpty) {
          _apiEndpoint = endpoint;
          return endpoint;
        }
      }
    } catch (_) {
    }

    try {
      final preferredProbe = await http.get(
        Uri.parse('$_preferredCopilotApiEndpoint/models'),
        headers: _commonHeaders(),
      );
      if (preferredProbe.statusCode == 200) {
        _apiEndpoint = _preferredCopilotApiEndpoint;
        return _apiEndpoint!;
      }
    } catch (_) {
    }

    _apiEndpoint = _defaultCopilotApiEndpoint;
    return _apiEndpoint!;
  }

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

  Set<String> _modelSupportedEndpoints(String model) {
    if (_cachedModels == null) return const {};

    final modelData = _cachedModels!.firstWhere(
      (item) => item['id'] == model,
      orElse: () => const {},
    );

    if (modelData.isEmpty) return const {};
    final endpoints = modelData['supported_endpoints'];
    if (endpoints is! List) return const {};
    return endpoints
      .whereType<String>()
      .map(_normalizeEndpoint)
      .where((item) => item.isNotEmpty)
      .toSet();
  }

  String _selectChatPath(String model, {required bool wantsToolCalls}) {
    final supportedEndpoints = _modelSupportedEndpoints(model);

    if (wantsToolCalls) {
      return '/chat/completions';
    }

    if (supportedEndpoints.isEmpty) {
      return '/chat/completions';
    }

    if (supportedEndpoints.contains('/responses')) {
      return '/responses';
    }

    if (supportedEndpoints.contains('/chat/completions')) {
      return '/chat/completions';
    }

    if (supportedEndpoints.contains('/messages')) {
      return '/v1/messages';
    }

    return '/chat/completions';
  }

  Map<String, dynamic> _buildRequestBodyForPath(
    String path,
    String model,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) {
    switch (path) {
      case '/responses':
        return {'model': model, 'input': messages, 'stream': true};
      case '/v1/messages':
        return {
          'model': model,
          'messages': messages,
          'max_tokens': 4096,
          'stream': true,
        };
      case '/chat/completions':
      default:
        return {
          'model': model,
          'messages': messages,
          'stream': true,
          if (tools.isNotEmpty) 'tools': tools,
        };
    }
  }

  String? _extractDeltaText(Map<String, dynamic> json, String path) {
    if (path == '/chat/completions') {
      return json['choices']?[0]?['delta']?['content'] as String?;
    }

    if (path == '/responses') {
      final type = json['type'] as String?;
      if (type == 'response.output_text.delta') {
        return json['delta'] as String?;
      }
      if (type == 'response.output_text.done') {
        return json['text'] as String?;
      }
      return null;
    }

    if (path == '/v1/messages') {
      final type = json['type'] as String?;
      if (type == 'content_block_delta') {
        return json['delta']?['text'] as String?;
      }
      return null;
    }

    return null;
  }

  String? _extractReasoningDelta(Map<String, dynamic> json, String path) {
    if (path == '/chat/completions') {
      final delta = json['choices']?[0]?['delta'];
      if (delta is! Map) return null;

      final direct = delta['reasoning_content'];
      if (direct is String && direct.isNotEmpty) return direct;

      final reasoning = delta['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) return reasoning;
      if (reasoning is Map) {
        final text = reasoning['text'];
        if (text is String && text.isNotEmpty) return text;
      }
      if (reasoning is List) {
        final buffer = StringBuffer();
        for (final item in reasoning) {
          if (item is String) {
            buffer.write(item);
          } else if (item is Map && item['text'] is String) {
            buffer.write(item['text']);
          }
        }
        final merged = buffer.toString();
        if (merged.isNotEmpty) return merged;
      }
      return null;
    }

    if (path == '/responses') {
      final type = (json['type'] as String?) ?? '';
      if (!type.contains('reasoning')) return null;

      final delta = json['delta'];
      if (delta is String && delta.isNotEmpty) return delta;
      final text = json['text'];
      if (text is String && text.isNotEmpty) return text;

      final summary = json['summary'];
      if (summary is String && summary.isNotEmpty) return summary;

      final content = json['content'];
      if (content is String && content.isNotEmpty) return content;
      return null;
    }

    if (path == '/v1/messages') {
      final type = json['type'] as String?;
      if (type == 'content_block_delta') {
        final delta = json['delta'];
        if (delta is Map) {
          final deltaType = delta['type'] as String?;
          if (deltaType == 'thinking_delta' || deltaType == 'reasoning_delta') {
            final text = delta['text'];
            if (text is String && text.isNotEmpty) return text;
          }
        }
      }
    }

    return null;
  }

  int _lineCount(String? text) {
    if (text == null || text.isEmpty) return 0;
    return text.split('\n').length;
  }

  String _shellCommandPreview(String command, List<String> args) {
    final parts = [command, ...args].map(_shellEscape).toList();
    return parts.join(' ');
  }

  String _shellEscape(String value) {
    if (value.isEmpty) return "''";
    final safePattern = RegExp(r'^[A-Za-z0-9_./:-]+');
    final match = safePattern.firstMatch(value);
    if (match != null && match.start == 0 && match.end == value.length) {
      return value;
    }
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  String _toolEditMarker(String filePath, int added, int removed) {
    final fileEncoded = base64Encode(utf8.encode(filePath));
    return '[[ROXUM_EDIT:$fileEncoded|$added|$removed]]\n';
  }

  String _toolTerminalMarker(
    String command, {
    String? stdout,
    String? stderr,
    String? exitCode,
  }) {
    final payload = jsonEncode({
      'command': command,
      'stdout': stdout ?? '',
      'stderr': stderr ?? '',
      'exitCode': exitCode,
    });
    final encoded = base64Encode(utf8.encode(payload));
    return '[[ROXUM_TERMINAL:$encoded]]\n';
  }

  String _toolStatusMarker(String status) {
    return '[[ROXUM_STATUS:$status]]\n';
  }

  String _toolStatusForFunction(String functionName) {
    const analyzingTools = {
      'activeEditorFile',
      'currentlySelectedText',
      'getLspDiagnostics',
      'readFile',
      'listFiles',
      'readFilesBatch',
      'globSearchFiles',
      'searchInFiles',
      'grepInFiles',
      'getPendingEditsForFile',
      'getFileInfo',
      'gitStatus',
      'gitDiff',
      'gitLog',
      'searchInWeb',
      'openLinks',
    };

    const patchTools = {
      'writeFile',
      'deleteFile',
      'renamePath',
      'rename',
      'insertAtLine',
      'replaceAllInFile',
      'editFile',
    };

    if (analyzingTools.contains(functionName)) {
      return 'Analyzing';
    }
    if (patchTools.contains(functionName)) {
      return 'Generating patch';
    }
    return 'Processing';
  }

  Future<Map<String, dynamic>> getCopilotModels() async {
    final apiEndpoint = await _resolveApiEndpoint();
    final modelUrl = '$apiEndpoint/models';

    final response = await http.get(
      Uri.parse(modelUrl),
      headers: _commonHeaders(),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final parsed = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{
              'data': decoded,
            };
      final data = parsed['data'];
      if (data is List) {
        _cachedModels = data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
      }
      return parsed;
    } else {
      throw Exception(
        'Failed to fetch models: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<String> chatWithModel({
    required String model,
    required List<Map<String, dynamic>> messages,
    ChatMode chatMode = ChatMode.ask,
    void Function(String)? onPartial,
  }) async {
    var tools = chatMode == ChatMode.agent
      ? _agenticTools?.getTools() ?? []
      : _agenticTools?.getTools(readAccessOnly: true) ?? [];
    final conversationMessages = List<Map<String, dynamic>>.from(messages);
    final apiEndpoint = await _resolveApiEndpoint();
    final chatPath = _selectChatPath(
      model,
      wantsToolCalls: tools.isNotEmpty,
    );
    final streamedOutput = StringBuffer();
    var emittingThinking = false;

    void pushPartial(String text) {
      if (text.isEmpty) return;
      streamedOutput.write(text);
      onPartial?.call(text);
    }

    while (true) {
      final requestBody = _buildRequestBodyForPath(
        chatPath,
        model,
        conversationMessages,
        tools,
      );

      _currentClient = http.Client();
      final request = http.Request('POST', Uri.parse('$apiEndpoint$chatPath'));
      request.headers.addAll(
        _commonHeaders(isJsonBody: true, chatMode: chatMode),
      );
      request.body = jsonEncode(requestBody);

      final streamedResponse = await _currentClient!.send(request);

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw Exception(body);
      }

      final lines = streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
      Map<String, dynamic>? finalMessage;
      List<Map<String, dynamic>> toolCallDeltas = [];

      await for (var line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data);
            if (chatPath == '/chat/completions') {
              final delta = json['choices']?[0]?['delta'];
              if (delta == null) continue;
              finalMessage ??= {
                'role': delta['role'] ?? 'assistant',
                'content': '',
              };

              final reasoningDelta = _extractReasoningDelta(json, chatPath);
              if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
                if (!emittingThinking) {
                  emittingThinking = true;
                  const openMarker = '[[ROXUM_THINK_START]]\n';
                  finalMessage['content'] += openMarker;
                  pushPartial(openMarker);
                }
                finalMessage['content'] += reasoningDelta;
                pushPartial(reasoningDelta);
              }

              final deltaText = _extractDeltaText(json, chatPath);
              if (deltaText != null && deltaText.isNotEmpty) {
                if (emittingThinking) {
                  emittingThinking = false;
                  const closeMarker = '\n[[ROXUM_THINK_END]]\n';
                  finalMessage['content'] += closeMarker;
                  pushPartial(closeMarker);
                }
                finalMessage['content'] += deltaText;
                pushPartial(deltaText);
              }

              if (delta['tool_calls'] is List) {
                for (final rawToolCallDelta in delta['tool_calls']) {
                  if (rawToolCallDelta is! Map) {
                    continue;
                  }

                  final toolCallDelta = Map<String, dynamic>.from(rawToolCallDelta);
                  final rawIndex = toolCallDelta['index'];
                  final index = rawIndex is int
                      ? rawIndex
                      : int.tryParse(rawIndex?.toString() ?? '');
                  if (index == null || index < 0) {
                    continue;
                  }

                  while (index >= toolCallDeltas.length) {
                    toolCallDeltas.add({});
                  }

                  if (toolCallDelta['id'] != null) {
                    toolCallDeltas[index]['id'] = toolCallDelta['id'];
                  }

                  final functionDelta = toolCallDelta['function'];
                  if (functionDelta is Map) {
                    toolCallDeltas[index]['function'] ??= <String, dynamic>{};
                    if (functionDelta['name'] != null) {
                      toolCallDeltas[index]['function']['name'] =
                          functionDelta['name'];
                    }
                    if (functionDelta['arguments'] != null) {
                      toolCallDeltas[index]['function']['arguments'] ??= '';
                      toolCallDeltas[index]['function']['arguments'] += functionDelta['arguments'];
                    }
                  }
                }
              }
            } else {
              finalMessage ??= {'role': 'assistant', 'content': ''};
              final reasoningDelta = _extractReasoningDelta(json, chatPath);
              if (reasoningDelta != null && reasoningDelta.isNotEmpty) {
                if (!emittingThinking) {
                  emittingThinking = true;
                  const openMarker = '[[ROXUM_THINK_START]]\n';
                  finalMessage['content'] += openMarker;
                  pushPartial(openMarker);
                }
                finalMessage['content'] += reasoningDelta;
                pushPartial(reasoningDelta);
              }

              final deltaText = _extractDeltaText(json, chatPath);
              if (deltaText != null && deltaText.isNotEmpty) {
                if (emittingThinking) {
                  emittingThinking = false;
                  const closeMarker = '\n[[ROXUM_THINK_END]]\n';
                  finalMessage['content'] += closeMarker;
                  pushPartial(closeMarker);
                }
                finalMessage['content'] += deltaText;
                pushPartial(deltaText);
              }
            }
          } catch (e) {
            continue;
          }
        }
      }

      _currentClient?.close();
      _currentClient = null;

      if (finalMessage == null) {
        throw Exception('No message received from stream');
      }

      if (emittingThinking) {
        emittingThinking = false;
        const closeMarker = '\n[[ROXUM_THINK_END]]\n';
        finalMessage['content'] += closeMarker;
        pushPartial(closeMarker);
      }

      final message = finalMessage;
      if (toolCallDeltas.isNotEmpty) {
        final validToolCalls = toolCallDeltas.where((call) {
          final id = call['id']?.toString();
          final function = call['function'];
          final functionName = function is Map ? function['name']?.toString() : null;
          return id != null && id.isNotEmpty && functionName != null && functionName.isNotEmpty;
        }).toList();

        if (validToolCalls.isNotEmpty) {
          message['tool_calls'] = validToolCalls;
        }
      }

      conversationMessages.add(message);

      final toolCallsFromMessage = message['tool_calls'] is List
        ? message['tool_calls'] as List
        : const [];
      if (chatPath != '/chat/completions' ||
          toolCallsFromMessage.isEmpty) {
        final output = streamedOutput.toString();
        if (output.isNotEmpty) return output;
        return message['content'] ?? '';
      }

      pushPartial(_toolStatusMarker('Processing'));

      for (final rawCall in toolCallsFromMessage) {
        if (rawCall is! Map) {
          continue;
        }

        final call = Map<String, dynamic>.from(rawCall);
        final callId = call['id']?.toString();
        if (callId == null || callId.isEmpty) {
          stderr.writeln('[CopilotChat] Malformed tool call without id: $call');
          continue;
        }

        final function = call['function'];
        if (function is! Map) {
          stderr.writeln('[CopilotChat] Malformed tool call without function: $call');
          continue;
        }

        final functionMap = Map<String, dynamic>.from(function);
        final functionName = functionMap['name']?.toString();
        if (functionName == null || functionName.isEmpty) {
          stderr.writeln('[CopilotChat] Malformed tool call without name: $call');
          continue;
        }

        pushPartial(_toolStatusMarker(_toolStatusForFunction(functionName)));

        final rawArgs = functionMap['arguments'];
        Map<String, dynamic> args = <String, dynamic>{};
        if (rawArgs is String && rawArgs.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(rawArgs);
            if (decoded is Map<String, dynamic>) {
              args = decoded;
            } else if (decoded is Map) {
              args = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {
            stderr.writeln('[CopilotChat] Failed to decode tool args for $functionName: $rawArgs');
          }
        } else if (rawArgs is Map<String, dynamic>) {
          args = rawArgs;
        } else if (rawArgs is Map) {
          args = Map<String, dynamic>.from(rawArgs);
        }

        String result;

        try {
          final errorMessage = "Failed to call $functionName";
          switch (functionName) {
            case 'activeEditorFile':
              final res =
                  await _agenticTools?.activeEditorFile() ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? (res.data ?? 'No active file')
                  : (res.error ?? 'Error getting active file');
              break;
            case 'currentlySelectedText':
              final res =
                  await _agenticTools?.currentlySelectedText() ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? 'Start Line: ${res.data?['startLine'] ?? 'Unknown'}, End Line: ${res.data?['endLine'] ?? 'Unknown'}, Text: ${res.data?['selectedText'] ?? ''}'
                  : (res.error ?? 'Error getting selected text');
              break;
            case 'getLspDiagnostics':
              final res =
                  await _agenticTools?.getLspDiagnostics(args['filePath']) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? jsonEncode(res.data)
                  : (res.error ?? 'Error getting LSP diagnostics');
              break;
            case 'readFile':
              final res =
                  await _agenticTools?.readFile(
                    args['filePath'],
                    args['startLine'],
                    args['endLine'],
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? (res.data ?? 'No content')
                  : (res.error ?? 'Error reading file');
              break;
            case 'writeFile':
              String? previousContent;
              final previousRead = await _agenticTools?.readFile(
                args['filePath'],
              );
              if (previousRead != null && previousRead.success) {
                previousContent = previousRead.data;
              }

              final res =
                  await _agenticTools?.writeFile(
                    args['filePath'],
                    args['content'],
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? 'File written successfully'
                  : (res.error ?? 'Error writing file');
              if (res.success) {
                final added = _lineCount(args['content']?.toString());
                final removed = _lineCount(previousContent);
                pushPartial(
                  _toolStatusMarker('Generating patch (+$added/-$removed)'),
                );
                pushPartial(
                  _toolEditMarker(
                    args['filePath']?.toString() ?? 'unknown',
                    added,
                    removed,
                  ),
                );
              }
              break;
            case 'deleteFile':
              final previousRead = await _agenticTools?.readFile(args['filePath']);
              final res =
                  await _agenticTools?.deleteFile(args['filePath']) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? 'File deleted successfully'
                  : (res.error ?? 'Error deleting file');
              if (res.success) {
                final removed = _lineCount(previousRead?.data);
                pushPartial(
                  _toolStatusMarker('Generating patch (+0/-$removed)'),
                );
                pushPartial(
                  _toolEditMarker(
                    args['filePath']?.toString() ?? 'unknown',
                    0,
                    removed,
                  ),
                );
              }
              break;
            case 'renamePath':
              final res =
                  await _agenticTools?.renamePath(
                    args['oldPath'],
                    args['newPath'],
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? 'Path renamed successfully'
                  : (res.error ?? 'Error renaming path');
              break;
            case 'rename':
              final res =
                  await _agenticTools?.rename(
                    args['oldPath'],
                    args['newPath'],
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? 'Path renamed successfully'
                  : (res.error ?? 'Error renaming path');
              break;
            case 'insertAtLine':
              final res =
                  await _agenticTools?.insertAtLine(
                    args['filePath'],
                    args['line'],
                    args['text'],
                    position: args['position'] ?? 'before',
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? 'Text inserted successfully'
                  : (res.error ?? 'Error inserting text');
              if (res.success) {
                final added = _lineCount(args['text']?.toString());
                pushPartial(
                  _toolStatusMarker('Generating patch (+$added/-0)'),
                );
                pushPartial(
                  _toolEditMarker(
                    args['filePath']?.toString() ?? 'unknown',
                    added,
                    0,
                  ),
                );
              }
              break;
            case 'replaceAllInFile':
              final res =
                  await _agenticTools?.replaceAllInFile(
                    args['filePath'],
                    args['oldText'],
                    args['newText'],
                    useRegex: args['useRegex'] ?? false,
                    maxReplacements: args['maxReplacements'],
                    caseSensitive: args['caseSensitive'] ?? true,
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? jsonEncode(res.data)
                  : (res.error ?? 'Error replacing text');
              if (res.success) {
                final added = _lineCount(args['newText']?.toString());
                final removed = _lineCount(args['oldText']?.toString());
                pushPartial(
                  _toolStatusMarker('Generating patch (+$added/-$removed)'),
                );
                pushPartial(
                  _toolEditMarker(
                    args['filePath']?.toString() ?? 'unknown',
                    added,
                    removed,
                  ),
                );
              }
              break;
            case 'listFiles':
              final res =
                  await _agenticTools?.listFiles(
                    args['directoryPath'],
                    pattern: args['pattern'],
                    recursive: args['recursive'] ?? false,
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? (res.data?.join('\n') ?? 'No files')
                  : (res.error ?? 'Error listing files');
              break;
            case 'readFilesBatch':
              final parsedFiles = (args['files'] as List?) ?? const [];
              final res =
                  await _agenticTools?.readFilesBatch(parsedFiles) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? jsonEncode(res.data)
                  : (res.error ?? 'Error reading files batch');
              break;
            case 'globSearchFiles':
              final parsedExcludePatterns =
                  (args['excludePatterns'] as List?)
                      ?.map((item) => item.toString())
                      .toList();
              final res =
                  await _agenticTools?.globSearchFiles(
                    args['pattern'],
                    directoryPath: args['directoryPath'] ?? '.',
                    excludePatterns: parsedExcludePatterns,
                    recursive: args['recursive'] ?? true,
                    maxResults: args['maxResults'],
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? (res.data?.join('\n') ?? 'No matches')
                  : (res.error ?? 'Error searching files by glob');
              break;
            case 'searchInFiles':
              final res =
                  await _agenticTools?.searchInFiles(
                    args['query'],
                    filePattern: args['filePattern'],
                    caseSensitive: args['caseSensitive'] ?? false,
                    matchWholeWord: args['matchWholeWord'] ?? false,
                    useRegex: args['useRegex'] ?? false,
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? (res.data
                            ?.map(
                              (s) =>
                                  '${s.filePath}:${s.lineNumber}: ${s.lineContent}',
                            )
                            .join('\n') ??
                        'No results')
                  : (res.error ?? 'Error searching files');
              break;
            case 'grepInFiles':
              final res =
                  await _agenticTools?.grepInFiles(
                    args['query'],
                    filePattern: args['filePattern'],
                    caseSensitive: args['caseSensitive'] ?? false,
                    matchWholeWord: args['matchWholeWord'] ?? false,
                    useRegex: args['useRegex'] ?? false,
                    before: args['before'] ?? 2,
                    after: args['after'] ?? 2,
                    maxResults: args['maxResults'],
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? (res.data?.map((r) => r.toString()).join('\n') ?? 'No results')
                  : (res.error ?? 'Error grepping files');
              break;
            case 'editFile':
              final res =
                  await _agenticTools?.editFile(
                    args['filePath'],
                    args['oldText'],
                    args['newText'],
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? 'File edited successfully'
                  : (res.error ?? 'Error editing file');
              if (res.success) {
                final added = _lineCount(args['newText']?.toString());
                final removed = _lineCount(args['oldText']?.toString());
                pushPartial(
                  _toolStatusMarker('Generating patch (+$added/-$removed)'),
                );
                pushPartial(
                  _toolEditMarker(
                    args['filePath']?.toString() ?? 'unknown',
                    added,
                    removed,
                  ),
                );
              }
              break;
            case 'getPendingEditsForFile':
              final res =
                  await _agenticTools?.getPendingEditsForFile(
                    args['filePath'],
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? (res.data == null
                        ? 'No pending edits'
                        : jsonEncode(res.data!.toJson()))
                  : (res.error ?? 'Error getting pending edits');
              break;
            case 'getFileInfo':
              final res =
                  await _agenticTools?.getFileInfo(args['filePath']) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? 'Path: ${res.data?.path ?? 'Unknown'}, Size: ${res.data?.size ?? 0}, Modified: ${res.data?.modified ?? 'Unknown'}, IsDirectory: ${res.data?.isDirectory ?? false}'
                  : (res.error ?? 'Error getting file info');
              break;
            case 'openLinks':
              final res =
                  await _agenticTools?.openLinks(args['url']) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? (res.data?.toString() ?? 'No content')
                  : (res.error ?? 'Error fetching web page');
              break;
            case 'searchInWeb':
              final res =
                  await _agenticTools?.searchInWeb(args['searchQuery']) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? (res.data
                            ?.map((w) => '${w.title}\n${w.url}\n${w.snippet}')
                            .join('\n---\n') ??
                        'No results')
                  : (res.error ?? 'Error searching web');
              break;
            case 'runShellCommand':
              final parsedArgs =
                  (args['args'] as List?)
                      ?.map((item) => item.toString())
                      .toList() ??
                  <String>[];
              final parsedEnvs =
                  (args['envs'] as Map?)?.map(
                    (key, value) => MapEntry(key.toString(), value.toString()),
                  ) ??
                  <String, String>{};
              final preview = _shellCommandPreview(
                args['command']?.toString() ?? '',
                parsedArgs,
              );
              final res =
                  await _agenticTools?.runShellCommand(
                    args['command'],
                    parsedArgs,
                    parsedEnvs,
                  ) ??
                  ToolResult.error(errorMessage);
              if (res.success) {
                final data = res.data ?? const <String, String>{};
                pushPartial(
                  _toolTerminalMarker(
                    preview,
                    stdout: data['stdout'] ?? '',
                    stderr: data['stderr'] ?? '',
                    exitCode: data['exitCode'],
                  ),
                );
              } else {
                pushPartial(
                  _toolTerminalMarker(
                    preview,
                    stderr: res.error ?? 'Error running shell command',
                    exitCode: 'error',
                  ),
                );
              }
              result = res.success
                  ? jsonEncode(res.data)
                  : (res.error ?? 'Error running shell command');
              break;
            case 'gitStatus':
              final res =
                  await _agenticTools?.gitStatus() ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? jsonEncode(res.data?.toJson())
                  : (res.error ?? 'Error getting git status');
              break;
            case 'gitDiff':
              final res =
                  await _agenticTools?.gitDiff(
                    filePath: args['filePath'],
                    staged: args['staged'] ?? false,
                    contextLines: args['contextLines'] ?? 3,
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? (res.data ?? '')
                  : (res.error ?? 'Error getting git diff');
              break;
            case 'gitLog':
              final res =
                  await _agenticTools?.gitLog(
                    limit: args['limit'] ?? 20,
                    filePath: args['filePath'],
                  ) ??
                  ToolResult.error(errorMessage);
              result = res.success
                  ? jsonEncode(res.data?.map((c) => c.toJson()).toList() ?? [])
                  : (res.error ?? 'Error getting git log');
              break;
            default:
              result = 'Unknown tool: $functionName';
          }
        } catch (e) {
          result = 'Error executing tool $functionName: $e';
        }

        conversationMessages.add({
          'role': 'tool',
          'content': result,
          'tool_call_id': callId,
        });
      }
    }
  }

  void dispose() {
    _currentClient?.close();
    _conversationController.close();
  }
}

enum ChatMode { agent, ask }
