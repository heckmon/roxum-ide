import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:zikzak_inappwebview/zikzak_inappwebview.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';
import '../utils/themes.dart';

final _highlight = Highlight();
const _htmlEscape = HtmlEscape();

class MdView extends StatefulWidget {
  final String data;
  final AppTheme appTheme;

  const MdView({
    super.key,
    required this.data,
    required this.appTheme,
  });

  @override
  State<MdView> createState() => _MdViewState();
}

class _MdViewState extends State<MdView> {
  late String _html;

  @override
  void initState() {
    super.initState();
    _html = _buildHtml();
  }

  @override
  void didUpdateWidget(covariant MdView old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data || old.appTheme != widget.appTheme) {
      setState(() => _html = _buildHtml());
    }
  }

  String _buildHtml() {
    final config = context.read<ConfigBloc>().state.codeForgeConfig;
    final editorTheme = getMergedHighlightThemes(config)[config['theme']] ??
        atomOneDarkTheme;
    final highlighter = _CodeHighlighter(editorTheme);

    var body = m.markdownToHtml(
      widget.data,
      extensionSet: m.ExtensionSet.gitHubWeb,
    );
    body = _highlightCodeBlocks(body, highlighter);

    final bg = widget.appTheme.scaffoldBg;
    final fg = widget.appTheme.selectScreenCardTextColor;
    final rootStyle = editorTheme['root'];
    final codeBg = rootStyle?.backgroundColor ?? const Color(0xFF282C34);
    final codeFg = rootStyle?.color ?? const Color(0xFFABB2BF);
    final dark = bg.computeLuminance() < 0.5;

    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: ${dark ? 'dark' : 'light'}; }
  body {
    margin: 0; padding: 16px;
    background: ${_css(bg)}; color: ${_css(fg)};
    font-family: -apple-system, Roboto, "Segoe UI", sans-serif;
    line-height: 1.6; word-wrap: break-word;
  }
  a { color: ${dark ? '#58a6ff' : '#0969da'}; }
  img { max-width: 100%; }
  pre {
    background: ${_css(codeBg)}; color: ${_css(codeFg)};
    padding: 12px; border-radius: 8px; overflow-x: auto;
  }
  pre code { font-family: monospace; font-size: 13px; line-height: 1.4; background: none; padding: 0; }
  :not(pre) > code {
    font-family: monospace; font-size: 0.9em;
    background: rgba(127,127,127,.2); padding: 2px 5px; border-radius: 4px;
  }
  table { border-collapse: collapse; display: block; overflow-x: auto; }
  th, td { border: 1px solid rgba(127,127,127,.4); padding: 6px 10px; }
  blockquote { border-left: 4px solid rgba(127,127,127,.5); margin: 0; padding-left: 12px; opacity: .85; }
  hr { border: 0; border-top: 1px solid rgba(127,127,127,.4); }
</style>
</head>
<body>
$body
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: widget.appTheme.scaffoldBg,
        body: InAppWebView(
          initialData: InAppWebViewInitialData(
            data: _html,
            mimeType: 'text/html',
            encoding: 'utf-8',
          ),
        ),
      ),
    );
  }
}

final _preCodeRe = RegExp(
  r'<pre><code class="language-([^"]+)">([\s\S]*?)</code></pre>',
);

String _css(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String _unescapeCode(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

String _highlightCodeBlocks(String html, _CodeHighlighter highlighter) {
  return html.replaceAllMapped(_preCodeRe, (match) {
    final lang = match.group(1)!;
    final code = _unescapeCode(match.group(2)!);
    try {
      final span = highlighter.highlight(code, lang);
      if (span == null) return match.group(0)!;
      final b = StringBuffer();
      _spanToHtml(span, b);
      return '<pre><code>${b.toString()}</code></pre>';
    } catch (_) {
      return match.group(0)!;
    }
  });
}

void _spanToHtml(TextSpan s, StringBuffer b) {
  final st = s.style;
  final css = <String>[];
  if (st?.color != null) css.add('color:${_css(st!.color!)}');
  if (st?.fontWeight != null && st!.fontWeight!.value >= 600) {
    css.add('font-weight:bold');
  }
  if (st?.fontStyle == FontStyle.italic) css.add('font-style:italic');

  if (css.isNotEmpty) b.write('<span style="${css.join(';')}">');
  if (s.text != null) b.write(_htmlEscape.convert(s.text!));
  for (final c in s.children ?? const <InlineSpan>[]) {
    if (c is TextSpan) _spanToHtml(c, b);
  }
  if (css.isNotEmpty) b.write('</span>');
}

class _CodeHighlighter {
  final Map<String, TextStyle> theme;
  _CodeHighlighter(this.theme);

  static const _aliases = <String, String>{
    'js': 'javascript',
    'ts': 'typescript',
    'py': 'python',
    'sh': 'bash',
    'shell': 'bash',
    'yml': 'yaml',
    'rs': 'rust',
    'kt': 'kotlin',
    'c++': 'cpp',
    'md': 'markdown',
  };

  final _registered = <String>{};

  TextSpan? highlight(String code, String language) {
    final lower = language.trim().toLowerCase();
    final key = _aliases[lower] ?? lower;
    final entry =
        languages.where((l) => l.name.toLowerCase() == key).firstOrNull;
    final mode = entry?.language;
    if (mode == null) return null;

    if (_registered.add(key)) _highlight.registerLanguage(key, mode);
    final result = _highlight.highlight(code: code, language: key);
    final renderer = TextSpanRenderer(null, theme);
    result.render(renderer);
    return renderer.span;
  }
}