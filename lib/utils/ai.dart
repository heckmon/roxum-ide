import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:http/http.dart' as http;

enum ToolCallingMethod {
  none,
  openAiCompatible,
  anthropicMessages,
  geminiFunctionCalling,
}

class AiCompletion {
  Models model;
  bool enableCompletion;
  int debounceTime;
  CompletionType completionType;

  AiCompletion({
    required this.model,
    this.completionType = CompletionType.auto,
    this.debounceTime = 1000,
    this.enableCompletion = true,
  });
}

sealed class Models {
  String get url;
  String? get apiKey;
  String? get model;
  Map<String, String> get headers;
  ToolCallingMethod get toolCallingMethod => ToolCallingMethod.none;
  bool get supportsToolCalling => toolCallingMethod != ToolCallingMethod.none;
  String get chatUrl => url;

  static const String instruction =
      "You are a code completion engine. "
      "The input contains partial code context split into sections, with the exact insertion point marked by the placeholder '<|CURSOR|>'. "
      "Using only the provided context, generate the code that should be inserted at the cursor position. "
      "Do not repeat the placeholder, do not include explanations, comments, formatting markers, or surrounding context. "
      "Return only the code to insert.";

  Map<String, dynamic> buildRequest(String code);

  String responseParser(dynamic response);

  Map<String, dynamic> buildToolCallingRequest({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    bool stream = false,
  }) {
    switch (toolCallingMethod) {
      case ToolCallingMethod.anthropicMessages:
        final systemPrompts = messages
          .where((message) => message['role'] == 'system')
          .map((message) => message['content']?.toString() ?? '')
          .where((text) => text.isNotEmpty)
          .toList();

        final nonSystemMessages = messages
            .where((message) => message['role'] != 'system')
            .toList();

        return {
          if (model != null) 'model': model,
          'max_tokens': 4096,
          if (systemPrompts.isNotEmpty) 'system': systemPrompts.join('\n\n'),
          'messages': _toAnthropicMessages(nonSystemMessages),
          if (tools.isNotEmpty) 'tools': _toAnthropicTools(tools),
          if (stream) 'stream': true,
        };
      case ToolCallingMethod.geminiFunctionCalling:
        final systemPrompts = messages
          .where((message) => message['role'] == 'system')
          .map((message) => message['content']?.toString() ?? '')
          .where((text) => text.isNotEmpty)
          .toList();

        final nonSystemMessages = messages.where((message) => message['role'] != 'system').toList();

        return {
          'contents': _toGeminiContents(nonSystemMessages),
          if (systemPrompts.isNotEmpty)
            'systemInstruction': {
              'parts': [
                {'text': systemPrompts.join('\n\n')},
              ],
            },
          if (tools.isNotEmpty)
            'tools': [
              {
                'functionDeclarations': _toGeminiFunctionDeclarations(tools),
              }
            ],
        };
      case ToolCallingMethod.none:
      case ToolCallingMethod.openAiCompatible:
        return {
          if (model != null) 'model': model,
          'messages': messages,
          'stream': stream,
          if (tools.isNotEmpty) 'tools': tools,
        };
    }
  }

  String parseChatMessage(dynamic response) {
    switch (toolCallingMethod) {
      case ToolCallingMethod.anthropicMessages:
        try {
          final content = response['content'];
          if (content is! List) return '';
          final buffer = StringBuffer();
          for (final block in content) {
            if (block is Map && block['type'] == 'text') {
              final text = block['text']?.toString() ?? '';
              if (text.isNotEmpty) {
                if (buffer.isNotEmpty) buffer.write('\n');
                buffer.write(text);
              }
            }
          }
          return buffer.toString();
        } catch (_) {
          return '';
        }
      case ToolCallingMethod.geminiFunctionCalling:
        try {
          final parts = response['candidates']?[0]?['content']?['parts'];
          if (parts is! List) return '';
          final buffer = StringBuffer();
          for (final part in parts) {
            if (part is Map && part['text'] != null) {
              final text = part['text']?.toString() ?? '';
              if (text.isNotEmpty) {
                if (buffer.isNotEmpty) buffer.write('\n');
                buffer.write(text);
              }
            }
          }
          return buffer.toString();
        } catch (_) {
          return '';
        }
      case ToolCallingMethod.none:
      case ToolCallingMethod.openAiCompatible:
        try {
          return response["choices"]?[0]?["message"]?["content"]?.toString() ?? '';
        } catch (_) {
          return '';
        }
    }
  }

  List<Map<String, dynamic>> parseToolCalls(dynamic response) {
    switch (toolCallingMethod) {
      case ToolCallingMethod.anthropicMessages:
        try {
          final content = response['content'];
          if (content is! List) return const [];
          final calls = <Map<String, dynamic>>[];
          for (final block in content) {
            if (block is! Map || block['type'] != 'tool_use') continue;
            final id = block['id']?.toString();
            final name = block['name']?.toString();
            final input = block['input'];
            if (id == null || id.isEmpty || name == null || name.isEmpty) {
              continue;
            }
            final args = input is Map ? jsonEncode(input) : '{}';
            calls.add({
              'id': id,
              'type': 'function',
              'function': {
                'name': name,
                'arguments': args,
              },
            });
          }
          return calls;
        } catch (_) {
          return const [];
        }
      case ToolCallingMethod.geminiFunctionCalling:
        try {
          final parts = response['candidates']?[0]?['content']?['parts'];
          if (parts is! List) return const [];
          final calls = <Map<String, dynamic>>[];
          for (var i = 0; i < parts.length; i++) {
            final part = parts[i];
            if (part is! Map || part['functionCall'] is! Map) continue;
            final functionCall = Map<String, dynamic>.from(part['functionCall']);
            final name = functionCall['name']?.toString();
            if (name == null || name.isEmpty) continue;
            final callId = functionCall['id']?.toString();
            final argsMap = functionCall['args'];
            final args = argsMap is Map ? jsonEncode(argsMap) : '{}';
            final geminiFunctionCall = <String, dynamic>{
              ...functionCall,
              'name': name,
              'args': argsMap is Map ? Map<String, dynamic>.from(argsMap) : <String, dynamic>{},
            };
            final geminiPart = Map<String, dynamic>.from(part);
            if (callId != null && callId.isNotEmpty) {
              geminiFunctionCall['id'] = callId;
            }
            calls.add({
              'id': (callId != null && callId.isNotEmpty)
                  ? callId
                  : 'gemini_call_${DateTime.now().millisecondsSinceEpoch}_$i',
              'type': 'function',
              'function': {
                'name': name,
                'arguments': args,
              },
              '_geminiPart': geminiPart,
              '_geminiFunctionCall': geminiFunctionCall,
            });
          }
          return calls;
        } catch (_) {
          return const [];
        }
      case ToolCallingMethod.none:
      case ToolCallingMethod.openAiCompatible:
        try {
          final rawCalls = response["choices"]?[0]?['message']?["tool_calls"];
          if (rawCalls is! List) return const [];
          return rawCalls
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        } catch (_) {
          return const [];
        }
    }
  }

  List<Map<String, dynamic>> _toAnthropicTools(
    List<Map<String, dynamic>> tools,
  ) {
    final converted = <Map<String, dynamic>>[];
    for (final tool in tools) {
      final function = tool['function'];
      if (function is! Map) continue;
      converted.add({
        'name': function['name'],
        'description': function['description'] ?? '',
        'input_schema': function['parameters'] ?? {
          'type': 'object',
          'properties': {},
        },
      });
    }
    return converted;
  }

  List<Map<String, dynamic>> _toAnthropicMessages(
    List<Map<String, dynamic>> messages,
  ) {
    final converted = <Map<String, dynamic>>[];
    for (final message in messages) {
      final role = message['role']?.toString();
      if (role == null || role.isEmpty) continue;

      if (role == 'tool') {
        final toolCallId = message['tool_call_id']?.toString();
        if (toolCallId == null || toolCallId.isEmpty) continue;
        converted.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': toolCallId,
              'content': message['content']?.toString() ?? '',
            }
          ],
        });
        continue;
      }

      final content = message['content']?.toString() ?? '';
      final toolCalls = message['tool_calls'];
      if (role == 'assistant' && toolCalls is List && toolCalls.isNotEmpty) {
        final blocks = <Map<String, dynamic>>[];
        if (content.isNotEmpty) {
          blocks.add({'type': 'text', 'text': content});
        }

        for (final rawCall in toolCalls) {
          if (rawCall is! Map) continue;
          final call = Map<String, dynamic>.from(rawCall);
          final function = call['function'];
          if (function is! Map) continue;

          final id = call['id']?.toString();
          final name = function['name']?.toString();
          if (id == null || id.isEmpty || name == null || name.isEmpty) {
            continue;
          }

          Map<String, dynamic> input = {};
          final rawArgs = function['arguments'];
          if (rawArgs is String && rawArgs.trim().isNotEmpty) {
            try {
              final parsed = jsonDecode(rawArgs);
              if (parsed is Map<String, dynamic>) {
                input = parsed;
              } else if (parsed is Map) {
                input = Map<String, dynamic>.from(parsed);
              }
            } catch (_) {}
          } else if (rawArgs is Map<String, dynamic>) {
            input = rawArgs;
          } else if (rawArgs is Map) {
            input = Map<String, dynamic>.from(rawArgs);
          }

          blocks.add({
            'type': 'tool_use',
            'id': id,
            'name': name,
            'input': input,
          });
        }

        converted.add({
          'role': 'assistant',
          'content': blocks,
        });
        continue;
      }

      converted.add({
        'role': role,
        'content': content,
      });
    }
    return converted;
  }

  List<Map<String, dynamic>> _toGeminiFunctionDeclarations(
    List<Map<String, dynamic>> tools,
  ) {
    final declarations = <Map<String, dynamic>>[];
    for (final tool in tools) {
      final function = tool['function'];
      if (function is! Map) continue;
      final name = function['name']?.toString();
      if (name == null || name.isEmpty) continue;
      declarations.add({
        'name': name,
        'description': function['description'] ?? '',
        'parameters': _toGeminiSchema(function['parameters'], isRoot: true),
      });
    }
    return declarations;
  }

  Map<String, dynamic> _toGeminiSchema(
    dynamic rawSchema, {
    bool isRoot = false,
    int depth = 0,
  }) {
    if (depth > 40) {
      return <String, dynamic>{};
    }

    if (rawSchema == null) {
      return <String, dynamic>{};
    }

    final source = rawSchema is Map
        ? Map<String, dynamic>.from(rawSchema)
        : <String, dynamic>{};
    final schema = <String, dynamic>{};

    final type = _toGeminiType(source['type']);
    if (type != null) {
      schema['type'] = type;
    }

    if (_typeIncludesNull(source['type']) || source['nullable'] == true) {
      schema['nullable'] = true;
    }

    for (final key in const ['title', 'description', 'format', 'pattern']) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        schema[key] = value;
      }
    }

    for (final key in const [
      'maxItems',
      'minItems',
      'minProperties',
      'maxProperties',
      'minLength',
      'maxLength',
    ]) {
      final value = source[key];
      if (value is int || value is String) {
        schema[key] = value;
      }
    }

    for (final key in const ['minimum', 'maximum']) {
      final value = source[key];
      if (value is num) {
        schema[key] = value;
      }
    }

    final enumValues = source['enum'];
    if (enumValues is List && enumValues.isNotEmpty) {
      final sanitizedEnum = enumValues.where((value) => value != null).toList();
      if (sanitizedEnum.isNotEmpty) {
        schema['enum'] = sanitizedEnum;
      }
    }

    if (source.containsKey('default')) {
      schema['default'] = source['default'];
    }
    if (source.containsKey('example')) {
      schema['example'] = source['example'];
    }

    final properties = <String, dynamic>{};
    final rawProperties = source['properties'];
    if (rawProperties is Map) {
      for (final entry in rawProperties.entries) {
        final key = entry.key.toString();
        if (key.isEmpty) continue;
        final propertySchema = _toGeminiSchema(entry.value, depth: depth + 1);
        if (propertySchema.isNotEmpty) {
          properties[key] = propertySchema;
        }
      }
    }
    if (properties.isNotEmpty) {
      schema['properties'] = properties;
    }

    final rawRequired = source['required'];
    if (rawRequired is List) {
      final allowedKeys = properties.keys.toSet();
      final required = rawRequired
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty && allowedKeys.contains(value))
          .toList();
      if (required.isNotEmpty) {
        schema['required'] = required;
      }
    }

    final rawAnyOf = source['anyOf'];
    if (rawAnyOf is List) {
      final anyOf = rawAnyOf
          .map((value) => _toGeminiSchema(value, depth: depth + 1))
          .where((value) => value.isNotEmpty)
          .toList();
      if (anyOf.isNotEmpty) {
        schema['anyOf'] = anyOf;
      }
    }

    final rawItems = source['items'];
    if (rawItems != null) {
      final items = _toGeminiSchema(rawItems, depth: depth + 1);
      if (items.isNotEmpty) {
        schema['items'] = items;
      }
    }

    final rawPropertyOrdering = source['propertyOrdering'];
    if (rawPropertyOrdering is List) {
      final ordering = rawPropertyOrdering
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList();
      if (ordering.isNotEmpty) {
        schema['propertyOrdering'] = ordering;
      }
    }

    if (!schema.containsKey('type')) {
      if (schema.containsKey('properties')) {
        schema['type'] = 'object';
      } else if (schema.containsKey('items')) {
        schema['type'] = 'array';
      }
    }

    if (isRoot) {
      schema['type'] = 'object';
      schema.putIfAbsent('properties', () => <String, dynamic>{});
    }

    return schema;
  }

  String? _toGeminiType(dynamic rawType) {
    if (rawType is List) {
      for (final value in rawType) {
        final normalized = _toGeminiType(value);
        if (normalized != null && normalized != 'null') {
          return normalized;
        }
      }
      return _toGeminiType(rawType.isNotEmpty ? rawType.first : null);
    }

    if (rawType is! String) return null;
    switch (rawType.toLowerCase()) {
      case 'object':
        return 'object';
      case 'array':
        return 'array';
      case 'string':
        return 'string';
      case 'integer':
      case 'int':
        return 'integer';
      case 'number':
        return 'number';
      case 'boolean':
      case 'bool':
        return 'boolean';
      case 'null':
        return 'null';
      default:
        return null;
    }
  }

  bool _typeIncludesNull(dynamic rawType) {
    if (rawType is List) {
      return rawType.any((value) => value.toString().toLowerCase() == 'null');
    }
    return rawType is String && rawType.toLowerCase() == 'null';
  }

  List<Map<String, dynamic>> _toGeminiContents(
    List<Map<String, dynamic>> messages,
  ) {
    final toolCallNameById = <String, String>{};
    for (final message in messages) {
      final toolCalls = message['tool_calls'];
      if (toolCalls is! List) continue;
      for (final rawCall in toolCalls) {
        if (rawCall is! Map) continue;
        final call = Map<String, dynamic>.from(rawCall);
        final function = call['function'];
        if (function is! Map) continue;
        final id = call['id']?.toString();
        final name = function['name']?.toString();
        if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
          toolCallNameById[id] = name;
        }
      }
    }

    final converted = <Map<String, dynamic>>[];
    for (final message in messages) {
      final role = message['role']?.toString();
      if (role == null || role.isEmpty) continue;

      if (role == 'tool') {
        final toolCallId = message['tool_call_id']?.toString();
        final functionName = toolCallNameById[toolCallId ?? ''];
        if (functionName == null || functionName.isEmpty) continue;

        dynamic parsedResult = message['content']?.toString() ?? '';
        if (parsedResult is String && parsedResult.trim().isNotEmpty) {
          try {
            parsedResult = jsonDecode(parsedResult);
          } catch (_) {
            parsedResult = {'content': parsedResult};
          }
        }

        converted.add({
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': functionName,
                if (toolCallId != null && toolCallId.isNotEmpty) 'id': toolCallId,
                'response': parsedResult is Map ? parsedResult : {'result': parsedResult},
              }
            }
          ],
        });
        continue;
      }

      final parts = <Map<String, dynamic>>[];
      final content = message['content']?.toString() ?? '';
      if (content.isNotEmpty) {
        parts.add({'text': content});
      }

      final toolCalls = message['tool_calls'];
      if (role == 'assistant' && toolCalls is List && toolCalls.isNotEmpty) {
        for (var callIndex = 0; callIndex < toolCalls.length; callIndex++) {
          final rawCall = toolCalls[callIndex];
          if (rawCall is! Map) continue;
          final call = Map<String, dynamic>.from(rawCall);
          final function = call['function'];
          if (function is! Map) continue;
          final name = function['name']?.toString();
          final id = call['id']?.toString();
          if (name == null || name.isEmpty) continue;

          Map<String, dynamic> args = {};
          final rawArgs = function['arguments'];
          if (rawArgs is String && rawArgs.trim().isNotEmpty) {
            try {
              final parsed = jsonDecode(rawArgs);
              if (parsed is Map<String, dynamic>) {
                args = parsed;
              } else if (parsed is Map) {
                args = Map<String, dynamic>.from(parsed);
              }
            } catch (_) {}
          } else if (rawArgs is Map<String, dynamic>) {
            args = rawArgs;
          } else if (rawArgs is Map) {
            args = Map<String, dynamic>.from(rawArgs);
          }

          final rawGeminiFunctionCall = call['_geminiFunctionCall'];
          final functionCallPayload = <String, dynamic>{};
          if (rawGeminiFunctionCall is Map) {
            functionCallPayload.addAll(Map<String, dynamic>.from(rawGeminiFunctionCall));
          }

          functionCallPayload['name'] = name;
          if (id != null && id.isNotEmpty) {
            functionCallPayload['id'] = id;
          }
          functionCallPayload['args'] = args;

          final rawGeminiPart = call['_geminiPart'];
          final partPayload = <String, dynamic>{};
          if (rawGeminiPart is Map) {
            partPayload.addAll(Map<String, dynamic>.from(rawGeminiPart));
          }

          if (callIndex == 0 &&
              !partPayload.containsKey('thoughtSignature') &&
              !partPayload.containsKey('thought_signature')) {
            partPayload['thought_signature'] = 'skip_thought_signature_validator';
          }

          partPayload['functionCall'] = functionCallPayload;

          parts.add({
            ...partPayload,
          });
        }
      }

      if (parts.isEmpty) continue;

      converted.add({
        'role': role == 'assistant' ? 'model' : 'user',
        'parts': parts,
      });
    }

    return converted;
  }

  List<Map<String, dynamic>> buildToolResultMessages(
    List<Map<String, dynamic>> toolCalls,
    List<String> toolResults,
  ) {
    final resultMessages = <Map<String, dynamic>>[];
    for (var i = 0; i < toolCalls.length; i++) {
      final call = toolCalls[i];
      final toolCallId = call['id']?.toString();
      if (toolCallId == null || toolCallId.isEmpty) {
        continue;
      }
      resultMessages.add({
        'role': 'tool',
        'tool_call_id': toolCallId,
        'content': i < toolResults.length ? toolResults[i] : '',
      });
    }
    return resultMessages;
  }

  Future<String> completionResponse(String code) async {
    final uri = Uri.parse(url);
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(buildRequest(code)),
    );
    if (response.statusCode == 200) {
      return _cleanCode(responseParser(jsonDecode(response.body)));
    }
    throw Exception(
      "Failed to load AI suggestion \nStatus code: ${response.statusCode}\n error: ${response.body}",
    );
  }

  @protected
  String _cleanCode(String raw) {
    final codeBlockRegex = RegExp(r'```(?:\w+)?\n([\s\S]*?)\n```');
    final thinkRegex = RegExp(r'<think>[\s\S]*?<\/think>');
    raw = raw.replaceAll(thinkRegex, '').trim();
    final match = codeBlockRegex.firstMatch(raw);
    if (match != null) return match.group(1)!.trim();

    return raw.trim();
  }
}

sealed class OpenAiCompatible extends Models {
  @override
  ToolCallingMethod get toolCallingMethod => ToolCallingMethod.openAiCompatible;

  @protected
  String get baseUrl;
  @override
  String get url => "$baseUrl/chat/completions";

  @override
  Map<String, String> get headers => {
    "Content-Type": "application/json; charset=utf-8",
    "Authorization": "Bearer $apiKey",
  };

  @override
  Map<String, dynamic> buildRequest(String code) {
    return {
      "model": model,
      "messages": [
        {"role": "system", "content": Models.instruction},
        {"role": "user", "content": code},
      ],
    };
  }

  @override
  String responseParser(dynamic response) {
    try {
      return response["choices"][0]["message"]["content"];
    } catch (e) {
      throw FormatException(
        "Failed to parse AI response: $e \nResponse: $response",
      );
    }
  }
}

class Gemini extends Models {
  @override
  ToolCallingMethod get toolCallingMethod => ToolCallingMethod.geminiFunctionCalling;

  @override
  final String url, apiKey, model;
  @override
  Map<String, String> get headers => {'Content-Type': 'application/json; charset=utf-8'};
  int? temperature, maxOutputTokens, topP, topK, stopSequences;

  Gemini({
    required this.apiKey,
    this.model = 'gemini-2.5-flash-lite',
    this.temperature,
    this.maxOutputTokens,
    this.topP,
    this.topK,
    this.stopSequences,
  }) : url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';

  @override
  String responseParser(dynamic response) {
    try {
      if (response == null) return "";
      return response["candidates"]?[0]?["content"]?["parts"]?[0]?["text"] ??
          "AI completion is not available";
    } catch (e) {
      throw FormatException(
        "Failed to parse AI response: $e \nResponse: $response",
      );
    }
  }

  @override
  Map<String, dynamic> buildRequest(String code) {
    return {
      "systemInstruction": {
        "parts": [
          {"text": Models.instruction},
        ],
      },
      "contents": [
        {
          "parts": [
            {"text": code},
          ],
        },
      ],
      "generationConfig": {
        "stopSequences": ["Title"],
        "temperature": temperature ?? 1.0,
        "maxOutputTokens": maxOutputTokens ?? 800,
        "topP": topP ?? 0.8,
        "topK": topK ?? 10,
      },
    };
  }
}

class OpenAI extends Models {
  @override
  ToolCallingMethod get toolCallingMethod => ToolCallingMethod.openAiCompatible;

  @override
  final String url = 'https://api.openai.com/v1/responses', apiKey, model;

  @override
  String get chatUrl => 'https://api.openai.com/v1/chat/completions';

  OpenAI({required this.apiKey, required this.model});

  @override
  String responseParser(dynamic response) {
    try {
      return response[0]["content"][0]["text"];
    } catch (e) {
      throw FormatException(
        "Failed to parse AI response: $e \nResponse: $response",
      );
    }
  }

  @override
  Map<String, String> get headers => {
    'Content-Type': 'application/json; charset=utf-8',
    'Authorization': 'Bearer $apiKey',
  };

  @override
  Map<String, dynamic> buildRequest(String code) {
    return {"model": model, "instructions": Models.instruction, "input": code};
  }
}

class Claude extends Models {
  @override
  ToolCallingMethod get toolCallingMethod => ToolCallingMethod.anthropicMessages;

  @override
  final String url = 'https://api.anthropic.com/v1/messages', apiKey, model;

  Claude({required this.apiKey, required this.model});

  @override
  String responseParser(dynamic response) {
    try {
      return response["content"][0]["text"];
    } catch (e) {
      throw FormatException(
        "Failed to parse AI response: $e \nResponse: $response",
      );
    }
  }

  @override
  Map<String, String> get headers => {
    'Content-Type': 'application/json; charset=utf-8',
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
  };

  @override
  Map<String, dynamic> buildRequest(String code) {
    return {
      "model": model,
      "max_tokens": 1024,
      "system": Models.instruction,
      "messages": [
        {"role": "user", "content": code},
      ],
    };
  }
}

class Grok extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.x.ai/v1";
  @override
  final String apiKey, model;
  Grok({required this.apiKey, required this.model});
}

class DeepSeek extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.deepseek.com";
  @override
  final String apiKey, model;
  DeepSeek({required this.apiKey, required this.model});
}

class TogetherAi extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.together.xyz/v1";
  @override
  final String apiKey, model;
  TogetherAi({required this.apiKey, required this.model});
}

class Perplexity extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.perplexity.ai";
  @override
  final String apiKey, model;
  Perplexity({required this.apiKey, required this.model});
}

class OpenRouter extends OpenAiCompatible {
  @override
  String get baseUrl => "https://openrouter.ai/api/v1";
  @override
  final String apiKey, model;
  OpenRouter({required this.apiKey, required this.model});
}

class FireWorks extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.fireworks.ai/inference/v1";
  @override
  final String apiKey, model;
  FireWorks({required this.apiKey, required this.model});
}

class CustomModel extends Models {
  @override
  final ToolCallingMethod toolCallingMethod;

  @override
  final String url;
  @override
  String? get apiKey => null;
  @override
  final String? model;
  final String httpMethod;
  final Map<String, String> customHeaders;
  final Map<String, dynamic> Function(String code, String instruction)?
  requestBuilder;
  final String Function(dynamic response) customParser;

  CustomModel({
    required this.url,
    required this.customHeaders,
    required this.requestBuilder,
    required this.customParser,
    this.httpMethod = 'POST',
    this.toolCallingMethod = ToolCallingMethod.openAiCompatible,
    this.model,
  });

  @override
  String responseParser(dynamic response) {
    try {
      return customParser(response);
    } catch (e) {
      throw FormatException(
        "Failed to parse AI response: $e \nResponse: $response",
      );
    }
  }

  @override
  Map<String, String> get headers {
    final headers = {'Content-Type': 'application/json; charset=utf-8', ...customHeaders};

    return headers;
  }

  @override
  Map<String, dynamic> buildRequest(String code) {
    if (requestBuilder != null) {
      return requestBuilder!(code, Models.instruction);
    }
    return {
      if (model != null) 'model': model,
      'code': code,
      'parameters': {'instruction': Models.instruction, 'temperature': 0.2},
    };
  }

  @override
  Future<String> completionResponse(String code) async {
    try {
      final uri = Uri.parse(url);
      final response = httpMethod.toUpperCase() == 'GET'
        ? await http.get(uri, headers: headers)
        : await http.post(uri, headers: headers, body: jsonEncode(buildRequest(code)));

      if (response.statusCode == 200) {
        return responseParser(jsonDecode(response.body));
      } else {
        throw Exception('Request failed with status ${response.statusCode}\n ${response.body}\n$uri');
      }
    } catch (e) {
      throw Exception('Failed to complete request: $e');
    }
  }
}

class LocalLlama extends Models {
  final String modelPath, displayName;
  final int threads;
  final int topK, repeatLastN, seed, maxTokens, mirostat, contextSize, gpuLayers;
  final double temperature, topP, repeatPenalty, frequencyPenalty, presencePenalty, mirostatTau, mirostatEta;

  LocalLlama({
    required this.modelPath,
    required this.displayName,
    required this.threads,
    required this.contextSize,
    required this.gpuLayers,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.repeatPenalty = 1.1,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.repeatLastN = 64,
    this.seed = 42,
    this.maxTokens = 512,
    this.mirostat = 0,
    this.mirostatTau = 5.0,
    this.mirostatEta = 0.1,
  });

  @override String? get apiKey => null;
  @override Map<String, dynamic> buildRequest(String code) => {};
  @override Map<String, String> get headers => const {};
  @override String? get model => null;
  @override String responseParser(dynamic response) => response?.toString() ?? '';
  @override String get url => '';
  @override ToolCallingMethod get toolCallingMethod => ToolCallingMethod.openAiCompatible;
}

enum CompletionType {
  auto,
  manual,
  mixed,
}

// const Map<String, LocalLlamaPreset> modelPresets = {
//   'Qwen2.5-Coder-3B': LocalLlamaPreset(
//     temperature: 0.6,
//     topP: 0.9,
//     topK: 50,
//     repeatPenalty: 1.1,
//     frequencyPenalty: 0.2,
//     presencePenalty: 0.1,
//     maxTokens: 2048,
//     mirostat: 0,
//   ),
//   'Phi-3.5-mini': LocalLlamaPreset(
//     temperature: 0.7,
//     topP: 0.95,
//     topK: 40,
//     repeatPenalty: 1.05,
//     frequencyPenalty: 0.1,
//     presencePenalty: 0.1,
//     maxTokens: 4096,
//     mirostat: 1,
//     mirostatTau: 5.0,
//     mirostatEta: 0.1,
//   ),
//   'Phi-3-mini-4k': LocalLlamaPreset(
//     temperature: 0.7,
//     topP: 0.95,
//     topK: 40,
//     repeatPenalty: 1.05,
//     frequencyPenalty: 0.1,
//     presencePenalty: 0.1,
//     maxTokens: 4096,
//     mirostat: 1,
//     mirostatTau: 5.0,
//     mirostatEta: 0.1,
//   ),
//   'Qwen2.5.1-Coder-1.5B': LocalLlamaPreset(
//     temperature: 0.5,
//     topP: 0.85,
//     topK: 40,
//     repeatPenalty: 1.1,
//     maxTokens: 1024,
//   ),
//   'deepseek-coder-1.3B': LocalLlamaPreset(
//     temperature: 0.4,
//     topP: 0.9,
//     topK: 30,
//     repeatPenalty: 1.15,
//     frequencyPenalty: 0.15,
//     presencePenalty: 0.1,
//     maxTokens: 1024,
//   ),
//   'Granite-Code-3B': LocalLlamaPreset(
//     temperature: 0.6,
//     topP: 0.9,
//     topK: 50,
//     repeatPenalty: 1.1,
//     maxTokens: 2048,
//   ),
//   'Gemma-2-2B': LocalLlamaPreset(
//     temperature: 0.7,
//     topP: 0.9,
//     topK: 40,
//     repeatPenalty: 1.0,
//     frequencyPenalty: 0.1,
//     maxTokens: 2048,
//   ),
//   'CodeLlama-7B': LocalLlamaPreset(
//     temperature: 0.2,
//     topP: 0.9,
//     topK: 40,
//     repeatPenalty: 1.1,
//     maxTokens: 512,
//   ),
// };

// class LocalLlamaPreset {
//   final double temperature;
//   final double topP;
//   final int topK;
//   final double repeatPenalty;
//   final double frequencyPenalty;
//   final double presencePenalty;
//   final int repeatLastN;
//   final int seed;
//   final int maxTokens;
//   final int mirostat;
//   final double mirostatTau;
//   final double mirostatEta;

//   const LocalLlamaPreset({
//     this.temperature = 0.7,
//     this.topP = 0.9,
//     this.topK = 40,
//     this.repeatPenalty = 1.1,
//     this.frequencyPenalty = 0.0,
//     this.presencePenalty = 0.0,
//     this.repeatLastN = 64,
//     this.seed = 42,
//     this.maxTokens = 512,
//     this.mirostat = 0,
//     this.mirostatTau = 5.0,
//     this.mirostatEta = 0.1,
//   });
// }