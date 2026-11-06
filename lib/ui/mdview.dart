import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as m;
import 'package:zikzak_inappwebview/zikzak_inappwebview.dart';
import '../utils/themes.dart';

class MdView extends StatelessWidget {
  final String data;
  final AppTheme appTheme;
  
  const MdView({
    super.key,
    required this.data,
    required this.appTheme,
  });

  @override
  Widget build(BuildContext context) {
    final parsedData = m.markdownToHtml(
      data,
      extensionSet: m.ExtensionSet.gitHubWeb
    );
    return SafeArea(
      child: Scaffold(
        body: InAppWebView(
          onLoadStart: (controller, url) async{
            final bgColor = appTheme.scaffoldBg.toARGB32().toRadixString(16).substring(2);
            final fgColor = appTheme.selectScreenCardTextColor.toARGB32().toRadixString(16).substring(2);
            await controller.evaluateJavascript(
              source:
              '''
                document.body.style.backgroundColor = "#$bgColor";
                document.body.style.color = "#$fgColor";
              '''
            );
          },
          initialData: InAppWebViewInitialData(
            data: parsedData,
            mimeType: 'text/html',
            encoding: 'utf-8',
          ),
        ),
      ),
    );
  }
}
