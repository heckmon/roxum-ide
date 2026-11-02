import 'package:flutter/material.dart';
import 'package:re_highlight/styles/all.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:xterm2/xterm.dart';

final Map<String, Map<String, TextStyle>> highlightThemes = builtinAllThemes..removeWhere(
  (k, v) => v['root']?.backgroundColor == null || v['root']?.color == null
);

final fonts = [
  'monospace',
  'firaCode',
  'cascadia',
  'hack',
  'dejaVuSansMono',
  'inconsolata',
  'jetBrainsMono',
  'proggy',
  'sourceCodePro'
  ];

const String defaultTerminalThemeId = 'classic-green';

@immutable
class TerminalThemePreset {
  final String id;
  final String name;
  final TerminalTheme theme;

  const TerminalThemePreset({
    required this.id,
    required this.name,
    required this.theme,
  });

  Color get backgroundColor => theme.background;
  Color get foregroundColor => theme.foreground;
}

TerminalTheme _terminalPalette({
  required Color background,
  required Color foreground,
  required List<Color> normal,
  required List<Color> bright,
  Color? cursor,
  Color? selection,
  Color? searchHitBackground,
  Color? searchHitBackgroundCurrent,
  Color? searchHitForeground,
}) {
  return TerminalTheme(
    cursor: cursor ?? foreground,
    selection: selection ?? foreground.withValues(alpha: 0.22),
    foreground: foreground,
    background: background,
    black: normal[0],
    red: normal[1],
    green: normal[2],
    yellow: normal[3],
    blue: normal[4],
    magenta: normal[5],
    cyan: normal[6],
    white: normal[7],
    brightBlack: bright[0],
    brightRed: bright[1],
    brightGreen: bright[2],
    brightYellow: bright[3],
    brightBlue: bright[4],
    brightMagenta: bright[5],
    brightCyan: bright[6],
    brightWhite: bright[7],
    searchHitBackground: searchHitBackground ?? foreground.withValues(alpha: 0.14),
    searchHitBackgroundCurrent: searchHitBackgroundCurrent ?? foreground.withValues(alpha: 0.26),
    searchHitForeground: searchHitForeground ?? foreground,
  );
}

const terminalTheme = TerminalTheme(
  cursor: Colors.grey,
  selection: Color.fromARGB(134, 170, 191, 211),
  foreground: Colors.white,
  background: Colors.black,
  black: Color(0xff000000),
  white: Color(0xffffffff),
  red: Color(0xffff0000),
  green: Color(0xff00ff00),
  yellow: Color(0xffffff00),
  blue: Color(0xff0000ff),
  magenta: Color(0xffff00ff),
  cyan: Color(0xff00ffff),
  brightBlack: Color(0xff808080),
  brightRed: Color(0xffff5f5f),
  brightGreen: Color(0xff5fff5f),
  brightYellow: Color(0xffffff87),
  brightBlue: Color(0xff5f5fff),
  brightMagenta: Color(0xffff5fff),
  brightCyan: Color(0xff5fffff),
  brightWhite: Color(0xffffffff),
  searchHitBackground: Color(0xff444444),
  searchHitBackgroundCurrent: Color(0xff555555),
  searchHitForeground: Color(0xffffffff),
);

final Map<String, TerminalThemePreset> terminalThemePresets = {
  defaultTerminalThemeId: const TerminalThemePreset(
    id: defaultTerminalThemeId,
    name: 'Classic Green',
    theme: terminalTheme,
  ),
  'tokyo-night': TerminalThemePreset(
    id: 'tokyo-night',
    name: 'Tokyo Night',
    theme: _terminalPalette(
      background: const Color(0xff1a1b26),
      foreground: const Color(0xffc0caf5),
      cursor: const Color(0xff7aa2f7),
      normal: const [
        Color(0xff15161e),
        Color(0xfff7768e),
        Color(0xff9ece6a),
        Color(0xffe0af68),
        Color(0xff7aa2f7),
        Color(0xffbb9af7),
        Color(0xff7dcfff),
        Color(0xffc0caf5),
      ],
      bright: const [
        Color(0xff414868),
        Color(0xffff7a93),
        Color(0xffb9f27c),
        Color(0xfff0c674),
        Color(0xff82aaff),
        Color(0xffcaa9fa),
        Color(0xff9aedfe),
        Color(0xffffffff),
      ],
    ),
  ),
  'dracula': TerminalThemePreset(
    id: 'dracula',
    name: 'Dracula',
    theme: _terminalPalette(
      background: const Color(0xff282a36),
      foreground: const Color(0xfff8f8f2),
      cursor: const Color(0xfff8f8f2),
      normal: const [
        Color(0xff21222c),
        Color(0xffff5555),
        Color(0xff50fa7b),
        Color(0xfff1fa8c),
        Color(0xffbd93f9),
        Color(0xffff79c6),
        Color(0xff8be9fd),
        Color(0xfff8f8f2),
      ],
      bright: const [
        Color(0xff6272a4),
        Color(0xffff6e6e),
        Color(0xff69ff94),
        Color(0xffffffa5),
        Color(0xffd6acff),
        Color(0xffff92df),
        Color(0xffa4ffff),
        Color(0xffffffff),
      ],
    ),
  ),
  'nord-frost': TerminalThemePreset(
    id: 'nord-frost',
    name: 'Nord Frost',
    theme: _terminalPalette(
      background: const Color(0xff2e3440),
      foreground: const Color(0xffd8dee9),
      cursor: const Color(0xff88c0d0),
      normal: const [
        Color(0xff3b4252),
        Color(0xffbf616a),
        Color(0xffa3be8c),
        Color(0xffebcb8b),
        Color(0xff81a1c1),
        Color(0xffb48ead),
        Color(0xff88c0d0),
        Color(0xffe5e9f0),
      ],
      bright: const [
        Color(0xff4c566a),
        Color(0xffd06f79),
        Color(0xffb1d196),
        Color(0xfff0d399),
        Color(0xff8cafd2),
        Color(0xffc895bf),
        Color(0xff93ccdc),
        Color(0xffeceff4),
      ],
    ),
  ),
  'gruvbox-dark': TerminalThemePreset(
    id: 'gruvbox-dark',
    name: 'Gruvbox Dark',
    theme: _terminalPalette(
      background: const Color(0xff282828),
      foreground: const Color(0xffebdbb2),
      cursor: const Color(0xfffabd2f),
      normal: const [
        Color(0xff282828),
        Color(0xffcc241d),
        Color(0xff98971a),
        Color(0xffd79921),
        Color(0xff458588),
        Color(0xffb16286),
        Color(0xff689d6a),
        Color(0xffa89984),
      ],
      bright: const [
        Color(0xff928374),
        Color(0xfffb4934),
        Color(0xffb8bb26),
        Color(0xfffabd2f),
        Color(0xff83a598),
        Color(0xffd3869b),
        Color(0xff8ec07c),
        Color(0xfffbf1c7),
      ],
    ),
  ),
  'solarized-dark': TerminalThemePreset(
    id: 'solarized-dark',
    name: 'Solarized Dark',
    theme: _terminalPalette(
      background: const Color(0xff002b36),
      foreground: const Color(0xff839496),
      cursor: const Color(0xff93a1a1),
      normal: const [
        Color(0xff073642),
        Color(0xffdc322f),
        Color(0xff859900),
        Color(0xffb58900),
        Color(0xff268bd2),
        Color(0xffd33682),
        Color(0xff2aa198),
        Color(0xffeee8d5),
      ],
      bright: const [
        Color(0xff586e75),
        Color(0xffcb4b16),
        Color(0xff93a1a1),
        Color(0xff657b83),
        Color(0xff839496),
        Color(0xff6c71c4),
        Color(0xff268bd2),
        Color(0xfffdf6e3),
      ],
    ),
  ),
  'catppuccin-mocha': TerminalThemePreset(
    id: 'catppuccin-mocha',
    name: 'Catppuccin Mocha',
    theme: _terminalPalette(
      background: const Color(0xff1e1e2e),
      foreground: const Color(0xffcdd6f4),
      cursor: const Color(0xfff5e0dc),
      normal: const [
        Color(0xff45475a),
        Color(0xfff38ba8),
        Color(0xffa6e3a1),
        Color(0xfff9e2af),
        Color(0xff89b4fa),
        Color(0xffcba6f7),
        Color(0xff94e2d5),
        Color(0xffbac2de),
      ],
      bright: const [
        Color(0xff585b70),
        Color(0xfff38ba8),
        Color(0xffa6e3a1),
        Color(0xfff9e2af),
        Color(0xff89b4fa),
        Color(0xffcba6f7),
        Color(0xff94e2d5),
        Color(0xffa6adc8),
      ],
    ),
  ),
  'rose-pine': TerminalThemePreset(
    id: 'rose-pine',
    name: 'Rose Pine',
    theme: _terminalPalette(
      background: const Color(0xff191724),
      foreground: const Color(0xffe0def4),
      cursor: const Color(0xffebbcba),
      normal: const [
        Color(0xff26233a),
        Color(0xffeb6f92),
        Color(0xff31748f),
        Color(0xfff6c177),
        Color(0xff9ccfd8),
        Color(0xffc4a7e7),
        Color(0xffebbcba),
        Color(0xffe0def4),
      ],
      bright: const [
        Color(0xff6e6a86),
        Color(0xffeb6f92),
        Color(0xff9ccfd8),
        Color(0xfff6c177),
        Color(0xff31748f),
        Color(0xffc4a7e7),
        Color(0xffebbcba),
        Color(0xfffaf4ed),
      ],
    ),
  ),
  'monokai-pro': TerminalThemePreset(
    id: 'monokai-pro',
    name: 'Monokai Pro',
    theme: _terminalPalette(
      background: const Color(0xff2d2a2e),
      foreground: const Color(0xfffcfcfa),
      cursor: const Color(0xffffd866),
      normal: const [
        Color(0xff403e41),
        Color(0xffff6188),
        Color(0xffa9dc76),
        Color(0xffffd866),
        Color(0xff78dce8),
        Color(0xffab9df2),
        Color(0xff78dce8),
        Color(0xfffcfcfa),
      ],
      bright: const [
        Color(0xff727072),
        Color(0xffff7b9f),
        Color(0xffb7e283),
        Color(0xffffe07a),
        Color(0xff8be9fd),
        Color(0xffc1b3ff),
        Color(0xff8be9fd),
        Color(0xffffffff),
      ],
    ),
  ),
  'ayu-mirage': TerminalThemePreset(
    id: 'ayu-mirage',
    name: 'Ayu Mirage',
    theme: _terminalPalette(
      background: const Color(0xff1f2430),
      foreground: const Color(0xffcccac2),
      cursor: const Color(0xffffcc66),
      normal: const [
        Color(0xff1f2430),
        Color(0xfff28779),
        Color(0xffa6cc70),
        Color(0xffffcc66),
        Color(0xff5ccfe6),
        Color(0xffd4bfff),
        Color(0xff95e6cb),
        Color(0xffd9d7ce),
      ],
      bright: const [
        Color(0xff707a8c),
        Color(0xffffa08f),
        Color(0xffbbe67e),
        Color(0xffffd580),
        Color(0xff73d0ff),
        Color(0xffdfc8ff),
        Color(0xffa7f3d8),
        Color(0xffffffff),
      ],
    ),
  ),
  'one-half-dark': TerminalThemePreset(
    id: 'one-half-dark',
    name: 'One Half Dark',
    theme: _terminalPalette(
      background: const Color(0xff282c34),
      foreground: const Color(0xffdcdfe4),
      cursor: const Color(0xff61afef),
      normal: const [
        Color(0xff282c34),
        Color(0xffe06c75),
        Color(0xff98c379),
        Color(0xffe5c07b),
        Color(0xff61afef),
        Color(0xffc678dd),
        Color(0xff56b6c2),
        Color(0xffdcdfe4),
      ],
      bright: const [
        Color(0xff5a6374),
        Color(0xfff08990),
        Color(0xffa9d18e),
        Color(0xfff1cf95),
        Color(0xff82c4ff),
        Color(0xffd89ceb),
        Color(0xff77d0dd),
        Color(0xffffffff),
      ],
    ),
  ),
  'oceanic-next': TerminalThemePreset(
    id: 'oceanic-next',
    name: 'Oceanic Next',
    theme: _terminalPalette(
      background: const Color(0xff1b2b34),
      foreground: const Color(0xffc0c5ce),
      cursor: const Color(0xff6699cc),
      normal: const [
        Color(0xff1b2b34),
        Color(0xffec5f67),
        Color(0xff99c794),
        Color(0xfffac863),
        Color(0xff6699cc),
        Color(0xffc594c5),
        Color(0xff5fb3b3),
        Color(0xffc0c5ce),
      ],
      bright: const [
        Color(0xff65737e),
        Color(0xffff8b92),
        Color(0xffb4d9ad),
        Color(0xffffd68b),
        Color(0xff8eb4e5),
        Color(0xffd6add6),
        Color(0xff7ec7c7),
        Color(0xffeff1f5),
      ],
    ),
  ),
  'synthwave-84': TerminalThemePreset(
    id: 'synthwave-84',
    name: 'Synthwave 84',
    theme: _terminalPalette(
      background: const Color(0xff262335),
      foreground: const Color(0xfff4eee4),
      cursor: const Color(0xfff92aad),
      normal: const [
        Color(0xff1f1d2e),
        Color(0xfffe4450),
        Color(0xff72f1b8),
        Color(0xfffede5d),
        Color(0xff36f9f6),
        Color(0xffff7edb),
        Color(0xff00f7ff),
        Color(0xfff4eee4),
      ],
      bright: const [
        Color(0xff7b6f9f),
        Color(0xffff6975),
        Color(0xff9af5cb),
        Color(0xffffe983),
        Color(0xff67fbff),
        Color(0xffff9be8),
        Color(0xff66fbff),
        Color(0xffffffff),
      ],
    ),
  ),
  'forest-night': TerminalThemePreset(
    id: 'forest-night',
    name: 'Forest Night',
    theme: _terminalPalette(
      background: const Color(0xff0f1a14),
      foreground: const Color(0xffd8e3d0),
      cursor: const Color(0xff84cc16),
      normal: const [
        Color(0xff101b12),
        Color(0xffdc6f6f),
        Color(0xff78c26d),
        Color(0xffd4b86a),
        Color(0xff5ba2d0),
        Color(0xffb88ad4),
        Color(0xff5fbba6),
        Color(0xffd8e3d0),
      ],
      bright: const [
        Color(0xff5f6f61),
        Color(0xffe38a8a),
        Color(0xff9ad489),
        Color(0xffe2cb8a),
        Color(0xff7db9e0),
        Color(0xffc9a2e2),
        Color(0xff7ccfbb),
        Color(0xfff4f8ef),
      ],
    ),
  ),
  'sunset-ember': TerminalThemePreset(
    id: 'sunset-ember',
    name: 'Sunset Ember',
    theme: _terminalPalette(
      background: const Color(0xff2b1b17),
      foreground: const Color(0xfffceee6),
      cursor: const Color(0xffffb86c),
      normal: const [
        Color(0xff2b1b17),
        Color(0xffff6b6b),
        Color(0xfff7b267),
        Color(0xffffd166),
        Color(0xff7aa2f7),
        Color(0xffc792ea),
        Color(0xff89ddff),
        Color(0xfffceee6),
      ],
      bright: const [
        Color(0xff86635b),
        Color(0xffff8f8f),
        Color(0xffffc98f),
        Color(0xffffdf8a),
        Color(0xff9bb7ff),
        Color(0xffdab0ff),
        Color(0xfface8ff),
        Color(0xffffffff),
      ],
    ),
  ),
  'cyber-mint': TerminalThemePreset(
    id: 'cyber-mint',
    name: 'Cyber Mint',
    theme: _terminalPalette(
      background: const Color(0xff071418),
      foreground: const Color(0xffc5ffe2),
      cursor: const Color(0xff00ffa6),
      normal: const [
        Color(0xff0a1b21),
        Color(0xffff5f7a),
        Color(0xff00ffa6),
        Color(0xffffef82),
        Color(0xff3ea8ff),
        Color(0xffd68fff),
        Color(0xff4af7ff),
        Color(0xffc5ffe2),
      ],
      bright: const [
        Color(0xff4f6d75),
        Color(0xffff7f96),
        Color(0xff4fffc1),
        Color(0xfffff29f),
        Color(0xff72beff),
        Color(0xffe6adff),
        Color(0xff86fbff),
        Color(0xffffffff),
      ],
    ),
  ),
  'cobalt2': TerminalThemePreset(
    id: 'cobalt2',
    name: 'Cobalt2',
    theme: _terminalPalette(
      background: const Color(0xff193549),
      foreground: const Color(0xffffffff),
      cursor: const Color(0xffffd700),
      normal: const [
        Color(0xff000000),
        Color(0xffff5370),
        Color(0xff3ad900),
        Color(0xffffc600),
        Color(0xff00a6ff),
        Color(0xffff9d00),
        Color(0xff00dffc),
        Color(0xffffffff),
      ],
      bright: const [
        Color(0xff888888),
        Color(0xffff7a89),
        Color(0xff5fff4f),
        Color(0xffffd95e),
        Color(0xff66c2ff),
        Color(0xffffb84f),
        Color(0xff6bf0ff),
        Color(0xffffffff),
      ],
    ),
  ),
  'gruvbox-light': TerminalThemePreset(
    id: 'gruvbox-light',
    name: 'Gruvbox Light',
    theme: _terminalPalette(
      background: const Color(0xfffbf1c7),
      foreground: const Color(0xff3c3836),
      cursor: const Color(0xff458588),
      selection: const Color(0xffd5c4a1),
      normal: const [
        Color(0xffebdbb2),
        Color(0xffcc241d),
        Color(0xff98971a),
        Color(0xffd79921),
        Color(0xff458588),
        Color(0xffb16286),
        Color(0xff689d6a),
        Color(0xff3c3836),
      ],
      bright: const [
        Color(0xff7c6f64),
        Color(0xff9d0006),
        Color(0xff79740e),
        Color(0xffb57614),
        Color(0xff076678),
        Color(0xff8f3f71),
        Color(0xff427b58),
        Color(0xff282828),
      ],
    ),
  ),
  'solarized-light': TerminalThemePreset(
    id: 'solarized-light',
    name: 'Solarized Light',
    theme: _terminalPalette(
      background: const Color(0xfffdf6e3),
      foreground: const Color(0xff657b83),
      cursor: const Color(0xff586e75),
      selection: const Color(0xffeee8d5),
      normal: const [
        Color(0xff073642),
        Color(0xffdc322f),
        Color(0xff859900),
        Color(0xffb58900),
        Color(0xff268bd2),
        Color(0xffd33682),
        Color(0xff2aa198),
        Color(0xff657b83),
      ],
      bright: const [
        Color(0xff93a1a1),
        Color(0xffcb4b16),
        Color(0xff586e75),
        Color(0xff657b83),
        Color(0xff839496),
        Color(0xff6c71c4),
        Color(0xff268bd2),
        Color(0xff002b36),
      ],
    ),
  ),
  'catppuccin-latte': TerminalThemePreset(
    id: 'catppuccin-latte',
    name: 'Catppuccin Latte',
    theme: _terminalPalette(
      background: const Color(0xffeff1f5),
      foreground: const Color(0xff4c4f69),
      cursor: const Color(0xffdc8a78),
      selection: const Color(0xffccd0da),
      normal: const [
        Color(0xff5c5f77),
        Color(0xffd20f39),
        Color(0xff40a02b),
        Color(0xffdf8e1d),
        Color(0xff1e66f5),
        Color(0xff8839ef),
        Color(0xff179299),
        Color(0xff4c4f69),
      ],
      bright: const [
        Color(0xff6c6f85),
        Color(0xffd20f39),
        Color(0xff40a02b),
        Color(0xffdf8e1d),
        Color(0xff1e66f5),
        Color(0xff8839ef),
        Color(0xff179299),
        Color(0xff313244),
      ],
    ),
  ),
  'one-half-light': TerminalThemePreset(
    id: 'one-half-light',
    name: 'One Half Light',
    theme: _terminalPalette(
      background: const Color(0xfffafafa),
      foreground: const Color(0xff383a42),
      cursor: const Color(0xff0184bc),
      selection: const Color(0xffe5e7ea),
      normal: const [
        Color(0xff383a42),
        Color(0xffe45649),
        Color(0xff50a14f),
        Color(0xffc18401),
        Color(0xff0184bc),
        Color(0xffa626a4),
        Color(0xff0997b3),
        Color(0xfffafafa),
      ],
      bright: const [
        Color(0xff4f525d),
        Color(0xffdf6c75),
        Color(0xff98c379),
        Color(0xffe5c07b),
        Color(0xff61afef),
        Color(0xffc678dd),
        Color(0xff56b6c2),
        Color(0xffffffff),
      ],
    ),
  ),
  'paper-ink': TerminalThemePreset(
    id: 'paper-ink',
    name: 'Paper Ink',
    theme: _terminalPalette(
      background: const Color(0xfff5f3ef),
      foreground: const Color(0xff2b2b2b),
      cursor: const Color(0xff174ea6),
      selection: const Color(0xffe3ddd2),
      normal: const [
        Color(0xff2b2b2b),
        Color(0xffb00020),
        Color(0xff2e7d32),
        Color(0xffb28704),
        Color(0xff174ea6),
        Color(0xff7b1fa2),
        Color(0xff006064),
        Color(0xfff5f3ef),
      ],
      bright: const [
        Color(0xff5f6368),
        Color(0xffd93025),
        Color(0xff34a853),
        Color(0xfff9ab00),
        Color(0xff1a73e8),
        Color(0xff9334e6),
        Color(0xff00acc1),
        Color(0xffffffff),
      ],
    ),
  ),
};

TerminalThemePreset terminalThemePresetById(String? id) {
  if (id != null && terminalThemePresets.containsKey(id)) {
    return terminalThemePresets[id]!;
  }
  return terminalThemePresets[defaultTerminalThemeId]!;
}
const appBarDark = AppBarTheme(backgroundColor: Color(0xff181818),iconTheme: IconThemeData(color: Colors.grey, size: 32));
const appBarLight = AppBarTheme(backgroundColor: Color.fromARGB(255, 243, 242, 242),iconTheme: IconThemeData(color: Color.fromARGB(255, 25, 25, 25), size: 32));
const darkTileTheme = ListTileThemeData(
  titleTextStyle: TextStyle(color: Colors.white, fontSize: 18),
  subtitleTextStyle: TextStyle(color: Color(0xff6d6d6d))
);
const lightTileTheme = ListTileThemeData(
  titleTextStyle: TextStyle(color: Color.fromARGB(255, 36, 36, 36), fontSize: 18),
  subtitleTextStyle: TextStyle(color: Color(0xff6d6d6d))
);

const cardDarkTheme = CardTheme(color: Color.fromARGB(255, 37, 37, 37));
const cardLightTheme = CardTheme(color: Color.fromARGB(255, 241, 241, 241));
const popupBtnDarkTheme = PopupMenuThemeData(color: Color.fromARGB(255, 61, 61, 61));
const popupBtnLightTheme = PopupMenuThemeData(color: Color.fromARGB(255, 235, 235, 235));
const progressTheme = ProgressIndicatorThemeData(color: Color(0xff0e639c));

class FolderStyle {
  final dynamic folderClosedicon;
  final dynamic folderOpenedicon;
  final TextStyle? folderNameStyle;
  final dynamic iconForCreateFolder;
  final dynamic iconForCreateFile;
  final dynamic iconForDeleteFolder;
  final dynamic rootFolderClosedIcon;
  final dynamic rootFolderOpenedIcon;
  final double itemGap;
  FolderStyle({
    this.itemGap = 15,
    this.rootFolderClosedIcon = const Icon(Icons.chevron_right_sharp),
    this.rootFolderOpenedIcon = const Icon(Icons.keyboard_arrow_down_sharp),
    this.folderNameStyle = const TextStyle(),
    this.iconForCreateFolder = const Icon(Icons.create_new_folder),
    this.iconForCreateFile = const FaIcon(FontAwesomeIcons.fileCirclePlus, size: 20),
    this.iconForDeleteFolder = const Icon(Icons.delete),
    this.folderClosedicon = const Icon(Icons.folder),
    this.folderOpenedicon = const Icon(Icons.folder_open),
  });
}
class FileStyle {
  final dynamic fileIcon;
  final TextStyle? fileNameStyle;
  final dynamic iconForDeleteFile;
  FileStyle({
    this.fileNameStyle = const TextStyle(),
    this.fileIcon = const Icon(Icons.insert_drive_file),
    this.iconForDeleteFile = const Icon(Icons.delete),
  });
}

class EditingFieldStyle {
  final dynamic folderIcon;
  final dynamic fileIcon;
  final InputDecoration textfieldDecoration;
  final dynamic doneIcon;
  final dynamic cancelIcon;
  final double textFieldHeight;
  final double textFieldWidth;
  final Color? cursorColor;
  final double cursorHeight;
  final double cursorWidth;
  final Radius? cursorRadius;
  final TextAlignVertical? verticalTextAlign;
  final TextStyle? textStyle;
  EditingFieldStyle({
    this.textFieldHeight = 30,
    this.textFieldWidth = double.infinity,
    this.cursorHeight = 20,
    this.cursorWidth = 2.0,
    this.cursorRadius,
    this.cursorColor,
    this.verticalTextAlign,
    this.textStyle,
    this.textfieldDecoration = const InputDecoration(),
    this.folderIcon = const Icon(Icons.folder),
    this.fileIcon = const Icon(Icons.edit_document),
    this.doneIcon = const Icon(Icons.check),
    this.cancelIcon = const Icon(Icons.close)});
}

abstract class AppTheme{
  bool get isDark;
  Color get scaffoldBg;
  Color get selectScreenCardsBg;
  Color get selectScreenCardTextColor;
  Color get selectScreenDrawerBg;
  Color get editorPageToolSelectedColor;
  Color get editorPageToolSelectedBgColor;
  Color get editorPageToolbarBg;
  Color get editorPageToolColor;
  Color get editorPageDrawerBg;
  AppBarTheme get appBarTheme;
  CardTheme get cardTheme;
  PopupMenuThemeData get popupBtnTheme;
  ListTileThemeData get tileTheme;
  Icon get appThemeIcon;
}


class DarkTheme extends AppTheme{
  @override
  bool get isDark => true;
  @override
  Color get scaffoldBg => const Color(0xff181818);
  @override
  Color get selectScreenCardTextColor => const Color.fromARGB(255, 193, 193, 193);
  @override
  Color get selectScreenCardsBg => const Color(0xff2b2b2b);
  @override
  Color get selectScreenDrawerBg => const Color.fromARGB(255, 34, 34, 34);
  @override
  Color get editorPageToolSelectedColor => Colors.grey[400]!;
  @override
  Color get editorPageToolSelectedBgColor => const Color.fromARGB(255, 61, 61, 61);
  @override
  Color get editorPageDrawerBg => const Color(0xff2a2a2a);
  @override
  Color get editorPageToolColor => const Color(0xff6d6d6d);
  @override
  Color get editorPageToolbarBg => const Color(0xff181818);
  @override
  AppBarTheme get appBarTheme => appBarDark;
  @override
  CardTheme get cardTheme => cardDarkTheme;
  @override
  PopupMenuThemeData get popupBtnTheme => popupBtnDarkTheme;
  @override
  ListTileThemeData get tileTheme => darkTileTheme;
  @override
  Icon get appThemeIcon => const Icon(Icons.light_mode, color: Colors.grey,);
}

class LightTheme extends AppTheme{
  @override
  bool get isDark => false;
  @override
  Color get scaffoldBg => Colors.white;
  @override
  Color get selectScreenCardTextColor => const Color.fromARGB(255, 47, 47, 47);
  @override
  Color get selectScreenCardsBg => const Color.fromARGB(255, 232, 232, 232);
  @override
  Color get selectScreenDrawerBg => const Color.fromARGB(255, 255, 255, 255);
  @override
  Color get editorPageToolSelectedColor => const Color.fromARGB(255, 37, 37, 37);
  @override
  Color get editorPageToolSelectedBgColor => const Color.fromARGB(255, 186, 186, 186);
  @override
  Color get editorPageDrawerBg => const Color.fromARGB(255, 230, 230, 230);
  @override
  Color get editorPageToolColor => const Color.fromARGB(255, 151, 151, 151);
  @override
  Color get editorPageToolbarBg => Colors.white;
  @override
  AppBarTheme get appBarTheme => appBarLight;
  @override
  CardTheme get cardTheme => cardLightTheme;
  @override
  PopupMenuThemeData get popupBtnTheme => popupBtnLightTheme;
  @override
  ListTileThemeData get tileTheme => lightTileTheme;
  @override
  Icon get appThemeIcon => const Icon(Icons.dark_mode, color: Color.fromARGB(255, 36, 36, 36));
}

final Map<String, AppTheme> themeMap = {"dark": DarkTheme(), "light": LightTheme()};