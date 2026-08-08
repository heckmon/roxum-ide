import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:roxum/utils/constants.dart';

final txt = Mode();
final unknown = Mode();

const String _cursorMarker = '__CURSOR__';

CustomCodeSnippet _snippet(String label, String template) {
  var value = template;
  final cursorLocations = <int>{};

  while (true) {
    final markerIndex = value.indexOf(_cursorMarker);
    if (markerIndex == -1) break;
    cursorLocations.add(markerIndex);
    value = value.replaceFirst(_cursorMarker, '');
  }

  if (cursorLocations.isEmpty) {
    cursorLocations.add(value.length);
  }

  return CustomCodeSnippet(
    label: label,
    value: value,
    cursorLocations: cursorLocations,
  );
}

bool _hasAnyExt(Set<String> exts, List<String> targets) {
  for (final target in targets) {
    if (exts.contains(target)) return true;
  }
  return false;
}

List<CustomCodeSnippet> _defaultSnippetsForExtensions(List<String> extensions) {
  final exts = extensions.map((e) => e.toLowerCase()).toSet();

  if (_hasAnyExt(exts, ['py', 'pyi'])) {
    return [
      _snippet('if', 'if condition:\n    __CURSOR__'),
      _snippet('if-else', 'if condition:\n    __CURSOR__\nelse:\n    __CURSOR__'),
      _snippet('while', 'while condition:\n    __CURSOR__'),
      _snippet('for', 'for item in items:\n    __CURSOR__'),
      _snippet('def', 'def function_name(params):\n    __CURSOR__'),
      _snippet('class', 'class ClassName:\n    def __init__(self):\n        __CURSOR__'),
    ];
  }

  if (_hasAnyExt(exts, ['js', 'jsx', 'mjs', 'cjs', 'ts', 'tsx'])) {
    return [
      _snippet('if', 'if (condition) {\n  __CURSOR__\n}'),
      _snippet('if-else', 'if (condition) {\n  __CURSOR__\n} else {\n  __CURSOR__\n}'),
      _snippet('while', 'while (condition) {\n  __CURSOR__\n}'),
      _snippet('for-of', 'for (const item of items) {\n  __CURSOR__\n}'),
      _snippet('function', 'function name(params) {\n  __CURSOR__\n}'),
      _snippet('try-catch', 'try {\n  __CURSOR__\n} catch (error) {\n  console.error(error);\n}'),
    ];
  }

  if (_hasAnyExt(exts, ['java', 'kt', 'kts', 'cs', 'swift', 'scala', 'groovy'])) {
    return [
      _snippet('if', 'if (condition) {\n  __CURSOR__\n}'),
      _snippet('if-else', 'if (condition) {\n  __CURSOR__\n} else {\n  __CURSOR__\n}'),
      _snippet('while', 'while (condition) {\n  __CURSOR__\n}'),
      _snippet('for', 'for (int i = 0; i < items.length; i++) {\n  __CURSOR__\n}'),
      _snippet('class', 'class ClassName {\n  __CURSOR__\n}'),
      _snippet('method', 'void methodName() {\n  __CURSOR__\n}'),
    ];
  }

  if (_hasAnyExt(exts, ['c', 'cpp', 'c++', 'cc', 'm', 'mm', 'rs', 'go', 'd'])) {
    return [
      _snippet('if', 'if (condition) {\n  __CURSOR__\n}'),
      _snippet('if-else', 'if (condition) {\n  __CURSOR__\n} else {\n  __CURSOR__\n}'),
      _snippet('for', 'for (int i = 0; i < count; i++) {\n  __CURSOR__\n}'),
      _snippet('while', 'while (condition) {\n  __CURSOR__\n}'),
      _snippet('function', 'void function_name() {\n  __CURSOR__\n}'),
    ];
  }

  if (_hasAnyExt(exts, ['sh', 'bash', 'zsh'])) {
    return [
      _snippet('if', 'if [[ condition ]]; then\n  __CURSOR__\nfi'),
      _snippet('if-else', 'if [[ condition ]]; then\n  __CURSOR__\nelse\n  __CURSOR__\nfi'),
      _snippet('while', 'while [[ condition ]]; do\n  __CURSOR__\ndone'),
      _snippet('for', 'for item in "\${1:-items}"; do\n  __CURSOR__\ndone'),
      _snippet('function', 'function name() {\n  __CURSOR__\n}'),
      _snippet('case', 'case "\$1" in\n  value)\n    __CURSOR__\n    ;;\n  *)\n    ;;\nesac'),
    ];
  }

  if (_hasAnyExt(exts, ['html', 'htm', 'xml'])) {
    return [
      _snippet('tag', '<tag>__CURSOR__</tag>'),
      _snippet('html5', '<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="UTF-8" />\n  <meta name="viewport" content="width=device-width, initial-scale=1.0" />\n  <title>__CURSOR__</title>\n</head>\n<body>\n  __CURSOR__\n</body>\n</html>'),
      _snippet('div', '<div class="container">\n  __CURSOR__\n</div>'),
      _snippet('a', '<a href="__CURSOR__">link</a>'),
      _snippet('img', '<img src="__CURSOR__" alt="" />'),
    ];
  }

  if (_hasAnyExt(exts, ['css', 'scss', 'less'])) {
    return [
      _snippet('rule', '.selector {\n  __CURSOR__\n}'),
      _snippet('media', '@media (max-width: 768px) {\n  __CURSOR__\n}'),
      _snippet('flex-center', 'display: flex;\njustify-content: center;\nalign-items: center;\n__CURSOR__'),
      _snippet('variable', '--name: __CURSOR__;'),
      _snippet('keyframes', '@keyframes fade-in {\n  from { opacity: 0; }\n  to { opacity: 1; }\n}\n__CURSOR__'),
    ];
  }

  if (_hasAnyExt(exts, ['json'])) {
    return [
      _snippet('object', '{\n  "key": "__CURSOR__"\n}'),
      _snippet('array', '[\n  "__CURSOR__"\n]'),
      _snippet('kv', '"key": "__CURSOR__"'),
      _snippet('nested', '{\n  "name": "",\n  "meta": {\n    "__CURSOR__": ""\n  }\n}'),
      _snippet('config', '{\n  "enabled": true,\n  "timeout": 30,\n  "__CURSOR__": ""\n}'),
    ];
  }

  if (_hasAnyExt(exts, ['yaml', 'yml'])) {
    return [
      _snippet('key-value', 'key: __CURSOR__'),
      _snippet('list', 'items:\n  - __CURSOR__'),
      _snippet('nested', 'parent:\n  child: __CURSOR__'),
      _snippet('map', 'name: app\nversion: 1.0.0\n__CURSOR__: value'),
      _snippet('env', 'env:\n  KEY: __CURSOR__'),
    ];
  }

  if (_hasAnyExt(exts, ['md'])) {
    return [
      _snippet('h1', '# __CURSOR__'),
      _snippet('link', '[text](__CURSOR__)'),
      _snippet('code-block', '```\n__CURSOR__\n```'),
      _snippet('table', '| Column | Value |\n| --- | --- |\n| __CURSOR__ |  |'),
      _snippet('task-list', '- [ ] __CURSOR__'),
    ];
  }

  if (_hasAnyExt(exts, ['sql'])) {
    return [
      _snippet('select', 'SELECT __CURSOR__\nFROM table_name\nWHERE condition;'),
      _snippet('insert', 'INSERT INTO table_name (column1, column2)\nVALUES (__CURSOR__, value2);'),
      _snippet('update', 'UPDATE table_name\nSET column1 = __CURSOR__\nWHERE condition;'),
      _snippet('delete', 'DELETE FROM table_name\nWHERE __CURSOR__;'),
      _snippet('create-table', 'CREATE TABLE table_name (\n  id INTEGER PRIMARY KEY,\n  __CURSOR__ TEXT\n);'),
    ];
  }

  if (_hasAnyExt(exts, ['php', 'rb', 'lua', 'r', 'pl', 'jl', 'erl', 'ex', 'exs', 'fs', 'fsx', 'clj', 'cljs', 'hs'])) {
    return [
      _snippet('if', 'if (condition) {\n  __CURSOR__\n}'),
      _snippet('if-else', 'if (condition) {\n  __CURSOR__\n} else {\n  __CURSOR__\n}'),
      _snippet('while', 'while (condition) {\n  __CURSOR__\n}'),
      _snippet('function', 'function name(args) {\n  __CURSOR__\n}'),
      _snippet('loop', 'for (item in items) {\n  __CURSOR__\n}'),
      _snippet('log', 'print(__CURSOR__)'),
    ];
  }

  if (_hasAnyExt(exts, ['asm', 's'])) {
    return [
      _snippet('label', 'label:\n  __CURSOR__'),
      _snippet('function', '.global _start\n_start:\n  __CURSOR__'),
      _snippet('data', '.section .data\nmsg: .asciz "__CURSOR__"'),
      _snippet('text', '.section .text\n.global _start\n_start:\n  __CURSOR__'),
      _snippet('syscall', 'mov r7, #1\nmov r0, #0\nsvc #0\n__CURSOR__'),
    ];
  }

  return [
    _snippet('if', 'if (condition) {\n  __CURSOR__\n}'),
    _snippet('if-else', 'if (condition) {\n  __CURSOR__\n} else {\n  __CURSOR__\n}'),
    _snippet('while', 'while (condition) {\n  __CURSOR__\n}'),
    _snippet('loop', 'for (item in items) {\n  __CURSOR__\n}'),
    _snippet('function', 'function name() {\n  __CURSOR__\n}'),
    _snippet('comment', '// __CURSOR__'),
  ];
}

class Language {
  final String name, details, helloWorld;
  final List<String> extension;
  final Mode? language;
  final dynamic icon;
  final String? command, type, lspExecutable;
  final List<String>? args;
  final List<CustomCodeSnippet>? customCodeSnippet;
  Language({
    required this.name,
    required this.extension,
    required this.details,
    required this.language,
    required this.helloWorld,
    required this.icon,
    this.command,
    this.type,
    this.lspExecutable,
    this.args,
    List<CustomCodeSnippet>? customCodeSnippet,
  }) : customCodeSnippet = customCodeSnippet ?? _defaultSnippetsForExtensions(extension);
}

class RunTime with IconBuilder{
  @override
  final String name;
  final String details, url, archiveName, parentName;
  final int archiveSize;
  final String? version;
  final String iconUrl;

  RunTime({
    required this.name,
    required this.details,
    required this.archiveName,
    required this.parentName,
    required this.archiveSize,
    required this.url,
    required this.iconUrl,
    this.version
  });

  factory RunTime.fromJson(Map<String, dynamic> json) {
    return RunTime(
      name: json['name']?.toString() ?? '',
      details: json['details']?.toString() ?? '',
      archiveName: json['archiveName']?.toString() ?? '',
      parentName: json['parentName']?.toString() ?? '',
      archiveSize: (json['archiveSize'] as num?)?.toInt() ?? 0,
      url: json['url']?.toString() ?? '',
      iconUrl: (json['icon-url'] ?? json['iconUrl'] ?? '').toString(),
      version: json['version']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'details': details,
    'version': version,
    'url': url,
    'archiveName': archiveName,
    'archiveSize': archiveSize,
    'parentName': parentName,
    'icon-url': iconUrl,
  };

  Widget get icon => buildPackageIcon(iconUrl, 35);
}

class Extension with IconBuilder{
  @override
  final String name;
  final String details, url, archiveName, parentName, githubUrl;
  final List<String> fileExtension, serverFile;
  final double archiveSize, iconSize;
  final String iconUrl;

  Extension({
    required this.name,
    required this.details,
    required this.archiveName,
    required this.parentName,
    required this.archiveSize,
    required this.url,
    required this.githubUrl,
    required this.iconUrl,
    required this.fileExtension,
    required this.serverFile,
    this.iconSize = 35
  });

  factory Extension.fromJson(Map<String, dynamic> json) {
    return Extension(
      name: json['name']?.toString() ?? '',
      details: json['details']?.toString() ?? '',
      archiveName: json['archiveName']?.toString() ?? '',
      parentName: json['parentName']?.toString() ?? '',
      archiveSize: (json['archiveSize'] as num?)?.toDouble() ?? 0,
      url: json['url']?.toString() ?? '',
      iconUrl: (json['icon-url'] ?? json['iconUrl'] ?? '').toString(),
      fileExtension: (json['fileExtension'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
      serverFile: (json['serverFile'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
      githubUrl: 'github-url'
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'details': details,
    'archiveName': archiveName,
    'parentName': parentName,
    'archiveSize': archiveSize,
    'url': url,
    'fileExtension': fileExtension,
    'serverFile': serverFile,
    'icon-url': iconUrl,
    'github-url': githubUrl
  };

  Widget get icon => buildPackageIcon(iconUrl, iconSize);

}

  mixin IconBuilder {
    String get name;

    Widget buildPackageIcon(String iconUrl, double size) {
      
      if (iconUrl.isEmpty) {
        return Icon(Icons.extension, size: size);
      }

      final isRemote = iconUrl.startsWith('http://') || iconUrl.startsWith('https://');
      final isSvg = iconUrl.toLowerCase().endsWith('.svg');

      if (isRemote) {
        if (isSvg) {
          return SvgPicture.network(iconUrl, height: size, width: size);
        }
        return Image.network(iconUrl, height: size, width: size);
      }

      if (isSvg) {
        return SvgPicture.asset(
          iconUrl,
          height: size,
          width: size,
          colorFilter: name == "Github Copilot" ? ColorFilter.mode(Colors.grey[600]!, .srcIn) : null,
        );
      }

      return Image.asset(iconUrl, height: size, width: size);
    }
  }


final langtxt = Language(
  name: 'Text File',
  extension: ['txt'],
  details: 'A normal text file.',
  language: txt,
  helloWorld: 'Hello World',
  icon: SvgPicture.asset('assets/material_icons/document.svg',height: 35,width: 35)
);
final langpython = Language(
  name: 'Python',
  extension: ['py', 'pyi'],
  details: 'A popular language known for simplicity and versatility.',
  language: builtinAllLanguages['python'],
  helloWorld: 'print("Hello, World!")',
  command: 'python',
  icon: SvgPicture.asset('assets/material_icons/python.svg',height: 35,width: 35),
  type: 'interpreted',
  lspExecutable: "/data/data/com.roxum/bin/ty",
);
final langjavascript = Language(
  name: 'Javascript',
  extension: ['js', 'mjs', 'cjs'],
  details: 'A versatile scripting language for dynamic web development.',
  language: builtinAllLanguages['javascript'],
  helloWorld: 'console.log("Hello, World!");',
  command: 'node',
  icon: SvgPicture.asset('assets/material_icons/javascript.svg',height: 35,width: 35),
  type: 'interpreted',
  lspExecutable: "/data/data/com.roxum/bin/node",
  args: ["--stdio"]
);
final langjsx = Language(
  name: 'JSX',
  extension: ['jsx'],
  details: 'JavaScript with XML-like syntax for React components.',
  language: builtinAllLanguages['javascript'],
  helloWorld: 'const App = () => <h1>Hello, World!</h1>;',
  command: 'node',
  icon: SvgPicture.asset('assets/material_icons/react.svg',height: 35,width: 35),
  type: 'interpreted',
  lspExecutable: "/data/data/com.roxum/bin/node",
  args: ["--stdio"]
);
final langtypescript = Language(
    name: 'Typescript',
    extension: ['ts'],
    details: 'A statically typed superset of JavaScript.',
  language: builtinAllLanguages['typescript'],
    helloWorld: 'console.log("Hello, World!");',
    command: 'tsc',
    icon: SvgPicture.asset('assets/material_icons/typescript.svg',height: 35,width: 35),
    type: 'interpreted',
    lspExecutable: "/data/data/com.roxum/bin/node",
    args: ["--stdio"]
);
final langtsx = Language(
  name: 'TSX',
  extension: ['tsx'],
  details: 'TypeScript with XML-like syntax for React components.',
  language: builtinAllLanguages['typescript'],
  helloWorld: 'const App = (): JSX.Element => <h1>Hello, World!</h1>;',
  command: 'tsc',
  icon: SvgPicture.asset('assets/material_icons/react.svg',height: 35,width: 35),
  type: 'interpreted',
  lspExecutable: "/data/data/com.roxum/bin/node",
  args: ["--stdio"]
);
final langjava = Language(
  name: 'Java',
  extension: ['java'],
  details: 'A platform-independent language for enterprise and web apps.',
  language: builtinAllLanguages['java'],
  helloWorld:'public class tempCode{\n  public static void main(String[] args){ \n    System.out.println("Hello, World!");\n  }\n}',
  icon: SvgPicture.asset('assets/material_icons/java.svg', height: 35,width: 35),
  command: 'javac',
  type: 'compiled',
  lspExecutable: "/data/data/com.roxum/bin/kmp-lsp",
);
final langc = Language(
  name: 'C',
  extension: ['c'],
  details:'A powerful, low-level language widely used in system programming.',
  language: builtinAllLanguages['c'],
  helloWorld:'#include <stdio.h> \n\nint main(){\n  printf("Hello, World!");\n  return 0;\n}',
  command: 'clang',
  icon: SvgPicture.asset('assets/material_icons/c.svg',height: 35,width: 35),
  type: 'compiled',
  lspExecutable: "/data/data/com.roxum/bin/ccls",
);

final langH = Language(
  name: 'C/C++ header file',
  extension: ['h', 'hpp'],
  details: "C/C++ header file",
  language: builtinAllLanguages['c'],
  helloWorld: "",
  lspExecutable: "/data/data/com.roxum/bin/ccls",
  icon: SvgPicture.asset('assets/material_icons/h.svg',height: 35,width: 35),
);

final langcpp = Language(
  name: 'C++',
  extension: ['cpp','c++','cc'],
  details:'A high-performance language used for system programming and games.',
  language: builtinAllLanguages['cpp'],
  helloWorld:'#include <iostream> \n\nint main(){\n  std::cout << "Hello, World!" << std::endl;\n  return 0; }',
  command: 'clang++',
  icon: SvgPicture.asset('assets/material_icons/cpp.svg',height: 35,width: 35),
  type: 'compiled',
  lspExecutable: "/data/data/com.roxum/bin/ccls",
);

final langdart = Language(
  name: 'Dart',
  extension: ['dart'],
  details:'Optimized for building fast, multi-platform apps, often with Flutter.',
  language: builtinAllLanguages['dart'],
  helloWorld: 'void main(){\n print("Hello, World!");\n}',
  command: 'dart',
  type: 'compiled(no binary)',
  icon: SvgPicture.asset('assets/material_icons/dart.svg',height: 35,width: 35),
  customCodeSnippet: [
    CustomCodeSnippet(
      label: 'if',
      value: 'if (condition) {\n  \n}',
      cursorLocations: {4},
    ),

    CustomCodeSnippet(
      label: 'if-else',
      value: 'if (condition) {\n  \n} else {\n  \n}',
      cursorLocations: {18, 31},
    ),
  ],
  lspExecutable: '$binDir/dart'
);

final langhtml = Language(
  name: 'HTML',
  extension: ['html','htm'],
  details: 'The standard markup language for creating web pages.',
  language: builtinAllLanguages['xml'],
  helloWorld:
  '''
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="UTF-8"> 
    <meta name="viewport" content="width=device-width initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="ie=edge">
  </head>
  <body>
    <h1>Hello World</h1>
  </body>
  </html>
''',
  icon: SvgPicture.asset('assets/material_icons/html.svg',height: 35,width: 35),
  args: ["--stdio"],
  lspExecutable: "/data/data/com.roxum/bin/node",
);
final langcss = Language(
  name: 'CSS',
  extension: ['css'],
  details: 'Used to style and format web pages.',
  language: builtinAllLanguages['css'],
  helloWorld: '/* Hello, World! */',
  lspExecutable: "/data/data/com.roxum/bin/node",
  args: ["--stdio"],
  icon: SvgPicture.asset('assets/material_icons/css.svg',height: 35,width: 35),
);
final langscss = Language(
  name: 'SCSS',
  extension: ['scss'],
  details: 'Enhances CSS with features like variables and nesting.',
  language: builtinAllLanguages['scss'],
  helloWorld: '/* Hello, World! */',
  icon: SvgPicture.asset('assets/material_icons/sass.svg',height:35,width:35),
);
final langless = Language(
  name: 'Less',
  extension: ['less'],
  details: 'A CSS pre-processor with a more dynamic syntax.',
  language: builtinAllLanguages['less'],
  helloWorld: '/* Hello, World! */',
  icon: SvgPicture.asset('assets/material_icons/less.svg',height: 35,width: 35),
);
final langphp = Language(
  name: 'PHP',
  extension: ['php'],
  details: 'A server-side language for dynamic web development.',
  language: builtinAllLanguages['php'],
  helloWorld: '<?php echo "Hello, World!"; ?>',
  icon: SvgPicture.asset('assets/material_icons/php.svg',height: 35,width: 35),
  command: 'php');
final langsql = Language(
  name: 'SQL',
  extension: ['sql'],
  details: 'Used for querying and managing relational databases.',
  language: builtinAllLanguages['sql'],
  icon: SvgPicture.asset('assets/material_icons/database.svg',height: 35,width: 35),
  helloWorld: '-- Hello, World!',
);
final langxml = Language(
  name: 'XML',
  extension: ['xml'],
  details:'Markup language primarily used to store and transport structured data.',
  language: builtinAllLanguages['xml'],
  icon: SvgPicture.asset('assets/material_icons/xml.svg',height: 35,width: 35),
  helloWorld:'<catalog>\n <book id="1">\n  <title>Learning XML</title>\n  <author>John Doe</author>\n  <price>29.99</price>\n </book>\n</catalog>',
);
final langswift = Language(
  name: 'Swift',
  extension: ['swift'],
  details: 'Apple\'s language for iOS and macOS apps.',
  language: builtinAllLanguages['swift'],
  helloWorld: 'print("Hello, World!")',
  command: 'swift',
  icon: SvgPicture.asset('assets/material_icons/swift.svg',height: 35,width: 35),
  type: 'compiled',
  lspExecutable: "/data/data/com.roxum/bin/kmp-lsp",
);
final langkotlin = Language(
  name: 'Kotlin',
  extension: ['kt', 'kts'],
  details: 'Modern JVM language, popular for Android development.',
  language: builtinAllLanguages['kotlin'],
  helloWorld: 'fun main(){\n println("Hello, World!")\n}',
  command: 'kotlinc',
  icon: SvgPicture.asset('assets/material_icons/kotlin.svg',height: 35,width: 35),
  type: 'compiled',
  lspExecutable: "/data/data/com.roxum/bin/kmp-lsp",
);
final langcsharp = Language(
  name: 'C#',
  extension: ['cs'],
  details: 'A modern, object-oriented language for Windows apps and games.',
  language: builtinAllLanguages['csharp'],
  helloWorld:'using System;\n\nclass Program{\n static void Main(){\n  Console.WriteLine("Hello, World!");\n  }\n }',
  command: 'mcs',
  icon: SvgPicture.asset('assets/material_icons/csharp.svg',height: 35,width: 35),
  type: 'compiled'
);
final langrust = Language(
  name: 'Rust',
  extension: ['rs'],
  details: 'Focused on performance, safety, and concurrency.',
  language: builtinAllLanguages['rust'],
  helloWorld: 'fn main(){\n println!("Hello, World!");\n}',
  command: 'rustc',
  icon: SvgPicture.asset('assets/material_icons/rust.svg',height: 35,width: 35),
  type: 'compiled',
  lspExecutable: '/data/data/com.roxum/bin/rust-analyzer',
);
final langgo = Language(
  name: 'Go',
  extension: ['go'],
  details:'Known for simplicity and performance, ideal for concurrent programming.',
  language: builtinAllLanguages['go'],
  helloWorld:'package main\n\nimport "fmt"\n\nfunc main(){\n fmt.Println("Hello, World!")\n}',
  command: 'go run',
  icon: SvgPicture.asset('assets/material_icons/go_gopher.svg',height: 35,width: 35),
  type: 'compiled(no binary)',
  lspExecutable: '/data/data/com.roxum/bin/gopls',
);
final langruby = Language(
  name: 'Ruby',
  extension: ['rb'],
  details: 'Dynamic language, often used with the Rails framework.',
  language: builtinAllLanguages['ruby'],
  helloWorld: 'puts "Hello, World!"',
  command: 'ruby',
  icon: SvgPicture.asset('assets/material_icons/ruby.svg',height: 35,width: 35),
  type: 'compiled(no binary)'
);
final langjson = Language(
  name: 'Json',
  extension: ['json'],
  details: 'A lightweight format for data interchange.',
  language: builtinAllLanguages['json'],
  icon: SvgPicture.asset('assets/material_icons/json.svg',height: 35,width: 35),
  lspExecutable: "/data/data/com.roxum/bin/node",
  args: ["--stdio"],
  helloWorld: '{ "hello": "world" }',
);
final langmarkdown = Language(
  name: 'Markdown',
  extension: ['md'],
  details: 'A markup language for formatting plain text.',
  language: builtinAllLanguages['markdown'],
  args: ["--stdio"],
  icon: SvgPicture.asset('assets/material_icons/markdown.svg',height: 35,width: 35),
  helloWorld: '# Hello, World!',
);
final langyaml = Language(
  name: 'Yaml',
  extension: ['yml','yaml'],
  details: 'A readable data serialization format.',
  language: builtinAllLanguages['yaml'],
  icon: SvgPicture.asset('assets/material_icons/yaml.svg',height: 35,width: 35),
  helloWorld: '# Hello, World!',
);
final langr = Language(
  name: 'R',
  extension: ['r'],
  details: 'Used for statistical computing and data visualization.',
  language: builtinAllLanguages['r'],
  icon: SvgPicture.asset('assets/material_icons/r.svg',height: 35,width: 35),
  helloWorld: 'cat("Hello, World!")',
  type: 'interpreted'
);
final langscala = Language(
  name: 'Scala',
  extension: ['scala'],
  details: 'Combines functional and object-oriented programming.',
  language: builtinAllLanguages['scala'],
  command: 'scalac',
  icon: SvgPicture.asset('assets/material_icons/scala.svg',height: 35,width: 35),
  helloWorld:'object Hello{\n def main(args: Array[String]) = {\n  println("Hello, World!")  \n} \n}',
  type: 'compiled'
);
final langlua = Language(
  name: 'Lua',
  extension: ['lua'],
  details:'A lightweight scripting language often used in game development.',
  language: builtinAllLanguages['lua'],
  command: 'lua',
  icon: SvgPicture.asset('assets/material_icons/lua.svg',height: 35,width: 35),
  helloWorld: 'print("Hello, World!")',
  type: 'compiled(no binary)',
  lspExecutable: '/data/data/com.roxum/bin/emmyluals',
);
final langbash = Language(
  name: 'Bash',
  extension: ['sh', 'bash', 'zsh'],
  details: 'A shell scripting language for automating Unix-based tasks.',
  language: builtinAllLanguages['bash'],
  helloWorld: 'echo "Hello, World!"',
  command: 'bash',
  icon: SvgPicture.asset('assets/material_icons/console.svg',height: 35,width: 35),
  lspExecutable: '$binDir/node',
  args: ["start"],
  type: 'interpreted'
);
final langhaskell = Language(
  name: 'Haskell',
  extension: ['hs'],
  details: 'A purely functional language with strong static typing.',
  language: builtinAllLanguages['haskell'],
  helloWorld: 'main = putStrLn "Hello, World!"',
  icon: SvgPicture.asset('assets/material_icons/haskell.svg',height: 35,width: 35),
);
final langelixir = Language(
  name: 'Elixir',
  extension: ['ex','exs'],
  details: 'A functional language for building scalable applications.',
  language: builtinAllLanguages['elixir'],
  helloWorld: 'IO.puts "Hello, World!"',
  command: 'elixir',
  type: 'compiled(no binary)',
  icon: SvgPicture.asset('assets/material_icons/elixir.svg',height: 35,width: 35),
);
final langobjectivec = Language(
  name: 'Objective C',
  extension: ['m','mm'],
  details: 'Used for macOS and iOS development.',
  language: builtinAllLanguages['objectivec'],
  helloWorld:'#import <Foundation/Foundation.h> \nint main() {\n NSLog(@"Hello, World!");\n return 0;\n}',
  command: 'gcc',
  icon: SvgPicture.asset('assets/material_icons/objective-c.svg',height: 35,width: 35),
  type: 'compiled'
);
final langfsharp = Language(
  name: 'Fsharp',
  extension: ['fsx','fs'],
  details: 'A functional-first language for .NET applications.',
  language: builtinAllLanguages['fsharp'],
  helloWorld: 'printfn "Hello, World!"',
  command: 'mono',
  type: 'compiled',
  icon: SvgPicture.asset('assets/material_icons/fsharp.svg',height: 35,width: 35),
);
final langperl = Language(
  name: 'Perl',
  extension: ['pl'],
  details: 'Known for text processing and system scripting.',
  language: builtinAllLanguages['perl'],
  helloWorld: 'print "Hello, World!";',
  command: 'perl',
  type: 'interpreted',
  icon: SvgPicture.asset('assets/material_icons/perl.svg',height: 35,width: 35),
); 
final langclojure = Language(
  name: 'Clojure',
  extension: ['clj','cljs'],
  details:'A functional language running on the JVM, known for immutability.',
  language: builtinAllLanguages['clojure'],
  helloWorld: '(println "Hello, World!")',
  command: 'lein run',
  icon: SvgPicture.asset('assets/material_icons/clojure.svg',height: 35,width: 35),
);
final langarduino = Language(
  name: 'Arduino',
  extension: ['ino'],
  details:
      'Used to program Arduino microcontrollers for interactive devices.',
  language: builtinAllLanguages['arduino'],
  helloWorld:
      'void setup(){\n  Serial.begin(9600);\n} \n\nvoid loop(){\n  Serial.println("Hello, World!");\n  delay(1000);\n}',
  icon: SvgPicture.asset(
    'assets/icons/file-type-arduino.svg',
    height: 35,
    width: 35,
  )
);
final langx86asm = Language(
  name: 'x86 assembly',
  extension: ['asm'],
  details: 'Low-level language for x86 processors.',
  language: builtinAllLanguages['x86asm'],
  helloWorld:'mov eax, 0 \nmov ebx, 4 \nmov ecx, msg \nmov edx, 13 \nint 0x80 \nret \nmsg db "Hello, World!", 0',
  icon: SvgPicture.asset('assets/material_icons/assembly.svg',height: 35,width: 35),
);
final langarmasm = Language(
  name: 'ARM assembly',
  extension: ['s','S'],
  details:'Low-level language for ARM processors, common in embedded systems.',
  language: builtinAllLanguages['armasm'],
  helloWorld:'.section .data \nmsg: .asciz "Hello, World!" \n.section .text \n.global _start \n_start: \nldr r0, =msg \nmov r7, #4 \nsvc #0',
  icon: SvgPicture.asset('assets/material_icons/assembly.svg',height: 35,width: 35),
);
final langavrasm = Language(
  name: 'AVR assembly',
  extension: ['asm'],
  details: 'Assembly language for AVR microcontrollers in embedded systems.',
  language: builtinAllLanguages['avrasm'],
  helloWorld:'.section .data \nmsg: .asciz "Hello, World!" \n.section .text \n.global _start \n_start: \nldi r16, low(msg) \nout 0x20, r16 \nldi r16, high(msg) \nout 0x21, r16',
  icon: SvgPicture.asset('assets/material_icons/assembly.svg',height: 35,width: 35),
);
final langcoffeescript = Language(
    name: 'Coffeescript',
    extension: ['coffee'],
    details: 'Compiles to JavaScript, offering a cleaner syntax.',
    language: builtinAllLanguages['coffeescript'],
    helloWorld: 'console.log "Hello, World!"',
    command: 'coffee',
    type: 'interpreted',
    icon: SvgPicture.asset('assets/material_icons/coffeescript.svg',height: 35,width: 35),
  );

final langaccesslog = Language(
  name: 'Access Log',
  extension: ['log'],
  details: 'Common format for logging web server requests.',
  language: builtinAllLanguages['accesslog'],
  helloWorld: '# Placeholder for Hello, World!',
  icon: SvgPicture.asset('assets/material_icons/log.svg',height: 35,width: 35),
);
final langada = Language(
  name: 'Ada',
  extension: ['ada'],
  details: 'A structured, statically typed, high-level language.',
  language: builtinAllLanguages['ada'],
  helloWorld: 'with Ada.Text_IO; use Ada.Text_IO;\nbegin\n  Put_Line("Hello, World!");\nend;',
  icon: SvgPicture.asset('assets/material_icons/ada.svg',height: 35,width: 35),
);
final langangelscript = Language(
  name: 'AngelScript',
  extension: ['as'],
  details: 'A scripting language designed for game development.',
  language: builtinAllLanguages['angelscript'],
  helloWorld: 'void main() {\n print("Hello, World!");\n}',
  icon: SvgPicture.asset(
    'assets/material_icons/angelscript.svg',
    height: 40,
    width: 40,
    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)
  ),
);
final langbrainfuck = Language(
  name: 'Brainfuck',
  extension: ['bf'],
  details: 'A minimalist, esoteric programming language.',
  language: builtinAllLanguages['brainfuck'],
  helloWorld: '++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+<<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.',
  icon: SvgPicture.asset('assets/material_icons/brainfuck.svg',height: 35,width: 35),
);
final langcmake = Language(
  name: 'CMake',
  extension: ['cmake'],
  details: 'Cross-platform build system.',
  language: builtinAllLanguages['cmake'],
  helloWorld: '# Placeholder for Hello, World!',
  icon: SvgPicture.asset('assets/material_icons/cmake.svg',height: 35,width: 35),
);
final langd = Language(
  name: 'D',
  extension: ['d'],
  details: 'A system programming language with C-like syntax and features.',
  language: builtinAllLanguages['d'],
  helloWorld: 'import std.stdio; void main() { writeln("Hello, World!"); }',
  icon: SvgPicture.asset('assets/material_icons/d.svg',height: 35,width: 35),
);
final langerlang = Language(
  name: 'Erlang',
  extension: ['erl'],
  details: 'A language for building scalable, fault-tolerant systems.',
  language: builtinAllLanguages['erlang'],
  helloWorld: 'io:format("Hello, World!~n").',
  icon: SvgPicture.asset('assets/material_icons/erlang.svg',height: 35,width: 35),
);
final langfortran = Language(
  name: 'Fortran',
  extension: ['f90'],
  details: 'A language for numerical and scientific computing.',
  language: builtinAllLanguages['fortran'],
  helloWorld: 'program hello\n  print *, "Hello, World!"\nend program hello',
  icon: SvgPicture.asset('assets/material_icons/fortran.svg',height: 35,width: 35),
);
final langgradle = Language(
  name: 'Gradle',
  extension: ['gradle'],
  details: 'Configuration file used for Android development.',
  language: builtinAllLanguages['gradle'],
  helloWorld: 'program hello\n  print *, "Hello, World!"\nend program hello',
  icon: SvgPicture.asset('assets/material_icons/gradle.svg',height: 35,width: 35),
);
final langgroovy = Language(
  name: 'Groovy',
  extension: ['groovy'],
  details: 'A language for the JVM with dynamic and static features.',
  language: builtinAllLanguages['groovy'],
  helloWorld: 'println "Hello, World!"',
  icon: SvgPicture.asset('assets/material_icons/groovy.svg',height: 35,width: 35),
);
final langjulia = Language(
  name: 'Julia',
  extension: ['jl'],
  details: 'A high-performance language for technical computing.',
  language: builtinAllLanguages['julia'],
  helloWorld: 'println("Hello, World!")',
  icon: SvgPicture.asset('assets/material_icons/julia.svg',height: 35,width: 35),
);
final langlisp = Language(
  name: 'Lisp',
  extension: ['lisp'],
  details: 'A family of functional, symbolic programming languages.',
  language: builtinAllLanguages['lisp'],
  helloWorld: '(print "Hello, World!")',
  icon: SvgPicture.asset('assets/material_icons/lisp.svg',height: 35,width: 35),
);
final langverilog = Language(
  name: 'Verilog',
  extension: ['v'],
  details: 'A hardware description language used in digital design.',
  language: builtinAllLanguages['verilog'],
  helloWorld: 'module hello;\ninitial begin\n  \$display("Hello, World!");\nend\nendmodule',
  icon: SvgPicture.asset('assets/material_icons/verilog.svg',height: 35,width: 35),
);

List<Language> languages = [
  langtxt,
  langpython,
  langjavascript,
  langjsx,
  langtypescript,
  langtsx,
  langjava,
  langc,
  langcpp,
  langdart,
  langhtml,
  langcss,
  langkotlin,
  langrust,
  langgo,
  langcsharp,
  langscss,
  langless,
  langphp,
  langsql,
  langxml,
  langswift,
  langruby,
  langjson,
  langmarkdown,
  langyaml,
  langr,
  langscala,
  langlua,
  langbash,
  langhaskell,
  langelixir,
  langobjectivec,
  langfsharp,
  langperl,
  langclojure,
  langarduino,
  langx86asm,
  langarmasm,
  langavrasm,
  langcoffeescript,
  langaccesslog,
  langada,
  langangelscript,
  langbrainfuck,
  langcmake,
  langd,
  langerlang,
  langfortran,
  langgradle,
  langgroovy,
  langjulia,
  langlisp,
  langverilog,
  langH
];

final List<RunTime> runtimes = [];

final List<Extension> extensions = [];

void updatePackageCatalog({
  required List<RunTime> fetchedRuntimes,
  required List<Extension> fetchedExtensions,
}) {
  runtimes
    ..clear()
    ..addAll(fetchedRuntimes);

  extensions
    ..clear()
    ..addAll(fetchedExtensions);
}