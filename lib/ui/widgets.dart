import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:code_forge/code_forge.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_json/flutter_json.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:markdown_widget/config/configs.dart';
import 'package:markdown_widget/widget/all.dart';
import 'package:path/path.dart' as path;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:roxum/utils/agentic_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/repo_bloc/repo_bloc.dart';
import '../bloc/ui_bloc/ui_bloc.dart';
import '../terminal/terminal.dart';
import '../utils/ai.dart';
import '../utils/copilot_chat.dart';
import '../utils/functions.dart';
import '../utils/languages.dart';
import '../utils/themes.dart';
import '../utils/constants.dart';

Directory? _findRepoRoot(File file) {
  try {
    Directory dir = file.parent;
    while (true) {
      if (Directory(path.join(dir.path, '.git')).existsSync()) return dir;
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
  } catch (_) {}
  return null;
}

String _extractGitFilename(String gitStatusLine) {
  String fileName = gitStatusLine.substring(2).trim();

  if (fileName.startsWith('"') && fileName.endsWith('"')) {
    fileName = fileName.substring(1, fileName.length - 1);
  }

  return fileName;
}

void _refreshRepoStatusForFile(BuildContext context, File file) {
  try {
    final root = _findRepoRoot(file);
    if (root != null) {
      context.read<RepoStatusBloc>().add(LoadRepoStatus(root.path));
    }
  } catch (_) {}
}

int _lineCount(String? text) {
  if (text == null || text.isEmpty) return 0;
  return text.split('\n').length;
}

({int added, int removed}) _pendingDiffCounts(PendingEditFile? pending) {
  if (pending == null) return (added: 0, removed: 0);

  var added = 0;
  var removed = 0;
  for (final hunk in pending.editHunks) {
    if (hunk.type == 'added') {
      added += _lineCount(hunk.addedText ?? hunk.newText);
      continue;
    }
    if (hunk.type == 'removed') {
      removed += _lineCount(hunk.removedText ?? hunk.oldText);
      continue;
    }
    added += _lineCount(hunk.addedText);
    removed += _lineCount(hunk.removedText);
  }

  return (added: added, removed: removed);
}

int _lineAtOffset(String text, int offset) {
  if (text.isEmpty) return 0;
  final safeOffset = offset.clamp(0, text.length);
  return '\n'.allMatches(text.substring(0, safeOffset)).length;
}

({int start, int end}) _resolveDisplayLineRange(
  PendingEditFile pending,
  EditHunk hunk,
) {
  final needle = hunk.oldText;
  if (needle.isNotEmpty) {
    final first = pending.oldText.indexOf(needle);
    if (first >= 0) {
      final second = pending.oldText.indexOf(needle, first + 1);
      if (second == -1) {
        final start = _lineAtOffset(pending.oldText, first);
        final endOffset = (first + needle.length - 1).clamp(first, pending.oldText.length);
        final end = _lineAtOffset(pending.oldText, endOffset);
        return (start: start, end: end);
      }
    }
  }

  return (start: hunk.sourceStartLine, end: hunk.sourceEndLine);
}

Widget drawerButtons(
  VoidCallback onPressed,
  dynamic icon, {
  Color color = const Color(0xff6d6d6d),
  Color bgColor = Colors.transparent,
  EdgeInsets? padding,
}) {
  final isMaterialIcon = icon is IconData;
  final isFontAwesomeIcon = icon is FaIconData;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 15),
    child: Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      padding: padding ?? EdgeInsets.symmetric(
        horizontal: isMaterialIcon || isFontAwesomeIcon ? 4 : 2.5,
        vertical: isMaterialIcon || isFontAwesomeIcon ? 5 : 8,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: isMaterialIcon
          ? Icon(icon, color: color, size: 35)
          : isFontAwesomeIcon
            ? FaIcon(icon, color: color, size: 30)
            : (icon is Widget ? icon : Icon(Icons.help_outline, color: color)),
      ),
    ),
  );
}

Widget fileTiles(
  VoidCallback onPressed,
  String text,
  dynamic icon,
  bool isDark, {
  double val = 0,
}) {
  return Padding(
    padding: const EdgeInsets.only(left: 15),
    child: ListTile(
      onTap: onPressed,
      title: Text(
        text,
        style: TextStyle(
          color: isDark
            ? const Color.fromARGB(255, 118, 180, 234)
            : const Color.fromARGB(255, 20, 107, 183),
          fontWeight: isDark ? FontWeight.w300 : FontWeight.w400,
        ),
      ),
      leading: Padding(
        child: icon,
        padding: EdgeInsets.only(left: val),
      ),
      iconColor: const Color.fromARGB(255, 29, 107, 176),
    ),
  );
}

Widget settingsDivider = Divider(
  thickness: 0.4,
  indent: 18,
  endIndent: 18,
  color: Colors.grey,
);

Widget settingsType(String type, bool isDark) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
  child: Text(
    type,
    style: TextStyle(color: Color(isDark ? 0xffacc3fc : 0xff181a26)),
  ),
);

dynamic settingsTile(
  VoidCallback? onPressed,
  String title,
  dynamic icon,
  bool isDark, {
  String? subTitle,
  Widget? trailing,
  bool isEnabled = true,
}) {
  return ListTile(
    enabled: isEnabled,
    minVerticalPadding: 13,
    dense: true,
    onTap: onPressed,
    leading: icon,
    trailing: trailing,
    title: Text(
      title,
      style: TextStyle(
        fontSize: 17.5,
        fontWeight: isDark ? FontWeight.w400 : FontWeight.w500,
        color: isDark
          ? Colors.grey[400]
          : const Color.fromARGB(255, 93, 93, 93),
      ),
    ),
    subtitle: subTitle != null
        ? Text(
            subTitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isDark ? FontWeight.w400 : FontWeight.w500,
              color: isDark
                ? Colors.grey[400]
                : const Color.fromARGB(255, 93, 93, 93),
            ),
          )
        : null,
  );
}

Widget drawerTile(VoidCallback onPressed, String title, dynamic icon) {
  return ListTile(onTap: onPressed, title: Text(title), leading: icon);
}

Widget projectTile(
  String projectName,
  String projectDetails,
  icon,
  Color cardBg,
  VoidCallback onTap, {
  Widget? trailing,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
    child: Card(
      color: cardBg,
      child: ListTile(
        onTap: onTap,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        leading: icon,
        title: Text(projectName),
        subtitle: Text(
          projectDetails,
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: trailing,
      ),
    ),
  );
}

Widget bottomTool(
  bool isDark,
  dynamic iconData,
  VoidCallback? onPressed, [
  VoidCallback? onLongPress,
  bool isEnabled = true,
]) {
  final effectiveEnabled = isEnabled && onPressed != null;
  final iconColor = !isDark
    ? const Color.fromARGB(255, 40, 40, 40)
    : const Color.fromARGB(255, 194, 194, 194);
  final disabledColor = isDark
    ? Colors.grey.shade700
    : Colors.grey.shade500;

  return SizedBox(
    height: 37,
    width: 50,
    child: IconButton(
      highlightColor: Colors.lightBlue.withAlpha(160),
      style: ButtonStyle(
        shape: WidgetStateProperty.all(
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      ),
      padding: EdgeInsets.zero,
      onPressed: effectiveEnabled
        ? () {
            try {
              onPressed.call();
            } catch (_) {}
          }
        : null,
      
      icon: iconData is IconData ? Icon(
        iconData,
        color: effectiveEnabled ? iconColor : disabledColor,
      ) : Container(
            padding: EdgeInsets.all(5.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: effectiveEnabled
                  ? (isDark ? Colors.grey[400]! : Colors.grey)
                  : disabledColor,
                width: 0.5
              )
            ),
            child: Text(
              iconData,
              style: TextStyle(
                color: effectiveEnabled
                  ? (isDark ? Colors.grey[400]! : Colors.grey)
                  : disabledColor,
                fontSize: 12
              )
            )
      )
    ),
  );
}

class CodeEditor extends StatefulWidget {
  final File filePath;
  final CodeForgeController codeController;
  final UndoRedoController undoRedoController;
  final ScrollController hscrollController;
  final ScrollController vscrollController;
  final Language language;
  final FindController findController;
  final bool showFindPanel;
  final VoidCallback? onFindPanelClose;
  const CodeEditor({
    super.key,
    required this.codeController,
    required this.undoRedoController,
    required this.hscrollController,
    required this.vscrollController,
    required this.filePath,
    required this.language,
    required this.findController,
    this.showFindPanel = false,
    this.onFindPanelClose,
  });

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> with AutomaticKeepAliveClientMixin {
  double _initialFontSize = 10.0;
  double _currentScale = 1.0;
  Timer? _saveTimer, _statusRefreshTimer;
  Timer? _copilotDebounceTimer;
  StreamSubscription<CopilotState>? _copilotSubscription;
  String? _currentCopilotUuid;
  bool _isUpdatingGhostText = false;
  bool _awaitingManualCopilotCompletion = false;

  @override
  void initState() {
    super.initState();
    final controller = widget.codeController;
    final ext = path.extension(widget.filePath.path).toLowerCase();
    if ((ext == '.tsx' || ext == '.jsx') && controller.lspConfig == null) {
      try {
        controller.lspConfig = LspSocketConfig(
          workspacePath: widget.filePath.parent.path,
          languageId: ext.substring(1),
          serverUrl: 'ws://127.0.0.1:65535',
          disableError: true,
          disableWarning: true,
        );
      } catch (_) {}
    }
    try {
      if (controller.text.isEmpty && widget.filePath.existsSync()) {
        controller.openedFile = widget.filePath.path;
        controller.notifyListeners();
      }
    } catch (_) {
    }
    final generalState = context.read<GeneralBloc>().state;
    final configState = context.read<ConfigBloc>().state;
    
    _setupCopilotListener();
    
    controller.addListener(() {
      if (!mounted || _isUpdatingGhostText) return;

      final isManual = configState.codeForgeConfig['manualCompletion'] ?? false;
      if (!isManual && controller.lastTypedCharacter != "") {
        _requestCopilotCompletion();
      }
      
      if (generalState.generalSettings['autoSave'] ?? true) {
        _saveTimer?.cancel();
        _saveTimer = Timer(const Duration(milliseconds: 85), () {
          try {
            controller.saveFile();
          } catch (_) {}
          _statusRefreshTimer?.cancel();
          _statusRefreshTimer = Timer(const Duration(milliseconds: 400), () {
            if (mounted) {
              _refreshRepoStatusForFile(context, widget.filePath);
            }
          });
        });
      }
    });
  }

  void _setupCopilotListener() {
    final copilotBloc = context.read<CopilotBloc>();
    _copilotSubscription = copilotBloc.stream.listen((state) {
      if (!mounted) return;
      
      final completion = state.currentCompletion;
      if (_awaitingManualCopilotCompletion) {
        if (completion != null) {
          _awaitingManualCopilotCompletion = false;
        } else {
          _awaitingManualCopilotCompletion = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No completion available'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      if (completion != null && completion.uuid != _currentCopilotUuid) {
        _currentCopilotUuid = completion.uuid;
        _displayCopilotGhostText(completion);
      } else if (completion == null && _currentCopilotUuid != null) {
        _currentCopilotUuid = null;
        _isUpdatingGhostText = true;
        widget.codeController.clearGhostText();
        _isUpdatingGhostText = false;
      }
    });
  }

  void _displayCopilotGhostText(CopilotCompletionData completion) {
    final controller = widget.codeController;
    final cursor = controller.selection.start;
    final text = controller.text;
    final lines = text.substring(0, cursor).split('\n');
    final line = lines.length - 1;
    final column = lines.last.length;
    
    _isUpdatingGhostText = true;
    controller.setGhostText(GhostText(
      line: line,
      column: column,
      text: completion.displayText,
      style: TextStyle(
        color: Colors.grey.withValues(alpha: 0.6),
        fontStyle: FontStyle.italic,
      ),
      shouldPersist: false,
    ));
    _isUpdatingGhostText = false;
  }

  void _requestCopilotCompletion() {
    _copilotDebounceTimer?.cancel();
    
    final copilotBloc = context.read<CopilotBloc>();
    final state = copilotBloc.state;
    
    if (!state.isEnabled || state.status != CopilotStatus.signedIn) {
      return;
    }
    
    _copilotDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      
      _isUpdatingGhostText = true;
      widget.codeController.clearGhostText();
      _currentCopilotUuid = null;
      _isUpdatingGhostText = false;
      
      final controller = widget.codeController;
      final cursor = controller.selection.start;
      final text = controller.text;
      final lines = text.substring(0, cursor).split('\n');
      final line = lines.length - 1;
      final character = lines.last.length;
      
      copilotBloc.add(CopilotRequestCompletion(
        filePath: widget.filePath.path,
        content: text,
        line: line,
        character: character,
        languageId: widget.language.name.toLowerCase(),
      ));
    });
  }

  void requestCopilotCompletionManual() {
    final copilotBloc = context.read<CopilotBloc>();
    final state = copilotBloc.state;
    
    if (!state.isEnabled || state.status != CopilotStatus.signedIn) {
      return;
    }
    
    _isUpdatingGhostText = true;
    widget.codeController.clearGhostText();
    _currentCopilotUuid = null;
    _isUpdatingGhostText = false;
    
    final controller = widget.codeController;
    final cursor = controller.selection.start;
    final text = controller.text;
    final lines = text.substring(0, cursor).split('\n');
    final line = lines.length - 1;
    final character = lines.last.length;

    _awaitingManualCopilotCompletion = true;
    
    copilotBloc.add(CopilotRequestCompletion(
      filePath: widget.filePath.path,
      content: text,
      line: line,
      character: character,
      languageId: widget.language.name.toLowerCase(),
    ));
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _statusRefreshTimer?.cancel();
    _copilotDebounceTimer?.cancel();
    _copilotSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final codeController = widget.codeController;
    return BlocBuilder<GeneralBloc, GeneralState>(
      builder: (context, generalState) {
        return BlocBuilder<ConfigBloc, ConfigState>(
          builder: (context, configState) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: (details) {
                if (details.pointerCount == 2) {
                  _initialFontSize = configState.fontSize;
                }
              },
              onScaleUpdate: (details) {
                if (details.pointerCount == 2) {
                  _currentScale = details.scale;
                  double newFontSize = _initialFontSize * _currentScale;
                  newFontSize = newFontSize.clamp(8.0, 48.0);
                  context.read<ConfigBloc>().add(
                    SetFontSize(fontSize: newFontSize),
                  );
                }
              },
              child: BlocBuilder<AIBloc, AIState>(
                builder: (context, aiState) {
                  final ext = path.extension(widget.filePath.path).toLowerCase();
                  final primaryMode = widget.language.language;

                  return CodeForge(
                    key: ValueKey('${widget.filePath.path}:${widget.language.name}'),
                    horizontalScrollController: null,
                    verticalScrollController: null,
                    lineWrap: (configState.codeForgeConfig['lineWrap'] ?? false) as bool,
                    enableFolding: (configState.codeForgeConfig['enableFolding'] ?? true) as bool,
                    language: primaryMode,
                    extraLanguages: (() {
                      if (ext == '.tsx' || ext == '.jsx') {
                        final Mode? xmlMode = langxml.language;
                        if (xmlMode != null) {
                          return <Mode>[xmlMode];
                        }
                      }
                      return const <Mode>[];
                    })(),
                    customCodeSnippets: widget.language.customCodeSnippet,
                    filePath: widget.filePath.path,
                    enableGuideLines: (configState.codeForgeConfig['indentLineStatus'] ?? true) as bool,
                    selectionStyle: CodeSelectionStyle(
                      selectionColor: Colors.blueAccent.withAlpha(80),
                      cursorBubbleColor: Colors.blue,
                    ),
                    matchHighlightStyle: const MatchHighlightStyle(
                      currentMatchStyle: TextStyle(backgroundColor: Color(0xFFFFA726)),
                      otherMatchStyle: TextStyle(backgroundColor: Color(0x55FFFF00)),
                    ),
                    editorTheme: getMergedHighlightThemes(configState.codeForgeConfig)[configState.codeForgeConfig['theme']],
                    textStyle: TextStyle(
                      fontFamily: configState.codeForgeConfig['fontFamily'],
                      fontSize: configState.fontSize,
                    ),
                    controller: codeController,
                    undoController: widget.undoRedoController,
                    findController: widget.findController,
                    finderBuilder: (context, findController) {
                      return FindPanelWidget(
                        controller: findController,
                        onClose: widget.onFindPanelClose,
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

const double _kFindPanelWidth = 380, _kFindPanelHeight = 36;
const double _kReplacePanelHeight = _kFindPanelHeight * 2;
const double _kFindIconSize = 18;
const double _kFindInputFontSize = 13, _kFindResultFontSize = 11;

class FindPanelWidget extends StatelessWidget implements PreferredSizeWidget {
  final FindController controller;
  final VoidCallback? onClose;

  const FindPanelWidget({super.key, required this.controller, this.onClose});

  @override
  Size get preferredSize => Size(
    double.infinity,
    !controller.isActive ? 0 : (controller.isReplaceMode ? _kReplacePanelHeight : _kFindPanelHeight + 2) + 10,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        if (!controller.isActive) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(right: 8, top: 4),
          alignment: Alignment.topRight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (n, e) {
                if (e.logicalKey == LogicalKeyboardKey.escape) {
                  controller.isActive = false;
                  onClose?.call();
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.tab &&
                    controller.isReplaceMode &&
                    controller.findInputFocusNode.hasFocus) {
                  controller.replaceInputFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                width: _kFindPanelWidth,
                decoration: BoxDecoration(
                  color: const Color(0xff252526),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(80),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        controller.isReplaceMode
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        color: Colors.grey[400],
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(
                        maxWidth: 22,
                        minHeight: preferredSize.height,
                        maxHeight: preferredSize.height,
                      ),
                      tooltip: 'Toggle Replace',
                      onPressed: controller.toggleReplaceMode,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFindRow(context),
                          if (controller.isReplaceMode)
                            _buildReplaceRow(context),
                          if (!controller.isReplaceMode)
                            const SizedBox(height: 2),
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
    );
  }

  Widget _buildFindRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: _kFindPanelHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildTextField(
                  focusNode: controller.findInputFocusNode,
                  controller: controller.findInputController,
                  iconsWidth: 60,
                  padding: const EdgeInsets.only(
                    left: 3,
                    right: 5,
                    top: 4,
                    bottom: 2,
                  ),
                  hintText: 'Find',
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildCheckText(
                      context: context,
                      text: 'Aa',
                      tooltip: 'Match Case',
                      checked: controller.caseSensitive,
                      onPressed: controller.toggleCaseSensitive,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: _buildCheckText(
                        context: context,
                        text: 'W',
                        tooltip: 'Match Whole Word',
                        checked: controller.matchWholeWord,
                        onPressed: controller.toggleMatchWholeWord,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildCheckText(
                        context: context,
                        text: '\u2022\u2731',
                        tooltip: 'Use Regular Expression',
                        checked: controller.isRegex,
                        onPressed: controller.toggleRegex,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _buildResultText(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIconButton(
              icon: Icons.arrow_upward,
              tooltip: 'Previous (Shift+Enter)',
              onPressed: controller.matchCount == 0
                  ? null
                  : controller.previous,
            ),
            _buildIconButton(
              icon: Icons.arrow_downward,
              tooltip: 'Next (Enter)',
              onPressed: controller.matchCount == 0 ? null : controller.next,
            ),
            _buildIconButton(
              icon: Icons.close,
              tooltip: 'Close (Escape)',
              onPressed: () {
                controller.toggleActive();
                onClose?.call();
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
      ],
    );
  }

  Widget _buildReplaceRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: _kFindPanelHeight,
            child: _buildTextField(
              focusNode: controller.replaceInputFocusNode,
              controller: controller.replaceInputController,
              padding: const EdgeInsets.only(
                left: 3,
                right: 5,
                top: 2,
                bottom: 4,
              ),
              hintText: 'Replace',
              onSubmit: (_) {
                controller.replace();
                controller.replaceInputFocusNode.requestFocus();
              },
            ),
          ),
        ),
        _buildIconButton(
          icon: Icons.done,
          tooltip: 'Replace',
          onPressed: controller.matchCount == 0 ? null : controller.replace,
        ),
        _buildIconButton(
          icon: Icons.done_all,
          tooltip: 'Replace All',
          onPressed: controller.matchCount == 0 ? null : controller.replaceAll,
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    double iconsWidth = 0,
    EdgeInsets padding = EdgeInsets.zero,
    String? hintText,
    ValueChanged<String>? onSubmit,
  }) {
    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        maxLines: 1,
        focusNode: focusNode,
        autofocus: false,
        style: const TextStyle(
          fontSize: _kFindInputFontSize,
          color: Colors.white,
        ),
        onSubmitted: onSubmit,
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xff3c3c3c),
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.grey[600],
            fontSize: _kFindInputFontSize,
          ),
          contentPadding: EdgeInsets.fromLTRB(8, 5, iconsWidth, 5),
          enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(width: 0.5, color: Colors.grey[700]!),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(width: 1, color: Color(0xff0178b9)),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckText({
    required BuildContext context,
    required String text,
    required String tooltip,
    required bool checked,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              text,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _kFindInputFontSize,
                color: checked ? const Color(0xff0178b9) : Colors.grey[500],
                fontWeight: checked ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    VoidCallback? onPressed,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: _kFindIconSize,
            color: onPressed != null ? Colors.grey[400] : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _buildResultText() {
    final text = controller.matchCount == 0
        ? 'No results'
        : '${controller.currentMatchIndex + 1}/${controller.matchCount}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: _kFindResultFontSize,
          color: controller.matchCount == 0
              ? Colors.red[300]
              : Colors.grey[400],
        ),
      ),
    );
  }
}

class EditorArea extends StatefulWidget {
  final ActiveEditor editor;
  final AppTheme appTheme;
  final String workspacePath;
  final TabController? tabController;
  const EditorArea({
    super.key,
    required this.editor,
    required this.appTheme,
    required this.workspacePath,
    this.tabController,
  });

  @override
  State<EditorArea> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorArea> with AutomaticKeepAliveClientMixin {
  late final ActiveEditor editor;
  late final AppTheme appTheme;
  late final CodeForgeController controller;
  late final UndoRedoController undoRedoController;
  late Language language;
  late final File file;
  late final String ext;
  final GlobalKey<_CodeEditorState> _editorKey = GlobalKey();
  final cursor = ValueNotifier<({int line, int col})>((line: 0, col: 0));
  final isGeneratingCompletion = ValueNotifier<bool>(false);
  PendingEditFile? _pendingEdits;
  bool _isApplyingPendingAction = false;
  Timer? _pendingRefreshTimer;

  String _lspLanguageIdForPath(Language lang, String filePath) {
    return lspLanguageIdForFile(language: lang, filePath: filePath);
  }

  ({int line, int col}) _lineAndColumnAtCursor(CodeForgeController targetController) {
    final offset = targetController.selection.extentOffset.clamp(0, targetController.length);
    final line = targetController.getLineAtOffset(offset);
    final lineStartOffset = targetController.findLineStart(offset);
    final col = offset - lineStartOffset;
    return (line: line, col: col);
  }

  double _languageDropdownWidth(BuildContext context) {
    const fontSize = 11.0;
    final style = TextStyle(
      color: appTheme.selectScreenCardTextColor,
      fontSize: fontSize,
    );
    final painter = TextPainter(
      text: TextSpan(text: language.name, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();

    const chromeWidth = 28.0;
    const horizontalPadding = 10.0;
    return painter.width + chromeWidth + horizontalPadding;
  }

  Future<void> _overrideLanguage(Language selectedLanguage) async {
    if (selectedLanguage.name == language.name) return;

    final activeEditorBloc = context.read<ActiveEditorBloc>();
    final codeForgeConfig = context.read<ConfigBloc>().state.codeForgeConfig;

    LspConfig? nextLspConfig;
    if (codeForgeConfig['enableLSP'] == true) {
      nextLspConfig = await activeEditorBloc.getOrStartSharedLspConfig(
        languageId: _lspLanguageIdForPath(selectedLanguage, file.path),
        ext: lspServerExtForFilePath(file.path),
        executable: selectedLanguage.lspExecutable,
        args: selectedLanguage.args ?? const [],
      );
    }

    if (!mounted) return;

    final currentEditors = List<ActiveEditor>.from(activeEditorBloc.state.activeEditors);
    final currentPath = File(file.path).absolute.path;
    final index = currentEditors.indexWhere(
      (item) => File(item.file.path).absolute.path == currentPath,
    );

    if (index >= 0) {
      final existing = currentEditors[index];
      currentEditors[index] = ActiveEditor(
        file: existing.file,
        controller: existing.controller,
        languageDetails: selectedLanguage,
        undoRedoController: existing.undoRedoController,
        hscroll: existing.hscroll,
        vscroll: existing.vscroll,
        isActive: existing.isActive,
        findController: existing.findController,
        customTitle: existing.customTitle,
      );
      activeEditorBloc.add(ActiveEditorEvent(currentEditors));
    }

    setState(() {
      language = selectedLanguage;
      controller.lspConfig = nextLspConfig;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.focusNode?.requestFocus();
    });
  }

  @override
  void initState() {
    editor = widget.editor;
    appTheme = widget.appTheme;
    controller = editor.controller;
    undoRedoController = editor.undoRedoController;
    language = editor.languageDetails;
    file = editor.file;
    ext = path.extension(file.path);
    _reloadPendingEdits();
    _pendingRefreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _reloadPendingEdits(silent: true),
    );

    controller.addListener((){
      if(!mounted || !context.mounted || !controller.selection.isValid) return;
      cursor.value = _lineAndColumnAtCursor(controller);
    });
    super.initState();
  }

  @override
  void didUpdateWidget(covariant EditorArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor.file.path != widget.editor.file.path) {
      _reloadPendingEdits();
    }
  }

  Future<void> _reloadPendingEdits({bool silent = false}) async {
    final pending = await PendingEditFile.getForFile(File(file.path).absolute.path);
    if (!mounted) return;
    if (silent && _pendingEdits?.editHunks.length == pending?.editHunks.length) {
      return;
    }
    setState(() {
      _pendingEdits = pending;
    });
  }

  Future<void> _keepHunk(EditHunk hunk) async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    await tools.keepPendingEditHunk(file.path, hunk.id);
    await _reloadPendingEdits();
    if (mounted) {
      setState(() => _isApplyingPendingAction = false);
    }
  }

  Future<void> _rejectHunk(EditHunk hunk) async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    final result = await tools.rejectPendingEditHunk(file.path, hunk.id);
    await _reloadPendingEdits();
    if (mounted) {
      setState(() => _isApplyingPendingAction = false);
      if (!result.success && result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error!)),
        );
      }
    }
  }

  Future<void> _keepAll() async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    await tools.keepAllPendingEdits(file.path);
    await _reloadPendingEdits();
    if (mounted) setState(() => _isApplyingPendingAction = false);
  }

  Future<void> _rejectAll() async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    final result = await tools.rejectAllPendingEdits(file.path);
    await _reloadPendingEdits();
    if (mounted) {
      setState(() => _isApplyingPendingAction = false);
      if (!result.success && result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error!)),
        );
      }
    }
  }

  Future<void> _applyPendingAgenticDiffForFile(
    CodeForgeController targetController,
    String filePath,
  ) async {
    try {
      final canonicalPath = File(filePath).absolute.path;
      final pending = await PendingEditFile.getForFile(canonicalPath);
      if (!mounted) return;
      if (pending == null || pending.editHunks.isEmpty) return;
      pending.applyDecorations(targetController);
    } catch (_) {}
  }

  ButtonStyle _pendingActionStyle({bool destructive = false}) {
    final accent = destructive
        ? const Color(0xFFC62828)
        : (appTheme.isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32));
    return OutlinedButton.styleFrom(
      foregroundColor: accent,
      side: BorderSide(color: accent.withValues(alpha: 0.75)),
      backgroundColor: accent.withValues(alpha: appTheme.isDark ? 0.12 : 0.08),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    );
  }

  Widget? _buildPendingDiffPanel() {
    final pending = _pendingEdits;
    if (pending == null || pending.editHunks.isEmpty) {
      return null;
    }
    final counts = _pendingDiffCounts(pending);

    return Positioned(
      right: 10,
      bottom: 10,
      child: Container(
        width: 310,
        constraints: const BoxConstraints(maxHeight: 250),
        decoration: BoxDecoration(
          color: appTheme.isDark ? const Color(0xff1f1f1f) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.compare_arrows, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Pending Diff',
                    style: TextStyle(
                      color: appTheme.selectScreenCardTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '+${counts.added}',
                    style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '-${counts.removed}',
                    style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: pending.editHunks.length,
                  itemBuilder: (context, index) {
                    final hunk = pending.editHunks[index];
                    final displayRange = _resolveDisplayLineRange(pending, hunk);
                    final lineLabel = hunk.type == 'removed'
                      ? 'After L${displayRange.start + 1}'
                      : 'L${displayRange.start + 1}-${displayRange.end + 1}';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      decoration: BoxDecoration(
                        color: appTheme.isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$lineLabel ${hunk.type}',
                              style: TextStyle(
                                color: appTheme.selectScreenCardTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          OutlinedButton(
                            style: _pendingActionStyle(),
                            onPressed: _isApplyingPendingAction ? null : () => _keepHunk(hunk),
                            child: const Text('Keep'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            style: _pendingActionStyle(destructive: true),
                            onPressed: _isApplyingPendingAction ? null : () => _rejectHunk(hunk),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    style: _pendingActionStyle(),
                    onPressed: _isApplyingPendingAction ? null : _keepAll,
                    child: const Text('Keep all'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: _pendingActionStyle(destructive: true),
                    onPressed: _isApplyingPendingAction ? null : _rejectAll,
                    child: const Text('Reject all'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestExternalModelCompletion() async {
    final aiState = context.read<AIBloc>().state;
    final completionModel = aiState.completionModel;
    if (completionModel == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected completion model is not configured correctly.')),
      );
      return;
    }

    final text = controller.text;
    final cursorOffset = controller.selection.start.clamp(0, text.length);
    final cursorLine = controller.getLineAtOffset(cursorOffset);
    final lineStartOffset = controller.findLineStart(cursorOffset);
    final beforeCursor = text.substring(0, cursorOffset);
    final cursorColumn = cursorOffset - lineStartOffset;

    final prompt = '''Language: ${language.name}\nFile: ${file.path}\nCode:\n$beforeCursor<|CURSOR|>${text.substring(cursorOffset)}''';

    try {
      if (completionModel is LocalLlama) {
        final llamaBloc = context.read<LocalLlamaBloc>();
        if (llamaBloc.state.loadedModelPath != completionModel.modelPath ||
            !llamaBloc.state.isReady) {
          llamaBloc.add(LocalLlamaLoadModel(completionModel));
          await llamaBloc.stream.firstWhere(
            (s) => s.status == LocalLlamaStatus.ready || s.status == LocalLlamaStatus.error,
          );
          if (llamaBloc.state.status == LocalLlamaStatus.error) {
            throw Exception('Failed to load model: ${llamaBloc.state.error}');
          }
        }
        final llamaController = llamaBloc.controller;
        if (llamaController == null) throw Exception('Llama controller is null');

        final buffer = StringBuffer();
        isGeneratingCompletion.value = true;
        await for (final token in llamaController.generate(
          prompt: "${Models.instruction}\n\n$prompt",
          maxTokens: completionModel.maxTokens,
          temperature: completionModel.temperature,
          topP: completionModel.topP,
          topK: completionModel.topK,
          repeatPenalty: completionModel.repeatPenalty,
          frequencyPenalty: completionModel.frequencyPenalty,
          presencePenalty: completionModel.presencePenalty,
          repeatLastN: completionModel.repeatLastN,
          seed: completionModel.seed,
          mirostat: completionModel.mirostat,
          mirostatTau: completionModel.mirostatTau,
          mirostatEta: completionModel.mirostatEta,
        )) {
          buffer.write(token);
          controller.setGhostText(GhostText(
            line: cursorLine,
            column: cursorColumn,
            text: buffer.toString(),
            style: TextStyle(
            color: Colors.grey.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ));
        }
        isGeneratingCompletion.value = false;
        return;
      }

      isGeneratingCompletion.value = true;
      final suggestion = await completionModel.completionResponse(prompt);
      isGeneratingCompletion.value = false;

      if (!mounted) return;
      if (suggestion.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No completion available for this position.')),
        );
        return;
      }

      controller.clearGhostText();
      controller.setGhostText(
        GhostText(
          line: cursorLine,
          column: cursorColumn,
          text: suggestion,
          style: TextStyle(
            color: Colors.grey.withValues(alpha: 0.6),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Completion request failed: $e'), duration: const Duration(seconds: 3)),
      );
    } finally {
      isGeneratingCompletion.value = false;
    }
  }

  @override
  void dispose() {
    _pendingRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sctrl = ScrollController();
    super.build(context);
    final codeForgeConfig = context.watch<ConfigBloc>().state.codeForgeConfig;
    final activeEditorBloc = context.watch<ActiveEditorBloc>();
    final lspLanguageId = _lspLanguageIdForPath(language, file.path);
    final lspCacheKey = ActiveEditorBloc.buildLspCacheKey(
      workspacePath: widget.workspacePath,
      languageId: lspLanguageId,
    );
    final lspExt = language.extension.isNotEmpty
        ? language.extension[0]
        : path.extension(file.path).replaceFirst('.', '');
    final isLspServerInstalled = isLspServerAvailable(
      ext: lspExt,
      executable: language.lspExecutable,
      args: language.args ?? const [],
    );
    final workspaceLspConfig = activeEditorBloc.sharedLspConfigs[lspCacheKey];
    final isWorkspaceLspRunning =
        workspaceLspConfig != null && workspaceLspConfig == controller.lspConfig;
    final lspEnabled = (codeForgeConfig['enableLSP'] ?? false) == true;
    final lspFeatureToggle = Map<String, dynamic>.from(
      codeForgeConfig['LSPFeatureToggle'] ?? {},
    );
    final disabledLspFeatures = List<String>.from(
      lspFeatureToggle[language.name.toLowerCase()] ?? const [],
    );
    bool isLspFeatureEnabled(String feature) {
      if (!lspEnabled || !isLspServerInstalled || !isWorkspaceLspRunning) {
        return false;
      }
      return !disabledLspFeatures.contains(feature);
    }

    final codeActionEnabled = isLspFeatureEnabled('codeAction');
    final inlayHintEnabled = isLspFeatureEnabled('inlayHint');
    final goToDefinitionEnabled = isLspFeatureEnabled('goToDefinition');
    final signatureHelpEnabled = isLspFeatureEnabled('signatureHelp');

    final pageContent = Column(
      children: [
        Expanded(
          child: Builder(
            builder: (context) {
              final pendingPanel = _buildPendingDiffPanel();
              return Stack(
                children: [
                  CodeEditor(
                    key: _editorKey,
                    language: language,
                    undoRedoController: undoRedoController,
                    codeController: controller,
                    filePath: editor.file,
                    findController: editor.findController!,
                    hscrollController: editor.hscroll,
                    vscrollController: editor.vscroll,
                  ),
                  ?pendingPanel,
                ],
              );
            },
          ),
        ),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: appTheme.isDark
                ? const Color.fromARGB(255, 25, 25, 25)
                : const Color.fromARGB(255, 236, 236, 236),
            border: Border(
              top: BorderSide(color: Colors.grey.withValues(alpha: 0.3), width: 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: .end,
            children: [
              ValueListenableBuilder(
                valueListenable: cursor,
                builder: (_, lineColValue, _) {
                  return Text(
                    'Ln ${lineColValue.line + 1}, Col ${lineColValue.col + 1}',
                    style: TextStyle(
                      color: appTheme.selectScreenCardTextColor,
                      fontSize: 11,
                    ),
                  );
                }
              ),
              const SizedBox(width: 20),
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: SizedBox(
                  width: _languageDropdownWidth(context),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Language>(
                      dropdownColor: appTheme.editorPageDrawerBg,
                      isDense: true,
                      isExpanded: true,
                      value: language,
                      iconSize: 16,
                      style: TextStyle(
                        color: appTheme.selectScreenCardTextColor,
                        fontSize: 11,
                      ),
                      items: languages.map((lang) {
                        return DropdownMenuItem<Language>(
                          value: lang,
                          child: Row(
                            spacing: 3,
                            children: [
                              SizedBox(
                                height:14,
                                width: 14,
                                child: lang.icon
                              ),
                              Text(
                                lang.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        _overrideLanguage(value);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: .centerEnd,
          child: ValueListenableBuilder(
            valueListenable: isGeneratingCompletion,
            builder:(context, aiValue, _) => aiValue ? Padding(
              padding: const EdgeInsets.only(right: 7, bottom: 7),
              child: Container(
                height: 50,
                width: 300,
                decoration: BoxDecoration(
                  color: appTheme.selectScreenDrawerBg,
                  borderRadius: .circular(10)
                ),
                child: Column(
                  children: [
                    Expanded(
                      flex: 15,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Row(
                          spacing: 8,
                          children: [
                            Icon(
                              Icons.info_outlined,
                              color: Colors.blue
                            ),
                            Expanded(
                              child: Text(
                                "Generating...",
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor
                                )
                              )
                            ),
                          ]
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: LinearProgressIndicator(
                          borderRadius: .circular(5)
                        ),
                      )
                    )
                  ]
                )
              ),
            ) : SizedBox.shrink(),
          ),
        ),
        RawScrollbar(
          controller: sctrl,
          scrollbarOrientation: ScrollbarOrientation.top,
          thumbColor: appTheme.selectScreenCardTextColor.withAlpha(50),
          interactive: false,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: SingleChildScrollView(
            controller: sctrl,
            padding: EdgeInsets.zero,
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 78,
                  color: appTheme.isDark
                    ? const Color.fromARGB(255, 32, 32, 32)
                    : const Color.fromARGB(255, 219, 218, 218),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            height: 37,
                            width: 50,
                            child: Tooltip(
                              message: "tab",
                              child: IconButton(
                                highlightColor: Colors.lightBlue.withAlpha(160),
                                style: ButtonStyle(
                                  shape: WidgetStateProperty.all(
                                    const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(10)),
                                    ),
                                  ),
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  final ghostText = controller.ghostText;
                                  if(ghostText != null){
                                    controller.insertText(ghostText.text, ghostText.line, ghostText.column);
                                    controller.clearGhostText();
                                  } else {
                                    controller.indent();
                                  }
                                },
                                icon: SvgPicture.asset(
                                  "assets/icons/tab.svg",
                                  height: 25,
                                  width: 25,
                                  colorFilter: ColorFilter.mode(
                                    appTheme.isDark
                                      ? const Color.fromARGB(255, 194, 194, 194)
                                      : const Color.fromARGB(255, 40, 40, 40),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Tooltip(
                            message: "undo",
                            child: AnimatedBuilder(
                              animation: undoRedoController,
                              builder: (context, _) {
                                return bottomTool(
                                  appTheme.isDark,
                                  Icons.undo,
                                  undoRedoController.undo,
                                  null,
                                  undoRedoController.canUndo,
                                );
                              },
                            ),
                          ),
                          Tooltip(
                            message: "redo",
                            child: AnimatedBuilder(
                              animation: undoRedoController,
                              builder: (context, _) {
                                return bottomTool(
                                  appTheme.isDark,
                                  Icons.redo,
                                  undoRedoController.redo,
                                  null,
                                  undoRedoController.canRedo,
                                );
                              },
                            ),
                          ),
                          Tooltip(
                            message: "upward",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.arrow_upward,
                              controller.pressUpArrowKey,
                            ),
                          ),
                          Tooltip(
                            message: "request ai completion",
                            child: SizedBox(
                              height: 37,
                              width: 50,
                              child: IconButton(
                                highlightColor: Colors.lightBlue.withAlpha(160),
                                style: ButtonStyle(
                                  shape: WidgetStateProperty.all(
                                    const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(10)),
                                    ),
                                  ),
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () async {
                                  final String? codeModel = context.read<AIBloc>().state.modelSelected['code'];
                                  if (codeModel != null && codeModel.isNotEmpty && context.read<AIBloc>().state.isEnabled) {
                                    if(codeModel == "copilot"){
                                      _editorKey.currentState?.requestCopilotCompletionManual();
                                    } else {
                                      await _requestExternalModelCompletion();
                                    }
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                          "No completion model found. Configure one in the settings",
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                icon: SvgPicture.asset(
                                  "assets/icons/ai.svg",
                                  height: 25,
                                  width: 25,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Tooltip(
                            message: "zoom in",
                            child: bottomTool(appTheme.isDark, Icons.zoom_in, () {
                              double currentFontSize = context.read<ConfigBloc>().state.fontSize;
                              context.read<ConfigBloc>().add(SetFontSize(fontSize: currentFontSize * 1.15));
                            }),
                          ),
                          Tooltip(
                            message: "zoom out",
                            child: bottomTool(appTheme.isDark, Icons.zoom_out, () {
                              double currentFontSize = context.read<ConfigBloc>().state.fontSize;
                              context.read<ConfigBloc>().add(SetFontSize(fontSize: currentFontSize * 0.9));
                            }),
                          ),
                          Tooltip(
                            message: "backward",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.arrow_back,
                              controller.pressLetfArrowKey,
                            ),
                          ),
                          Tooltip(
                            message: "downward",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.arrow_downward,
                              controller.pressDownArrowKey,
                            ),
                          ),
                          Tooltip(
                            message: "forward",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.arrow_forward,
                              controller.pressRightArrowKey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 78,
                  color: appTheme.isDark
                    ? const Color.fromARGB(255, 32, 32, 32)
                    : const Color.fromARGB(255, 219, 218, 218),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Tooltip(
                            message: "code actions",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.lightbulb,
                              (){
                                controller.getCodeAction();
                              },
                              null,
                              codeActionEnabled,
                            ),
                          ),
                          Tooltip(
                            message: "inlay hints",
                            child: SizedBox(
                              height: 37,
                              width: 50,
                              child: InkWell(
                                onTap: inlayHintEnabled
                                  ? (){
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: appTheme.cardTheme.color,
                                      content: Padding(
                                        padding: const EdgeInsets.only(left: 10),
                                        child: Row(
                                          spacing: 7, 
                                          children: [
                                            Icon(Icons.info_outline_rounded, color: Colors.blueAccent),
                                            Text("Hold down to see inlay hints")
                                          ]
                                        ),
                                      )
                                    )
                                  );
                                } : null,
                                onLongPress: inlayHintEnabled ? controller.showInlayHints : null,
                                onLongPressUp: inlayHintEnabled ? controller.hideInlayHints : null,
                                child: Icon(
                                  Icons.highlight_outlined,
                                  color: inlayHintEnabled
                                    ? (!appTheme.isDark
                                        ? const Color.fromARGB(255, 40, 40, 40)
                                        : const Color.fromARGB(255, 194, 194, 194))
                                    : (appTheme.isDark ? Colors.grey.shade700 : Colors.grey.shade500),
                                )
                              ),
                            ),
                          ),
                          
                          Tooltip(
                            message: "go to defenition",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.devices_fold_outlined,
                              () async{
                                if(controller.lspConfig == null || controller.openedFile == null) return;
                                final cursorOffset = controller.selection.extentOffset.clamp(0, controller.length);
                                final line = controller.getLineAtOffset(cursorOffset);
                                final lineText = controller.getLineText(line);
                                final lineStartOffset = controller.findLineStart(cursorOffset);
                                final character = (cursorOffset - lineStartOffset).clamp(0, lineText.length);

                                Map<String, dynamic> def = {};
                                try {
                                  def = await controller.lspConfig!.getDefinition(
                                    controller.openedFile!,
                                    line,
                                    character,
                                  );
                                } catch (_) {
                                  def = {};
                                }
                            
                                final String? defFile = def["uri"];
                                if (defFile != null){
                                  if(!context.mounted) return;
                                  final defPath = File(Uri.parse(defFile).toFilePath()).absolute.path;
                                  if(defPath == controller.openedFile){
                                    final int? line = def["range"]?["start"]?["line"];
                                    if(line != null){
                                      controller.scrollToLine(line);
                                    }
                                  } else {
                                    final int? line = def["range"]?["start"]?["line"];
                                    final activeEditorBloc = context.read<ActiveEditorBloc>();
                                    final currentState = List<ActiveEditor>.from(
                                      activeEditorBloc.state.activeEditors,
                                    );
                            
                                    final existingIndex = currentState.indexWhere(
                                      (item) => File(item.file.path).absolute.path == defPath,
                                    );
                            
                                    if (existingIndex >= 0) {
                                      for (var i = 0; i < currentState.length; i++) {
                                        currentState[i].isActive = i == existingIndex;
                                      }
                                      activeEditorBloc.add(ActiveEditorEvent(currentState));
                            
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        final tabController = widget.tabController;
                                        if (tabController != null && existingIndex < tabController.length) {
                                          tabController.animateTo(existingIndex);
                                        }
                                        if (line != null) {
                                          currentState[existingIndex].controller.scrollToLine(line);
                                        }
                                      });
                                    } else {
                                      final targetFile = File(defPath);
                                      if (!targetFile.existsSync()) return;
                            
                                      for (final item in currentState) {
                                        item.isActive = false;
                                      }
                            
                                      final lang = languages.firstWhere(
                                        (language) => language.extension.contains(
                                          path.extension(targetFile.path).replaceFirst(".", ""),
                                        ),
                                        orElse: () => languages[0],
                                      );
                            
                                      final config = context.read<ConfigBloc>().state.codeForgeConfig;
                                      LspConfig? lspConfig;
                                      if (config['enableLSP']) {
                                        lspConfig = await activeEditorBloc.getOrStartSharedLspConfig(
                                          languageId: _lspLanguageIdForPath(lang, targetFile.path),
                                          ext: lspServerExtForFilePath(targetFile.path),
                                          executable: lang.lspExecutable,
                                          args: lang.args ?? [],
                                        );
                                      }
                            
                                      final newController = CodeForgeController(lspConfig: lspConfig);
                                      await _applyPendingAgenticDiffForFile(newController, targetFile.path);
                                      final newEditor = ActiveEditor(
                                        file: targetFile,
                                        controller: newController,
                                        languageDetails: lang,
                                        undoRedoController: UndoRedoController(),
                                        hscroll: ScrollController(),
                                        vscroll: ScrollController(),
                                        isActive: true,
                                        findController: FindController(newController),
                                      );
                            
                                      currentState.add(newEditor);
                                      activeEditorBloc.add(ActiveEditorEvent(currentState));
                            
                                      final newIndex = currentState.length - 1;
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        final tabController = widget.tabController;
                                        if (tabController != null && newIndex < tabController.length) {
                                          tabController.animateTo(newIndex);
                                        }
                                        if (line != null) {
                                          Future.delayed(const Duration(milliseconds: 100), () {
                                            if (!mounted) return;
                                            newEditor.controller.scrollToLine(line);
                                          });
                                        }
                                      });
                                    }
                                  }
                                }
                              },
                              null,
                              goToDefinitionEnabled,
                            ),
                          ),
                          Tooltip(
                            message: "home key",
                            child: bottomTool(
                              appTheme.isDark,
                              "Home",
                              controller.pressHomeKey
                            ),
                          ),
                          Tooltip(
                            message: "end key",
                            child: bottomTool(
                              appTheme.isDark,
                              "End",
                              controller.pressEndKey
                            ),
                          )
                        ],
                      ),
                      Row(
                        children: [
                          Tooltip(
                            message: "move line up",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.keyboard_double_arrow_up_outlined,
                              controller.moveLineUp
                            ),
                          ),

                          Tooltip(
                            message: "move line down",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.keyboard_double_arrow_down_outlined,
                              controller.moveLineDown
                            ),
                          ),

                          Tooltip(
                            message: "duplicate selection",
                            child: bottomTool(
                              appTheme.isDark,
                              "Dup",
                              controller.duplicateLine
                            ),
                          ),

                          Tooltip(
                            message: "signature help",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.signpost,
                              () => controller.callSignatureHelp(),
                              null,
                              signatureHelpEnabled,
                            ),
                          ),

                          Tooltip(
                            message: "highlight current line",
                            child: bottomTool(
                              appTheme.isDark,
                              Icons.format_paint,
                              (){
                                final line = controller.getLineAtOffset(controller.selection.extentOffset);
                            
                                if(controller.lineDecorations.any((l) => l.id == line.toString())){
                                  final decoratedId = controller.lineDecorations.singleWhere((l) => l.id == line.toString()).id;
                                  controller.removeLineDecoration(decoratedId);
                                  controller.removeGutterDecoration(decoratedId);
                                  return;
                                }
                            
                                controller.addLineDecoration(
                                  LineDecoration(
                                    id: line.toString(),
                                    startLine: line,
                                    endLine: controller.getLineAtOffset(controller.selection.extentOffset),
                                    type: LineDecorationType.background,
                                    color: Colors.blue.withAlpha(95)
                                  )
                                );
                            
                                controller.addGutterDecoration(
                                  GutterDecoration(
                                    id: line.toString(),
                                    startLine: line,
                                    endLine: controller.getLineAtOffset(controller.selection.extentOffset),
                                    type: GutterDecorationType.dot,
                                    color: Colors.blue
                                  )
                                );
                              }
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ],
    );
    return pageContent;
  }

  @override
  bool get wantKeepAlive => true;
}

class DirectoryTreeViewerCustom extends StatefulWidget {
  final String rootPath;
  final bool isUnfoldedFirst;
  final bool enableCreateFolderOption;
  final bool enableCreateFileOption;
  final bool enableDeleteFolderOption;
  final bool enableDeleteFileOption;
  final bool enableRenameFolderOption;
  final bool enableRenameFileOption;
  final bool enableGitFeatures;
  final FolderStyle? folderStyle;
  final FileStyle? fileStyle;
  final EditingFieldStyle? editingFieldStyle;
  final void Function(File)? onFileTap;
  final List<Widget>? folderActions;
  final List<Widget>? fileActions;
  final Widget Function(String fileExtension)? fileIconBuilder;
  final AppTheme appTheme;
  final ActiveEditorState? activeEditorState;

  const DirectoryTreeViewerCustom({
    super.key,
    required this.rootPath,
    required this.appTheme,
    this.onFileTap,
    this.folderActions,
    this.fileActions,
    this.folderStyle,
    this.fileStyle,
    this.isUnfoldedFirst = true,
    this.editingFieldStyle,
    this.enableCreateFileOption = false,
    this.enableCreateFolderOption = false,
    this.enableDeleteFileOption = false,
    this.enableDeleteFolderOption = false,
    this.enableRenameFolderOption = false,
    this.enableRenameFileOption = false,
    this.enableGitFeatures = false,
    this.fileIconBuilder,
    this.activeEditorState,
  });

  @override
  State<DirectoryTreeViewerCustom> createState() => _DirectoryTreeViewerState();
}

class _DirectoryTreeViewerState extends State<DirectoryTreeViewerCustom> {
  static const double _guideIndentWidth = 14;
  static const double _guideRowHeight = 30;

  String? newEntryPath;
  String? renamingPath;
  bool isFolderCreation = false;
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _renameController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _renameController.dispose();
    super.dispose();
  }

  (Color, String?) _getFileColor(File file, RepoStatusState repoState, String? highlightedPath) {
    final isHighlighted = highlightedPath != null && path.normalize(file.path) == path.normalize(highlightedPath);
    final defaultColor = !isHighlighted
      ? widget.appTheme.selectScreenCardTextColor
      : widget.appTheme.isDark ? Colors.blue[200]! : Colors.blue[600]!;
    if (repoState is! RepoStatusLoaded) return (defaultColor, null);
    final relativePath = path.relative(file.path, from: widget.rootPath);
    for (final line in repoState.staged) {
      final fileName = _extractGitFilename(line);
      if (fileName == relativePath) {
        final status = line.substring(0, 2).trim();
        final indicator = gitFileStatus[status];
        return (indicator?.$2 ?? defaultColor, indicator?.$1);
      }
    }
    for (final line in repoState.unstaged) {
      final fileName = _extractGitFilename(line);
      if (fileName == relativePath) {
        final status = line.substring(0, 2).trim();
        final indicator = gitFileStatus[status];
        return (indicator?.$2 ?? defaultColor, indicator?.$1);
      }
    }
    return (defaultColor, null);
  }

  bool isUnfolded(String dirPath) => context.read<FolderBloc>().state.folderStates[dirPath] ?? false;
  void toggleFolder(String dirPath) => context.read<FolderBloc>().toggleFolder(dirPath);

  bool _isPathWithinRoot(String entityPath) {
    final normalizedRoot = path.normalize(widget.rootPath);
    final normalizedEntity = path.normalize(entityPath);
    return normalizedEntity == normalizedRoot || normalizedEntity.startsWith('$normalizedRoot${path.separator}');
  }

  String? _activeFilePath() {
    final editorState = widget.activeEditorState;
    final editors = editorState?.activeEditors;
    if (editors == null || editors.isEmpty) return null;

    final activeIndex = editors.indexWhere((editor) => editor.isActive);
    final activeEditor = activeIndex >= 0 ? editors[activeIndex] : editors.first;
    return activeEditor.file.path;
  }

  bool _isPathOnHighlightPath(String candidatePath, String? highlightPath) {
    if (highlightPath == null) return false;
    final normalizedCandidate = path.normalize(candidatePath);
    final normalizedHighlight = path.normalize(highlightPath);
    if (normalizedCandidate == normalizedHighlight) return true;
    return normalizedHighlight.startsWith('$normalizedCandidate${path.separator}');
  }

  String? _resolveHighlightPath(FolderState folderState) {
    final activeFilePath = _activeFilePath();
    if (activeFilePath != null && _isPathWithinRoot(activeFilePath)) {
      return path.normalize(activeFilePath);
    }

    final lastUnfoldedFolderPath = folderState.lastUnfoldedFolderPath;
    if (lastUnfoldedFolderPath == null) return null;
    if (!_isPathWithinRoot(lastUnfoldedFolderPath)) return null;
    return path.normalize(lastUnfoldedFolderPath);
  }

  void startCreating(String parentPath, bool isFolder) {
    setState(() {
      newEntryPath = parentPath;
      isFolderCreation = isFolder;
      _controller.clear();
      renamingPath = null;
    });
    if (!isUnfolded(parentPath)) {
      toggleFolder(parentPath);
    }
  }

  void stopCreating() {
    setState(() {
      newEntryPath = null;
    });
  }

  void startRenaming(String entityPath) {
    setState(() {
      renamingPath = entityPath;
      _renameController.text = path.basename(entityPath);
      newEntryPath = null;
    });
  }

  void stopRenaming() {
    setState(() {
      renamingPath = null;
      _renameController.clear();
    });
  }

  void createEntry(Directory parent) {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      final newPath = path.join(parent.path, value);
      if (isFolderCreation) {
        Directory(newPath).createSync();
      } else {
        File(newPath).createSync();
      }
    }
    stopCreating();
    try {
      context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.rootPath));
    } catch (_) {}
  }

  void renameEntry(String oldPath, bool isFolder) {
    final value = _renameController.text.trim();
    if (value.isNotEmpty && value != path.basename(oldPath)) {
      final parentDir = path.dirname(oldPath);
      final newPath = path.join(parentDir, value);
      try {
        if (isFolder) {
          Directory(oldPath).renameSync(newPath);
        } else {
          File(oldPath).renameSync(newPath);
        }
      } catch (_) {}
    }
    stopRenaming();
    try {
      context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.rootPath));
    } catch (_) {}
  }

  void _showFolderContextMenu(
    BuildContext context,
    Directory directory,
    Offset tapPosition,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final isRootDirectory = directory.path == widget.rootPath;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.enableCreateFileOption)
          PopupMenuItem(
            child: Row(
              children: [
                widget.folderStyle?.iconForCreateFile ?? FolderStyle().iconForCreateFile,
                const SizedBox(width: 15),
                Text(
                  'New File',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => Future.delayed(
              Duration.zero,
              () => startCreating(directory.path, false),
            ),
          ),
        if (widget.enableCreateFolderOption)
          PopupMenuItem(
            child: Row(
              children: [
                widget.folderStyle?.iconForCreateFolder ??
                    FolderStyle().iconForCreateFolder,
                const SizedBox(width: 11),
                Text(
                  'New Folder',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => Future.delayed(
              Duration.zero,
              () => startCreating(directory.path, true),
            ),
          ),
        if (widget.enableRenameFolderOption && !isRootDirectory)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(
                  Icons.edit,
                  size: 25,
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Rename Folder',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => Future.delayed(
              Duration.zero,
              () => startRenaming(directory.path),
            ),
          ),
        if (isRootDirectory)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(
                  Icons.refresh,
                  size: 25,
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Refresh Explorer',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => Future.delayed(Duration.zero, () {
              if (context.mounted) {
                try {
                  context.read<RepoStatusBloc>().add(
                    LoadRepoStatus(widget.rootPath),
                  );
                } catch (_) {}
              }
            }),
          ),
        if (isRootDirectory)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(
                  Icons.unfold_more,
                  size: 25,
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Expand All',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () =>
                Future.delayed(Duration.zero, () => _expandAllFolders()),
          ),
        if (isRootDirectory)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(
                  Icons.unfold_less,
                  size: 25,
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Collapse All',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () =>
                Future.delayed(Duration.zero, () => _collapseAllFolders()),
          ),
        if (widget.enableDeleteFolderOption && !isRootDirectory)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(Icons.delete, size: 25, color: Colors.red[300]),
                const SizedBox(width: 8),
                Text(
                  'Delete Folder',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => _showDeleteFolderConfirmation(context, directory),
          ),
      ],
    );
  }

  void _showFileContextMenu(
    BuildContext context,
    File file,
    Offset tapPosition,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.enableRenameFileOption)
          PopupMenuItem(
            child: Row(
              children: [
                Icon(
                  Icons.edit,
                  size: 25,
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Rename File',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () =>
                Future.delayed(Duration.zero, () => startRenaming(file.path)),
          ),
        if (widget.enableDeleteFileOption)
          PopupMenuItem(
            child: Row(
              children: [
                widget.fileStyle?.iconForDeleteFile ?? FileStyle().iconForDeleteFile,
                const SizedBox(width: 8),
                Text(
                  'Delete File',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            onTap: () => _showDeleteFileConfirmation(context, file),
          ),
      ],
    );
  }

  Widget _buildDirectoryTree(
    Directory directory,
    RepoStatusState repoState,
    FolderState folderState,
  ) {
    final highlightedPath = _resolveHighlightPath(folderState);
    return _buildDirectoryTreeNode(
      directory,
      repoState,
      ancestorHasNext: const [],
      ancestorPaths: const [],
      highlightedPath: highlightedPath,
      isRoot: true,
      isLast: true,
    );
  }

  Widget _buildDirectoryTreeNode(
    Directory directory,
    RepoStatusState repoState, {
    required List<bool> ancestorHasNext,
    required List<String> ancestorPaths,
    required String? highlightedPath,
    required bool isRoot,
    required bool isLast,
  }) {
    final entries = directory.listSync();
    entries.sort((a, b) {
      if (a is Directory && b is File) return -1;
      if (a is File && b is Directory) return 1;
      return a.path.compareTo(b.path);
    });

    final ownPrefix = isRoot ? const SizedBox.shrink()
    : _buildTreePrefix(
        ancestorHasNext: ancestorHasNext,
        ancestorPaths: ancestorPaths,
        currentPath: directory.path,
        highlightedPath: highlightedPath,
        isLast: isLast,
      );

  final childAncestorHasNext = [...ancestorHasNext, !isLast];
  final childAncestorPaths = [...ancestorPaths, directory.path];
  final isHighlighted = highlightedPath != null && path.normalize(directory.path) == path.normalize(highlightedPath);
  final folderNameBaseStyle = widget.folderStyle?.folderNameStyle ?? FolderStyle().folderNameStyle ?? const TextStyle();
  final folderNameStyle = folderNameBaseStyle.copyWith(
    color: isHighlighted
      ? widget.appTheme.isDark ? Colors.white : Colors.black
      : (folderNameBaseStyle.color ?? widget.appTheme.selectScreenCardTextColor),
  );

    if (renamingPath == directory.path) {
      return _buildRenameField(directory.path, true, prefix: ownPrefix);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => toggleFolder(directory.path),
          onLongPressStart: (details) => _showFolderContextMenu(
            context,
            directory,
            details.globalPosition,
          ),
          child: Container(
            height: _guideRowHeight,
            decoration: BoxDecoration(
              color: isHighlighted ? widget.appTheme.editorPageToolSelectedBgColor.withAlpha(200) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                ownPrefix,
                isUnfolded(directory.path)
                  ? widget.folderStyle?.folderOpenedicon ?? FolderStyle().folderOpenedicon
                  : widget.folderStyle?.folderClosedicon ?? FolderStyle().folderClosedicon,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    path.basename(directory.path),
                    style: folderNameStyle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (widget.folderActions != null) ...widget.folderActions!,
              ],
            ),
          ),
        ),
        if (isUnfolded(directory.path))
          Padding(
            padding: const EdgeInsets.only(right: 7.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: () {
                final children = <Widget>[];
                final total = entries.length;

                for (int i = 0; i < entries.length; i++) {
                  final entry = entries[i];
                  final entryIsLast = i == total - 1 && newEntryPath != directory.path;

                  if (entry is Directory) {
                    children.add(
                      _buildDirectoryTreeNode(
                        entry,
                        repoState,
                        ancestorHasNext: childAncestorHasNext,
                        ancestorPaths: childAncestorPaths,
                        highlightedPath: highlightedPath,
                        isRoot: false,
                        isLast: entryIsLast,
                      ),
                    );
                  } else {
                    children.add(
                      _buildFileItem(
                        entry as File,
                        repoState,
                        ancestorHasNext: childAncestorHasNext,
                        ancestorPaths: childAncestorPaths,
                        highlightedPath: highlightedPath,
                        isLast: entryIsLast,
                      ),
                    );
                  }
                }

                if (newEntryPath == directory.path) {
                  children.add(
                    _buildNewEntryField(
                      directory,
                      prefix: _buildTreePrefix(
                        ancestorHasNext: childAncestorHasNext,
                        ancestorPaths: childAncestorPaths,
                        currentPath: directory.path,
                        highlightedPath: highlightedPath,
                        isLast: true,
                      ),
                    ),
                  );
                }
                return children;
              }(),
            ),
          ),
      ],
    );
  }

  Widget _buildTreePrefix({
    required List<bool> ancestorHasNext,
    required List<String> ancestorPaths,
    required String currentPath,
    required String? highlightedPath,
    required bool isLast,
  }) {
    final guideColor = widget.appTheme.selectScreenCardTextColor.withValues(
      alpha: widget.appTheme.isDark ? 0.24 : 0.32,
    );
    final highlightedGuideColor = widget.appTheme.editorPageToolSelectedColor.withValues(
      alpha: widget.appTheme.isDark ? 0.95 : 0.80,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < ancestorHasNext.length; i++)
          _GuideSegment(
            width: _guideIndentWidth,
            height: _guideRowHeight,
            lineColor: _isPathOnHighlightPath(
              i < ancestorPaths.length ? ancestorPaths[i] : '',
              highlightedPath,
            )
                ? highlightedGuideColor
                : guideColor,
            showVertical: ancestorHasNext[i],
          ),
        _GuideSegment(
          width: _guideIndentWidth,
          height: _guideRowHeight,
          lineColor: _isPathOnHighlightPath(currentPath, highlightedPath)
              ? highlightedGuideColor
              : guideColor,
          showVertical: true,
          isNodeConnector: true,
          isLast: isLast,
        ),
      ],
    );
  }

  Widget _buildNewEntryField(Directory parent, {Widget? prefix}) {
    return Row(
      children: [
        prefix ?? const SizedBox.shrink(),
        isFolderCreation
          ? widget.editingFieldStyle?.folderIcon ?? EditingFieldStyle().folderIcon
          : widget.editingFieldStyle?.fileIcon ?? EditingFieldStyle().fileIcon,
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: widget.editingFieldStyle?.textFieldHeight,
            child: TextField(
              style: widget.editingFieldStyle?.textStyle,
              textAlignVertical: widget.editingFieldStyle?.verticalTextAlign,
              cursorRadius: widget.editingFieldStyle?.cursorRadius,
              cursorWidth: widget.editingFieldStyle?.cursorWidth ?? 2.0,
              cursorHeight: widget.editingFieldStyle?.cursorHeight,
              cursorColor: widget.editingFieldStyle?.cursorColor,
              autofocus: true,
              decoration:
                widget.editingFieldStyle?.textfieldDecoration ??
                EditingFieldStyle().textfieldDecoration,
              controller: _controller,
              onSubmitted: (_) => createEntry(parent),
            ),
          ),
        ),
        IconButton(
          icon:
            widget.editingFieldStyle?.doneIcon ??
            EditingFieldStyle().doneIcon,
          onPressed: () => createEntry(parent),
        ),
        IconButton(
          icon:
            widget.editingFieldStyle?.cancelIcon ??
            EditingFieldStyle().cancelIcon,
          onPressed: stopCreating,
        ),
      ],
    );
  }

  Widget _buildRenameField(String entityPath, bool isFolder, {Widget? prefix}) {
    return Row(
      children: [
        prefix ?? const SizedBox.shrink(),
        isFolder
          ? widget.editingFieldStyle?.folderIcon ?? EditingFieldStyle().folderIcon
          : widget.editingFieldStyle?.fileIcon ?? EditingFieldStyle().fileIcon,
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: widget.editingFieldStyle?.textFieldHeight,
            child: TextField(
              style: widget.editingFieldStyle?.textStyle,
              textAlignVertical: widget.editingFieldStyle?.verticalTextAlign,
              cursorRadius: widget.editingFieldStyle?.cursorRadius,
              cursorWidth: widget.editingFieldStyle?.cursorWidth ?? 2.0,
              cursorHeight: widget.editingFieldStyle?.cursorHeight,
              cursorColor: widget.editingFieldStyle?.cursorColor,
              autofocus: true,
              decoration: (
                widget.editingFieldStyle?.textfieldDecoration
                  ?? EditingFieldStyle().textfieldDecoration
                ).copyWith(hintText: path.basename(entityPath)),
              controller: _renameController,
              onSubmitted: (_) => renameEntry(entityPath, isFolder),
            ),
          ),
        ),
        IconButton(
          icon:
            widget.editingFieldStyle?.doneIcon ??
            EditingFieldStyle().doneIcon,
          onPressed: () => renameEntry(entityPath, isFolder),
        ),
        IconButton(
          icon: widget.editingFieldStyle?.cancelIcon ?? EditingFieldStyle().cancelIcon,
          onPressed: stopRenaming,
        ),
      ],
    );
  }

  Widget _buildFileItem(
    File file,
    RepoStatusState repoState, {
    required List<bool> ancestorHasNext,
    required List<String> ancestorPaths,
    required String? highlightedPath,
    required bool isLast,
  }) {
    final baseStyle = widget.fileStyle?.fileNameStyle ?? FileStyle().fileNameStyle ?? const TextStyle();

    final prefix = _buildTreePrefix(
      ancestorHasNext: ancestorHasNext,
      ancestorPaths: ancestorPaths,
      currentPath: file.path,
      highlightedPath: highlightedPath,
      isLast: isLast,
    );

    if (renamingPath == file.path) {
      return _buildRenameField(file.path, false, prefix: prefix);
    }

    final (color, letter) = _getFileColor(file, repoState, highlightedPath);
    final isHighlighted = highlightedPath != null && path.normalize(file.path) == path.normalize(highlightedPath);
    final key = GlobalKey();
    return InkWell(
      key: key,
      onTap: () => widget.onFileTap?.call(file),
      onLongPress: () {
        final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
        final position = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
        _showFileContextMenu(context, file, position);
      },
      child: Container(
        height: _guideRowHeight,
        decoration: BoxDecoration(
          color: isHighlighted ? widget.appTheme.editorPageToolSelectedBgColor.withAlpha(200) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            prefix,
            widget.fileIconBuilder?.call(path.extension(file.path).toLowerCase())
            ?? widget.fileStyle?.fileIcon
            ?? FileStyle().fileIcon,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path.basename(file.path),
                style: baseStyle.copyWith(
                  color: color,
                  height: 1.0,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (letter != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  letter,
                  style: baseStyle.copyWith(
                    color: color,
                    fontSize: 15,
                  ),
                ),
              ),
            if (widget.fileActions != null) ...widget.fileActions!,
          ],
        ),
      ),
    );
  }

  void _expandAllFolders() {
    final folderBloc = context.read<FolderBloc>();
    final allPaths = _getAllDirectoryPaths(Directory(widget.rootPath));
    folderBloc.setAllFoldersExpanded(allPaths, true);
  }

  void _collapseAllFolders() {
    final folderBloc = context.read<FolderBloc>();
    final allPaths = _getAllDirectoryPaths(Directory(widget.rootPath));
    folderBloc.setAllFoldersExpanded(allPaths, false);
  }

  List<String> _getAllDirectoryPaths(Directory directory) {
    final paths = <String>[];
    try {
      final entries = directory.listSync(recursive: true);
      for (final entry in entries) {
        if (entry is Directory) {
          paths.add(entry.path);
        }
      }
    } catch (_) {}
    return paths;
  }

  void _showDeleteFolderConfirmation(
    BuildContext context,
    Directory directory,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: widget.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange[400],
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Delete Folder',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete "${path.basename(directory.path)}" and all its contents? This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withValues(
                      alpha: 0.8,
                    ),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _performFolderDeletion(context, directory);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _performFolderDeletion(BuildContext context, Directory directory) {
    try {
      directory.deleteSync(recursive: true);
      setState(() {});
      if (context.mounted) {
        try {
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.rootPath));
        } catch (_) {}
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteFileConfirmation(BuildContext context, File file) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: widget.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange[400],
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Delete File',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete "${path.basename(file.path)}"? This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withValues(
                      alpha: 0.8,
                    ),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _performFileDeletion(context, file);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _performFileDeletion(BuildContext context, File file) {
    try {
      file.deleteSync();
      setState(() {});
      if (context.mounted) {
        try {
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.rootPath));
        } catch (_) {}
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rootDirectory = Directory(widget.rootPath);
    if (!rootDirectory.existsSync()) {
      return const Center(child: Text('Directory does not exist'));
    }
    if (widget.enableGitFeatures) {
      return BlocBuilder<RepoStatusBloc, RepoStatusState>(
        builder: (context, repoState) {
          return BlocBuilder<FolderBloc, FolderState>(
            builder: (context, folderState) {
              return SingleChildScrollView(
                child: _buildDirectoryTree(
                  rootDirectory,
                  repoState,
                  folderState,
                ),
              );
            },
          );
        },
      );
    } else {
      return BlocBuilder<FolderBloc, FolderState>(
        builder: (context, folderState) {
          return SingleChildScrollView(
            child: _buildDirectoryTree(
              rootDirectory,
              const RepoStatusInitial(),
              folderState,
            ),
          );
        },
      );
    }
  }
}

class _GuideSegment extends StatelessWidget {
  final double width;
  final double height;
  final Color lineColor;
  final bool showVertical;
  final bool isNodeConnector;
  final bool isLast;

  const _GuideSegment({
    required this.width,
    required this.height,
    required this.lineColor,
    required this.showVertical,
    this.isNodeConnector = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _GuideSegmentPainter(
          color: lineColor,
          showVertical: showVertical,
          isNodeConnector: isNodeConnector,
          isLast: isLast,
        ),
      ),
    );
  }
}

class _GuideSegmentPainter extends CustomPainter {
  final Color color;
  final bool showVertical;
  final bool isNodeConnector;
  final bool isLast;

  const _GuideSegmentPainter({
    required this.color,
    required this.showVertical,
    required this.isNodeConnector,
    required this.isLast,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final x = size.width / 2;
    final yMid = size.height / 2;

    if (showVertical && !isNodeConnector) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      return;
    }

    if (!isNodeConnector) return;

    canvas.drawLine(Offset(x, 0), Offset(x, yMid), paint);
    if (!isLast) {
      canvas.drawLine(Offset(x, yMid), Offset(x, size.height), paint);
    }
    canvas.drawLine(Offset(x, yMid), Offset(size.width, yMid), paint);
  }

  @override
  bool shouldRepaint(covariant _GuideSegmentPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.showVertical != showVertical ||
        oldDelegate.isNodeConnector != isNodeConnector ||
        oldDelegate.isLast != isLast;
  }
}

class FindWordWidget extends StatefulWidget {
  final AppTheme appTheme;
  final TextEditingController findWordController, replaceWordController;
  final ActiveEditorState editorState;
  final TabController? tabController;
  final String workspacePath;
  final void Function(File file, int lineNumber, String searchQuery)?
  onFileOpen;
  const FindWordWidget({
    super.key,
    required this.appTheme,
    required this.findWordController,
    required this.editorState,
    required this.replaceWordController,
    required this.tabController,
    required this.workspacePath,
    this.onFileOpen,
  });

  @override
  State<FindWordWidget> createState() => _FindWordWidgetState();
}

class _FindWordWidgetState extends State<FindWordWidget> {
  final ScrollController _resultsScrollController = ScrollController();
    Timer? _debounceTimer;
    int _searchId = 0;
    final InvertedIndex _invertedIndex = InvertedIndex();

  ActiveEditor? _getActiveEditor() {
    if (widget.editorState.activeEditors.isEmpty) return null;

    if (widget.tabController != null) {
      final index = widget.tabController!.index;
      if (index >= 0 && index < widget.editorState.activeEditors.length) {
        return widget.editorState.activeEditors[index];
      }
    }

    for (final editor in widget.editorState.activeEditors) {
      if (editor.isActive) {
        return editor;
      }
    }

    return widget.editorState.activeEditors.first;
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

  Future<void> _searchWorkspace(
    BuildContext context,
    String query,
    WorkspaceSearchState searchState,
  ) async {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      if (context.mounted) {
        context.read<WorkspaceSearchBloc>().add(ClearSearchResults());
      }
      return;
    }

    final debounceCompleter = Completer<void>();
    _debounceTimer = Timer(
      const Duration(milliseconds: 300),
      debounceCompleter.complete,
    );
    await debounceCompleter.future;

    if (!context.mounted) return;

    final myId = ++_searchId;

    context.read<WorkspaceSearchBloc>().add(SetSearching(isSearching: true));

    if (_invertedIndex.isReady &&
        !searchState.isRegex &&
        searchState.matchWholeWord &&
        query.length >= 3 &&
        !query.contains(RegExp(r'\s'))) {
      final hit = _invertedIndex.lookup(query);
      if (hit != null) {
        final results = <SearchResultData>[];
        for (final entry in hit.entries) {
          final relativePath =
              entry.key.replaceFirst('${widget.workspacePath}/', '');
          try {
            int lineNo = 0;
            await for (final line in File(entry.key)
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
              lineNo++;
              if (entry.value.contains(lineNo)) {
                results.add(SearchResultData(
                  filePath:     entry.key,
                  relativePath: relativePath,
                  lineNumber:   lineNo,
                  lineContent:  line.trim(),
                ));
              }
            }
          } catch (_) {}
        }

        if (!context.mounted || _searchId != myId) return;
        context.read<WorkspaceSearchBloc>().add(
          UpdateSearchResults(results: results, query: query),
        );
        return;
      }
    }

    final params = SearchParams(
      workspacePath: widget.workspacePath,
      query: query,
      matchCase: searchState.matchCase,
      matchWholeWord: searchState.matchWholeWord,
      isRegex: searchState.isRegex,
    );

    List<RawResult> rawResults;
    try {
      rawResults = await compute(searchIsolate, params);
    } catch (_) {
      rawResults = const [];
    }

    if (!context.mounted || _searchId != myId) return;

    final results = rawResults
      .map((r) => SearchResultData(
        filePath: r.filePath,
        relativePath: r.relativePath,
        lineNumber: r.lineNumber,
        lineContent: r.lineContent,
      )).toList();

    context.read<WorkspaceSearchBloc>().add(
      UpdateSearchResults(results: results, query: query),
    );
  }

  Future<void> _replaceInWorkspace(
    BuildContext context,
    String findText,
    String replaceText,
    WorkspaceSearchState searchState,
  ) async {
    if (findText.isEmpty || searchState.results.isEmpty) return;

    final filesModified = <String>{};

    for (final result in searchState.results) {
      try {
        final file = File(result.filePath);
        String content = await file.readAsString();
        String newContent;

        if (searchState.isRegex) {
          try {
            final regex = RegExp(
              findText,
              caseSensitive: searchState.matchCase,
            );
            newContent = content.replaceAll(regex, replaceText);
          } catch (_) {
            continue;
          }
        } else if (searchState.matchWholeWord) {
          final pattern = RegExp(
            '\\b${RegExp.escape(findText)}\\b',
            caseSensitive: searchState.matchCase,
          );
          newContent = content.replaceAll(pattern, replaceText);
        } else {
          if (searchState.matchCase) {
            newContent = content.replaceAll(findText, replaceText);
          } else {
            newContent = content.replaceAll(
              RegExp(RegExp.escape(findText), caseSensitive: false),
              replaceText,
            );
          }
        }

        if (content != newContent) {
          await file.writeAsString(newContent);
          filesModified.add(result.filePath);
        }
      } catch (_) {}
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Replaced in ${filesModified.length} file(s)'),
          duration: const Duration(seconds: 2),
        ),
      );

      _searchWorkspace(context, findText, searchState);
    }
  }


  @override
  void initState() {
    super.initState();
    _invertedIndex.build(widget.workspacePath);
  }


  @override
  void dispose() {
    _debounceTimer?.cancel();
    _resultsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceSearchBloc, WorkspaceSearchState>(
      builder: (context, searchState) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 17, bottom: 15),
                child: Text(
                  "SEARCH",
                  style: TextStyle(
                    fontWeight: widget.appTheme.isDark
                      ? FontWeight.w300
                      : FontWeight.w500,
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final activeEditor = _getActiveEditor();
                      if (activeEditor != null && activeEditor.findController != null) {
                        Navigator.of(context).pop();

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          activeEditor.findController!.isActive = true;
                          activeEditor.findController!.findInputFocusNode.requestFocus();
                        });
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No active editor'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    icon: Icon(
                      Icons.article_outlined,
                      color: widget.appTheme.selectScreenCardTextColor,
                      size: 18,
                    ),
                    label: Text(
                      "Find in Current File",
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: widget.appTheme.selectScreenCardTextColor.withAlpha(100),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  "Search in Workspace",
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildOptionButton(
                      'Aa',
                      'Match Case',
                      searchState.matchCase,
                      () {
                        context.read<WorkspaceSearchBloc>().add(
                          UpdateSearchOptions(
                            matchCase: !searchState.matchCase,
                            matchWholeWord: searchState.matchWholeWord,
                            isRegex: searchState.isRegex,
                          ),
                        );
                        if (widget.findWordController.text.isNotEmpty) {
                          _searchWorkspace(
                            context,
                            widget.findWordController.text,
                            searchState.copyWith(
                              matchCase: !searchState.matchCase,
                            ),
                          );
                        }
                      },
                    ),
                    _buildOptionButton(
                      'ab',
                      'Match Word',
                      searchState.matchWholeWord,
                      () {
                        context.read<WorkspaceSearchBloc>().add(
                          UpdateSearchOptions(
                            matchCase: searchState.matchCase,
                            matchWholeWord: !searchState.matchWholeWord,
                            isRegex: searchState.isRegex,
                          ),
                        );
                        if (widget.findWordController.text.isNotEmpty) {
                          _searchWorkspace(
                            context,
                            widget.findWordController.text,
                            searchState.copyWith(
                              matchWholeWord: !searchState.matchWholeWord,
                            ),
                          );
                        }
                      },
                      underline: true,
                    ),
                    _buildOptionButton(
                      '\u2022\u2731',
                      'Regex',
                      searchState.isRegex,
                      () {
                        context.read<WorkspaceSearchBloc>().add(
                          UpdateSearchOptions(
                            matchCase: searchState.matchCase,
                            matchWholeWord: searchState.matchWholeWord,
                            isRegex: !searchState.isRegex,
                          ),
                        );
                        if (widget.findWordController.text.isNotEmpty) {
                          _searchWorkspace(
                            context,
                            widget.findWordController.text,
                            searchState.copyWith(isRegex: !searchState.isRegex),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: widget.findWordController,
                    onChanged: (value) {
                      if (value.length >= 2) {
                        _searchWorkspace(context, value, searchState);
                      } else if (value.isEmpty) {
                        context.read<WorkspaceSearchBloc>().add(
                          ClearSearchResults(),
                        );
                      }
                    },
                    onSubmitted: (value) =>
                        _searchWorkspace(context, value, searchState),
                    cursorColor: Colors.grey,
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintStyle: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor
                            .withAlpha(120),
                        fontSize: 14,
                      ),
                      hintText: "Search",
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: const OutlineInputBorder(),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xff0178b9)),
                      ),
                      suffixIcon: widget.findWordController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                size: 18,
                                color: widget.appTheme.selectScreenCardTextColor
                                    .withAlpha(150),
                              ),
                              onPressed: () {
                                widget.findWordController.clear();
                                context.read<WorkspaceSearchBloc>().add(
                                  ClearSearchResults(),
                                );
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),

              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: TextField(
                          controller: widget.replaceWordController,
                          cursorColor: Colors.grey,
                          style: TextStyle(
                            color: widget.appTheme.selectScreenCardTextColor,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintStyle: TextStyle(
                              color: widget.appTheme.selectScreenCardTextColor
                                  .withAlpha(120),
                              fontSize: 14,
                            ),
                            hintText: "Replace",
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: const OutlineInputBorder(),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xff0178b9)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: searchState.results.isNotEmpty
                          ? () => _replaceInWorkspace(
                              context,
                              widget.findWordController.text,
                              widget.replaceWordController.text,
                              searchState,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: searchState.results.isNotEmpty
                              ? const Color(0xff0e639c)
                              : Colors.grey[700],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        height: 38,
                        width: 38,
                        child: const Icon(
                          Icons.find_replace,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              if (searchState.isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 17),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.appTheme.selectScreenCardTextColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Searching...",
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withAlpha(150),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else if (searchState.results.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 17),
                  child: Text(
                    "${searchState.results.length} result${searchState.results.length == 1 ? '' : 's'} found",
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withAlpha(150),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 8),

              Expanded(
                child: searchState.results.isEmpty
                    ? Center(
                        child: Text(
                          widget.findWordController.text.isEmpty
                              ? "Enter search term"
                              : searchState.isSearching
                              ? ""
                              : "No results found",
                          style: TextStyle(
                            color: widget.appTheme.selectScreenCardTextColor
                                .withAlpha(100),
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _resultsScrollController,
                        itemCount: searchState.results.length,
                        itemBuilder: (context, index) {
                          final result = searchState.results[index];
                          return _buildResultTile(result, searchState.query);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionButton(
    String text,
    String tooltip,
    bool isActive,
    VoidCallback onTap, {
    bool underline = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xff0178b9).withAlpha(100)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive
                  ? widget.appTheme.selectScreenCardTextColor
                  : Colors.transparent,
              width: 0.5,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: widget.appTheme.selectScreenCardTextColor,
              fontSize: 13,
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: widget.appTheme.selectScreenCardTextColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultTile(SearchResultData result, String searchQuery) {
    return InkWell(
      onTap: () {
        final file = File(result.filePath);

        final existingIndex = widget.editorState.activeEditors.indexWhere(
          (editor) => editor.file.path == file.path,
        );

        if (existingIndex >= 0) {
          if (widget.tabController != null) {
            widget.tabController!.animateTo(existingIndex);
          }
          Navigator.of(context).pop();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            final editor = widget.editorState.activeEditors[existingIndex];
            if (editor.findController != null) {
              _goToMatchNearLine(editor, result.lineNumber, searchQuery);
            }
          });
        } else {
          Navigator.of(context).pop();
          widget.onFileOpen?.call(file, result.lineNumber, searchQuery);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: widget.appTheme.selectScreenCardTextColor.withAlpha(30),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  height: 14,
                  width: 14,
                  child: (() {
                    try {
                      final ext = path
                          .extension(result.filePath)
                          .replaceAll('.', '');
                      return languages
                          .singleWhere((lang) => lang.extension.contains(ext))
                          .icon;
                    } catch (_) {
                      return langtxt.icon;
                    }
                  })(),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    result.relativePath,
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  ':${result.lineNumber}',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(
                      120,
                    ),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              result.lineContent,
              style: TextStyle(
                color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class SourceControl extends StatefulWidget {
  final AppTheme appTheme;
  final String workSpace;
  final bool isRepoThere;
  final Function(String fileName, String workspacePath, ActiveEditorBloc bloc)? onOpenDiffView;
  final ActiveEditorBloc? activeEditorsBloc;
  const SourceControl({
    super.key,
    required this.appTheme,
    required this.workSpace,
    required this.isRepoThere,
    this.onOpenDiffView,
    this.activeEditorsBloc,
  });

  @override
  State<SourceControl> createState() => _SourceControlState();
}

class _SourceControlState extends State<SourceControl> {
  bool _isARepo = false;
  late final TextEditingController _commitController;
  late final StreamSubscription<GitCommitState> _commitSub;
  bool _stagedExpanded = true;
  bool _unstagedExpanded = true;
  bool _commitGraphExpanded = true;
  late final ScrollController _commitGraphScrollController;
  final ScrollController _stagedScrollController = ScrollController();
  final ScrollController _unstagedScrollController = ScrollController();
  StreamSubscription<FileSystemEvent>? _gitWatcher;
  DateTime? _lastGitRefresh;
  bool _isGeneratingCommitMessage = false;
  bool _requestedCopilotCommitModels = false;

  static const int _maxCommitDiffChars = 16000;
  static const int _maxUntrackedPreviewChars = 1200;

  @override
  void initState() {
    _commitController = TextEditingController(
      text: context.read<GitCommitBloc>().state.commitMessage,
    );

    _commitSub = context.read<GitCommitBloc>().stream.listen((s) {
      final newText = s.commitMessage;
      if (newText != _commitController.text) {
        _commitController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
      }
    });

    _commitGraphScrollController = ScrollController();

    if (widget.isRepoThere) {
      final currentState = context.read<RepoStatusBloc>().state;
      if (currentState is RepoStatusInitial) {
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
      }
      _setupGitWatcher();
    }
    super.initState();
  }

  void _setupGitWatcher() {
    _gitWatcher?.cancel();
    final gitDir = Directory(path.join(widget.workSpace, '.git'));
    if (gitDir.existsSync()) {
      _gitWatcher = gitDir.watch(recursive: true).listen((event) {
        if (mounted) {
          final now = DateTime.now();
          if (_lastGitRefresh == null ||
              now.difference(_lastGitRefresh!).inSeconds >= 2) {
            _lastGitRefresh = now;
            context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
          }
        }
      });
    }
  }

  void _requestCopilotModelsIfNeeded(
    bool githubSignedIn,
    bool copilotSignedIn,
    CopilotChatState chatState,
  ) {
    final copilotAvailable = githubSignedIn || copilotSignedIn;
    if (!copilotAvailable) {
      _requestedCopilotCommitModels = false;
      return;
    }

    if (_requestedCopilotCommitModels ||
        chatState.isFetchingModels ||
        chatState.hasFetchedModels) {
      return;
    }

    _requestedCopilotCommitModels = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CopilotChatBloc>().add(CopilotChatFetchModels(forceRefresh: true));
    });
  }

  Future<ProcessResult> _runGitCommand(List<String> args) async {
    final sharedPath = await NativeChannel.getLibraryPath();
    return Process.run(
      '$binDir/git',
      args,
      workingDirectory: widget.workSpace,
      environment: gitEnvs(sharedPath),
    );
  }

  Future<List<String>> _loadRecentCommitSubjects() async {
    final result = await _runGitCommand(['log', '-n', '8', '--pretty=format:%s']);
    if (result.exitCode != 0) {
      return const [];
    }

    return result.stdout
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<String> _loadCommitDiffContext({required bool stagedOnly}) async {
    final diffArgs = stagedOnly
        ? ['diff', '--cached', '--no-color', '--no-ext-diff', '--patch', '--unified=3', '--']
        : ['diff', '--no-color', '--no-ext-diff', '--patch', '--unified=3', '--'];

    final trackedDiffResult = await _runGitCommand(diffArgs);
    final buffer = StringBuffer();
    if (trackedDiffResult.exitCode == 0) {
      final trackedDiff = trackedDiffResult.stdout.toString().trimRight();
      if (trackedDiff.isNotEmpty) {
        buffer.writeln(trackedDiff);
      }
    }

    if (!stagedOnly) {
      final untrackedFilesResult = await _runGitCommand([
        'ls-files',
        '--others',
        '--exclude-standard',
      ]);

      final untrackedFiles = untrackedFilesResult.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(6)
          .toList();

      if (untrackedFiles.isNotEmpty) {
        buffer.writeln('\n# Untracked file previews');
      }

      for (final relativePath in untrackedFiles) {
        final file = File(path.join(widget.workSpace, relativePath));
        if (!file.existsSync()) continue;

        try {
          final bytes = await file.readAsBytes();
          if (bytes.contains(0)) continue;

          final decoded = utf8.decode(bytes, allowMalformed: true).trimRight();
          if (decoded.isEmpty) continue;

          final preview = _truncateText(decoded, _maxUntrackedPreviewChars);
          buffer.writeln('\n## $relativePath');
          for (final line in preview.split('\n')) {
            buffer.writeln('+$line');
          }
        } catch (_) {
          continue;
        }
      }
    }

    return _truncateText(buffer.toString().trim(), _maxCommitDiffChars);
  }

  String _truncateText(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n\n[truncated]';
  }

  String _buildCommitGenerationPrompt({
    required String diffText,
    required List<String> recentCommits,
    required bool stagedOnly,
  }) {
    final styleHints = recentCommits.isEmpty
        ? '- No recent commits found.'
        : recentCommits.map((msg) => '- $msg').join('\n');

    final source = stagedOnly
        ? 'staged changes only'
        : 'working tree changes (including untracked file previews)';

    return '''
You are generating a git commit message.

Rules:
- Return exactly one commit subject line.
- Use imperative mood.
- Maximum 72 characters.
- Do not use markdown, bullet points, quotes, or code fences.
- Do not include issue numbers unless they appear explicitly in the changes.

Changes source: $source

Recent commit style examples (style reference only):
$styleHints

Changes:
$diffText
''';
  }

  String _normalizeGeneratedCommitMessage(String raw) {
    var text = raw.trim();
    final fenced = RegExp(r'```(?:\w+)?\s*([\s\S]*?)\s*```').firstMatch(text);
    if (fenced != null) {
      text = fenced.group(1)!.trim();
    }

    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';

    var message = lines.first;
    message = message.replaceFirst(RegExp(r'^[-*]\s+'), '');
    message = message.replaceFirst(
      RegExp(r'^(commit message|message)\s*:\s*', caseSensitive: false),
      '',
    );

    if ((message.startsWith('"') && message.endsWith('"')) ||
        (message.startsWith('\'') && message.endsWith('\''))) {
      message = message.substring(1, message.length - 1).trim();
    }

    if (message.length > 72) {
      final chunk = message.substring(0, 72);
      final lastSpace = chunk.lastIndexOf(' ');
      if (lastSpace >= 50) {
        message = chunk.substring(0, lastSpace).trimRight();
      } else {
        message = chunk.trimRight();
      }
    }

    return message;
  }

  List<Models> _collectExternalCommitModels(AIState aiState) {
    if (!aiState.isEnabled) return const [];

    final models = <Models>[];
    final seen = <String>{};

    void addModel(Models? model) {
      if (model == null) return;
      final key = '${model.runtimeType}|${model.url}|${model.model ?? ''}';
      if (seen.add(key)) {
        models.add(model);
      }
    }

    addModel(aiState.chatModel);
    addModel(aiState.completionModel);
    return models;
  }

  bool _canGenerateCommitMessage({
    required AIState aiState,
    required bool githubSignedIn,
    required bool copilotSignedIn,
    required CopilotChatState chatState,
  }) {
    if (!aiState.isEnabled) return false;

    final hasCopilotModels = (githubSignedIn || copilotSignedIn) && chatState.models.isNotEmpty;
    final hasExternalModels = _collectExternalCommitModels(aiState).isNotEmpty;
    return hasCopilotModels || hasExternalModels;
  }

  Future<String?> _tryGenerateWithCopilotModels(
    CopilotChatState chatState,
    String prompt,
  ) async {
    final chatClient = context.read<CopilotChatBloc>().chatClient;
    if (chatClient == null) return null;

    final modelIds = chatState.models
        .map((model) => model['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    for (final modelId in modelIds) {
      try {
        final response = await chatClient.chatWithModel(
          model: modelId,
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          chatMode: ChatMode.ask,
        );

        final normalized = _normalizeGeneratedCommitMessage(response);
        if (normalized.isNotEmpty) {
          return normalized;
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<String?> _tryGenerateWithExternalModels(
    List<Models> models,
    String prompt,
  ) async {
    for (final model in models) {
      try {
        final response = await model.completionResponse(prompt);
        final normalized = _normalizeGeneratedCommitMessage(response);
        if (normalized.isNotEmpty) {
          return normalized;
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<void> _generateCommitMessage({
    required BuildContext context,
    required AIState aiState,
    required CopilotChatState chatState,
    required bool githubSignedIn,
    required bool copilotSignedIn,
  }) async {
    if (_isGeneratingCommitMessage) return;

    final repoState = context.read<RepoStatusBloc>().state;
    if (repoState is! RepoStatusLoaded) {
      _showErrorSnackBar(context, 'Repository status is still loading');
      return;
    }

    if (repoState.staged.isEmpty && repoState.unstaged.isEmpty) {
      _showErrorSnackBar(context, 'No changes available to generate a commit message');
      return;
    }

    setState(() => _isGeneratingCommitMessage = true);

    try {
      final stagedOnly = repoState.staged.isNotEmpty;
      final diffText = await _loadCommitDiffContext(stagedOnly: stagedOnly);
      if (diffText.isEmpty && context.mounted) {
        _showErrorSnackBar(context, 'Could not gather changes for commit message generation');
        return;
      }

      final recentCommits = await _loadRecentCommitSubjects();
      final prompt = _buildCommitGenerationPrompt(
        diffText: diffText,
        recentCommits: recentCommits,
        stagedOnly: stagedOnly,
      );

      String? generated;

      if (aiState.isEnabled && (githubSignedIn || copilotSignedIn) && chatState.models.isNotEmpty) {
        generated = await _tryGenerateWithCopilotModels(chatState, prompt);
      }

      if ((generated == null || generated.isEmpty) && aiState.isEnabled) {
        final externalModels = _collectExternalCommitModels(aiState);
        generated = await _tryGenerateWithExternalModels(externalModels, prompt);
      }

      if (!context.mounted) return;

      if (generated == null || generated.isEmpty) {
        _showErrorSnackBar(context, 'No working AI model could generate a commit message');
        return;
      }

      context.read<GitCommitBloc>().add(GitCommitEvent(commitMessage: generated));
      _showSuccessSnackBar(context, 'Commit message generated');
    } catch (_) {
      if (!mounted) return;
      _showErrorSnackBar(context, 'Failed to generate commit message');
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCommitMessage = false);
      }
    }
  }

  @override
  void dispose() {
    _gitWatcher?.cancel();
    _commitSub.cancel();
    _commitController.dispose();
    _commitGraphScrollController.dispose();
    _stagedScrollController.dispose();
    _unstagedScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SourceControl oldWidget) {
    if (oldWidget.workSpace != widget.workSpace) {
      try {
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
        if (widget.isRepoThere) {
          context.read<RepoStatusBloc>().add(LoadCommitGraph(widget.workSpace));
          _setupGitWatcher();
        }
      } catch (_) {}
    }
    super.didUpdateWidget(oldWidget);
  }

  Widget _buildCollapsibleChangesList({
    required String title,
    required bool isExpanded,
    required VoidCallback onToggle,
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    required Widget actionButton,
    required ScrollController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              top: 12,
              bottom: 4,
              right: 4,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(
                      150,
                    ),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(
                      150,
                    ),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$itemCount',
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ),
                const Expanded(child: SizedBox()),
                actionButton,
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: child,
            );
          },
          child: isExpanded
              ? ConstrainedBox(
                  key: ValueKey('$title-expanded'),
                  constraints: BoxConstraints(
                    maxHeight: itemCount > 5 ? 250 : itemCount * 50.0,
                  ),
                  child: Scrollbar(
                    controller: controller,
                    thumbVisibility: itemCount > 5,
                    child: ListView.builder(
                      controller: controller,
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: itemCount,
                      itemBuilder: itemBuilder,
                    ),
                  ),
                )
              : SizedBox.shrink(key: ValueKey('$title-collapsed')),
        ),
      ],
    );
  }

  Widget _buildCollapsibleCommitGraph() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () =>
              setState(() => _commitGraphExpanded = !_commitGraphExpanded),
          child: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              top: 12,
              bottom: 8,
              right: 4,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _commitGraphExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(
                      150,
                    ),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  "Commit History",
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(
                      150,
                    ),
                    fontSize: 14,
                  ),
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: child,
            );
          },
          child: _commitGraphExpanded
              ? ConstrainedBox(
                  key: const ValueKey('commit-graph-expanded'),
                  constraints: const BoxConstraints(maxHeight: 600),
                  child: BlocBuilder<RepoStatusBloc, RepoStatusState>(
                    builder: (context, state) {
                      if (state is RepoStatusLoaded && state.commits != null) {
                        if (state.commits!.isEmpty) {
                          return Center(
                            child: Text(
                              'No commits found',
                              style: TextStyle(
                                color:
                                    widget.appTheme.selectScreenCardTextColor,
                              ),
                            ),
                          );
                        }
                        final commits = state.commits!;
                        return Scrollbar(
                          controller: _commitGraphScrollController,
                          thumbVisibility: commits.length > 10,
                          child: SingleChildScrollView(
                            controller: _commitGraphScrollController,
                            child: GitCommitGraph(
                              commits: commits,
                              appTheme: widget.appTheme,
                            ),
                          ),
                        );
                      } else if (state is RepoStatusLoading) {
                        return const Center(child: CircularProgressIndicator());
                      } else {
                        return Center(
                          child: Text(
                            'Loading commits...',
                            style: TextStyle(
                              color: widget.appTheme.selectScreenCardTextColor,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                )
              : SizedBox.shrink(key: const ValueKey('commit-graph-collapsed')),
        ),
      ],
    );
  }

  

  Future<void> _performPush(BuildContext context) async {
    _showLoadingDialog(context, 'Pushing...');
    try {
      final result = await gitPush(widget.workSpace);
      if (context.mounted) {
        Navigator.of(context).pop();
        if (result.exitCode == 0) {
          _showSuccessSnackBar(context, 'Push successful');
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
        } else {
          _showErrorSnackBar(context, 'Push failed: ${result.stderr}');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _showErrorSnackBar(context, 'Push failed: $e');
      }
    }
  }

  Future<void> _performPull(BuildContext context) async {
    _showLoadingDialog(context, 'Pulling...');
    try {
      final result = await gitPull(widget.workSpace);
      if (context.mounted) {
        Navigator.of(context).pop();
        if (result.exitCode == 0) {
          _showSuccessSnackBar(context, 'Pull successful');
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
          context.read<RepoStatusBloc>().add(LoadCommitGraph(widget.workSpace));
        } else {
          final out = '${result.stdout}'.trim();
          final err = '${result.stderr}'.trim();
          final conflictDetected = out.contains('CONFLICT') || err.contains('CONFLICT');

          if (conflictDetected) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Merge conflict detected'),
                content: SingleChildScrollView(
                  child: Text(
                    'Merge conflicts were found during pull.\n\n${err.isNotEmpty ? 'Error:\n$err\n\n' : ''}${out.isNotEmpty ? 'Output:\n$out' : ''}',
                    style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
                      context.read<RepoStatusBloc>().add(LoadCommitGraph(widget.workSpace));
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          } else {
            _showErrorSnackBar(context, 'Pull failed: ${result.stderr}');
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _showErrorSnackBar(context, 'Pull failed: $e');
      }
    }
  }

  Future<void> _performCommitAndPush(
    BuildContext context,
    String message,
  ) async {
    _showLoadingDialog(context, 'Committing and pushing...');
    try {
      final commitResult = await gitCommit(
        widget.workSpace,
        message,
        all: true,
      );
      if (commitResult.exitCode != 0) {
        if (context.mounted) {
          Navigator.of(context).pop();
          _showErrorSnackBar(context, 'Commit failed: ${commitResult.stderr}');
        }
        return;
      }

      final pushResult = await gitPush(widget.workSpace);
      if (context.mounted) {
        Navigator.of(context).pop();
        if (pushResult.exitCode == 0) {
          _showSuccessSnackBar(context, 'Commit and push successful');
          context.read<GitCommitBloc>().add(GitCommitEvent(commitMessage: ''));
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
        } else {
          _showErrorSnackBar(context, 'Push failed: ${pushResult.stderr}');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _showErrorSnackBar(context, 'Failed: $e');
      }
    }
  }

  Future<void> _performCommitAndSync(
    BuildContext context,
    String message,
  ) async {
    _showLoadingDialog(context, 'Committing and syncing...');
    try {
      final commitResult = await gitCommit(
        widget.workSpace,
        message,
        all: true,
      );
      if (commitResult.exitCode != 0) {
        if (context.mounted) {
          Navigator.of(context).pop();
          _showErrorSnackBar(context, 'Commit failed: ${commitResult.stderr}');
        }
        return;
      }

      final syncResult = await gitSync(widget.workSpace);
      if (context.mounted) {
        Navigator.of(context).pop();
        if (syncResult.exitCode == 0) {
          _showSuccessSnackBar(context, 'Commit and sync successful');
          context.read<GitCommitBloc>().add(GitCommitEvent(commitMessage: ''));
          context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
        } else {
          _showErrorSnackBar(context, 'Sync failed: ${syncResult.stderr}');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        _showErrorSnackBar(context, 'Failed: $e');
      }
    }
  }

  void _showLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: widget.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : Colors.white,
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(
              message,
              style: TextStyle(
                color: widget.appTheme.selectScreenCardTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  

  void _showCreateBranchDialog(BuildContext context) {
    final repoBloc = context.read<RepoStatusBloc>();
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.appTheme.isDark
                  ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                  : [
                      const Color.fromARGB(255, 250, 250, 250),
                      const Color.fromARGB(255, 240, 240, 240)
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Create Branch',
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Branch name',
                  hintStyle: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor
                        .withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Color(0xff5090c8),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      if (controller.text.trim().isEmpty) return;
                      Navigator.pop(dialogContext);
                      final result = await gitCreateBranch(
                        widget.workSpace,
                        controller.text.trim(),
                      );
                      if (dialogContext.mounted) {
                        if (result.exitCode == 0) {
                          _showSuccessSnackBar(
                            dialogContext,
                            'Branch created and checked out',
                          );
                          repoBloc.add(
                            LoadRepoStatus(widget.workSpace),
                          );
                        } else {
                          _showErrorSnackBar(
                            dialogContext,
                            'Failed: ${result.stderr}',
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateBranchFromDialog(
    BuildContext context,
    List<String> branches,
  ) {
    final repoBloc = context.read<RepoStatusBloc>();
    final controller = TextEditingController();
    String? selectedBranch;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.call_split,
                        color: Colors.cyan,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Create Branch From',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Source Branch',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: branches
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedBranch = val),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    hintText: 'New branch name',
                    hintStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (controller.text.trim().isEmpty || selectedBranch == null) {
                          return;
                        }
                        Navigator.pop(dialogContext);
                        final result = await gitCreateBranch(
                          widget.workSpace,
                          controller.text.trim(),
                          fromRef: selectedBranch,
                        );
                        if (dialogContext.mounted) {
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(
                              dialogContext,
                              'Branch created from $selectedBranch',
                            );
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMergeBranchDialog(
    BuildContext context,
    List<String> branches,
    String? currentBranch,
  ) {
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedBranch;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.merge_type,
                        color: Colors.blue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Merge Branch',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Current branch: ${currentBranch ?? "unknown"}',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor
                        .withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Branch to merge',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: branches
                      .where((b) => b != currentBranch)
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedBranch = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedBranch == null) return;
                        Navigator.pop(dialogContext);
                        _showLoadingDialog(dialogContext, 'Merging...');
                        final result = await gitMergeBranch(
                          widget.workSpace,
                          selectedBranch!,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(
                              dialogContext,
                              'Merged $selectedBranch',
                            );
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Merge failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Merge'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRebaseBranchDialog(
    BuildContext context,
    List<String> branches,
    String? currentBranch,
  ) {
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedBranch;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.swap_calls,
                        color: Colors.deepOrange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Rebase onto Branch',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Current branch: ${currentBranch ?? "unknown"}',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor
                        .withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Rebase onto',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: branches
                      .where((b) => b != currentBranch)
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedBranch = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedBranch == null) return;
                        Navigator.pop(dialogContext);
                        _showLoadingDialog(dialogContext, 'Rebasing...');
                        final result = await gitRebaseBranch(
                          widget.workSpace,
                          selectedBranch!,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(
                              dialogContext,
                              'Rebased onto $selectedBranch',
                            );
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Rebase failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Rebase'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRenameBranchDialog(BuildContext context, List<String> branches) {
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedBranch;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.edit_outlined,
                        color: Colors.amber,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Rename Branch',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Branch to rename',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: branches
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setDialogState(() => selectedBranch = val);
                    controller.text = val ?? '';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    hintText: 'New name',
                    hintStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedBranch == null || controller.text.trim().isEmpty) return;
                        Navigator.pop(dialogContext);
                        final result = await gitRenameBranch(
                          widget.workSpace,
                          selectedBranch!,
                          controller.text.trim(),
                        );
                        if (dialogContext.mounted) {
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(dialogContext, 'Branch renamed');
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Rename'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteBranchDialog(
    BuildContext context,
    List<String> branches,
    String? currentBranch,
  ) {
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedBranch;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Delete Branch',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Branch to delete',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: branches
                      .where((b) => b != currentBranch)
                      .map(
                        (b) => DropdownMenuItem(
                          value: b,
                          child: Text(b),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedBranch = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedBranch == null) return;
                        Navigator.pop(dialogContext);
                        final result = await gitDeleteBranch(
                          widget.workSpace,
                          selectedBranch!,
                        );
                        if (dialogContext.mounted) {
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(dialogContext, 'Branch deleted');
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteRemoteBranchDialog(
    BuildContext context,
    List<String> remoteBranches,
  ) {
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedBranch;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.cloud_off_outlined,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Delete Remote Branch',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedBranch,
                  dropdownColor: widget.appTheme.isDark
                    ? const Color(0xff2b2b2b)
                    : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Remote branch to delete',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: remoteBranches.map((b) {
                    final display = b.replaceFirst('origin/', '');
                    return DropdownMenuItem(
                      value: display,
                      child: Text(b),
                    );
                  }).toList(),
                  onChanged: (val) => setDialogState(() => selectedBranch = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedBranch == null) return;
                        Navigator.pop(dialogContext);
                        _showLoadingDialog(dialogContext, 'Deleting remote branch...');
                        final result = await gitDeleteRemoteBranch(
                          widget.workSpace,
                          selectedBranch!,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(dialogContext, 'Remote branch deleted');
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(dialogContext, 'Failed: ${result.stderr}');
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPublishBranchDialog(
    BuildContext context,
    String? currentBranch,
  ) async {
    if (currentBranch == null) return;
    _showLoadingDialog(context, 'Publishing branch...');
    final result = await gitPublishBranch(widget.workSpace, currentBranch);
    if (context.mounted) {
      Navigator.pop(context);
      if (result.exitCode == 0) {
        _showSuccessSnackBar(context, 'Branch published to origin');
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
      } else {
        _showErrorSnackBar(context, 'Failed: ${result.stderr}');
      }
    }
  }

  

  void _showStashDialog(
    BuildContext context, {
    bool includeUntracked = false,
    bool stagedOnly = false,
  }) {
    final repoBloc = context.read<RepoStatusBloc>();
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.appTheme.isDark
                  ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                  : [
                      const Color.fromARGB(255, 250, 250, 250),
                      const Color.fromARGB(255, 240, 240, 240)
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.save_outlined,
                      color: Colors.orange,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      stagedOnly
                          ? 'Stash Staged'
                          : (includeUntracked
                              ? 'Stash (Include Untracked)'
                              : 'Stash'),
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: controller,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Stash message (optional)',
                  hintStyle: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor
                        .withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Color(0xff5090c8),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      final result = await gitStash(
                        widget.workSpace,
                        message: controller.text.trim().isEmpty
                            ? null
                            : controller.text.trim(),
                        includeUntracked: includeUntracked,
                        stagedOnly: stagedOnly,
                      );
                      if (dialogContext.mounted) {
                        if (result.exitCode == 0) {
                          _showSuccessSnackBar(dialogContext, 'Changes stashed');
                          repoBloc.add(
                            LoadRepoStatus(widget.workSpace),
                          );
                        } else {
                          _showErrorSnackBar(
                            dialogContext,
                            'Failed: ${result.stderr}',
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Stash'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showApplyStashDialog(
    BuildContext context,
    List<Map<String, String>> stashes, {
    bool pop = false,
  }) {
    if (stashes.isEmpty) {
      _showErrorSnackBar(context, 'No stashes available');
      return;
    }
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedStash;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: widget.appTheme.isDark
              ? const Color(0xff2b2b2b)
              : Colors.white,
          title: Text(
            pop ? 'Pop Stash' : 'Apply Stash',
            style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
          ),
          content: DropdownButtonFormField<String>(
            initialValue: selectedStash,
            dropdownColor: widget.appTheme.isDark
                ? const Color(0xff2b2b2b)
                : Colors.white,
            decoration: InputDecoration(
              labelText: 'Select stash',
              labelStyle: TextStyle(
                color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
              ),
            ),
            items: stashes
                .map(
                  (s) => DropdownMenuItem(
                    value: s['ref'],
                    child: Text(
                      '${s['ref']}: ${s['message']}',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) => setDialogState(() => selectedStash = val),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (selectedStash == null) return;
                Navigator.pop(dialogContext);
                final result = pop
                    ? await gitStashPop(
                        widget.workSpace,
                        stashRef: selectedStash,
                      )
                    : await gitStashApply(
                        widget.workSpace,
                        stashRef: selectedStash,
                      );
                if (dialogContext.mounted) {
                  if (result.exitCode == 0) {
                    _showSuccessSnackBar(
                      dialogContext,
                      pop ? 'Stash popped' : 'Stash applied',
                    );
                    repoBloc.add(
                      LoadRepoStatus(widget.workSpace),
                    );
                  } else {
                    _showErrorSnackBar(dialogContext, 'Failed: ${result.stderr}');
                  }
                }
              },
              child: Text(pop ? 'Pop' : 'Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDropStashDialog(
    BuildContext context,
    List<Map<String, String>> stashes,
  ) {
    if (stashes.isEmpty) {
      _showErrorSnackBar(context, 'No stashes available');
      return;
    }
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedStash;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: widget.appTheme.isDark
              ? const Color(0xff2b2b2b)
              : Colors.white,
          title: Text(
            'Drop Stash',
            style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
          ),
          content: DropdownButtonFormField<String>(
            initialValue: selectedStash,
            dropdownColor: widget.appTheme.isDark
                ? const Color(0xff2b2b2b)
                : Colors.white,
            decoration: InputDecoration(
              labelText: 'Select stash to drop',
              labelStyle: TextStyle(
                color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
              ),
            ),
            items: stashes
                .map(
                  (s) => DropdownMenuItem(
                    value: s['ref'],
                    child: Text(
                      '${s['ref']}: ${s['message']}',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (val) => setDialogState(() => selectedStash = val),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (selectedStash == null) return;
                Navigator.pop(dialogContext);
                final result = await gitStashDrop(
                  widget.workSpace,
                  stashRef: selectedStash,
                );
                if (dialogContext.mounted) {
                  if (result.exitCode == 0) {
                    _showSuccessSnackBar(dialogContext, 'Stash dropped');
                    repoBloc.add(
                      LoadRepoStatus(widget.workSpace),
                    );
                  } else {
                    _showErrorSnackBar(dialogContext, 'Failed: ${result.stderr}');
                  }
                }
              },
              child: const Text('Drop', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDropAllStashesDialog(BuildContext context) {
    final repoBloc = context.read<RepoStatusBloc>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.appTheme.isDark
          ? const Color(0xff2b2b2b)
          : Colors.white,
        title: Text(
          'Drop All Stashes',
          style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
        ),
        content: Text(
          'Are you sure you want to drop all stashes? This cannot be undone.',
          style: TextStyle(
            color: widget.appTheme.selectScreenCardTextColor.withAlpha(200),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final result = await gitStashClear(widget.workSpace);
              if (dialogContext.mounted) {
                if (result.exitCode == 0) {
                  _showSuccessSnackBar(dialogContext, 'All stashes dropped');
                  repoBloc.add(
                    LoadRepoStatus(widget.workSpace),
                  );
                } else {
                  _showErrorSnackBar(dialogContext, 'Failed: ${result.stderr}');
                }
              }
            },
            child: const Text('Drop All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showViewStashDialog(
    BuildContext context,
    List<Map<String, String>> stashes,
  ) {
    if (stashes.isEmpty) {
      _showErrorSnackBar(context, 'No stashes available');
      return;
    }
    String? selectedStash;
    String? stashContent;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: widget.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : Colors.white,
          title: Text(
            'View Stash',
            style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
          ),
          content: SizedBox(
            width: 400,
            height: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedStash,
                  dropdownColor: widget.appTheme.isDark
                    ? const Color(0xff2b2b2b)
                    : Colors.white,
                  decoration: InputDecoration(
                    labelText: 'Select stash',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withAlpha(150),
                    ),
                  ),
                  items: stashes
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['ref'],
                          child: Text(
                            '${s['ref']}: ${s['message']}',
                            style: TextStyle(
                              color: widget.appTheme.selectScreenCardTextColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) async {
                    setDialogState(() => selectedStash = val);
                    if (val != null) {
                      final content = await gitStashShow(widget.workSpace, val);
                      setDialogState(() => stashContent = content);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.appTheme.isDark
                          ? Colors.black26
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        stashContent ?? 'Select a stash to view',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: widget.appTheme.selectScreenCardTextColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  

  void _showCreateTagDialog(BuildContext context) {
    final repoBloc = context.read<RepoStatusBloc>();
    final nameController = TextEditingController();
    final messageController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.appTheme.isDark
                  ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                  : [
                      const Color.fromARGB(255, 250, 250, 250),
                      const Color.fromARGB(255, 240, 240, 240)
                    ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.label_outline,
                      color: Colors.purple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Create Tag',
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: nameController,
                autofocus: true,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Tag name (e.g., v1.0.0)',
                  hintStyle: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Color(0xff5090c8),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: messageController,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Message (optional, creates annotated tag)',
                  hintStyle: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor
                        .withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: widget.appTheme.isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Color(0xff5090c8),
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) return;
                      Navigator.pop(dialogContext);
                      final result = await gitCreateTag(
                        widget.workSpace,
                        nameController.text.trim(),
                        message: messageController.text.trim().isEmpty
                            ? null
                            : messageController.text.trim(),
                      );
                      if (dialogContext.mounted) {
                        if (result.exitCode == 0) {
                          _showSuccessSnackBar(dialogContext, 'Tag created');
                          repoBloc.add(
                            LoadRepoStatus(widget.workSpace),
                          );
                        } else {
                          _showErrorSnackBar(
                            dialogContext,
                            'Failed: ${result.stderr}',
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteTagDialog(BuildContext context, List<String> tags) {
    if (tags.isEmpty) {
      _showErrorSnackBar(context, 'No tags available');
      return;
    }
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedTag;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.label_off_outlined,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Delete Tag',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedTag,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Tag to delete',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: tags
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedTag = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedTag == null) return;
                        Navigator.pop(dialogContext);
                        final result = await gitDeleteTag(
                          widget.workSpace,
                          selectedTag!,
                        );
                        if (dialogContext.mounted) {
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(dialogContext, 'Tag deleted');
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(dialogContext, 'Failed: ${result.stderr}');
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteRemoteTagDialog(BuildContext context, List<String> tags) {
    if (tags.isEmpty) {
      _showErrorSnackBar(context, 'No tags available');
      return;
    }
    final repoBloc = context.read<RepoStatusBloc>();
    String? selectedTag;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.appTheme.isDark
                    ? [const Color(0xff2b2b2b), const Color(0xff1a1a1a)]
                    : [
                        const Color.fromARGB(255, 250, 250, 250),
                        const Color.fromARGB(255, 240, 240, 240)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.cloud_off_outlined,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Delete Remote Tag',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedTag,
                  dropdownColor: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Tag to delete from remote',
                    labelStyle: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: widget.appTheme.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(
                        color: Color(0xff5090c8),
                        width: 2,
                      ),
                    ),
                  ),
                  items: tags
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedTag = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedTag == null) return;
                        Navigator.pop(dialogContext);
                        _showLoadingDialog(dialogContext, 'Deleting remote tag...');
                        final result = await gitDeleteRemoteTag(
                          widget.workSpace,
                          selectedTag!,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          if (result.exitCode == 0) {
                            _showSuccessSnackBar(dialogContext, 'Remote tag deleted');
                            repoBloc.add(
                              LoadRepoStatus(widget.workSpace),
                            );
                          } else {
                            _showErrorSnackBar(
                              dialogContext,
                              'Failed: ${result.stderr}',
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGitActionsRow(
    BuildContext context,
    RepoStatusState repoState,
    bool isSignedIn,
  ) {
    final loaded = repoState is RepoStatusLoaded ? repoState : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.5, right: 5.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (repoState is RepoStatusLoaded && repoState.currentBranch != null)
          Expanded(
            child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: PopupMenuButton<String>(
                  tooltip: 'Switch branch',
                  color: widget.appTheme.isDark
                      ? const Color(0xff2b2b2b)
                      : Colors.white,
                  onSelected: (branch) async {
                    if (branch != repoState.currentBranch) {
                      _showLoadingDialog(context, 'Switching to $branch...');
                      final result = await gitCheckoutBranch(widget.workSpace, branch);
                      if (context.mounted) {
                        Navigator.pop(context);
                        if (result.exitCode == 0) {
                          _showSuccessSnackBar(context, 'Switched to $branch');
                          context.read<RepoStatusBloc>().add(
                                LoadRepoStatus(widget.workSpace),
                              );
                          context.read<RepoStatusBloc>().add(
                                LoadCommitGraph(widget.workSpace),
                              );
                        } else {
                          _showErrorSnackBar(
                            context,
                            'Failed: ${result.stderr}',
                          );
                        }
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    ...repoState.branches.map(
                      (branch) => PopupMenuItem<String>(
                        value: branch,
                        child: Row(
                          children: [
                            branch == repoState.currentBranch
                              ? Icon(Icons.check, size: 14, color: Colors.green)
                              : FaIcon(
                                FontAwesomeIcons.codeBranch,
                                size: 14,
                                color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
                              ),
                            const SizedBox(width: 8),
                            Text(
                              branch,
                              style: TextStyle(
                                color: widget.appTheme.selectScreenCardTextColor,
                                fontWeight: branch == repoState.currentBranch
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (repoState.remoteBranches.isNotEmpty) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(
                          'Remote Branches',
                          style: TextStyle(
                            color: widget.appTheme.selectScreenCardTextColor.withAlpha(100),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      ...repoState.remoteBranches
                          .where((rb) => !repoState.branches.contains(rb.replaceFirst('origin/', '')))
                          .map(
                            (branch) => PopupMenuItem<String>(
                              value: branch,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.cloud_outlined,
                                    size: 14,
                                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      branch,
                                      style: TextStyle(
                                        color: widget.appTheme.selectScreenCardTextColor,
                                      ),
                                      overflow: TextOverflow.ellipsis
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FaIcon(
                        FontAwesomeIcons.codeBranch,
                        size: 15,
                        color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
                      ),
                      const SizedBox(width: 3),
                      SizedBox(
                        width: 45,
                        child: Text(
                          repoState.currentBranch!,
                          style: TextStyle(
                            color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: widget.appTheme.selectScreenCardTextColor.withAlpha(150),
                      ),
                      if (repoState.unpushedCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(40),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '↑${repoState.unpushedCount}',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ),
          Tooltip(
            message: 'Pull',
            child: IconButton(
              visualDensity: VisualDensity(horizontal: -2, vertical: -2),
              onPressed: () => _performPull(context),
              icon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_downward,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(200),
                    size: 17,
                  ),
                  if ((loaded?.unpulledCount ?? 0) > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.lightBlueAccent.withAlpha(40),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'M ${loaded?.unpulledCount ?? 0}',
                        style: const TextStyle(
                          color: Colors.lightBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              style: IconButton.styleFrom(
                backgroundColor: widget.appTheme.isDark
                  ? Colors.white.withAlpha(20)
                  : Colors.black.withAlpha(20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Push',
            child: IconButton(
              visualDensity: VisualDensity(horizontal: -2, vertical: -2),
              onPressed: loaded?.hasUpstream == true
                ? () => _performPush(context)
                : null,
              icon: Icon(
                Icons.arrow_upward,
                color: loaded?.hasUpstream == true
                  ? widget.appTheme.selectScreenCardTextColor.withAlpha(200)
                  : widget.appTheme.selectScreenCardTextColor.withAlpha(80),
                size: 17,
              ),
              style: IconButton.styleFrom(
                backgroundColor: widget.appTheme.isDark
                  ? Colors.white.withAlpha(20)
                  : Colors.black.withAlpha(20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz,color: widget.appTheme.selectScreenCardTextColor.withAlpha(200)),
            color: widget.appTheme.isDark
              ? const Color(0xff2b2b2b)
              : Colors.white,
            onSelected: (value) =>
                _handleGitMenuAction(context, value, loaded, isSignedIn),
            itemBuilder: (context) => [
              _buildPopupMenuWithSubmenu('Branch', FontAwesomeIcons.codeBranch, [
                ('merge', 'Merge...'),
                ('rebase', 'Rebase Branch...'),
                ('divider', ''),
                ('create_branch', 'Create Branch...'),
                ('create_branch_from', 'Create Branch From...'),
                ('rename_branch', 'Rename Branch...'),
                ('divider', ''),
                ('delete_branch', 'Delete Branch...'),
                ('delete_remote_branch', 'Delete Remote Branch...'),
                ('publish_branch', 'Publish Branch'),
              ], loaded, isSignedIn),
              _buildPopupMenuWithSubmenu('Stash', Icons.archive, [
                ('stash', 'Stash'),
                ('stash_untracked', 'Stash (Include Untracked)'),
                ('stash_staged', 'Stash Staged'),
                ('divider', ''),
                ('apply_latest_stash', 'Apply Latest Stash'),
                ('apply_stash', 'Apply Stash...'),
                ('divider', ''),
                ('pop_latest_stash', 'Pop Latest Stash'),
                ('pop_stash', 'Pop Stash...'),
                ('divider', ''),
                ('drop_stash', 'Drop Stash...'),
                ('drop_all_stashes', 'Drop All Stashes'),
                ('view_stash', 'View Stash...'),
              ], loaded, isSignedIn),
              _buildPopupMenuWithSubmenu('Tags', Icons.local_offer, [
                ('create_tag', 'Create Tag...'),
                ('delete_tag', 'Delete Tag...'),
                ('delete_remote_tag', 'Delete Remote Tag...'),
              ], loaded, isSignedIn),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuEntry<String> _buildPopupMenuWithSubmenu(
    String title,
    dynamic icon,
    List<(String, String)> subItems,
    RepoStatusLoaded? loaded,
    bool isSignedIn,
  ) {
    return PopupMenuItem<String>(
      padding: EdgeInsets.zero,
      child: PopupMenuButton<String>(
        offset: const Offset(200, 0),
        color: widget.appTheme.isDark ? const Color(0xff2b2b2b) : Colors.white,
        onSelected: (value) {
          
          Navigator.pop(context);
          
          Future.microtask(() {
            if(mounted) {
              _handleGitMenuAction(context, value, loaded, isSignedIn);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              (() {
                if (icon is IconData) {
                  return Icon(
                    icon,
                    size: 18,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                  );
                }
                if (icon is Widget) {
                  return icon;
                }
                try {
                  return FaIcon(
                    icon,
                    size: 18,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                  );
                } catch (_) {
                  return Icon(
                    Icons.help_outline,
                    size: 18,
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                  );
                }
              }()),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: widget.appTheme.selectScreenCardTextColor.withAlpha(120),
              ),
            ],
          ),
        ),
        itemBuilder: (context) => subItems.map((item) {
          if (item.$1 == 'divider') {
            return const PopupMenuDivider() as PopupMenuEntry<String>;
          }
          return PopupMenuItem<String>(
            value: item.$1,
            child: Text(
              item.$2,
              style: TextStyle(
                color: widget.appTheme.selectScreenCardTextColor,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _handleGitMenuAction(
    BuildContext context,
    String action,
    RepoStatusLoaded? loaded,
    bool isSignedIn,
  ) {
    switch (action) {
      case 'merge':
        _showMergeBranchDialog(
          context,
          loaded?.branches ?? [],
          loaded?.currentBranch,
        );
        break;
      case 'rebase':
        _showRebaseBranchDialog(
          context,
          loaded?.branches ?? [],
          loaded?.currentBranch,
        );
        break;
      case 'create_branch':
        _showCreateBranchDialog(context);
        break;
      case 'create_branch_from':
        _showCreateBranchFromDialog(context, loaded?.branches ?? []);
        break;
      case 'rename_branch':
        _showRenameBranchDialog(context, loaded?.branches ?? []);
        break;
      case 'delete_branch':
        _showDeleteBranchDialog(
          context,
          loaded?.branches ?? [],
          loaded?.currentBranch,
        );
        break;
      case 'delete_remote_branch':
        _showDeleteRemoteBranchDialog(context, loaded?.remoteBranches ?? []);
        break;
      case 'publish_branch':
        _showPublishBranchDialog(context, loaded?.currentBranch);
        break;
      case 'stash':
        _showStashDialog(context);
        break;
      case 'stash_untracked':
        _showStashDialog(context, includeUntracked: true);
        break;
      case 'stash_staged':
        _showStashDialog(context, stagedOnly: true);
        break;
      case 'apply_latest_stash':
        _applyLatestStash(context);
        break;
      case 'apply_stash':
        _showApplyStashDialog(context, loaded?.stashes ?? []);
        break;
      case 'pop_latest_stash':
        _popLatestStash(context);
        break;
      case 'pop_stash':
        _showApplyStashDialog(context, loaded?.stashes ?? [], pop: true);
        break;
      case 'drop_stash':
        _showDropStashDialog(context, loaded?.stashes ?? []);
        break;
      case 'drop_all_stashes':
        _showDropAllStashesDialog(context);
        break;
      case 'view_stash':
        _showViewStashDialog(context, loaded?.stashes ?? []);
        break;
      case 'create_tag':
        _showCreateTagDialog(context);
        break;
      case 'delete_tag':
        _showDeleteTagDialog(context, loaded?.tags ?? []);
        break;
      case 'delete_remote_tag':
        _showDeleteRemoteTagDialog(context, loaded?.tags ?? []);
        break;
    }
  }

  Future<void> _applyLatestStash(BuildContext context) async {
    final result = await gitStashApply(widget.workSpace);
    if (context.mounted) {
      if (result.exitCode == 0) {
        _showSuccessSnackBar(context, 'Latest stash applied');
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
      } else {
        _showErrorSnackBar(context, 'Failed: ${result.stderr}');
      }
    }
  }

  Future<void> _popLatestStash(BuildContext context) async {
    final result = await gitStashPop(widget.workSpace);
    if (context.mounted) {
      if (result.exitCode == 0) {
        _showSuccessSnackBar(context, 'Latest stash popped');
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
      } else {
        _showErrorSnackBar(context, 'Failed: ${result.stderr}');
      }
    }
  }

  Widget _buildCommitButton(
    BuildContext context,
    RepoStatusLoaded repoState,
    bool isSignedIn,
  ) {
    final stagedEmpty = repoState.staged.isEmpty;
    final unstagedEmpty = repoState.unstaged.isEmpty;
    final hasChanges = !stagedEmpty || !unstagedEmpty;
    final hasRemote = repoState.hasRemote;
    final hasUpstream = repoState.hasUpstream;
    final unpushedCount = repoState.unpushedCount;
    final unpulledCount = repoState.unpulledCount;

    final bool showPush = !hasChanges && unpushedCount > 0 && hasUpstream;
    final bool showPublish =
        !hasChanges && hasRemote && !hasUpstream && isSignedIn;

    final Widget incomingSection = unpulledCount > 0
        ? Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.appTheme.isDark
                ? Colors.blueGrey.withAlpha(40)
                : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.arrow_downward, size: 14, color: Colors.blue),
                const SizedBox(width: 6),
                Text(
                  'Incoming changes: M $unpulledCount',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    Widget buttonSection;

    if (showPush) {
      buttonSection = SizedBox(
        width: 250,
        child: ElevatedButton.icon(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            backgroundColor: const WidgetStatePropertyAll(Color(0xff0e639c)),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          onPressed: () => _performPush(context),
          icon: const Icon(Icons.cloud_upload, size: 18),
          label: Text('Push ($unpushedCount)'),
        ),
      );
    } else if (showPublish) {
      buttonSection = SizedBox(
        width: 250,
        child: ElevatedButton.icon(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            backgroundColor: const WidgetStatePropertyAll(Color(0xff0e639c)),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          onPressed: () => _showPublishBranchDialog(context, repoState.currentBranch),
          icon: const Icon(Icons.cloud_upload, size: 18),
          label: const Text('Publish Branch'),
        ),
      );
    } else {
      buttonSection = SizedBox(
        width: 250,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ButtonStyle(
                  shape: const WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(6),
                        bottomLeft: Radius.circular(6),
                      ),
                    ),
                  ),
                  backgroundColor: WidgetStatePropertyAll(
                    hasChanges
                        ? const Color(0xff0e639c)
                        : const Color.fromARGB(255, 15, 61, 92),
                  ),
                  foregroundColor: WidgetStatePropertyAll(
                    hasChanges ? Colors.white : Colors.grey,
                  ),
                  textStyle: const WidgetStatePropertyAll(
                    TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                onPressed: hasChanges
                    ? () => _handleCommit(context, stagedEmpty, unstagedEmpty)
                    : null,
                child: const Text('\u2713 Commit'),
              ),
            ),
            Container(
              width: 50,
              height: 40,
              decoration: BoxDecoration(
                border: const BorderDirectional(
                  start: BorderSide(color: Colors.white, width: 0.5),
                ),
                color: hasChanges
                    ? const Color(0xff0e639c)
                    : const Color.fromARGB(255, 15, 61, 92),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(6),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: PopupMenuButton<String>(
                enabled: hasChanges,
                icon: FaIcon(
                  FontAwesomeIcons.caretDown,
                  color: hasChanges ? Colors.white : Colors.grey,
                  size: 14,
                ),
                color: widget.appTheme.cardTheme.color,
                onSelected: (value) {
                  final commitMessage = context.read<GitCommitBloc>().state.commitMessage;
                  if (commitMessage.isEmpty) {
                    _showCommitMessageError(context);
                    return;
                  }
                  if (value == 'commit_push') {
                    _performCommitAndPush(context, commitMessage);
                  } else if (value == 'commit_sync') {
                    _performCommitAndSync(context, commitMessage);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'commit_push',
                    child: Text(
                      'Commit and Push',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'commit_sync',
                    child: Text(
                      'Commit and Sync',
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [incomingSection, buttonSection],
    );
  }

  void _handleCommit(
    BuildContext context,
    bool stagedEmpty,
    bool unstagedEmpty,
  ) async {
    final commitMessage = context.read<GitCommitBloc>().state.commitMessage;
    if (commitMessage.isEmpty) {
      _showCommitMessageError(context);
      return;
    }

    if (!stagedEmpty) {
      await gitCommit(widget.workSpace, commitMessage);
      if (context.mounted) {
        context.read<GitCommitBloc>().add(GitCommitEvent(commitMessage: ''));
        context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
      }
    } else if (!unstagedEmpty) {
      final repoBloc = context.read<RepoStatusBloc>();
      final gitBloc = context.read<GitCommitBloc>();
      showDialog(
        context: context,
        builder: (context) => BlocProvider.value(
          value: repoBloc,
          child: BlocProvider.value(
            value: gitBloc,
            child: AlertDialog(
              title: Text(
                "Changes aren't staged",
                style: TextStyle(color: Colors.grey[400], fontSize: 20),
              ),
              backgroundColor: widget.appTheme.isDark
                  ? const Color(0xff2b2b2b)
                  : const Color.fromARGB(255, 240, 240, 240),
              icon: const Icon(Icons.warning_amber_outlined, size: 35),
              iconColor: Colors.amber,
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    "Cancel",
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await gitCommit(widget.workSpace, commitMessage, all: true);
                    if (context.mounted) {
                      gitBloc.add(GitCommitEvent(commitMessage: ''));
                      repoBloc.add(LoadRepoStatus(widget.workSpace));
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text(
                    "Stage all and Commit",
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _showCommitMessageError(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Commit message cannot be empty.",
          style: TextStyle(color: Colors.grey[400], fontSize: 20),
        ),
        backgroundColor: widget.appTheme.isDark
            ? const Color(0xff2b2b2b)
            : const Color.fromARGB(255, 240, 240, 240),
        icon: const Icon(Icons.info_outline, size: 35),
        iconColor: Colors.red,
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showInitializeRepoDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: widget.appTheme.isDark
                ? const Color(0xff2b2b2b)
                : const Color.fromARGB(255, 240, 240, 240),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xff0e639c).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.create_new_folder,
                      color: Color(0xff0e639c),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "Initialize Repository",
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                "This will create a new Git repository in the current folder. This action initializes Git tracking for version control.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor.withValues(
                    alpha: 0.8,
                  ),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _initializeRepository(widget.workSpace);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff0e639c),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      "Initialize",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPublishToGithubDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: widget.appTheme.isDark
                ? const Color(0xff2b2b2b)
                : const Color.fromARGB(255, 240, 240, 240),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const FaIcon(
                      FontAwesomeIcons.github,
                      color: Colors.black87,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "Publish to GitHub",
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                "This will create a new repository on GitHub and push your local code. You'll need to authenticate with GitHub first.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: widget.appTheme.selectScreenCardTextColor.withValues(
                    alpha: 0.8,
                  ),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amber[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Make sure you have GitHub CLI installed and authenticated.",
                        style: TextStyle(
                          color: Colors.amber[800],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await _publishToGithub();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      "Publish",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initializeRepository(String workspacePath) async {
    try {
      await initRepo(workspacePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Repository initialized successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isARepo = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize repository: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _publishToGithub() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Publishing to GitHub... (Feature coming soon)'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish to GitHub: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isTemp = widget.workSpace == templateDir;
    _isARepo = Directory(path.join(widget.workSpace, '.git')).existsSync();
    final List<Widget> noRepoFound = [
      Text(
        "The folder currently open\ndosen't hava a Git repository.\nYou can initialize a repository\nwhich will enable source control\nfeatures powered by Git.",
        textAlign: TextAlign.start,
        style: TextStyle(
          color: widget.appTheme.isDark
              ? Colors.grey[400]
              : widget.appTheme.selectScreenCardTextColor,
        ),
      ),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: _showInitializeRepoDialog,
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(5)),
            ),
          ),
          backgroundColor: WidgetStatePropertyAll(Color(0xff0e639c)),
          foregroundColor: WidgetStatePropertyAll(Colors.white),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        child: const Text("Initialize Repository"),
      ),
      const SizedBox(height: 13.5),
      Text(
        "You can directly publish this\nfolder to a GitHub repository.\nOnce published, you'll have\naccess to source control featured\npowered by Git and GitHub",
        textAlign: TextAlign.start,
        style: TextStyle(
          color: widget.appTheme.isDark
              ? Colors.grey[400]
              : widget.appTheme.selectScreenCardTextColor,
        ),
      ),
      const SizedBox(height: 13.5),
      SizedBox(
        width: 200,
        child: ElevatedButton(
          onPressed: _showPublishToGithubDialog,
          style: const ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(5)),
              ),
            ),
            backgroundColor: WidgetStatePropertyAll(Color(0xff0e639c)),
            foregroundColor: WidgetStatePropertyAll(Colors.white),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          child: const Row(
            children: [
              FaIcon(FontAwesomeIcons.github, color: Colors.white),
              SizedBox(width: 8),
              Text("Publish to Github"),
            ],
          ),
        ),
      ),
    ];
    return !isTemp
      ? SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 25, left: 10),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    "SOURCE CONTROL",
                    style: TextStyle(
                      fontWeight: widget.appTheme.isDark
                          ? FontWeight.w300
                          : FontWeight.w500,
                      color: widget.appTheme.selectScreenCardTextColor,
                    ),
                  ),
                ),
                const SizedBox(height: 13.5),
                if (!_isARepo) ...noRepoFound,
                if (_isARepo) ...[
                  BlocBuilder<GithubAuthCubit, GithubAuthState>(
                    builder: (context, authState) {
                      final isSignedIn = authState.isSignedIn;
                      return BlocBuilder<RepoStatusBloc, RepoStatusState>(
                        builder: (context, repoState) {
                          return _buildGitActionsRow(context, repoState, isSignedIn);
                        },
                      );
                    },
                  ),
                  BlocBuilder<GitCommitBloc, GitCommitState>(
                    builder: (context, commitState) {
                      return SizedBox(
                        height: 50,
                        width: 250,
                        child: TextField(
                          controller: _commitController,
                          keyboardType: TextInputType.url,
                          style: const TextStyle(color: Colors.grey),
                          cursorColor: Colors.grey,
                          onChanged: (val) {
                            context.read<GitCommitBloc>().add(
                              GitCommitEvent(commitMessage: val),
                            );
                          },
                          decoration: InputDecoration(
                            suffixIcon: BlocBuilder<AIBloc, AIState>(
                              builder: (context, aiState) {
                                return BlocBuilder<GithubAuthCubit, GithubAuthState>(
                                  builder: (context, authState) {
                                    return BlocBuilder<CopilotChatBloc, CopilotChatState>(
                                      builder: (context, chatState) {
                                        final copilotSignedIn = context.read<CopilotBloc>().state.isSignedIn;
                                        _requestCopilotModelsIfNeeded(authState.isSignedIn, copilotSignedIn, chatState);

                                        final canGenerate = !_isGeneratingCommitMessage &&
                                            _canGenerateCommitMessage(
                                              aiState: aiState,
                                              githubSignedIn: authState.isSignedIn,
                                              copilotSignedIn: copilotSignedIn,
                                              chatState: chatState,
                                            );

                                        final tooltip = _isGeneratingCommitMessage
                                            ? 'Generating commit message...'
                                            : (!aiState.isEnabled
                                                ? 'AI is disabled in settings'
                                                : canGenerate
                                                    ? 'Generate commit message'
                                                    : (chatState.isFetchingModels
                                                        ? 'Loading AI models...'
                                                        : 'No AI model available'));

                                        return Tooltip(
                                          message: tooltip,
                                          child: IconButton(
                                            onPressed: canGenerate
                                                ? () => _generateCommitMessage(
                                                      context: context,
                                                      aiState: aiState,
                                                      chatState: chatState,
                                                      githubSignedIn: authState.isSignedIn,
                                                      copilotSignedIn: copilotSignedIn,
                                                    )
                                                : null,
                                            icon: _isGeneratingCommitMessage
                                                ? const SizedBox(
                                                    height: 20,
                                                    width: 20,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : SvgPicture.asset(
                                                    'assets/icons/ai.svg',
                                                    height: 20,
                                                    width: 20,
                                                    colorFilter: ColorFilter.mode(
                                                      canGenerate
                                                          ? widget.appTheme.selectScreenCardTextColor
                                                              .withValues(alpha: 0.85)
                                                          : widget.appTheme.selectScreenCardTextColor
                                                              .withValues(alpha: 0.35),
                                                      BlendMode.srcIn,
                                                    ),
                                                  ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                            hintText: "Commit message",
                            hintStyle: TextStyle(
                              color: widget.appTheme.selectScreenCardTextColor
                                  .withAlpha(120),
                            ),
                            border: const OutlineInputBorder(),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(
                                color: Color(0xff0e639c),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  BlocBuilder<GithubAuthCubit, GithubAuthState>(
                    builder: (context, authState) {
                      final isSignedIn = authState.isSignedIn;
                      return BlocBuilder<RepoStatusBloc, RepoStatusState>(
                        builder: (_, repoState) {
                          return Column(
                            children: [
                              if (repoState is RepoStatusLoaded)
                                _buildCommitButton(context, repoState, isSignedIn),
                              if (repoState is RepoStatusLoading || repoState is RepoStatusInitial) ...[
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.only(top: 20),
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ] else if (repoState is RepoStatusError) ...[
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    'Error: ${repoState.message}',
                                    style: TextStyle(
                                      color: widget.appTheme.selectScreenCardTextColor,
                                    ),
                                  ),
                                ),
                              ] else if (repoState is RepoStatusLoaded) ...[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (repoState.staged.isNotEmpty)
                                      _buildCollapsibleChangesList(
                                        title: "Staged Changes",
                                        isExpanded: _stagedExpanded,
                                        onToggle: () => setState(() => _stagedExpanded =!_stagedExpanded),
                                        itemCount: repoState.staged.length,
                                        actionButton: Tooltip(
                                          message: "Unstage All Changes",
                                          child: IconButton(
                                            onPressed: () async {
                                              await unstageAll(
                                                widget.workSpace,
                                              );
                                              try {
                                                if (context.mounted) {
                                                  context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
                                                }
                                              } catch (_) {}
                                            },
                                            icon: Text(
                                              "—",
                                              style: TextStyle(
                                                color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                                              ),
                                            ),
                                          ),
                                        ),
                                        controller: _stagedScrollController,
                                        itemBuilder: (_, index) {
                                          final fileName =
                                              _extractGitFilename(
                                                repoState.staged[index],
                                              );
                                          final (String, Color)
                                          repoIndicator =
                                              gitFileStatus[repoState.staged[index].substring(0, 2).trim()]!;
                                          return Padding(
                                            padding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(8),
                                                onTap: () {},
                                                child: Container(
                                                  padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10,
                                                    ),
                                                  decoration: BoxDecoration(
                                                    color: widget.appTheme.isDark
                                                      ? Colors.white.withValues(alpha: 0.03)
                                                      : Colors.black.withValues(alpha: 0.03),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: repoIndicator.$2.withValues(alpha: 0.2),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 32,
                                                        height: 32,
                                                        padding: const EdgeInsets.all(6),
                                                        decoration: BoxDecoration(
                                                          color: repoIndicator.$2.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: (() {
                                                          try {
                                                            return languages.singleWhere((lang) => 
                                                              lang.extension.contains(
                                                                path.extension(path.basename(fileName),).replaceAll('.','',)
                                                              )).icon;
                                                          } catch (e) {
                                                            return Icon(
                                                              Icons .insert_drive_file,
                                                              size: 18,
                                                              color: repoIndicator.$2,
                                                            );
                                                          }
                                                        })(),
                                                      ),
                                                      const SizedBox(
                                                        width: 12,
                                                      ),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text(path.basename(fileName),
                                                              style: TextStyle(
                                                                fontSize: 13.5,
                                                                fontWeight: FontWeight.w500,
                                                                color: repoIndicator.$2,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            const SizedBox(
                                                              height: 2,
                                                            ),
                                                            Text(
                                                              fileName,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: widget.appTheme.selectScreenCardTextColor.withValues(alpha:0.5),
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 3,
                                                          ),
                                                        decoration: BoxDecoration(
                                                          color: repoIndicator.$2.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          repoIndicator.$1,
                                                          style: TextStyle(
                                                            color: repoIndicator.$2,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        width: 4,
                                                      ),
                                                      Tooltip(
                                                        message:"Unstage Changes",
                                                        child: InkWell(
                                                          borderRadius:BorderRadius.circular(4),
                                                          onTap: () async {
                                                            await unstageChange(fileName,widget.workSpace);
                                                            if (context.mounted) {
                                                              try {
                                                                context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
                                                              } catch (_) {}
                                                            }
                                                          },
                                                          child: Padding(
                                                            padding: const EdgeInsets.all(6),
                                                            child: Icon(
                                                              Icons.remove_circle_outline,
                                                              size: 18,
                                                              color: widget.appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                                                            ),
                                                          ),
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
                                    if (repoState.unstaged.isNotEmpty)
                                      _buildCollapsibleChangesList(
                                        title: "Unstaged Changes",
                                        isExpanded: _unstagedExpanded,
                                        onToggle: () => setState(
                                          () => _unstagedExpanded =
                                              !_unstagedExpanded,
                                        ),
                                        itemCount: repoState.unstaged.length,
                                        actionButton: Tooltip(
                                          message: "Stage All Changes",
                                          child: IconButton(
                                            onPressed: () async {
                                              await stageAll(
                                                widget.workSpace,
                                              );
                                              if (context.mounted) {
                                                try {
                                                  context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
                                                } catch (_) {}
                                              }
                                            },
                                            icon: Icon(
                                              Icons.add,
                                              color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                                            ),
                                          ),
                                        ),
                                        controller: _unstagedScrollController,
                                        itemBuilder: (_, index) {
                                          final fileName =_extractGitFilename(repoState.unstaged[index]);
                                          final (String, Color)
                                          repoIndicator = gitFileStatus[repoState.unstaged[index].substring(0, 2).trim()]!;
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8,vertical: 3),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius:BorderRadius.circular(8),
                                                onTap: () {
                                                  widget.onOpenDiffView?.call(fileName, widget.workSpace, widget.activeEditorsBloc!);
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: widget.appTheme.isDark
                                                      ? Colors.white.withValues(alpha: 0.03)
                                                      : Colors.black.withValues(alpha: 0.03),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: repoIndicator.$2.withValues(alpha: 0.2),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 32,
                                                        height: 32,
                                                        padding: const EdgeInsets.all(6),
                                                        decoration: BoxDecoration(
                                                          color: repoIndicator.$2.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: (() {
                                                          try {
                                                            return languages.singleWhere((lang)
                                                              => lang.extension.contains(path.extension(
                                                                  path.basename(fileName)).replaceAll('.', ''),
                                                                  ),
                                                                ).icon;
                                                          } catch (e) {
                                                            return Icon(
                                                              Icons.insert_drive_file,
                                                              size: 18,
                                                              color: repoIndicator.$2,
                                                            );
                                                          }
                                                        })(),
                                                      ),
                                                      const SizedBox(width: 12,),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text(path.basename(fileName),
                                                              style: TextStyle(
                                                                fontSize:13.5,
                                                                fontWeight: FontWeight.w500,
                                                                color: repoIndicator.$2,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            const SizedBox(height: 2),
                                                            Text(
                                                              fileName,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: widget.appTheme.selectScreenCardTextColor.withValues(alpha:0.5),
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6,vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: repoIndicator.$2.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          repoIndicator.$1,
                                                          style: TextStyle(
                                                            color: repoIndicator.$2,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Tooltip(
                                                        message: "Discard Change",
                                                        child: InkWell(
                                                          borderRadius: BorderRadius.circular(4),
                                                          onTap: () {
                                                            final repoBloc = context.read<RepoStatusBloc>();
                                                            showDialog(
                                                              context: context,
                                                              builder: (context) => BlocProvider.value(
                                                                value: repoBloc,
                                                                child: AlertDialog(
                                                                  title: Text(
                                                                    "Are you sure want to discard the changes?",
                                                                    style: TextStyle(
                                                                      color: Colors.grey[400],
                                                                      fontSize: 20,
                                                                    ),
                                                                  ),
                                                                  backgroundColor:widget.appTheme.isDark
                                                                      ? const Color(0xff2b2b2b)
                                                                      : const Color.fromARGB(255,240,240,240),
                                                                  icon: const Icon(Icons.info_outline, size: 35),
                                                                  iconColor: Colors.blue,
                                                                  actionsAlignment:MainAxisAlignment.center,
                                                                  actions: [
                                                                    TextButton(
                                                                      onPressed: () => Navigator.of(context,).pop(),
                                                                      child: const Text(
                                                                        "Cancel",
                                                                        style: TextStyle(
                                                                          color:Colors.red,
                                                                          fontSize:17,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width:25),
                                                                    TextButton(
                                                                      onPressed: () async {
                                                                        try {
                                                                          await gitRestoreFile(fileName, widget.workSpace);
                                                                          if (!context.mounted) return;

                                                                          final activeEditorBloc = widget.activeEditorsBloc;
                                                                          if (activeEditorBloc != null) {
                                                                            final activeEditors = activeEditorBloc.state.activeEditors;
                                                                            ActiveEditor? activeEditor;

                                                                            for (final editor in activeEditors) {
                                                                              if (editor.isActive) {
                                                                                activeEditor = editor;
                                                                                break;
                                                                              }
                                                                            }

                                                                            activeEditor ??= activeEditors.isNotEmpty ? activeEditors.first: null;
                                                                            activeEditor?.controller.refetchFile();
                                                                          }

                                                                          try {
                                                                            repoBloc.add(LoadRepoStatus(widget.workSpace));
                                                                          } catch (_) {}
                                                                        } catch (_) {
                                                                          if (context.mounted) {
                                                                            _showErrorSnackBar(
                                                                              context,
                                                                              'Failed to discard changes',
                                                                            );
                                                                          }
                                                                        } finally {
                                                                          if (context.mounted) {
                                                                            Navigator.of(context).pop();
                                                                          }
                                                                        }
                                                                      },
                                                                      child: const Text(
                                                                        "Yes",
                                                                        style: TextStyle(
                                                                          color: Colors.blue,
                                                                          fontSize: 17,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                          child: Padding(
                                                            padding: const EdgeInsets.all(6),
                                                            child: FaIcon(
                                                              FontAwesomeIcons.arrowRotateLeft,
                                                              size: 16,
                                                              color: widget.appTheme.selectScreenCardTextColor.withValues(alpha:0.6),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        width: 4,
                                                      ),
                                                      Tooltip(
                                                        message: "Stage Changes",
                                                        child: InkWell(
                                                          borderRadius: BorderRadius.circular(4),
                                                          onTap: () async {
                                                            await stageChange(fileName, widget.workSpace);
                                                            if (context.mounted) {
                                                              try {
                                                                context.read<RepoStatusBloc>().add(LoadRepoStatus(widget.workSpace));
                                                              } catch (_) {}
                                                            }
                                                          },
                                                          child: Padding(
                                                            padding: const EdgeInsets.all(6),
                                                            child: Icon(
                                                              Icons.add_circle_outline,
                                                              size: 18,
                                                              color: widget.appTheme.selectScreenCardTextColor.withValues(alpha:0.6),
                                                            ),
                                                          ),
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
                                    Divider(thickness: 0.1,endIndent: 12,color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                                    ),
                                    _buildCollapsibleCommitGraph(),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        )
      : Center(
          child: Text(
            "Cannot initalize a git repository in the temp directory.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.appTheme.selectScreenCardTextColor,
            ),
          ),
        );
  }
}

class APITesting extends StatelessWidget {
  final Map<String, String> params, headers;
  final TextEditingController apiUrlController;
  final AppTheme appTheme;
  final TabController paramTabController, apiTabController;
  const APITesting({
    super.key,
    required this.params,
    required this.headers,
    required this.apiUrlController,
    required this.appTheme,
    required this.paramTabController,
    required this.apiTabController,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 15),
      child: BlocBuilder<ApiBloc, ApiState>(
        builder: (context, webState) {
          Map<TextEditingController, TextEditingController> paramControllers = {
            for (int _ in Iterable.generate(webState.params.length + 1))
              TextEditingController(): TextEditingController(),
          };
          Map<TextEditingController, TextEditingController> headerControllers =
              {
                for (int _ in Iterable.generate(webState.headers.length + 1))
                  TextEditingController(): TextEditingController(),
              };
          if (webState.params.isNotEmpty) {
            for (int index = 0; index < webState.params.length; index++) {
              paramControllers.keys.toList()[index].text = webState.params.keys.toList()[index];
              paramControllers.values.toList()[index].text = webState.params.values.toList()[index];
              params[webState.params.keys.toList()[index]] = webState.params.values.toList()[index];
            }
          }
          if (webState.headers.isNotEmpty) {
            for (int index = 0; index < webState.headers.length; index++) {
              headerControllers.keys.toList()[index].text = webState.headers.keys.toList()[index];
              headerControllers.values.toList()[index].text = webState.headers.values.toList()[index];
              headers[webState.headers.keys.toList()[index]] = webState.headers.values.toList()[index];
            }
          }
          apiUrlController.text = webState.url ?? "Enter URL";
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 15),
              Text(
                "API TESTING",
                style: TextStyle(
                  color: appTheme.selectScreenCardTextColor,
                  fontWeight: appTheme.isDark
                    ? FontWeight.w300
                    : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 15),
              DropdownButtonHideUnderline(
                child: DropdownButton(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  value: webState.method,
                  dropdownColor: appTheme.isDark
                    ? const Color(0xff2b2b2b)
                    : const Color.fromARGB(255, 241, 241, 241),
                  items: [
                    DropdownMenuItem(
                      value: "POST",
                      child: Text(
                        "POST",
                        style: TextStyle(
                          color: const Color(0xffe0790b),
                          fontWeight: appTheme.isDark
                            ? FontWeight.w500
                            : FontWeight.w600,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: "GET",
                      child: Text(
                        "GET",
                        style: TextStyle(
                          color: const Color(0xff26cda3),
                          fontWeight: appTheme.isDark
                            ? FontWeight.w500
                            : FontWeight.w600,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: "PUT",
                      child: Text(
                        "PUT",
                        style: TextStyle(
                          color: const Color(0xff097bed),
                          fontWeight: appTheme.isDark
                            ? FontWeight.w500
                            : FontWeight.w600,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: "DELETE",
                      child: Text(
                        "DELETE",
                        style: TextStyle(
                          color: const Color(0xfff22814),
                          fontWeight: appTheme.isDark
                            ? FontWeight.w500
                            : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    context.read<ApiBloc>().add(ApiEvent(method: value!));
                  },
                ),
              ),
              SizedBox(
                height: 50,
                width: 250,
                child: TextField(
                  controller: apiUrlController,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(color: Colors.grey),
                  cursorColor: Colors.grey,
                  onChanged: (val) {
                    context.read<ApiBloc>().add(GetUrl(url: val));
                  },
                  decoration: const InputDecoration(
                    hintText: "Enter Url",
                    border: OutlineInputBorder(),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xff0e639c)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TabBar(
                labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                controller: paramTabController,
                dividerColor: appTheme.isDark
                  ? const Color.fromARGB(255, 61, 61, 61)
                  : const Color.fromARGB(255, 182, 182, 182),
                dividerHeight: 1.5,
                unselectedLabelColor: appTheme.isDark
                  ? Colors.grey
                  : const Color.fromARGB(255, 102, 102, 102),
                labelColor: const Color.fromARGB(255, 62, 142, 195),
                indicatorColor: const Color(0xff0e639c),
                indicatorWeight: 2.5,
                tabs: const [
                  Tab(text: "Params"),
                  Tab(text: "Headers"),
                  Tab(text: "Body"),
                ],
              ),
              const SizedBox(height: 15),
              SizedBox(
                height:
                    60 *
                    ((() {
                      if (webState.params.isEmpty && webState.headers.isEmpty) {
                        return 1.0;
                      }
                      if (webState.params.length > webState.headers.length) {
                        return webState.params.length.toDouble() + 1.0;
                      }
                      return webState.headers.length.toDouble() + 1.0;
                    })()),
                child: TabBarView(
                  controller: paramTabController,
                  children: [
                    Column(
                      children: List.generate(webState.params.length + 1, (
                        index,
                      ) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  cursorColor: Colors.grey,
                                  style: TextStyle(
                                    color: appTheme.selectScreenCardTextColor,
                                  ),
                                  controller: paramControllers.keys
                                      .toList()[index],
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 8.5,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xff0e639c),
                                      ),
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 5,
                                child: TextField(
                                  cursorColor: Colors.grey,
                                  style: TextStyle(
                                    color: appTheme.selectScreenCardTextColor,
                                  ),
                                  controller: paramControllers.values
                                      .toList()[index],
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 8.5,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xff0e639c),
                                      ),
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  if (index == webState.params.length) {
                                    if (paramControllers.keys.toList()[index].text.isNotEmpty &&
                                        paramControllers.values.toList()[index].text.isNotEmpty) {
                                      params.addEntries({
                                          paramControllers.keys.toList()[index].text: paramControllers.values.toList()[index].text,
                                        }.entries,
                                      );
                                    }
                                  } else {
                                    params.remove(
                                      paramControllers.keys.toList()[index].text,
                                    );
                                  }
                                  context.read<ApiBloc>().add(
                                    GetParams(params: params),
                                  );
                                  String baseUrl = apiUrlController.text.split(
                                    '?',
                                  )[0];
                                  String queryString = '';
                                  if (params.isNotEmpty) {
                                    queryString = params.entries.map((entry) =>'${entry.key}=${entry.value}').join('&');
                                  }
                                  String newUrl = queryString.isNotEmpty
                                    ? '$baseUrl?$queryString'
                                    : baseUrl;
                                  apiUrlController.value = apiUrlController.value.copyWith(
                                    text: newUrl,
                                    selection: TextSelection.collapsed(
                                      offset: newUrl.length,
                                    ),
                                  );
                                  context.read<ApiBloc>().add(
                                    GetUrl(url: newUrl),
                                  );
                                },
                                icon: Icon(
                                  index == webState.params.length
                                    ? Icons.add
                                    : Icons.remove,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                    Column(
                      children: List.generate(webState.headers.length + 1, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  cursorColor: Colors.grey,
                                  style: const TextStyle(color: Colors.grey),
                                  controller: headerControllers.keys.toList()[index],
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 8.5,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xff0e639c),
                                      ),
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                flex: 5,
                                child: TextField(
                                  cursorColor: Colors.grey,
                                  style: const TextStyle(color: Colors.grey),
                                  controller: headerControllers.values.toList()[index],
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 0,
                                      horizontal: 8.5,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xff0e639c),
                                      ),
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  if (index == webState.headers.length) {
                                    if (headerControllers.keys.toList()[index].text.isNotEmpty &&
                                        headerControllers.values.toList()[index].text.isNotEmpty) {
                                      headers.addEntries({
                                        headerControllers.keys.toList()[index].text: headerControllers.values.toList()[index].text,
                                      }.entries,
                                      );
                                    }
                                  } else {
                                    headers.remove(
                                      headerControllers.keys.toList()[index].text,
                                    );
                                  }
                                  context.read<ApiBloc>().add(
                                    GetHeaders(headers: headers),
                                  );
                                },
                                icon: Icon(
                                  index == webState.headers.length
                                    ? Icons.add
                                    : Icons.remove,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 7),
                      child: TextField(
                        textAlignVertical: TextAlignVertical.top,
                        cursorColor: Colors.grey,
                        style: TextStyle(color: Colors.grey),
                        maxLines: null,
                        minLines: null,
                        decoration: InputDecoration(
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xff0e639c)),
                          ),
                          border: OutlineInputBorder(),
                        ),
                        expands: true,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 100,
                child: ElevatedButton(
                  onPressed: () async {
                    Map<String, dynamic> data = await sendRequest(
                      url: apiUrlController.text,
                      method: webState.method,
                      headers: webState.headers,
                    );
                    if (context.mounted) {
                      context.read<ApiBloc>().add(GotApiData(data: data));
                    }
                  },
                  style: const ButtonStyle(
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                    backgroundColor: WidgetStatePropertyAll(Color(0xff0e639c)),
                    foregroundColor: WidgetStatePropertyAll(Colors.white),
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  child: const Text("Send"),
                ),
              ),
              webState.data == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.bottomCenter,
                    child: TabBar(
                      controller: apiTabController,
                      dividerColor: const Color.fromARGB(255, 61, 61, 61),
                      dividerHeight: 1.5,
                      unselectedLabelColor: Colors.grey,
                      labelColor: const Color.fromARGB(255, 62, 142, 195),
                      indicatorColor: const Color(0xff0e639c),
                      indicatorWeight: 2.5,
                      tabs: const [
                        Tab(
                          child: Text("{ }", style: TextStyle(fontSize: 22)),
                        ),
                        Tab(icon: FaIcon(FontAwesomeIcons.html5)),
                        Tab(icon: Icon(Icons.raw_on_sharp, size: 35)),
                      ],
                    ),
                  ),
              const SizedBox(height: 20),
              webState.data == null
                ? const SizedBox.shrink()
                : Expanded(
                    child: TabBarView(
                      controller: apiTabController,
                      children: [
                        JsonWidget(
                          expandIcon: const Icon(
                            Icons.keyboard_arrow_down_sharp,
                            color: Colors.grey,
                          ),
                          collapseIcon: const Icon(
                            Icons.keyboard_arrow_right_sharp,
                            color: Colors.grey,
                          ),
                          json: webState.data!,
                        ),
                        InAppWebView(
                          onWebViewCreated: (InAppWebViewController webViewController) {
                            webViewController.loadData(
                              data: webState.data!['body'],
                            );
                          },
                        ),
                        SingleChildScrollView(
                          child: Text(
                            webState.data!.toString(),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}



class AIChat extends StatefulWidget {
  final String filePath, workspacePath;
  const AIChat({
    required this.filePath,
    required this.workspacePath, 
    super.key
  });

  @override
  State<AIChat> createState() => _AIChatState();
}

class _ModelOption {
  final String id, name;
  final String? provider;
  final String? rateLabel;
  final Widget icon;
  final bool isCopilot;
  _ModelOption({
    required this.id,
    required this.name,
    this.provider,
    this.rateLabel,
    required this.icon,
    this.isCopilot = false,
  });
}

class _AIChatState extends State<AIChat> with SingleTickerProviderStateMixin {
  static final RegExp _toolEditPattern = RegExp(r'^\[\[ROXUM_EDIT:([^|\]]+)\|(\d+)\|(\d+)\]\]$');
  static final RegExp _toolTerminalPattern = RegExp(r'^\[\[ROXUM_TERMINAL:([^\]]+)\]\]$');
  static final RegExp _toolStatusPattern = RegExp(r'^\[\[ROXUM_STATUS:([^\]]+)\]\]$');
  static const String _thinkingStartMarker = '[[ROXUM_THINK_START]]';
  static const String _thinkingEndMarker = '[[ROXUM_THINK_END]]';

  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _statusPulseController;
  http.Client? _currentClient;
  bool _initialScrollDone = false;
  bool _requestedCopilotModelRefresh = false;
  PendingEditFile? _pendingEdits;
  Timer? _pendingRefreshTimer;
  bool _isApplyingPendingAction = false;
  bool _isPendingPollingActive = false;
  bool _copilotSignedInFromPrefs = false;
  StreamSubscription<CopilotState>? _copilotStateSubscription;
  List<AIConversation>? _pendingEditBaseConversations;
  List<AIConversation>? _pendingEditedConversations;
  String? _pendingEditOriginalText;

  @override
  void initState() {
    super.initState();
    _statusPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    final uiState = context.read<AIChatUIBloc>().state;
    _promptController.text = uiState.promptText;
    _promptController.addListener(_onPromptChanged);
    _scrollController.addListener(_onScrollChanged);
    _loadCopilotSignInPref();
    _copilotStateSubscription = context.read<CopilotBloc>().stream.listen((state) {
      final nextValue = state.isSignedIn;
      if (nextValue == _copilotSignedInFromPrefs || !mounted) {
        return;
      }
      setState(() {
        _copilotSignedInFromPrefs = nextValue;
      });
    });
    _reloadPendingEdits();
  }

  Future<void> _loadCopilotSignInPref() async {
    final isSignedIn = await isCopilotSignedPref();
    if (!mounted) {
      return;
    }
    if (_copilotSignedInFromPrefs == isSignedIn) {
      return;
    }
    setState(() {
      _copilotSignedInFromPrefs = isSignedIn;
    });
  }

  @override
  void didUpdateWidget(covariant AIChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _reloadPendingEdits();
    }
  }

  void _updatePendingPolling(bool isGenerating) {
    if (isGenerating && !_isPendingPollingActive) {
      _isPendingPollingActive = true;
      _pendingRefreshTimer?.cancel();
      _pendingRefreshTimer = Timer.periodic(
        const Duration(milliseconds: 750),
        (_) => _reloadPendingEdits(silent: true),
      );
      return;
    }

    if (!isGenerating && _isPendingPollingActive) {
      _isPendingPollingActive = false;
      _pendingRefreshTimer?.cancel();
      _pendingRefreshTimer = null;
      _reloadPendingEdits(silent: true);
    }
  }

  Future<void> _reloadPendingEdits({bool silent = false}) async {
    if (widget.filePath.isEmpty) {
      if (!mounted) return;
      setState(() => _pendingEdits = null);
      return;
    }
    final pending = await PendingEditFile.getForFile(File(widget.filePath).absolute.path);
    if (!mounted) return;
    if (silent && _pendingEdits?.editHunks.length == pending?.editHunks.length) {
      return;
    }
    setState(() {
      _pendingEdits = pending;
    });
  }

  Future<void> _keepHunkFromDrawer(EditHunk hunk) async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    await tools.keepPendingEditHunk(widget.filePath, hunk.id);
    await _reloadPendingEdits();
    if (mounted) setState(() => _isApplyingPendingAction = false);
  }

  Future<void> _rejectHunkFromDrawer(EditHunk hunk) async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    final result = await tools.rejectPendingEditHunk(widget.filePath, hunk.id);
    await _reloadPendingEdits();
    if (mounted) {
      setState(() => _isApplyingPendingAction = false);
      if (!result.success && result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error!)),
        );
      }
    }
  }

  Future<void> _keepAllFromDrawer() async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    await tools.keepAllPendingEdits(widget.filePath);
    await _reloadPendingEdits();
    if (mounted) setState(() => _isApplyingPendingAction = false);
  }

  Future<void> _rejectAllFromDrawer() async {
    setState(() => _isApplyingPendingAction = true);
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    final result = await tools.rejectAllPendingEdits(widget.filePath);
    await _reloadPendingEdits();
    if (mounted) {
      setState(() => _isApplyingPendingAction = false);
      if (!result.success && result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error!)),
        );
      }
    }
  }

  ButtonStyle _drawerPendingActionStyle(AppTheme appTheme, {bool destructive = false}) {
    final accent = destructive
      ? const Color(0xFFC62828)
      : (appTheme.isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32));
    return OutlinedButton.styleFrom(
      foregroundColor: accent,
      side: BorderSide(color: accent.withValues(alpha: 0.75)),
      backgroundColor: accent.withValues(alpha: appTheme.isDark ? 0.12 : 0.08),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    );
  }

  Widget _buildPendingDiffDrawerPanel(AppTheme appTheme) {
    final pending = _pendingEdits;
    if (pending == null || pending.editHunks.isEmpty) {
      return const SizedBox.shrink();
    }
    final counts = _pendingDiffCounts(pending);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: appTheme.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Pending hunks: ${pending.editHunks.length}',
                style: TextStyle(
                  color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.88),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text('+${counts.added}', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('-${counts.removed}', style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 112,
            child: ListView.builder(
              itemCount: pending.editHunks.length,
              itemBuilder: (context, index) {
                final hunk = pending.editHunks[index];
                final displayRange = _resolveDisplayLineRange(pending, hunk);
                final lineLabel = hunk.type == 'removed'
                  ? 'After L${displayRange.start + 1}'
                  : 'L${displayRange.start + 1}-${displayRange.end + 1}';
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$lineLabel ${hunk.type}',
                        style: TextStyle(
                          color: appTheme.selectScreenCardTextColor,
                          fontSize: 11.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    OutlinedButton(
                      style: _drawerPendingActionStyle(appTheme),
                      onPressed: _isApplyingPendingAction ? null : () => _keepHunkFromDrawer(hunk),
                      child: const Text('Keep'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      style: _drawerPendingActionStyle(appTheme, destructive: true),
                      onPressed: _isApplyingPendingAction ? null : () => _rejectHunkFromDrawer(hunk),
                      child: const Text('Reject'),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.bottomRight,
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  style: _drawerPendingActionStyle(appTheme),
                  onPressed: _isApplyingPendingAction ? null : _keepAllFromDrawer,
                  child: const Text('Keep all'),
                ),
                OutlinedButton(
                  style: _drawerPendingActionStyle(appTheme, destructive: true),
                  onPressed: _isApplyingPendingAction ? null : _rejectAllFromDrawer,
                  child: const Text('Reject all'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onPromptChanged() {
    final bloc = context.read<AIChatUIBloc>();
    final current = bloc.state;
    bloc.add(AIChatUIEvent(
      chatMode: current.chatMode,
      promptText: _promptController.text,
      selectedModelId: current.selectedModelId,
      scrollOffset: current.scrollOffset,
      isGenerating: current.isGenerating,
    ));
  }

  void _onScrollChanged() {
    if (_scrollController.hasClients) {
      _updateBlocState(scrollOffset: _scrollController.offset);
    }
  }

  void _updateBlocState({
    ChatMode? chatMode,
    String? promptText,
    String? selectedModelId,
    double? scrollOffset,
    bool? isGenerating,
  }) {
    if (!mounted) return;

    final bloc = context.read<AIChatUIBloc>();
    final current = bloc.state;
    bloc.add(AIChatUIEvent(
      chatMode: chatMode ?? current.chatMode,
      promptText: promptText ?? current.promptText,
      selectedModelId: selectedModelId ?? current.selectedModelId,
      scrollOffset: scrollOffset ?? current.scrollOffset,
      isGenerating: isGenerating ?? current.isGenerating,
    ));
  }

  bool get _hasPendingConversationEdit => _pendingEditBaseConversations != null;

  List<AIConversation> _cloneConversations(List<AIConversation> conversations) {
    return conversations.map((c) => AIConversation(c.userRequest, c.modelResponse)).toList();
  }

  void _restorePendingConversationEdit() {
    if (!_hasPendingConversationEdit) return;
    setState(() {
      _pendingEditBaseConversations = null;
      _pendingEditedConversations = null;
      _pendingEditOriginalText = null;
    });
  }

  void _startPendingConversationEdit(int index, List<AIConversation> baseConversations) {
    if (index < 0 || index >= baseConversations.length) return;

    final originalText = baseConversations[index].userRequest;
    final trimmedConversations = _cloneConversations(
      baseConversations.take(index).toList(),
    );

    setState(() {
      _pendingEditBaseConversations = _cloneConversations(baseConversations);
      _pendingEditedConversations = trimmedConversations;
      _pendingEditOriginalText = originalText;
    });

    _promptController.text = originalText;
    _promptController.selection = TextSelection.fromPosition(
      TextPosition(offset: _promptController.text.length),
    );
  }

  Future<void> _retryConversationFromIndex({
    required int index,
    required AIConversation conversation,
    required List<AIConversation> sourceConversations,
    required AIChatUIState aiChatUIState,
    required ChatSessionState sessionState,
    required CopilotChatState chatState,
    required Models? chatModel,
  }) async {
    if (aiChatUIState.isGenerating) return;

    final prompt = conversation.userRequest.trim();
    if (prompt.isEmpty) return;

    final retryConversations = _cloneConversations(
      sourceConversations.take(index).toList(),
    );

    if (_hasPendingConversationEdit) {
      _restorePendingConversationEdit();
    }

    _promptController.text = prompt;
    _promptController.selection = TextSelection.fromPosition(
      TextPosition(offset: _promptController.text.length),
    );

    final selectedModel = aiChatUIState.selectedModelId ?? '';
    final selectedCopilotModel = chatState.models.firstWhere(
      (model) => model['id'] == selectedModel,
      orElse: () => const <String, dynamic>{},
    );

    if (selectedCopilotModel.isNotEmpty) {
      _sendCopilotChatPrompt(
        retryConversations,
        sessionState.currentSession?.id,
        selectedModel,
        widget.workspacePath,
      );
      return;
    }

    if (chatModel != null) {
      _sendPrompt(chatModel, retryConversations, sessionState.currentSession?.id);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chat model not available'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _showUserBubbleActions({
    required int index,
    required AIConversation conversation,
    required List<AIConversation> baseConversations,
    required AIChatUIState aiChatUIState,
    required ChatSessionState sessionState,
    required CopilotChatState chatState,
    required Models? chatModel,
    required AppTheme appTheme,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: appTheme.isDark ? const Color(0xff1e1e2e) : Colors.white,
      builder: (sheetContext) {
        final textColor = appTheme.selectScreenCardTextColor;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.copy_outlined, color: textColor),
                title: Text('Copy', style: TextStyle(color: textColor)),
                onTap: () => Navigator.of(sheetContext).pop('copy'),
              ),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: textColor),
                title: Text('Edit', style: TextStyle(color: textColor)),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              ListTile(
                leading: Icon(Icons.refresh_outlined, color: textColor),
                title: Text('Try again', style: TextStyle(color: textColor)),
                onTap: () => Navigator.of(sheetContext).pop('retry'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: conversation.userRequest));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied to clipboard')),
      );
      return;
    }

    if (action == 'edit') {
      _startPendingConversationEdit(index, baseConversations);
      return;
    }

    if (action == 'retry') {
      await _retryConversationFromIndex(
        index: index,
        conversation: conversation,
        sourceConversations: baseConversations,
        aiChatUIState: aiChatUIState,
        sessionState: sessionState,
        chatState: chatState,
        chatModel: chatModel,
      );
    }
  }

  String _userFacingChatErrorMessage(Object error) {
    final text = error.toString();
    if (text.contains('Connection closed')) {
      return 'Generation stopped by user';
    }
    return 'Request failed: $text';
  }

  void _logChatError(String source, Object error, StackTrace stackTrace) {
    debugPrint('[AIChat][$source] $error');
    debugPrint('[AIChat][$source][stack] $stackTrace');
  }

  void _stopGeneration() {
    if (!mounted) return;

    _currentClient?.close();
    _currentClient = null;

    context.read<CopilotChatBloc>().chatClient?.cancelCurrentRequest();
    context.read<LocalLlamaBloc>().add(LocalLlamaStopGeneration());

    _updateBlocState(isGenerating: false);
  }

  @override
  void dispose() {
    _statusPulseController.dispose();
    _copilotStateSubscription?.cancel();
    _promptController.removeListener(_onPromptChanged);
    _scrollController.removeListener(_onScrollChanged);
    _currentClient?.close();
    _pendingRefreshTimer?.cancel();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String? _formatCopilotRate(Map<String, dynamic> model) {
    final billing = model['billing'];
    if (billing is! Map<String, dynamic>) return null;
    final multiplier = billing['multiplier'];
    if (multiplier is! num) return null;

    if (multiplier == multiplier.toInt()) {
      return '${multiplier.toInt()}x';
    }

    final fixed = multiplier.toStringAsFixed(2);
    final compact = fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '${compact}x';
  }

  Widget _buildModeSelector(Color textColor, bool isDark, ChatMode chatMode) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ChatMode>(
          value: chatMode,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, color: textColor.withAlpha(150), size: 18),
          dropdownColor: isDark ? const Color(0xff2d2d2d) : Colors.white,
          style: TextStyle(color: textColor, fontSize: 13),
          items: [
            DropdownMenuItem(
              value: ChatMode.ask,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 14, color: textColor.withAlpha(180)),
                  const SizedBox(width: 6),
                  Text('Ask', style: TextStyle(color: textColor, fontSize: 13)),
                ],
              ),
            ),
            DropdownMenuItem(
              value: ChatMode.agent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_outlined, size: 14, color: textColor.withAlpha(180)),
                  const SizedBox(width: 6),
                  Text('Agent', style: TextStyle(color: textColor, fontSize: 13)),
                ],
              ),
            ),
          ],
          onChanged: (mode) {
            if (mode != null) {
              _updateBlocState(chatMode: mode);
            }
          },
        ),
      ),
    );
  }

  Widget _buildModelSelector(
    BuildContext context, 
    AIState aiState, 
    CopilotChatState chatState, 
    Color textColor, 
    bool isDark,
    bool copilotSignedIn,
    String? selectedModelId,
  ) {
    final isCopilotAvailable = copilotSignedIn;
    final List<_ModelOption> models = [];
    
    if (isCopilotAvailable) {
      for (final model in chatState.models) {
        final id = model['id'] as String?;
        final name = model['name'] as String?;
        if (id == null || name == null) continue;
        final rateLabel = _formatCopilotRate(model);
        final detailParts = <String>[
          if (rateLabel != null && rateLabel.isNotEmpty) rateLabel,
        ];
        models.add(_ModelOption(
          id: id,
          name: name,
          provider: 'GitHub Copilot',
          rateLabel: detailParts.isEmpty ? null : detailParts.join(' | '),
          icon: SvgPicture.asset(
            'assets/icons/github-copilot-icon.svg',
            height: 14,
            width: 14,
            colorFilter: ColorFilter.mode(Colors.green, BlendMode.srcIn),
          ),
          isCopilot: true,
        ));
      }
    }
    
    for (final entry in aiState.config.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      final config = entry.value as Map<String, dynamic>;
      final provider = (config['apiProvider'] ?? config['provider'] ?? '').toString();
      final isLocalLlama = provider == 'LocalLlama';
      final modelName = (isLocalLlama
          ? (config['modelName'] ?? config['model'] ?? entry.key)
          : (config['model'] ?? entry.key)).toString();

      Widget icon;
      if (isLocalLlama) {
        icon = BlocBuilder<LocalLlamaBloc, LocalLlamaState>(
          builder: (context, llamaState) {
            final isLoaded = llamaState.loadedModelPath == (config['modelPath'] ?? '').toString();
            return Icon(
              Icons.memory,
              size: 14,
              color: isLoaded ? Colors.teal : Colors.grey,
            );
          },
        );
      } else {
        icon = _getProviderIcon(provider, textColor);
      }

      models.add(_ModelOption(
        id: entry.key,
        name: modelName,
        provider: isLocalLlama ? 'On-device' : (provider != 'Unknown' ? provider : null),
        icon: icon,
        isCopilot: false,
      ));
    }

    final uniqueModels = <_ModelOption>[];
    final seenIds = <String>{};
    for (final model in models) {
      if (seenIds.add(model.id)) uniqueModels.add(model);
    }

    if (uniqueModels.isEmpty) return const SizedBox.shrink();
    
    final currentModelId = selectedModelId != null && models.any((m) => m.id == selectedModelId)
      ? selectedModelId
      : models.first.id;
  
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentModelId,
          isDense: true,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: textColor.withAlpha(150), size: 18),
          dropdownColor: isDark ? const Color(0xff2d2d2d) : Colors.white,
          style: TextStyle(color: textColor, fontSize: 13),
          items: models.map((model) {
            return DropdownMenuItem<String>(
              value: model.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  model.icon,
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      model.name,
                      style: TextStyle(color: textColor, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (model.provider != null && !model.isCopilot) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(${model.provider})',
                      style: TextStyle(color: textColor.withAlpha(100), fontSize: 11),
                    ),
                  ],
                  if (model.rateLabel != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      model.rateLabel!,
                      style: TextStyle(
                        color: textColor.withAlpha(150),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          onChanged: (modelId) {
            if (modelId == null) return;
            _updateBlocState(selectedModelId: modelId);
            final currentModelSelected = Map<String, dynamic>.from(aiState.modelSelected);
            currentModelSelected['chat'] = modelId;
            context.read<AIBloc>().add(ModelSelectEvent(currentModelSelected));
          }
        ),
      ),
    );
  }

  Widget _getProviderIcon(String provider, Color textColor) {
    IconData iconData;
    Color color;
    
    switch (provider.toLowerCase()) {
      case 'openai':
        iconData = Icons.auto_awesome;
        color = Colors.green;
        break;
      case 'google':
      case 'gemini':
        iconData = Icons.auto_awesome;
        color = Colors.blue;
        break;
      case 'anthropic':
      case 'claude':
        iconData = Icons.psychology;
        color = Colors.orange;
        break;
      case 'openrouter':
        iconData = Icons.route;
        color = Colors.purple;
        break;
      default:
        iconData = Icons.smart_toy_outlined;
        color = textColor.withAlpha(150);
    }
    
    return Icon(iconData, size: 14, color: color);
  }

  String _decodeBase64(String encoded, {String fallback = ''}) {
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return fallback;
    }
  }

  String _stripToolUiMarkers(String input) {
    final lines = input.split('\n');
    final clean = <String>[];
    var insideThinkingBlock = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed == _thinkingStartMarker) {
        insideThinkingBlock = true;
        continue;
      }
      if (trimmed == _thinkingEndMarker) {
        insideThinkingBlock = false;
        continue;
      }
      if (insideThinkingBlock) {
        continue;
      }
      if (_toolEditPattern.hasMatch(trimmed) ||
          _toolTerminalPattern.hasMatch(trimmed) ||
          _toolStatusPattern.hasMatch(trimmed)) {
        continue;
      }
      clean.add(line);
    }
    return clean.join('\n').trim();
  }

  Widget _buildToolStatusIndicator(String status, AppTheme appTheme) {
    final baseColor = appTheme.selectScreenCardTextColor.withAlpha(135);
    final glowColor = appTheme.selectScreenCardTextColor.withAlpha(230);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: AnimatedBuilder(
        animation: _statusPulseController,
        builder: (context, child) {
          final t = _statusPulseController.value;
          final center = -0.9 + (t * 2.8);

          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) {
              return LinearGradient(
                colors: [baseColor, glowColor, baseColor],
                stops: const [0.2, 0.5, 0.8],
                begin: Alignment(center - 1.0, 0),
                end: Alignment(center + 1.0, 0),
              ).createShader(rect);
            },
            child: child,
          );
        },
        child: Text(
          status,
          style: TextStyle(
            color: baseColor,
            fontStyle: FontStyle.italic,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildToolEditSummary(String filePath, int added, int removed, AppTheme appTheme) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: appTheme.isDark
          ? Colors.white.withAlpha(15)
          : Colors.black.withAlpha(12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              path.basename(filePath),
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '+$added',
            style: const TextStyle(
              color: Color(0xFF2E7D32),
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '-$removed',
            style: const TextStyle(
              color: Color(0xFFC62828),
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolTerminal(
    String command,
    AppTheme appTheme,
    int markerIndex, {
    String? stdout,
    String? stderr,
    String? exitCode,
  }) {
    final hasCapturedOutput =
      (stdout != null && stdout.isNotEmpty) ||
      (stderr != null && stderr.isNotEmpty) ||
      (exitCode != null && exitCode.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: appTheme.isDark
          ? Colors.white.withAlpha(10)
          : Colors.black.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withAlpha(85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            command,
            style: TextStyle(
              color: appTheme.selectScreenCardTextColor,
              fontFamily: 'monospace',
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 8),
          if (hasCapturedOutput)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: appTheme.isDark
                  ? Colors.black.withAlpha(80)
                  : Colors.white.withAlpha(180),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.withAlpha(70)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  [
                    if (stdout != null && stdout.isNotEmpty) stdout,
                    if (stderr != null && stderr.isNotEmpty)
                      '[stderr]\n$stderr',
                    if (exitCode != null && exitCode.isNotEmpty)
                      '[Process exited: $exitCode]',
                  ].join('\n'),
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 170,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: EmbeddedTerminal(
                  key: ValueKey('tool-terminal-$markerIndex-$command'),
                  projectDir: widget.workspacePath,
                  args: ['-c', command],
                  showKeyboardMenu: false,
                  readOnly: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThinkingPanel(String thinkingText, AppTheme appTheme) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: appTheme.isDark
          ? Colors.white.withAlpha(8)
          : Colors.black.withAlpha(6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withAlpha(70)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          dense: true,
          title: Text(
            'Thinking',
            style: TextStyle(
              color: appTheme.selectScreenCardTextColor.withAlpha(180),
              fontStyle: FontStyle.italic,
              fontSize: 12.5,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                thinkingText.trim(),
                style: TextStyle(
                  color: appTheme.selectScreenCardTextColor.withAlpha(190),
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantResponseContent(
    String response,
    MarkdownConfig config,
    AppTheme appTheme,
  ) {
    final lines = response.split('\n');
    final widgets = <Widget>[];
    final markdownBuffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    var markerIndex = 0;
    var insideThinkingBlock = false;

    void flushMarkdown() {
      final content = markdownBuffer.toString().trim();
      if (content.isNotEmpty) {
        widgets.add(
          MarkdownBlock(
            data: content,
            config: config,
          ),
        );
      }
      markdownBuffer.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed == _thinkingStartMarker) {
        flushMarkdown();
        insideThinkingBlock = true;
        thinkingBuffer.clear();
        continue;
      }

      if (trimmed == _thinkingEndMarker) {
        if (insideThinkingBlock) {
          final thinkingText = thinkingBuffer.toString().trim();
          if (thinkingText.isNotEmpty) {
            widgets.add(_buildThinkingPanel(thinkingText, appTheme));
          }
          thinkingBuffer.clear();
          insideThinkingBlock = false;
        }
        continue;
      }

      if (insideThinkingBlock) {
        thinkingBuffer.writeln(line);
        continue;
      }

      final editMatch = _toolEditPattern.firstMatch(trimmed);
      if (editMatch != null) {
        flushMarkdown();
        final filePath = _decodeBase64(editMatch.group(1)!, fallback: 'unknown');
        final added = int.tryParse(editMatch.group(2) ?? '0') ?? 0;
        final removed = int.tryParse(editMatch.group(3) ?? '0') ?? 0;
        widgets.add(_buildToolEditSummary(filePath, added, removed, appTheme));
        markerIndex++;
        continue;
      }

      final statusMatch = _toolStatusPattern.firstMatch(trimmed);
      if (statusMatch != null) {
        flushMarkdown();
        final status = statusMatch.group(1)?.trim() ?? '';
        if (status.isNotEmpty) {
          widgets.add(_buildToolStatusIndicator(status, appTheme));
        }
        continue;
      }

      final terminalMatch = _toolTerminalPattern.firstMatch(trimmed);
      if (terminalMatch != null) {
        flushMarkdown();
        final terminalPayload = _decodeBase64(terminalMatch.group(1)!, fallback: '');
        var command = terminalPayload;
        String? stdout;
        String? stderr;
        String? exitCode;

        try {
          final decoded = jsonDecode(terminalPayload);
          if (decoded is Map<String, dynamic>) {
            command = decoded['command']?.toString() ?? '';
            stdout = decoded['stdout']?.toString();
            stderr = decoded['stderr']?.toString();
            exitCode = decoded['exitCode']?.toString();
          }
        } catch (_) {}

        if (command.isNotEmpty) {
          widgets.add(
            _buildToolTerminal(
              command,
              appTheme,
              markerIndex,
              stdout: stdout,
              stderr: stderr,
              exitCode: exitCode,
            ),
          );
          markerIndex++;
        }
        continue;
      }

      markdownBuffer.writeln(line);
    }

    flushMarkdown();
    if (insideThinkingBlock) {
      final thinkingText = thinkingBuffer.toString().trim();
      if (thinkingText.isNotEmpty) {
        widgets.add(_buildThinkingPanel(thinkingText, appTheme));
      }
    }
    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  List<Map<String, dynamic>> _buildChatHistory(List<AIConversation> conversations) {
    final List<Map<String, dynamic>> history = [];
    for (final conv in conversations) {
      history.add({"role": "user", "content": conv.userRequest});
      if (conv.modelResponse != null && conv.modelResponse!.isNotEmpty) {
        final response = _stripToolUiMarkers(conv.modelResponse!);
        if (response.isNotEmpty) {
          history.add({"role": "assistant", "content": response});
        }
      }
    }
    return history;
  }
  
  List<Map<String, dynamic>> _buildGeminiHistory(List<AIConversation> conversations) {
    final List<Map<String, dynamic>> history = [];
    for (final conv in conversations) {
      history.add({
        "role": "user",
        "parts": [{"text": conv.userRequest}]
      });
      if (conv.modelResponse != null && conv.modelResponse!.isNotEmpty) {
        final response = _stripToolUiMarkers(conv.modelResponse!);
        if (response.isEmpty) {
          continue;
        }
        history.add({
          "role": "model",
          "parts": [{"text": response}]
        });
      }
    }
    return history;
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

  String _shellCommandPreview(String command, List<String> args) {
    final parts = [command, ...args].map(_shellEscape).toList();
    return parts.join(' ');
  }

  String _shellEscape(String value) {
    if (value.isEmpty) return "''";
    final safePattern = RegExp(r'^[A-Za-z0-9_./:-]+$');
    if (safePattern.hasMatch(value)) {
      return value;
    }
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  Future<String> _executeExternalToolCall({
    required AgenticTools tools,
    required String functionName,
    required Map<String, dynamic> args,
    required void Function(String) pushPartial,
  }) async {
    try {
      switch (functionName) {
        case 'activeEditorFile':
          final res = await tools.activeEditorFile();
          return res.success
            ? (res.data ?? 'No active file')
            : (res.error ?? 'Error getting active file');
        case 'currentlySelectedText':
          final res = await tools.currentlySelectedText();
          return res.success
            ? 'Start Line: ${res.data?['startLine'] ?? 'Unknown'}, End Line: ${res.data?['endLine'] ?? 'Unknown'}, Text: ${res.data?['selectedText'] ?? ''}'
            : (res.error ?? 'Error getting selected text');
        case 'getLspDiagnostics':
          final res = await tools.getLspDiagnostics(args['filePath']);
          return res.success
            ? jsonEncode(res.data)
            : (res.error ?? 'Error getting LSP diagnostics');
        case 'readFile':
          final res = await tools.readFile(
            args['filePath'],
            args['startLine'],
            args['endLine'],
          );
          return res.success
            ? (res.data ?? 'No content')
            : (res.error ?? 'Error reading file');
        case 'writeFile':
          String? previousContent;
          final previousRead = await tools.readFile(args['filePath']);
          if (previousRead.success) {
            previousContent = previousRead.data;
          }
          final res = await tools.writeFile(
            args['filePath'],
            args['content'],
          );
          if (res.success) {
            final added = _lineCount(args['content']?.toString());
            final removed = _lineCount(previousContent);
            pushPartial(_toolStatusMarker('Generating patch (+$added/-$removed)'));
            pushPartial(
              _toolEditMarker(
                args['filePath']?.toString() ?? 'unknown',
                added,
                removed,
              ),
            );
          }
          return res.success
            ? 'File written successfully'
            : (res.error ?? 'Error writing file');
        case 'deleteFile':
          final previousRead = await tools.readFile(args['filePath']);
          final res = await tools.deleteFile(args['filePath']);
          if (res.success) {
            final removed = _lineCount(previousRead.data);
            pushPartial(_toolStatusMarker('Generating patch (+0/-$removed)'));
            pushPartial(
              _toolEditMarker(
                args['filePath']?.toString() ?? 'unknown',
                0,
                removed,
              ),
            );
          }
          return res.success
            ? 'File deleted successfully'
            : (res.error ?? 'Error deleting file');
        case 'renamePath':
          final res = await tools.renamePath(
            args['oldPath'],
            args['newPath'],
          );
          return res.success
            ? 'Path renamed successfully'
            : (res.error ?? 'Error renaming path');
        case 'rename':
          final res = await tools.rename(
            args['oldPath'],
            args['newPath'],
          );
          return res.success
            ? 'Path renamed successfully'
            : (res.error ?? 'Error renaming path');
        case 'insertAtLine':
          final res = await tools.insertAtLine(
            args['filePath'],
            args['line'],
            args['text'],
            position: args['position'] ?? 'before',
          );
          if (res.success) {
            final added = _lineCount(args['text']?.toString());
            pushPartial(_toolStatusMarker('Generating patch (+$added/-0)'));
            pushPartial(
              _toolEditMarker(
                args['filePath']?.toString() ?? 'unknown',
                added,
                0,
              ),
            );
          }
          return res.success
            ? 'Text inserted successfully'
            : (res.error ?? 'Error inserting text');
        case 'replaceAllInFile':
          final res = await tools.replaceAllInFile(
            args['filePath'],
            args['oldText'],
            args['newText'],
            useRegex: args['useRegex'] ?? false,
            maxReplacements: args['maxReplacements'],
            caseSensitive: args['caseSensitive'] ?? true,
          );
          if (res.success) {
            final added = _lineCount(args['newText']?.toString());
            final removed = _lineCount(args['oldText']?.toString());
            pushPartial(_toolStatusMarker('Generating patch (+$added/-$removed)'));
            pushPartial(
              _toolEditMarker(
                args['filePath']?.toString() ?? 'unknown',
                added,
                removed,
              ),
            );
          }
          return res.success
            ? jsonEncode(res.data)
            : (res.error ?? 'Error replacing text');
        case 'listFiles':
          final res = await tools.listFiles(
            args['directoryPath'],
            pattern: args['pattern'],
            recursive: args['recursive'] ?? false,
          );
          return res.success
            ? (res.data?.join('\n') ?? 'No files')
            : (res.error ?? 'Error listing files');
        case 'readFilesBatch':
          final parsedFiles = (args['files'] as List?) ?? const [];
          final res = await tools.readFilesBatch(parsedFiles);
          return res.success
            ? jsonEncode(res.data)
            : (res.error ?? 'Error reading files batch');
        case 'globSearchFiles':
          final parsedExcludePatterns = (args['excludePatterns'] as List?)?.map((item) => item.toString()).toList();
          final res = await tools.globSearchFiles(
            args['pattern'],
            directoryPath: args['directoryPath'] ?? '.',
            excludePatterns: parsedExcludePatterns,
            recursive: args['recursive'] ?? true,
            maxResults: args['maxResults'],
          );
          return res.success
            ? (res.data?.join('\n') ?? 'No matches')
            : (res.error ?? 'Error searching files by glob');
        case 'searchInFiles':
          final res = await tools.searchInFiles(
            args['query'],
            filePattern: args['filePattern'],
            caseSensitive: args['caseSensitive'] ?? false,
            matchWholeWord: args['matchWholeWord'] ?? false,
            useRegex: args['useRegex'] ?? false,
          );
          return res.success
            ? (res.data?.map((s) => '${s.filePath}:${s.lineNumber}: ${s.lineContent}').join('\n') ?? 'No results')
            : (res.error ?? 'Error searching files');
        case 'grepInFiles':
          final res = await tools.grepInFiles(
            args['query'],
            filePattern: args['filePattern'],
            caseSensitive: args['caseSensitive'] ?? false,
            matchWholeWord: args['matchWholeWord'] ?? false,
            useRegex: args['useRegex'] ?? false,
            before: args['before'] ?? 2,
            after: args['after'] ?? 2,
            maxResults: args['maxResults'],
          );
          return res.success
            ? (res.data?.map((r) => r.toString()).join('\n') ?? 'No results')
            : (res.error ?? 'Error grepping files');
        case 'editFile':
          final res = await tools.editFile(
            args['filePath'],
            args['oldText'],
            args['newText'],
          );
          if (res.success) {
            final added = _lineCount(args['newText']?.toString());
            final removed = _lineCount(args['oldText']?.toString());
            pushPartial(_toolStatusMarker('Generating patch (+$added/-$removed)'));
            pushPartial(
              _toolEditMarker(
                args['filePath']?.toString() ?? 'unknown',
                added,
                removed,
              ),
            );
          }
          return res.success
            ? 'File edited successfully'
            : (res.error ?? 'Error editing file');
        case 'getPendingEditsForFile':
          final res = await tools.getPendingEditsForFile(args['filePath']);
          return res.success
            ? (res.data == null ? 'No pending edits' : jsonEncode(res.data!.toJson()))
            : (res.error ?? 'Error getting pending edits');
        case 'getFileInfo':
          final res = await tools.getFileInfo(args['filePath']);
          return res.success
            ? 'Path: ${res.data?.path ?? 'Unknown'}, Size: ${res.data?.size ?? 0}, Modified: ${res.data?.modified ?? 'Unknown'}, IsDirectory: ${res.data?.isDirectory ?? false}'
            : (res.error ?? 'Error getting file info');
        case 'openLinks':
          final res = await tools.openLinks(args['url']);
          return res.success
            ? (res.data?.toString() ?? 'No content')
            : (res.error ?? 'Error fetching web page');
        case 'searchInWeb':
          final res = await tools.searchInWeb(args['searchQuery']);
          return res.success
            ? (res.data?.map((w) => '${w.title}\n${w.url}\n${w.snippet}').join('\n---\n') ?? 'No results')
            : (res.error ?? 'Error searching web');
        case 'runShellCommand':
          final parsedArgs = (args['args'] as List?)?.map((item) => item.toString()).toList() ?? <String>[];
          final parsedEnvs = (args['envs'] as Map?)?.map((key, value) => MapEntry(key.toString(), value.toString())) ?? <String, String>{};
          final preview = _shellCommandPreview(
            args['command']?.toString() ?? '',
            parsedArgs,
          );
          final res = await tools.runShellCommand(
            args['command'],
            parsedArgs,
            parsedEnvs,
          );
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
          return res.success
            ? jsonEncode(res.data)
            : (res.error ?? 'Error running shell command');
        case 'gitStatus':
          final res = await tools.gitStatus();
          return res.success
            ? jsonEncode(res.data?.toJson())
            : (res.error ?? 'Error getting git status');
        case 'gitDiff':
          final res = await tools.gitDiff(
            filePath: args['filePath'],
            staged: args['staged'] ?? false,
            contextLines: args['contextLines'] ?? 3,
          );
          return res.success
            ? (res.data ?? '')
            : (res.error ?? 'Error getting git diff');
        case 'gitLog':
          final res = await tools.gitLog(
            limit: args['limit'] ?? 20,
            filePath: args['filePath'],
          );
          return res.success
              ? jsonEncode(res.data?.map((c) => c.toJson()).toList() ?? [])
              : (res.error ?? 'Error getting git log');
        default:
          return 'Unknown tool: $functionName';
      }
    } catch (e) {
      return 'Error executing tool $functionName: $e';
    }
  }

  Future<String> _sendExternalToolCallingPrompt({
    required Models chatModel,
    required List<AIConversation> history,
    required String prompt,
    required ChatMode chatMode,
    required void Function(String) pushPartial,
  }) async {
    final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
    final availableTools = chatMode == ChatMode.agent
      ? tools.getTools()
      : tools.getTools(readAccessOnly: true);

    final conversationMessages = _buildChatHistory(history);
    if (chatMode == ChatMode.agent) {
      conversationMessages.insert(0, {
        'role': 'system',
        'content': 'You are running in Roxum IDE with workspace tool access. Use available tools to inspect, edit, and run commands when asked for code changes. Do not claim missing permissions unless a tool call fails with an explicit permission error.',
      });
    }
    conversationMessages.add({'role': 'user', 'content': prompt});

    _currentClient = http.Client();
    final streamedOutput = StringBuffer();

    void appendOutput(String text) {
      if (text.isEmpty) return;
      streamedOutput.write(text);
      pushPartial(text);
    }

    try {
      var loop = 0;
      while (loop < 8) {
        loop++;
        final requestBody = chatModel.buildToolCallingRequest(
          messages: conversationMessages,
          tools: availableTools,
          stream: false,
        );

        final response = await _currentClient!.post(
          Uri.parse(chatModel.chatUrl),
          headers: chatModel.headers,
          body: jsonEncode(requestBody),
        );

        if (response.statusCode != 200) {
          throw Exception(
            'Request failed with status ${response.statusCode}: ${response.body}',
          );
        }

        final decoded = jsonDecode(response.body);
        final assistantText = chatModel.parseChatMessage(decoded);
        final toolCalls = chatModel.parseToolCalls(decoded);

        conversationMessages.add({
          'role': 'assistant',
          'content': assistantText,
          if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
        });

        if (assistantText.isNotEmpty) {
          appendOutput(assistantText);
        }

        if (toolCalls.isEmpty) {
          final output = streamedOutput.toString();
          if (output.isNotEmpty) return output;
          return assistantText;
        }

        appendOutput(_toolStatusMarker('Processing'));

        final toolResults = <String>[];
        for (final call in toolCalls) {
          final callFunction = call['function'];
          if (callFunction is! Map) {
            toolResults.add('Malformed tool call without function payload');
            continue;
          }

          final function = Map<String, dynamic>.from(callFunction);
          final functionName = function['name']?.toString();
          if (functionName == null || functionName.isEmpty) {
            toolResults.add('Malformed tool call without function name');
            continue;
          }

          appendOutput(_toolStatusMarker(_toolStatusForFunction(functionName)));

          final rawArgs = function['arguments'];
          Map<String, dynamic> args = <String, dynamic>{};
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

          final result = await _executeExternalToolCall(
            tools: tools,
            functionName: functionName,
            args: args,
            pushPartial: appendOutput,
          );
          toolResults.add(result);
        }

        conversationMessages.addAll(
          chatModel.buildToolResultMessages(toolCalls, toolResults),
        );
      }

      throw Exception('Tool loop exceeded maximum iterations');
    } finally {
      _currentClient?.close();
      _currentClient = null;
    }
  }
  
  String? _parseStreamChunk(String chunk, Models chatModel) {
    final buffer = StringBuffer();
    
    switch (chatModel) {
      case Gemini():
        for (final line in chunk.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('data: ')) {
            final data = trimmed.substring(6).trim();
            if (data.isEmpty) continue;
            try {
              final json = jsonDecode(data);
              final text = json["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];
              if (text != null) buffer.write(text);
            } catch (_) {}
          } else if (trimmed.isNotEmpty && !trimmed.startsWith(':')) {
            try {
              final json = jsonDecode(trimmed);
              if (json is List && json.isNotEmpty) {
                for (final item in json) {
                  final text = item["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];
                  if (text != null) buffer.write(text);
                }
              } else if (json is Map) {
                final text = json["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];
                if (text != null) buffer.write(text);
              }
            } catch (_) {}
          } else {
            buffer.write(chunk);
          }
        }
        
      case Claude():
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]' || data.isEmpty) continue;
            try {
              final json = jsonDecode(data);
              final type = json["type"];
              if (type == "content_block_delta") {
                final text = json["delta"]?["text"];
                if (text != null) buffer.write(text);
              }
            } catch (e) {
              buffer.write(e.toString());
            }
          }
        }
        
      case OpenAI():
      case Grok():
      case DeepSeek():
      case TogetherAi():
      case Perplexity():
      case OpenRouter():
      case FireWorks():
      case CustomModel():
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]' || data.isEmpty) continue;
            try {
              final json = jsonDecode(data);
              final content = json["choices"]?[0]?["delta"]?["content"];
              if (content != null) buffer.write(content);
            } catch (_) {}
          }
        }
      
      case LocalLlama(): return '';
    }
    
    return buffer.isEmpty ? null : buffer.toString();
  }

  String _getStreamingUrl(Models chatModel) {
    switch (chatModel) {
      case Gemini():
        final uri = Uri.parse(chatModel.url);
        final newPath = uri.path.replaceFirst(':generateContent', ':streamGenerateContent');
        final newParams = Map<String, String>.from(uri.queryParameters);
        newParams['alt'] = 'sse';
        return uri.replace(path: newPath, queryParameters: newParams).toString();
      case OpenAI():
        return chatModel.chatUrl;
      case Claude():
        return chatModel.url; 
      default:
        return chatModel.url; 
    }
  }
  
  Map<String, dynamic> _buildRequestBody(Models chatModel, String prompt, List<AIConversation> history) {
    switch (chatModel) {
      case Gemini():
        final geminiHistory = _buildGeminiHistory(history);
        geminiHistory.add({
          "role": "user",
          "parts": [{"text": prompt}]
        });
        return {
          "contents": geminiHistory,
          "generationConfig": {
            "temperature": 1.0,
            "maxOutputTokens": 8192,
            "topP": 0.8,
            "topK": 10,
          },
        };
      case Claude():
        final messages = _buildChatHistory(history);
        messages.add({"role": "user", "content": prompt});
        return {
          "model": chatModel.model,
          "max_tokens": 4096,
          "stream": true,
          "messages": messages,
        };
      case OpenAI():
      case Grok():
      case DeepSeek():
      case TogetherAi():
      case Perplexity():
      case OpenRouter():
      case FireWorks():
        final messages = _buildChatHistory(history);
        messages.add({"role": "user", "content": prompt});
        return {
          "model": chatModel.model,
          "stream": true,
          "messages": messages,
        };
      case CustomModel():
        final messages = _buildChatHistory(history);
        messages.add({"role": "user", "content": prompt});
        return {
          "model": chatModel.model,
          "stream": true,
          "messages": messages,
        };
      case LocalLlama(): return {};
    }
  }

  void _sendPrompt(Models chatModel, List<AIConversation> currentList, String? sessionId) async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    final chatSessionBloc = context.read<ChatSessionBloc>();
    final chatMode = mounted
      ? context.read<AIChatUIBloc>().state.chatMode
      : ChatMode.ask;
    final isFirstMessage = currentList.isEmpty;

    final newList = currentList.map((c) => AIConversation(c.userRequest, c.modelResponse)).toList();
    newList.add(AIConversation(prompt, ""));
    
    chatSessionBloc.add(UpdateCurrentSession(conversations: newList));

    final int index = newList.length - 1;
    _promptController.clear();
    
    _updateBlocState(isGenerating: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    if (chatMode == ChatMode.agent && chatModel.supportsToolCalling) {
      try {
        final response = await _sendExternalToolCallingPrompt(
          chatModel: chatModel,
          history: currentList,
          prompt: prompt,
          chatMode: chatMode,
          pushPartial: (partial) {
            newList[index] = newList[index].copyWith(
              modelResponse: (newList[index].modelResponse ?? '') + partial,
            );
            chatSessionBloc.add(UpdateCurrentSession(conversations: newList));
          },
        );

        final currentSession = chatSessionBloc.state.currentSession;
        if (currentSession != null) {
          final updated = currentSession.conversations
              .map((c) => AIConversation(c.userRequest, c.modelResponse))
              .toList();

          if (index < updated.length) {
            updated[index] = updated[index].copyWith(modelResponse: response);
            chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
          }
        }

        _updateBlocState(isGenerating: false);

        if (isFirstMessage && response.isNotEmpty) {
          _generateTitle(chatModel, prompt, response);
        }
      } catch (e, st) {
        _logChatError('sendPrompt.agenticExternal', e, st);
        final currentSession = chatSessionBloc.state.currentSession;
        if (currentSession != null) {
          final updated = currentSession.conversations
              .map((c) => AIConversation(c.userRequest, c.modelResponse))
              .toList();
          if (index < updated.length) {
            updated[index] = updated[index].copyWith(
              modelResponse: _userFacingChatErrorMessage(e),
            );
            chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
          }
        }
        _updateBlocState(isGenerating: false);
      }
      return;
    }

    final url = Uri.parse(_getStreamingUrl(chatModel));
    _currentClient = http.Client();
    final request = http.Request('POST', url);
    request.headers.addAll(chatModel.headers);
    
    final historyForRequest = currentList;
    request.body = jsonEncode(_buildRequestBody(chatModel, prompt, historyForRequest));

    try {
      final streamedResponse = await _currentClient!.send(request);
      final StringBuffer fullResponse = StringBuffer();
      
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        final parsed = _parseStreamChunk(chunk, chatModel);
        if (parsed != null) {
          fullResponse.write(parsed);
          
          final currentSession = chatSessionBloc.state.currentSession;
          if (currentSession != null) {
            final updated = currentSession.conversations
              .map((c) => AIConversation(c.userRequest, c.modelResponse))
              .toList();

            if (index < updated.length) {
              updated[index] = updated[index].copyWith(
                modelResponse: fullResponse.toString(),
              );
              chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
            }
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      }

      if (fullResponse.isEmpty) {
        final fallbackClient = http.Client();
        try {
          final response = await fallbackClient.post(
            Uri.parse(chatModel.url),
            headers: chatModel.headers,
            body: jsonEncode(_buildRequestBody(chatModel, prompt, historyForRequest)..remove('stream')),
          );
          if (response.statusCode == 200) {
            final json = jsonDecode(response.body);
            final parsed = chatModel.responseParser(json);
            final currentSession = chatSessionBloc.state.currentSession;
            if (currentSession != null) {
              final updated = currentSession.conversations
                  .map((c) => AIConversation(c.userRequest, c.modelResponse))
                  .toList();
              if (index < updated.length) {
                updated[index] = updated[index].copyWith(modelResponse: parsed);
                chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
              }
            }
          }
        } finally {
          fallbackClient.close();
        }
      }
      
      _currentClient?.close();
      _currentClient = null;
      _updateBlocState(isGenerating: false);
      
      if (isFirstMessage && fullResponse.isNotEmpty) {
        _generateTitle(chatModel, prompt, fullResponse.toString());
      }
    } catch (e, st) {
      _logChatError('sendPrompt', e, st);
      final currentSession = chatSessionBloc.state.currentSession;
      if (currentSession != null) {
        final updated = currentSession.conversations.map((c) => AIConversation(c.userRequest, c.modelResponse)).toList();
        if (index < updated.length) {
          updated[index] = updated[index].copyWith(
            modelResponse: _userFacingChatErrorMessage(e),
          );
          chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
        }
      }
      _currentClient?.close();
      _currentClient = null;
      _updateBlocState(isGenerating: false);
    }
  }

  Future<void> _generateTitle(Models chatModel, String userPrompt, String aiResponse) async {
    final chatSessionBloc = context.read<ChatSessionBloc>();
    final currentSession = chatSessionBloc.state.currentSession;
    if (currentSession == null) return;

    try {
      final titlePrompt = "Generate a short title (max 5 words) for this conversation. Only respond with the title, nothing else.\n\nUser: $userPrompt\n\nAssistant: ${aiResponse.substring(0, aiResponse.length > 200 ? 200 : aiResponse.length)}";
      
      final url = Uri.parse(chatModel.url);
      final titleRequest = http.Request('POST', url);
      titleRequest.headers.addAll(chatModel.headers);
      
      Map<String, dynamic> requestBody;
      switch (chatModel) {
        case Gemini():
          requestBody = {
            "contents": [
              {
                "parts": [{"text": titlePrompt}]
              }
            ],
            "generationConfig": {
              "temperature": 0.7,
              "maxOutputTokens": 50,
            },
          };
        default:
          requestBody = {
            "model": chatModel.model,
            "messages": [
              {"role": "user", "content": titlePrompt}
            ],
            "max_tokens": 50,
            "temperature": 0.7,
          };
      }
      
      titleRequest.body = jsonEncode(requestBody);
      
      final client = http.Client();
      final httpResponse = await client.post(url, headers: chatModel.headers, body: titleRequest.body);
      
      if (httpResponse.statusCode == 200) {
        final json = jsonDecode(httpResponse.body);
        try {
          String title = chatModel.responseParser(json);
          
          title = title.replaceAll('"', '').replaceAll('\n', ' ').replaceAll('*', '').trim();
          
          title = title.replaceFirst(RegExp(r'^(Title:|Topic:|Subject:)\s*', caseSensitive: false), '');
          if (title.length > 50) title = title.substring(0, 50);
          if (title.isNotEmpty && title.toLowerCase() != 'ai completion not available') {
            chatSessionBloc.add(UpdateSessionTitle(
              sessionId: currentSession.id,
              title: title,
            ));
          }
        } catch (e) {
          
          final fallbackTitle = userPrompt.split(' ').take(5).join(' ');
          chatSessionBloc.add(UpdateSessionTitle(
            sessionId: currentSession.id,
            title: fallbackTitle,
          ));
        }
      }
      client.close();
    } catch (e) {
      
      try {
        final fallbackTitle = userPrompt.split(' ').take(5).join(' ');
        chatSessionBloc.add(UpdateSessionTitle(
          sessionId: currentSession.id,
          title: fallbackTitle,
        ));
      } catch (_) {}
    }
  }

  void _sendCopilotChatPrompt(List<AIConversation> currentList, String? sessionId, String modelId, String workspacePath) async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    final copilotChatBloc = context.read<CopilotChatBloc>();
    final chatSessionBloc = context.read<ChatSessionBloc>();

    if (copilotChatBloc.chatClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copilot chat not available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final newList = currentList.map((c) => AIConversation(c.userRequest, c.modelResponse)).toList();
    newList.add(AIConversation(prompt, ""));
    
    chatSessionBloc.add(UpdateCurrentSession(conversations: newList));

    final int index = newList.length - 1;
    _promptController.clear();
    
    _updateBlocState(isGenerating: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      final messages = _buildChatHistory(currentList);
      final chatMode = mounted
          ? context.read<AIChatUIBloc>().state.chatMode
          : ChatMode.ask;
      if (chatMode == ChatMode.agent) {
        messages.insert(0, {
          'role': 'system',
          'content': 'You are running in Roxum IDE with workspace tool access. Use available tools to inspect, edit, and run commands when asked for code changes. Do not claim missing permissions unless a tool call fails with an explicit permission error.',
        });
      }
      messages.add({'role': 'user', 'content': prompt});
      copilotChatBloc.chatClient!.agenticTools = AgenticTools(workspacePath: workspacePath, context: context);
      final response = await copilotChatBloc.chatClient!.chatWithModel(
        model: modelId,
        messages: messages,
        chatMode: chatMode,
        onPartial: (partial) {
          newList[index] = newList[index].copyWith(modelResponse: (newList[index].modelResponse ?? "") + partial);
          chatSessionBloc.add(UpdateCurrentSession(conversations: newList));
        },
      );
      
      final currentSession = chatSessionBloc.state.currentSession;
      if (currentSession != null) {
        final updated = currentSession.conversations
            .map((c) => AIConversation(c.userRequest, c.modelResponse))
            .toList();

        if (index < updated.length) {
          updated[index] = updated[index].copyWith(
            modelResponse: response,
          );
          chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
        }

        if (index == 0 && response.isNotEmpty) {
          final fallbackTitle = prompt.split(' ').take(5).join(' ');
          chatSessionBloc.add(UpdateSessionTitle(
            sessionId: currentSession.id,
            title: fallbackTitle,
          ));
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
      
      _updateBlocState(isGenerating: false);
    } catch (e, st) {
      _logChatError('sendCopilotChatPrompt', e, st);
      final currentSession = chatSessionBloc.state.currentSession;
      if (currentSession != null) {
        final updated = currentSession.conversations
            .map((c) => AIConversation(c.userRequest, c.modelResponse))
            .toList();
        if (index < updated.length) {
          updated[index] = updated[index].copyWith(
            modelResponse: _userFacingChatErrorMessage(e),
          );
          chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
        }
      }
      
      _updateBlocState(isGenerating: false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendLocalLlamaPrompt(
    LocalLlama model,
    List<AIConversation> currentList,
    String? sessionId,
  ) async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    final llamaBloc = context.read<LocalLlamaBloc>();
    final chatSessionBloc = context.read<ChatSessionBloc>();
    final chatMode = mounted
      ? context.read<AIChatUIBloc>().state.chatMode
      : ChatMode.ask;
    final isFirstMessage = currentList.isEmpty;

    if (llamaBloc.state.loadedModelPath != model.modelPath || !llamaBloc.state.isReady) {
      llamaBloc.add(LocalLlamaLoadModel(model));
      await llamaBloc.stream.firstWhere(
        (s) => s.status == LocalLlamaStatus.ready || s.status == LocalLlamaStatus.error,
      );
      if (llamaBloc.state.status == LocalLlamaStatus.error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to load model: ${llamaBloc.state.error}'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

    final controller = llamaBloc.controller;
    if (controller == null) return;

    final newList = currentList.map((c) => AIConversation(c.userRequest, c.modelResponse)).toList();
    newList.add(AIConversation(prompt, ''));
    chatSessionBloc.add(UpdateCurrentSession(conversations: newList));

    final int index = newList.length - 1;
    _promptController.clear();
    _updateBlocState(isGenerating: true);

    _scrollToBottom();

    try {
      final messages = _buildChatHistory(currentList).map((m) => ChatMessage(
        role: m['role'] as String,
        content: m['content'] as String,
      )).toList();

      if (chatMode == ChatMode.agent && mounted) {
        final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
        
        final toolList = tools.getTools()
          .map((tool) {
            final func = tool['function'];
            final name = func['name']?.toString() ?? '';
            final desc = func['description']?.toString() ?? '';
            return '- $name: $desc';
          })
          .join('\n');

        messages.insert(0, ChatMessage(
          role: 'system',
          content: '''You are a code completion agent in Roxum IDE.

  When you need to use a tool, respond with a JSON block like:
  {"type": "tool_call", "function": "toolName", "arguments": {"key": "value"}}

  Available tools:
  $toolList

  After each tool call, I will provide the result. Continue with your response.
  Do not claim missing permissions unless a tool call fails explicitly.''',
        ));
      }

      messages.add(ChatMessage(role: 'user', content: prompt));

      final fullResponse = StringBuffer();
      var toolCallsParsed = <Map<String, dynamic>>[];

      try {
        final generateFuture = controller.generateChat(
          messages: messages,
          maxTokens: model.maxTokens,
          temperature: model.temperature,
          topP: model.topP,
          topK: model.topK,
          repeatPenalty: model.repeatPenalty,
          frequencyPenalty: model.frequencyPenalty,
          presencePenalty: model.presencePenalty,
          repeatLastN: model.repeatLastN,
          seed: model.seed,
          mirostat: model.mirostat,
          mirostatTau: model.mirostatTau,
          mirostatEta: model.mirostatEta,
        ).listen(
          (token) {
            fullResponse.write(token);
            newList[index] = newList[index].copyWith(
              modelResponse: fullResponse.toString(),
            );
            chatSessionBloc.add(UpdateCurrentSession(conversations: newList));
            _scrollToBottom();
          },
          onError: (e) {
            debugPrint('[LocalLlama] Stream error: $e');
            final currentSession = chatSessionBloc.state.currentSession;
            if (currentSession != null) {
              final updated = currentSession.conversations
                .map((c) => AIConversation(c.userRequest, c.modelResponse))
                .toList();
              if (index < updated.length) {
                updated[index] = updated[index].copyWith(
                  modelResponse: _userFacingChatErrorMessage(e),
                );
                chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
              }
            }
          },
        ).asFuture();

        await generateFuture.timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            throw TimeoutException('Local model generation timed out after 120s');
          },
        );
      } catch (e) {
        if (e is TimeoutException) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Generation timeout: ${e.message}'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
        _logChatError('sendLocalLlama.generateChat', e, StackTrace.current);
        _updateBlocState(isGenerating: false);
        return;
      }

      if (chatMode == ChatMode.agent && fullResponse.isNotEmpty) {
        toolCallsParsed = _extractToolCallsFromPrompt(fullResponse.toString());

        if (toolCallsParsed.isNotEmpty && mounted) {
          final tools = AgenticTools(workspacePath: widget.workspacePath, context: context);
          var currentMessages = List<ChatMessage>.from(messages);
          currentMessages.add(ChatMessage(role: 'assistant', content: fullResponse.toString()));

          for (var turnIdx = 0; turnIdx < 3 && toolCallsParsed.isNotEmpty; turnIdx++) {
            final toolResults = <String>[];

            for (final call in toolCallsParsed) {
              final functionName = call['function']?.toString();
              final args = call['arguments'] as Map<String, dynamic>? ?? {};

              if (functionName != null && functionName.isNotEmpty) {
                try {
                  final result = await _executeExternalToolCall(
                    tools: tools,
                    functionName: functionName,
                    args: args,
                    pushPartial: (partial) {},
                  );
                  toolResults.add(result);
                } catch (e) {
                  toolResults.add('Error executing $functionName: $e');
                }
              }
            }

            currentMessages.add(ChatMessage(
              role: 'user',
              content: 'Tool results:\n${toolResults.join('\n')}\n\nContinue your response based on the tool results.',
            ));

            final nextTurnResponse = StringBuffer();
            try {
              final nextGenerateFuture = controller.generateChat(
                messages: currentMessages,
                maxTokens: model.maxTokens,
                temperature: model.temperature,
                topP: model.topP,
                topK: model.topK,
                repeatPenalty: model.repeatPenalty,
                frequencyPenalty: model.frequencyPenalty,
                presencePenalty: model.presencePenalty,
                repeatLastN: model.repeatLastN,
                seed: model.seed,
                mirostat: model.mirostat,
                mirostatTau: model.mirostatTau,
                mirostatEta: model.mirostatEta,
              ).listen(
                (token) {
                  nextTurnResponse.write(token);
                  fullResponse.write(token);
                  newList[index] = newList[index].copyWith(
                    modelResponse: fullResponse.toString(),
                  );
                  chatSessionBloc.add(UpdateCurrentSession(conversations: newList));
                  _scrollToBottom();
                },
                onError: (e) {
                  debugPrint('[LocalLlama] Tool loop stream error: $e');
                },
              ).asFuture();

              await nextGenerateFuture.timeout(
                const Duration(seconds: 120),
                onTimeout: () {
                  throw TimeoutException('Tool loop generation timed out after 120s');
                },
              );
            } catch (e) {
              if (e is TimeoutException) {
                debugPrint('[LocalLlama] Tool turn timed out: ${e.message}');
              } else {
                debugPrint('[LocalLlama] Tool turn error: $e');
              }
              break;
            }

            currentMessages.add(ChatMessage(role: 'assistant', content: nextTurnResponse.toString()));

            toolCallsParsed = _extractToolCallsFromPrompt(nextTurnResponse.toString());

            if (toolCallsParsed.isEmpty) {
              break;
            }
          }
        }
      }

      _updateBlocState(isGenerating: false);

      if (isFirstMessage && fullResponse.isNotEmpty) {
        final currentSession = chatSessionBloc.state.currentSession;
        if (currentSession != null) {
          chatSessionBloc.add(UpdateSessionTitle(
            sessionId: currentSession.id,
            title: prompt.split(' ').take(5).join(' '),
          ));
        }
      }
    } catch (e, st) {
      _logChatError('sendLocalLlama', e, st);
      final currentSession = chatSessionBloc.state.currentSession;
      if (currentSession != null) {
        final updated = currentSession.conversations
          .map((c) => AIConversation(c.userRequest, c.modelResponse))
          .toList();
        if (index < updated.length) {
          updated[index] = updated[index].copyWith(
            modelResponse: _userFacingChatErrorMessage(e),
          );
          chatSessionBloc.add(UpdateCurrentSession(conversations: updated));
        }
      }
      _updateBlocState(isGenerating: false);
    }
  }

  List<Map<String, dynamic>> _extractToolCallsFromPrompt(String response) {
    final calls = <Map<String, dynamic>>[];
    try {
      final pattern = RegExp(
        r'\{\s*"type"\s*:\s*"tool_call".*?\}',
        dotAll: true,
        multiLine: true,
      );
      
      for (final match in pattern.allMatches(response)) {
        try {
          final json = jsonDecode(match.group(0)!);
          if (json is Map && json['type'] == 'tool_call') {
            calls.add({
              'function': json['function'],
              'arguments': json['arguments'] ?? {},
            });
          }
        } catch (_) {}
      }
    } catch (_) {}
    return calls;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasPendingConversationEdit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _hasPendingConversationEdit) {
          _restorePendingConversationEdit();
        }
      },
      child: BlocBuilder<AIChatUIBloc, AIChatUIState>(
        builder: (context, aiChatUIState) {
          return BlocBuilder<AppThemeBloc, AppThemeState>(
            builder: (context, appThemeState) {
              return BlocBuilder<AIBloc, AIState>(
                builder: (context, aiState) {
                  final Models? chatModel = aiState.chatModel;
                  final bool externalModelConfigured = !(aiState.config.isEmpty || aiState.modelSelected.isEmpty);

                  return BlocBuilder<ChatSessionBloc, ChatSessionState>(
                    builder: (context, sessionState) {
                      final baseConversations = sessionState.currentSession?.conversations ?? [];
                      final conversations = _pendingEditedConversations ?? baseConversations;
                      final sessionTitle = sessionState.currentSession?.title ?? 'New Chat';
                      final textColor = appThemeState.appTheme.selectScreenCardTextColor;
                      final isDark = appThemeState.appTheme.isDark;
                      
                      return BlocBuilder<GithubAuthCubit, GithubAuthState>(
                        builder: (context, authState) {
                          final copilotSignedIn = context.watch<CopilotBloc>().state.isSignedIn || _copilotSignedInFromPrefs;
                          
                          if (!externalModelConfigured && !copilotSignedIn) {
                            return Center(
                              child: Text(
                                "Chat model is not configured. Either create a model in settings or sign in with GitHub Copilot.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: appThemeState.appTheme.selectScreenCardTextColor,
                                ),
                              ),
                            );
                          }
                          
                          return BlocBuilder<LocalLlamaBloc, LocalLlamaState>(
                            builder: (context, llamaState) {
                              return BlocBuilder<CopilotChatBloc, CopilotChatState>(
                                builder: (context, chatState) {
                                  _updatePendingPolling(aiChatUIState.isGenerating);
                                  final pendingCounts = _pendingDiffCounts(_pendingEdits);
    
                                  if ((copilotSignedIn) && !_requestedCopilotModelRefresh && !chatState.isFetchingModels) {
                                    _requestedCopilotModelRefresh = true;
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      context.read<CopilotChatBloc>().add(CopilotChatFetchModels(forceRefresh: true));
                                    });
                                  }
                                  
                                  return SafeArea(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                            child: Column(
                                              children: [
                                                if (llamaState.isLoading)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 5.5),
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.teal.withAlpha(30),
                                                      borderRadius: .circular(8)
                                                    ),
                                                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                                                    child: Row(
                                                      children: [
                                                        const SizedBox(
                                                          width: 14, height: 14,
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Colors.teal,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          'Loading ${llamaState.loadedModelName ?? 'model'}…',
                                                          style: const TextStyle(
                                                            color: Colors.teal,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                Column(
                                                  spacing: 3.5,
                                                  children: [
                                                    _buildModelSelector(
                                                      context, 
                                                      aiState, 
                                                      chatState, 
                                                      textColor, 
                                                      isDark,
                                                      copilotSignedIn,
                                                      aiChatUIState.selectedModelId,
                                                    ),
                                                    Row(
                                                      children: [
                                                        Expanded(child: _buildModeSelector(textColor, isDark, aiChatUIState.chatMode)),
                                                        IconButton(
                                                          onPressed: () => _showHistoryDialog(context, appThemeState.appTheme, sessionState),
                                                          icon: Icon(Icons.history, color: textColor.withAlpha(200), size: 20),
                                                          tooltip: 'Chat History',
                                                          visualDensity: VisualDensity.compact,
                                                        ),
                                                        IconButton(
                                                          onPressed: () => context.read<ChatSessionBloc>().add(CreateNewSession()),
                                                          icon: Icon(Icons.add_comment_outlined, color: textColor.withAlpha(200), size: 20),
                                                          tooltip: 'New Chat',
                                                          visualDensity: VisualDensity.compact,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        sessionTitle,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w500,
                                                          fontSize: 14,
                                                          color: textColor.withAlpha(180),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          TextField(
                                            controller: _promptController,
                                            cursorColor: appThemeState.appTheme.selectScreenCardTextColor,
                                            textAlignVertical: TextAlignVertical.top,
                                            style: TextStyle(
                                              color: appThemeState.appTheme.selectScreenCardTextColor,
                                            ),
                                            maxLines: null,
                                            decoration: InputDecoration(
                                              focusedBorder: const OutlineInputBorder(
                                                borderSide: BorderSide(color: Color(0xff0178b9)),
                                              ),
                                              suffix: IconButton(
                                                onPressed: aiChatUIState.isGenerating
                                                  ? _stopGeneration
                                                  : () async {
                                                      if (_hasPendingConversationEdit) {
                                                        final currentText = _promptController.text.trim();
                                                        final oldText = _pendingEditOriginalText?.trim() ?? '';
                                                        if (currentText == oldText) {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            const SnackBar(
                                                              content: Text('Text must be different'),
                                                              backgroundColor: Colors.orange,
                                                            ),
                                                          );
                                                          return;
                                                        }
                                                      }
    
                                                      final sendingConversations = _cloneConversations(conversations);
                                                      if (_hasPendingConversationEdit) {
                                                        setState(() {
                                                          _pendingEditBaseConversations = null;
                                                          _pendingEditedConversations = null;
                                                          _pendingEditOriginalText = null;
                                                        });
                                                      }
    
                                                      String selectedModelId = aiChatUIState.selectedModelId ?? '';
                                                      if (selectedModelId.isEmpty) {
                                                        selectedModelId = aiState.modelSelected['chat'] ?? '';
                                                      }
                                                      if (selectedModelId.isEmpty && aiState.config.isNotEmpty) {
                                                        selectedModelId = aiState.config.keys.first;
                                                      }
                                                      final selectedModelConfig = aiState.config[selectedModelId];
                                                      final isLocalModel = selectedModelConfig is Map &&
                                                          (selectedModelConfig['apiProvider'] ?? selectedModelConfig['provider']) == 'LocalLlama';
                                                      final isCopilotModel = chatState.models.any((model) => model['id'] == selectedModelId);

                                                      if (isLocalModel) {
                                                        final config = selectedModelConfig as Map<String, dynamic>;
                                                        final localModel = LocalLlama(
                                                          modelPath: config['modelPath'] ?? '',
                                                          displayName: config['modelName'] ?? config['model'] ?? 'Local Model',
                                                          threads: config['threads'] ?? 4,
                                                          contextSize: config['contextSize'] ?? 4096,
                                                          gpuLayers: config['gpuLayers'] ?? 0,
                                                        );
                                                        _sendLocalLlamaPrompt(localModel, sendingConversations, sessionState.currentSession?.id);
                                                      } else if (isCopilotModel) {
                                                        _sendCopilotChatPrompt(sendingConversations, sessionState.currentSession?.id, selectedModelId, widget.workspacePath);
                                                      } else if (chatModel != null) {
                                                        _sendPrompt(chatModel, sendingConversations, sessionState.currentSession?.id);
                                                      } else {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(content: Text('Chat model not available'), backgroundColor: Colors.orange),
                                                        );
                                                      }
    
                                                    },
                                                icon: Icon(
                                                  aiChatUIState.isGenerating ? Icons.stop_circle_outlined : Icons.send,
                                                  color: appThemeState.appTheme.selectScreenCardTextColor,
                                                ),
                                              ),
                                              contentPadding: EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 5,
                                              ),
                                              labelText: 'Ask AI',
                                              labelStyle: TextStyle(
                                                color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8, right: 2.5),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child: languages.firstWhere(
                                                    (item) => item.extension.contains(
                                                      path.extension(widget.filePath).isNotEmpty ? path.extension(widget.filePath).substring(1) : '',
                                                    ),
                                                    orElse: () => languages.first,
                                                  ).icon,
                                                ),
                                                SizedBox(width: 3),
                                                Text(
                                                  path.basename(widget.filePath),
                                                  style: TextStyle(
                                                    color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                                  ),
                                                ),
                                                if (pendingCounts.added > 0 || pendingCounts.removed > 0) ...[
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '+${pendingCounts.added}',
                                                    style: const TextStyle(
                                                      color: Color(0xFF2E7D32),
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '-${pendingCounts.removed}',
                                                    style: const TextStyle(
                                                      color: Color(0xFFC62828),
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: BlocBuilder<ConfigBloc, ConfigState>(
                                              builder: (context, configState) {
                                                final theme = getMergedHighlightThemes(configState.codeForgeConfig)[configState.codeForgeConfig['theme']] ?? atomOneDarkTheme;
                                                
                                                if (!_initialScrollDone && conversations.isNotEmpty) {
                                                  _initialScrollDone = true;
                                                  final savedOffset = aiChatUIState.scrollOffset;
                                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                                    if (_scrollController.hasClients) {
                                                      if (savedOffset < 0) {
                                                        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                                                      } else {
                                                        final clampedOffset = savedOffset.clamp(
                                                          _scrollController.position.minScrollExtent,
                                                          _scrollController.position.maxScrollExtent,
                                                        );
                                                        _scrollController.jumpTo(clampedOffset);
                                                      }
                                                    }
                                                  });
                                                }
                                                
                                                return ListView.builder(
                                                  controller: _scrollController,
                                                  itemCount: conversations.length,
                                                  itemBuilder: (context, index) {
                                                    final isDark = appThemeState.appTheme.isDark;
                                                    final fileExtension = path.extension(widget.filePath);
                                                    final extensionWithoutDot = fileExtension.startsWith('.')
                                                      ? fileExtension.substring(1)
                                                      : fileExtension;
                                                    final previewLanguage = languages.singleWhere(
                                                      (item) => extensionWithoutDot.isNotEmpty &&
                                                          item.extension.contains(extensionWithoutDot),
                                                      orElse: () => languages.first,
                                                    );
                                                    final config = isDark
                                                      ? MarkdownConfig.darkConfig.copy(
                                                          configs: [
                                                            PConfig(
                                                              textStyle: TextStyle(
                                                                color: appThemeState.appTheme.selectScreenCardTextColor,
                                                              ),
                                                            ),
                                                            PreConfig(
                                                              language: previewLanguage.name.toLowerCase(),
                                                              theme: theme,
                                                              styleNotMatched: TextStyle(
                                                                color: theme['root']!.color,
                                                                fontFamily: configState.codeForgeConfig['fontFamily'],
                                                              ),
                                                              decoration: BoxDecoration(
                                                                color: theme['root']!.backgroundColor
                                                              )
                                                            )
                                                          ],
                                                        )
                                                      : MarkdownConfig.defaultConfig;
                                                    final conv = conversations[index];
                                                    final hasResponse =
                                                      conv.modelResponse != null &&
                                                      conv.modelResponse!.isNotEmpty;
                                                    final isStreaming = conv.modelResponse != null && conv.modelResponse!.isEmpty;
                                                    return Padding(
                                                      padding: const EdgeInsets.only(top: 8),
                                                      child: Column(
                                                        children: [
                                                          Align(
                                                            alignment: Alignment.centerRight,
                                                            child: Padding(
                                                              padding: const EdgeInsets.symmetric(
                                                                vertical: 6.5,
                                                              ),
                                                              child: GestureDetector(
                                                                onLongPress: () => _showUserBubbleActions(
                                                                  index: index,
                                                                  conversation: conv,
                                                                  baseConversations: baseConversations,
                                                                  aiChatUIState: aiChatUIState,
                                                                  sessionState: sessionState,
                                                                  chatState: chatState,
                                                                  chatModel: chatModel,
                                                                  appTheme: appThemeState.appTheme,
                                                                ),
                                                                child: Container(
                                                                  padding: EdgeInsets.symmetric(
                                                                    vertical: 5,
                                                                    horizontal: 8,
                                                                  ),
                                                                  decoration: BoxDecoration(
                                                                    color: Colors.blueAccent.withAlpha(
                                                                      200,
                                                                    ),
                                                                    borderRadius: BorderRadius.only(
                                                                      topLeft: Radius.circular(16),
                                                                      topRight: Radius.zero,
                                                                      bottomLeft: Radius.circular(16),
                                                                      bottomRight: Radius.circular(16),
                                                                    ),
                                                                  ),
                                                                  child: Text(
                                                                    conv.userRequest,
                                                                    style: TextStyle(
                                                                      color: Colors.white,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          Align(
                                                            alignment: Alignment.centerLeft,
                                                            child: hasResponse
                                                              ? _buildAssistantResponseContent(
                                                                  conv.modelResponse!,
                                                                  config,
                                                                  appThemeState.appTheme,
                                                                )
                                                              : isStreaming
                                                                ? Row(
                                                                    children: [
                                                                      SizedBox(
                                                                        width: 16,
                                                                        height: 16,
                                                                        child: CircularProgressIndicator(
                                                                          strokeWidth: 2,
                                                                          color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                                                        ),
                                                                      ),
                                                                      const SizedBox(width: 8),
                                                                      Text(
                                                                        'Thinking...',
                                                                        style: TextStyle(
                                                                          color: appThemeState.appTheme.selectScreenCardTextColor.withAlpha(150),
                                                                          fontStyle: FontStyle.italic,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  )
                                                                : const SizedBox.shrink(),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: _buildPendingDiffDrawerPanel(appThemeState.appTheme),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showHistoryDialog(BuildContext context, AppTheme appTheme, ChatSessionState initialState) {
    showDialog(
      context: context,
      builder: (dialogContext) => BlocBuilder<ChatSessionBloc, ChatSessionState>(
        builder: (context, sessionState) {
          return AlertDialog(
            backgroundColor: appTheme.isDark ? const Color(0xff1e1e2e) : Colors.white,
            title: Row(
              children: [
                Icon(
                  Icons.history,
                  color: appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(width: 12),
                Text(
                  'Chat History',
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: sessionState.sessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: appTheme.selectScreenCardTextColor.withAlpha(100),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No chat history yet',
                          style: TextStyle(
                            color: appTheme.selectScreenCardTextColor.withAlpha(150),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: sessionState.sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessionState.sessions[index];
                      final isSelected = sessionState.currentSession?.id == session.id;
                      return Card(
                        color: isSelected
                          ? (appTheme.isDark ? const Color(0xff3d3d5c) : Colors.blue.withAlpha(30))
                          : (appTheme.isDark ? const Color(0xff2a2a3e) : Colors.grey.shade100),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: Icon(
                            Icons.chat,
                            color: isSelected
                              ? Colors.blue
                              : appTheme.selectScreenCardTextColor.withAlpha(150),
                          ),
                          title: Text(
                            session.title,
                            style: TextStyle(
                              color: appTheme.selectScreenCardTextColor,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _formatDate(session.createdAt),
                            style: TextStyle(
                              color: appTheme.selectScreenCardTextColor.withAlpha(100),
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: Colors.red.withAlpha(180),
                              size: 20,
                            ),
                            onPressed: () {
                              _showDeleteConfirmation(context, appTheme, session.id, session.title);
                            },
                          ),
                          onTap: () {
                            context.read<ChatSessionBloc>().add(SelectSession(session.id));
                            Navigator.of(dialogContext).pop();
                          },
                        ),
                      );
                    },
                  ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  'Close',
                  style: TextStyle(
                    color: appTheme.isDark ? Colors.blue.shade300 : Colors.blue,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, AppTheme appTheme, String sessionId, String sessionTitle) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: appTheme.isDark ? const Color(0xff1e1e2e) : Colors.white,
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Chat',
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete this chat?',
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: appTheme.isDark 
                  ? Colors.white.withAlpha(10) 
                  : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.chat,
                    size: 20,
                    color: appTheme.selectScreenCardTextColor.withAlpha(150),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sessionTitle,
                      style: TextStyle(
                        color: appTheme.selectScreenCardTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor.withAlpha(150),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: appTheme.isDark ? Colors.white70 : Colors.grey.shade700,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<ChatSessionBloc>().add(DeleteSession(sessionId));
              Navigator.of(dialogContext).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text(
              'Delete',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

const List<Color> _gitGraphColors = [
  Color(0xFF569CD6),
  Color(0xFFD7BA7D),
  Color(0xFFC586C0),
  Color(0xFF4EC9B0),
  Color(0xFFD16969),
  Color(0xFF6A9955),
  Color(0xFFCE9178),
  Color(0xFFB5CEA8),
  Color(0xFFDCDCAA),
  Color(0xFF4FC1FF),
];

Color _getGraphColor(int index) {
  return _gitGraphColors[index % _gitGraphColors.length];
}

class VSCodeGitGraphPainter extends CustomPainter {
  final CommitRowInfo rowInfo;
  final double laneWidth;
  final double rowHeight;
  final bool isDark;
  final Color textColor;
  final Color secondaryTextColor;
  final Color backgroundColor;
  final double maxWidth;

  VSCodeGitGraphPainter({
    required this.rowInfo,
    required this.textColor,
    required this.secondaryTextColor,
    required this.backgroundColor,
    required this.maxWidth,
    this.laneWidth = 16,
    this.rowHeight = 36,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final nodePaint = Paint()..style = PaintingStyle.fill;
    final nodeStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final nodeCapPaint = Paint()..style = PaintingStyle.fill;

    final commitX = rowInfo.commitLane * laneWidth + laneWidth / 2;
    final commitY = rowHeight / 2;

    for (final line in rowInfo.lines) {
      final fromX = line.fromLane * laneWidth + laneWidth / 2;
      final toX = line.toLane * laneWidth + laneWidth / 2;
      final color = _getGraphColor(line.colorIndex);
      linePaint.color = color;

      if (line.isPassThrough) {
        canvas.drawLine(Offset(fromX, 0), Offset(fromX, rowHeight), linePaint);
      } else if (line.fromLane == line.toLane) {
        canvas.drawLine(
          Offset(fromX, commitY + 5),
          Offset(fromX, rowHeight),
          linePaint,
        );
      } else {
        final path = Path();

        if (line.toLane > line.fromLane) {
          path.moveTo(fromX, commitY + 5);
          path.cubicTo(
            fromX,
            commitY + 10,
            fromX + 14,
            rowHeight - 12,
            toX,
            rowHeight,
          );
        } else {
          path.moveTo(fromX, commitY + 5);
          path.cubicTo(
            fromX,
            commitY + 12,
            toX + 15,
            rowHeight,
            toX,
            rowHeight,
          );
        }
        canvas.drawPath(path, linePaint);
      }
    }

    final nodeColor = _getGraphColor(rowInfo.colorIndex);
    final isReferenceCommit = rowInfo.commit.isHead || rowInfo.commit.isRemoteHead;

    if (!isReferenceCommit) {
      linePaint.color = nodeColor;
      canvas.drawLine(
        Offset(commitX, 0),
        Offset(commitX, commitY - 5),
        linePaint,
      );
    }

    if (isReferenceCommit) {
      nodeCapPaint.color = backgroundColor;
      canvas.drawCircle(Offset(commitX, commitY), 8, nodeCapPaint);
      nodeStrokePaint.color = nodeColor.withAlpha(220);
      canvas.drawCircle(Offset(commitX, commitY), 7, nodeStrokePaint);
      nodePaint.color = nodeColor;
      canvas.drawCircle(Offset(commitX, commitY), 4, nodePaint);
    } else if (rowInfo.commit.isMerge) {
      nodePaint.color = nodeColor;
      canvas.drawCircle(Offset(commitX, commitY), 5, nodePaint);
      nodeStrokePaint.color = nodeColor.withAlpha(180);
      canvas.drawCircle(Offset(commitX, commitY), 7, nodeStrokePaint);
    } else {
      nodePaint.color = nodeColor;
      canvas.drawCircle(Offset(commitX, commitY), 5, nodePaint);
    }

    int maxLaneInRow = rowInfo.commitLane;
    for (final line in rowInfo.lines) {
      if (line.fromLane > maxLaneInRow) maxLaneInRow = line.fromLane;
      if (line.toLane > maxLaneInRow) maxLaneInRow = line.toLane;
    }

    final graphWidth = (maxLaneInRow + 1) * laneWidth + 12;
    double textStartX = graphWidth;
    final availableWidth = maxWidth - textStartX;

    if (availableWidth > 50) {
      if (rowInfo.commit.isMerge) {
        final badgePainter = TextPainter(
          text: TextSpan(
            text: 'Merge',
            style: TextStyle(
              color: _getGraphColor(rowInfo.colorIndex),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        badgePainter.layout();

        final badgeWidth = badgePainter.width + 8;
        final badgeHeight = badgePainter.height + 2;
        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(textStartX, 8, badgeWidth, badgeHeight),
          const Radius.circular(3),
        );

        final badgeBgPaint = Paint()
          ..color = _getGraphColor(rowInfo.colorIndex).withAlpha(40)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(badgeRect, badgeBgPaint);

        final badgeBorderPaint = Paint()
          ..color = _getGraphColor(rowInfo.colorIndex).withAlpha(100)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRRect(badgeRect, badgeBorderPaint);
        badgePainter.paint(canvas, Offset(textStartX + 4, 8));
        textStartX += badgeWidth + 6;
      }

      final messagePainter = TextPainter(
        text: TextSpan(
          text: rowInfo.commit.message,
          style: TextStyle(color: textColor, fontSize: 13, height: 1.2),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      messagePainter.layout(
        maxWidth: availableWidth - (rowInfo.commit.isMerge ? 50 : 0),
      );
      messagePainter.paint(canvas, Offset(textStartX, 6));

      final authorHash =
          '${rowInfo.commit.author} • ${rowInfo.commit.hash.substring(0, 7)}';
      final authorPainter = TextPainter(
        text: TextSpan(
          text: authorHash,
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 10,
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      authorPainter.layout(maxWidth: availableWidth);
      authorPainter.paint(canvas, Offset(graphWidth, 22));
    }
  }

  @override
  bool shouldRepaint(covariant VSCodeGitGraphPainter oldDelegate) {
    return oldDelegate.rowInfo != rowInfo ||
        oldDelegate.maxWidth != maxWidth ||
        oldDelegate.textColor != textColor;
  }
}

class GitCommitGraph extends StatelessWidget {
  final List<CommitNode> commits;
  final AppTheme appTheme;

  const GitCommitGraph({
    super.key,
    required this.commits,
    required this.appTheme,
  });

  @override
  Widget build(BuildContext context) {
    final rowInfos = assignVSCodeLanes(commits);
    const contentWidth = 500.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: contentWidth,
        height: commits.length * 36.0,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: rowInfos.length,
          itemBuilder: (context, index) {
            final rowInfo = rowInfos[index];
            return SizedBox(
              height: 36,
              child: CustomPaint(
                size: Size(contentWidth, 36),
                painter: VSCodeGitGraphPainter(
                  rowInfo: rowInfo,
                  isDark: appTheme.isDark,
                  textColor: appTheme.selectScreenCardTextColor,
                  secondaryTextColor: appTheme.selectScreenCardTextColor.withAlpha(150),
                  backgroundColor: appTheme.scaffoldBg,
                  maxWidth: contentWidth,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

Widget settingsTextField(
  TextEditingController controller,
  IconData icon,
  String labelText,
  Color labelColor,
  String? hintText,
  String? Function(String?) validator,
  [bool obscure = false]
){
  return TextFormField(
    controller: controller,
    style: TextStyle(
      color: labelColor
    ),
    obscureText: obscure,
    cursorColor: Colors.lightBlue,
    decoration: InputDecoration(
      prefixIcon: Icon(icon, color: Color(0xff007acc)),
      hintStyle: TextStyle(
        color: labelColor.withAlpha(150),
        fontStyle: FontStyle.italic,
        fontSize: 12
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(5),
        borderSide: BorderSide(
          color: Color(0xff007acc),
          width: 2,
        )
      ),
      hintText: hintText,
      labelText: labelText,
      labelStyle: TextStyle(
        color: labelColor.withAlpha(150),
        fontSize: 15
      ),
    ),
    validator: validator,
  );
}

Widget copyArea(
  BuildContext context,
  AppTheme appTheme,
  String text,
  double height
) => Container(
  height: height,
    width: 350,
    decoration: BoxDecoration(
      color: appTheme.scaffoldBg,
      border: .all(
        color: appTheme.selectScreenCardTextColor.withAlpha(120),
        width: 1
      ),
      borderRadius: .circular(6)
    ),
  child: Stack(
    children: [
      Padding(
        padding: const EdgeInsets.only(right: 35, top: 15, left: 10),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: "monospace",
            fontSize: 14
          )
        ),
      ),
      Positioned(
        right: 0,
        top: 0,
        child: IconButton(
          onPressed: () async{
            await Clipboard.setData(
              ClipboardData(text: text)
            );
            if(context.mounted){
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          icon: Icon(
            Icons.copy,
            color: appTheme.selectScreenCardTextColor.withAlpha(200)
          )
        ),
      )
    ]
  ),
);

class GgufDownloadManager extends StatefulWidget {
  final List<GgufModel> availableModels;

  const GgufDownloadManager({super.key, required this.availableModels});

  @override
  State<GgufDownloadManager> createState() => _GgufDownloadManagerState();
}

class _GgufDownloadManagerState extends State<GgufDownloadManager>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerUnregisteredCompletedTasks(context);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _registerUnregisteredCompletedTasks(BuildContext context) async {
    final cubit = context.read<GgufDownloadCubit>();
    for (final task in cubit.state.tasks) {
      if (task.status == GgufDownloadStatus.completed && !task.registered) {
        final result = await GgufModel.registerGgufModelWithAI(task);
        if (context.mounted) {
          context.read<AIBloc>().add(AIConfigEvent(result.aiConfig));
          context.read<AIBloc>().add(ModelSelectEvent(result.modelSelected));
          cubit.markTaskRegistered(task.taskId);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppThemeBloc>().state.appTheme;
    final isDark = appTheme.isDark;
    final textColor = appTheme.selectScreenCardTextColor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xff2b2b2b) : Colors.white,
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_download, color: Colors.lightBlue, size: 28),
                const SizedBox(width: 12),
                Text(
                  'GGUF Model Manager',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              labelColor: Colors.lightBlue,
              unselectedLabelColor: textColor.withAlpha(150),
              indicatorColor: Colors.lightBlue,
              tabs: const [
                Tab(text: 'Available Models'),
                Tab(text: 'Downloads'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAvailableTab(context, appTheme),
                  _buildDownloadsTab(context, appTheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableTab(BuildContext context, AppTheme appTheme) {
    final isDark = appTheme.isDark;

    String hardwareLevel(double params) {
      if (params <= 1.5) return "Light";
      if (params <= 3) return "Medium";
      return "Heavy";
    }

    Color hardwareColor(double params) {
      if (params <= 1.5) return Colors.green;
      if (params <= 3) return Colors.orange;
      return Colors.redAccent;
    }

    String hardwareNote(double params) {
      if (params <= 1.5) return "Runs on most phones";
      if (params <= 3) return "Needs decent RAM";
      return "High-end device needed";
    }

    Widget buildChip(String text, IconData icon) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return BlocBuilder<GgufDownloadCubit, GgufDownloadState>(
      builder: (context, state) {
        final cubit = context.read<GgufDownloadCubit>();

        return ListView.builder(
          itemCount: widget.availableModels.length,
          itemBuilder: (_, i) {
            final model = widget.availableModels[i];

            GgufDownloadTask? existing;
            for (var task in state.tasks) {
              if (task.url == model.url) {
                existing = task;
                break;
              }
            }

            final isCompleted = existing?.status == GgufDownloadStatus.completed;

            final isDownloading = existing?.status == GgufDownloadStatus.downloading;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isDark
                  ? appTheme.editorPageToolbarBg.withAlpha(150)
                  : Colors.grey.shade50,
                border: Border.all(
                  color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Image.network(model.imageUrl, width: 20, height: 20)
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          model.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: appTheme.selectScreenCardTextColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      buildChip("${model.paramSize}B", Icons.storage),
                      buildChip(model.quant, Icons.compress),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: hardwareColor(model.paramSize).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          hardwareLevel(model.paramSize),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hardwareColor(model.paramSize),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Text(
                    hardwareNote(model.paramSize),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.centerRight,
                    child: isCompleted
                      ? const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        )
                      : isDownloading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color:
                                    appTheme.selectScreenCardTextColor,
                              ),
                            )
                          : ElevatedButton.icon(
                              onPressed: () {
                                cubit.startDownload(model);
                                _tabController.animateTo(1);
                              },
                              icon: const Icon(
                                Icons.download,
                                size: 16,
                              ),
                              label: const Text("Download"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xff007acc),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                              ),
                            ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDownloadsTab(BuildContext context, AppTheme appTheme) {
    return BlocBuilder<GgufDownloadCubit, GgufDownloadState>(
      builder: (context, downldState) {
        final tasks = downldState.tasks.where((t) => t.status != GgufDownloadStatus.completed).toList();
        final completed = downldState.tasks.where((t) => t.status == GgufDownloadStatus.completed).toList();

        if (tasks.isEmpty && completed.isEmpty) {
          return Center(
            child: Text(
              'No downloads yet',
              style: TextStyle(color: appTheme.selectScreenCardTextColor.withAlpha(150)),
            ),
          );
        }

        return ListView(
          children: [
            if (tasks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Active Downloads', style: TextStyle(color: appTheme.selectScreenCardTextColor, fontWeight: FontWeight.w600)),
              ),
              ...tasks.map((task) => _buildTaskTile(task, appTheme, context.read<GgufDownloadCubit>())),
            ],
            if (completed.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Completed', style: TextStyle(color: appTheme.selectScreenCardTextColor, fontWeight: FontWeight.w600)),
              ),
              ...completed.map((task) => _buildTaskTile(task, appTheme, context.read<GgufDownloadCubit>())),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTaskTile(GgufDownloadTask task, AppTheme appTheme, GgufDownloadCubit cubit) {
    final isDark = appTheme.isDark;
    final isActive = task.status == GgufDownloadStatus.downloading;
    final isCompleted = task.status == GgufDownloadStatus.completed;
    final isFailed = task.status == GgufDownloadStatus.failed;
    final progress = task.progress.clamp(0.0, 100.0);
    final hasAccurateProgress = progress > 0.0 && progress < 100.0;

    return BlocBuilder<GgufDownloadCubit, GgufDownloadState>(
      builder: (context, downldState) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          elevation: 0,
          color: isDark ? const Color(0xff1e1e2e) : Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isCompleted ? Icons.check_circle : (isFailed ? Icons.error : Icons.downloading),
                      color: isCompleted ? Colors.green : (isFailed ? Colors.red : Colors.lightBlue),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        task.modelName,
                        style: TextStyle(
                          color: appTheme.selectScreenCardTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if(!isCompleted) IconButton(
                      icon: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: isDark ? const Color(0xff2b2b2b) : Colors.white,
                            title: Text(
                              'Cancel download?',
                              style: TextStyle(color: appTheme.selectScreenCardTextColor),
                            ),
                            content: Text(
                              'Remove "${task.modelName}" from the list? The downloaded file will also be deleted.',
                              style: TextStyle(color: appTheme.selectScreenCardTextColor.withAlpha(180)),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () async{
                                  Navigator.of(ctx).pop();
                                  if(downldState.id != null){
                                    final msg = await GgufDownloadCubit.cancelGGUFDownload(downldState.id!);
                                    if(context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Canceled $msg')),
                                      );
                                    }
                                  }
                                  cubit.deleteTask(task.taskId);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: .circular(10))
                                ),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                      },
                      tooltip: 'Remove from list and delete file',
                    ),
                  ],
                ),
                if (isActive) ...[
                  const SizedBox(height: 8),
                  if (hasAccurateProgress)
                    LinearPercentIndicator(
                      progressColor: Colors.lightBlue,
                      percent: progress / 100,
                      lineHeight: 8,
                      barRadius: const Radius.circular(4),
                    )
                  else
                    const LinearProgressIndicator(),
                  const SizedBox(height: 4),
                  Text(
                    hasAccurateProgress ? '${progress.toStringAsFixed(1)}%' : 'Downloading…',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                if (isFailed) ...[
                  const SizedBox(height: 8),
                  Text('Download failed.', style: TextStyle(color: Colors.red.shade300, fontSize: 12)),
                ],
                Wrap(
                  spacing: 8,
                  children: [
                    if (isFailed)
                      ElevatedButton.icon(
                        onPressed: () => cubit.retryDownload(task),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (isCompleted)
                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: appTheme.isDark ? const Color(0xff181A26) : null,
                              title: Text(
                                'Delete model?',
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor,
                                  fontSize: 20,
                                ),
                              ),
                              content: Text(
                                'Are you sure you want to delete this model? This action cannot be undone.',
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor.withAlpha(150),
                                  fontSize: 16,
                                ),
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () async {
                                    final aiState = context.read<AIBloc>();
                                    final entries = Map<String, dynamic>.from(aiState.config);

                                    final configKey = entries.keys.firstWhere(
                                      (key) => key.startsWith("LocalLlama-") &&
                                        entries[key] is Map &&
                                        entries[key]['modelName'] == task.modelName,
                                      orElse: () => '',
                                    );

                                    if (configKey.isNotEmpty) {
                                      final updatedConfig = Map<String, dynamic>.from(aiState.config)
                                        ..remove(configKey);
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setString('aiConfig', jsonEncode(updatedConfig));

                                      final updatedModelSelected = Map<String, dynamic>.from(aiState.modelSelected);
                                      var modelSelectionChanged = false;
                                      if (updatedModelSelected['code'] == configKey) {
                                        updatedModelSelected['code'] = '';
                                        modelSelectionChanged = true;
                                      }
                                      if (updatedModelSelected['chat'] == configKey) {
                                        updatedModelSelected['chat'] = '';
                                        modelSelectionChanged = true;
                                        await prefs.remove('ai_selected_chat_model_id');
                                      }
                                      if (modelSelectionChanged) {
                                        await prefs.setString('modelSelected', jsonEncode(updatedModelSelected));
                                      }

                                      if (context.mounted) {
                                        context.read<AIBloc>().add(AIConfigEvent(updatedConfig));
                                        if (modelSelectionChanged) {
                                          context.read<AIBloc>().add(ModelSelectEvent(updatedModelSelected));
                                        }
                                      }
                                    }

                                    try {
                                      await File(task.localPath).delete();
                                    } catch (_) {}

                                    cubit.deleteTask(task.taskId);

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Successfully deleted model ${task.modelName}')
                                        ),
                                      );
                                      Navigator.of(context).pop(true);
                                    }
                                  },
                                  style: ButtonStyle(
                                    backgroundColor: WidgetStateProperty.all<Color>(Colors.red),
                                  ),
                                  child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text('Delete file'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class FlutterSwitch extends StatefulWidget {

  const FlutterSwitch({
    super.key,
    required this.value,
    required this.onToggle,
    this.activeColor = Colors.blue,
    this.inactiveColor = Colors.grey,
    this.activeTextColor = Colors.white70,
    this.inactiveTextColor = Colors.white70,
    this.toggleColor = Colors.white,
    this.activeToggleColor,
    this.inactiveToggleColor,
    this.width = 70.0,
    this.height = 35.0,
    this.toggleSize = 25.0,
    this.valueFontSize = 16.0,
    this.borderRadius = 20.0,
    this.padding = 4.0,
    this.showOnOff = false,
    this.activeText,
    this.inactiveText,
    this.activeTextFontWeight,
    this.inactiveTextFontWeight,
    this.switchBorder,
    this.activeSwitchBorder,
    this.inactiveSwitchBorder,
    this.toggleBorder,
    this.activeToggleBorder,
    this.inactiveToggleBorder,
    this.activeIcon,
    this.inactiveIcon,
    this.toggleShape = BoxShape.circle,
    this.toggleBorderRadius,
    this.duration = const Duration(milliseconds: 200),
    this.disabled = false,
  })  : assert(
    (switchBorder == null || activeSwitchBorder == null) && (switchBorder == null || inactiveSwitchBorder == null),
    'Cannot provide switchBorder when an activeSwitchBorder or inactiveSwitchBorder was given\n'
    'To give the switch a border, use "activeSwitchBorder: border" or "inactiveSwitchBorder: border".'),
  assert(
    (toggleBorder == null || activeToggleBorder == null) && (toggleBorder == null || inactiveToggleBorder == null),
    'Cannot provide toggleBorder when an activeToggleBorder or inactiveToggleBorder was given\n'
    'To give the toggle a border, use "activeToggleBorder: color" or "inactiveToggleBorder: color".');

  final bool value, showOnOff, disabled;
  final ValueChanged<bool> onToggle;
  final String? activeText, inactiveText;
  final Color activeColor, inactiveColor, activeTextColor, inactiveTextColor, toggleColor;
  final FontWeight? activeTextFontWeight, inactiveTextFontWeight;
  final Color? activeToggleColor, inactiveToggleColor;
  final double width, height, toggleSize, valueFontSize, borderRadius, padding;
  final BoxBorder? switchBorder, activeSwitchBorder, inactiveSwitchBorder, toggleBorder, activeToggleBorder, inactiveToggleBorder;
  final Widget? activeIcon, inactiveIcon;
  final Duration duration;
  final BoxShape toggleShape;
  final BorderRadiusGeometry? toggleBorderRadius;

  @override
  FlutterSwitchState createState() => FlutterSwitchState();
}

class FlutterSwitchState extends State<FlutterSwitch> with SingleTickerProviderStateMixin {
  late final Animation _toggleAnimation;
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
      duration: widget.duration,
    );
    _toggleAnimation = AlignmentTween(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.linear,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FlutterSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.value == widget.value) return;

    if (widget.value) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    Color toggleColor = Colors.white;
    Color switchColor = Colors.white;
    Border? switchBorder;
    Border? toggleBorder;

    if (widget.value) {
      toggleColor = widget.activeToggleColor ?? widget.toggleColor;
      switchColor = widget.activeColor;
      switchBorder = widget.activeSwitchBorder as Border? ?? widget.switchBorder as Border?;
      toggleBorder = widget.activeToggleBorder as Border? ?? widget.toggleBorder as Border?;
    } else {
      toggleColor = widget.inactiveToggleColor ?? widget.toggleColor;
      switchColor = widget.inactiveColor;
      switchBorder = widget.inactiveSwitchBorder as Border? ?? widget.switchBorder as Border?;
      toggleBorder = widget.inactiveToggleBorder as Border? ?? widget.toggleBorder as Border?;
    }

    double textSpace = widget.width - widget.toggleSize;

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return SizedBox(
          width: widget.width,
          child: Align(
            child: GestureDetector(
              onTap: () {
                if (!widget.disabled) {
                  if (widget.value) {
                    _animationController.forward();
                  } else {
                    _animationController.reverse();
                  }

                  widget.onToggle(!widget.value);
                }
              },
              child: Opacity(
                opacity: widget.disabled ? 0.6 : 1,
                child: Container(
                  width: widget.width,
                  height: widget.height,
                  padding: EdgeInsets.all(widget.padding),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    color: switchColor,
                    border: switchBorder,
                  ),
                  child: Stack(
                    children: <Widget>[
                      AnimatedOpacity(
                        opacity: widget.value ? 1.0 : 0.0,
                        duration: widget.duration,
                        child: Container(
                          width: textSpace,
                          padding: EdgeInsets.symmetric(horizontal: 4.0),
                          alignment: Alignment.centerLeft,
                          child: _activeText,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: AnimatedOpacity(
                          opacity: !widget.value ? 1.0 : 0.0,
                          duration: widget.duration,
                          child: Container(
                            width: textSpace,
                            padding: EdgeInsets.symmetric(horizontal: 4.0),
                            alignment: Alignment.centerRight,
                            child: _inactiveText,
                          ),
                        ),
                      ),
                      Align(
                        alignment: _toggleAnimation.value,
                        child: Container(
                          width: widget.toggleSize,
                          height: widget.toggleSize,
                          padding: EdgeInsets.all(4.0),
                          decoration: BoxDecoration(
                            shape: widget.toggleShape,
                            color: toggleColor,
                            border: toggleBorder,
                            borderRadius: widget.toggleBorderRadius
                          ),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Stack(
                              children: [
                                Center(
                                  child: AnimatedOpacity(
                                    opacity: widget.value ? 1.0 : 0.0,
                                    duration: widget.duration,
                                    child: widget.activeIcon,
                                  ),
                                ),
                                Center(
                                  child: AnimatedOpacity(
                                    opacity: !widget.value ? 1.0 : 0.0,
                                    duration: widget.duration,
                                    child: widget.inactiveIcon,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  FontWeight get _activeTextFontWeight =>
      widget.activeTextFontWeight ?? FontWeight.w900;
  FontWeight get _inactiveTextFontWeight =>
      widget.inactiveTextFontWeight ?? FontWeight.w900;

  Widget get _activeText {
    if (widget.showOnOff) {
      return Text(
        widget.activeText ?? "On",
        style: TextStyle(
          color: widget.activeTextColor,
          fontWeight: _activeTextFontWeight,
          fontSize: widget.valueFontSize,
        ),
      );
    }

    return Text("");
  }

  Widget get _inactiveText {
    if (widget.showOnOff) {
      return Text(
        widget.inactiveText ?? "Off",
        style: TextStyle(
          color: widget.inactiveTextColor,
          fontWeight: _inactiveTextFontWeight,
          fontSize: widget.valueFontSize,
        ),
        textAlign: TextAlign.right,
      );
    }

    return Text("");
  }
}