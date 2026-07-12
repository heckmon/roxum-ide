import 'package:flutter/material.dart';
import 'package:html/dom.dart' as h;
import 'package:html/dom_parsing.dart';
import 'package:html/parser.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../utils/functions.dart';
import '../utils/themes.dart';

class MdView extends StatelessWidget {
  final String data;
  final AppTheme appTheme;
  final ConfigState theme;
  const MdView({
    super.key,
    required this.data,
    required this.appTheme,
    required this.theme
  });

  @override
  Widget build(BuildContext context) {
    final isDark = appTheme.isDark;
    final config = isDark ? MarkdownConfig.darkConfig : MarkdownConfig.defaultConfig;
    final editorTheme = getMergedHighlightThemes(theme.codeForgeConfig)[theme.codeForgeConfig['theme']];
    return SafeArea(
      child: Scaffold(
        body: MarkdownWidget(
          data: data,
          config: config.copy(configs: [
            PreConfig(
              theme: editorTheme ?? atomOneDarkTheme,
              styleNotMatched: TextStyle(color:editorTheme!['root']!.color),
              decoration: BoxDecoration(
                color: editorTheme['root']!.backgroundColor!,
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  width: 0.2,
                  color: editorTheme['root']!.color ?? Colors.grey,
                ),
              )
            ),
            PConfig(
              textStyle: TextStyle(fontSize: 16, color: appTheme.selectScreenCardTextColor),
            ),
          ]),
          markdownGenerator: MarkdownGenerator(
            textGenerator: (node, config, visitor) =>
                CustomTextNode(node.textContent, config, visitor),
          ),
        ),
      ),
    );
  }
}


final RegExp htmlRep = RegExp(r'<[^>]*>', multiLine: true, caseSensitive: true);


class CustomTextNode extends ElementNode {
  final String text;
  final MarkdownConfig config;
  final WidgetVisitor visitor;

  CustomTextNode(this.text, this.config, this.visitor);

  @override
  void onAccepted(SpanNode parent) {
    final textStyle = config.p.textStyle.merge(parentStyle);
    children.clear();
    if (!text.contains(htmlRep)) {
      accept(TextNode(text: text, style: textStyle));
      return;
    }
    final spans = parseHtml(
      m.Text(text),
      visitor: WidgetVisitor(
        config: visitor.config,
        generators: visitor.generators,
        richTextBuilder: visitor.richTextBuilder,
      ),
      parentStyle: parentStyle,
    );
    for (var element in spans) {
      accept(element);
    }
  }
}


List<SpanNode> parseHtml(
  m.Text node, {
  ValueCallback<dynamic>? onError,
  WidgetVisitor? visitor,
  TextStyle? parentStyle,
}) {
  try {
    final text = node.textContent.replaceAll(
        visitor?.splitRegExp ?? WidgetVisitor.defaultSplitRegExp, '');
    if (!text.contains(htmlRep)) return [TextNode(text: node.text)];
    h.DocumentFragment document = parseFragment(text);
    return HtmlToSpanVisitor(visitor: visitor, parentStyle: parentStyle)
        .toVisit(document.nodes.toList());
  } catch (e) {
    onError?.call(e);
    return [TextNode(text: node.text)];
  }
}

class HtmlElement extends m.Element {
  @override
  final String textContent;

  HtmlElement(super.tag, super.children, this.textContent);
}

class HtmlToSpanVisitor extends TreeVisitor {
  final List<SpanNode> _spans = [];
  final List<SpanNode> _spansStack = [];
  final WidgetVisitor visitor;
  final TextStyle parentStyle;

  HtmlToSpanVisitor({WidgetVisitor? visitor, TextStyle? parentStyle})
      : visitor = visitor ?? WidgetVisitor(),
        parentStyle = parentStyle ?? const TextStyle();

  List<SpanNode> toVisit(List<h.Node> nodes) {
    _spans.clear();
    for (final node in nodes) {
      final emptyNode = ConcreteElementNode(style: parentStyle);
      _spans.add(emptyNode);
      _spansStack.add(emptyNode);
      visit(node);
      _spansStack.removeLast();
    }
    final result = List.of(_spans);
    _spans.clear();
    _spansStack.clear();
    return result;
  }

  @override
  void visitText(h.Text node) {
    final last = _spansStack.last;
    if (last is ElementNode) {
      final textNode = TextNode(text: node.text);
      last.accept(textNode);
    }
  }

  @override
  void visitElement(h.Element node) {
    final localName = node.localName ?? '';
    final mdElement = m.Element(localName, []);
    mdElement.attributes.addAll(node.attributes.cast());
    SpanNode spanNode = visitor.getNodeByElement(mdElement, visitor.config);
    if (spanNode is! ElementNode) {
      final n = ConcreteElementNode(tag: localName, style: parentStyle);
      n.accept(spanNode);
      spanNode = n;
    }
    final last = _spansStack.last;
    if (last is ElementNode) {
      last.accept(spanNode);
    }
    _spansStack.add(spanNode);
    for (var child in node.nodes.toList(growable: false)) {
      visit(child);
    }
    _spansStack.removeLast();
  }
}