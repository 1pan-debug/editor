import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Vim editing modes. Command mode owns a dedicated input field rendered by
/// the editor page; the engine only parses its submitted text.
enum VimMode { normal, insert, command }

String vimModeDisplayName(VimMode mode) {
  return switch (mode) {
    VimMode.normal => 'NORMAL',
    VimMode.insert => 'INSERT',
    VimMode.command => 'COMMAND',
  };
}

/// State machine for the editor's Vim-style mode.
///
/// The engine is deliberately decoupled from widgets: it receives key data
/// and a [TextEditingController], applies edits through the controller, and
/// delegates file/undo actions to callbacks so the editor page keeps its
/// existing save and unsaved-changes flows.
class VimEngine extends ChangeNotifier {
  VimEngine({
    required this.onUndo,
    required this.onWrite,
    required this.onQuit,
    required this.onWriteQuit,
    required this.onMessage,
  });

  final VoidCallback onUndo;
  final VoidCallback onWrite;
  final void Function(bool force) onQuit;
  final VoidCallback onWriteQuit;
  final ValueChanged<String> onMessage;

  VimMode _mode = VimMode.normal;
  VimMode get mode => _mode;

  String register = '';
  bool registerIsLinewise = false;
  String? pendingOperator;

  void setMode(VimMode value) {
    if (_mode == value) {
      return;
    }
    _mode = value;
    notifyListeners();
  }

  /// Returns to normal mode and clears transient state.
  void reset() {
    register = '';
    registerIsLinewise = false;
    pendingOperator = null;
    setMode(VimMode.normal);
  }

  /// Leaves command mode without executing anything.
  void cancelCommand() {
    pendingOperator = null;
    setMode(VimMode.normal);
  }

  /// Entry point used by the editor: extracts modifiers from the platform
  /// keyboard state and forwards to [handleKey].
  KeyEventResult handleKeyEvent(KeyEvent event, TextEditingController controller) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    return handleKey(
      event.logicalKey,
      controller,
      shiftPressed: HardwareKeyboard.instance.isShiftPressed,
      character: event.character,
    );
  }

  /// Handles one key press. Returns [KeyEventResult.handled] when the key was
  /// consumed so the text field never sees it.
  KeyEventResult handleKey(
    LogicalKeyboardKey key,
    TextEditingController controller, {
    required bool shiftPressed,
    String? character,
  }) {
    switch (_mode) {
      case VimMode.command:
        // The command bar owns the keyboard while it is open.
        return KeyEventResult.ignored;
      case VimMode.insert:
        return _handleInsertKey(key, controller);
      case VimMode.normal:
        return _handleNormalKey(
          key,
          controller,
          shiftPressed: shiftPressed,
          character: character,
        );
    }
  }

  KeyEventResult _handleInsertKey(
    LogicalKeyboardKey key,
    TextEditingController controller,
  ) {
    if (key != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    final composing = controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      // Let the IME finish its composition first.
      return KeyEventResult.ignored;
    }
    _exitInsertMode(controller);
    return KeyEventResult.handled;
  }

  void _exitInsertMode(TextEditingController controller) {
    final text = controller.text;
    final offset = controller.selection.extentOffset.clamp(0, text.length);
    final (lineStart, _) = lineBounds(text, offset);
    final newOffset = offset > lineStart ? offset - 1 : offset;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    setMode(VimMode.normal);
  }

  KeyEventResult _handleNormalKey(
    LogicalKeyboardKey key,
    TextEditingController controller, {
    required bool shiftPressed,
    String? character,
  }) {
    if (key == LogicalKeyboardKey.escape) {
      pendingOperator = null;
      return KeyEventResult.handled;
    }

    final hasModifier =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (hasModifier) {
      // Application shortcuts (Ctrl+S, Ctrl+F, …) pass through untouched.
      return KeyEventResult.ignored;
    }

    final text = controller.text;
    final offset = controller.selection.extentOffset.clamp(0, text.length);
    final (lineStart, lineEnd) = lineBounds(text, offset);

    // Character-driven keys that have no stable logical key across layouts.
    if (character == ':' ||
        key == LogicalKeyboardKey.colon ||
        (key == LogicalKeyboardKey.semicolon && shiftPressed)) {
      pendingOperator = null;
      setMode(VimMode.command);
      return KeyEventResult.handled;
    }
    if (character == r'$' ||
        (key == LogicalKeyboardKey.digit7 && shiftPressed)) {
      controller.selection = TextSelection.collapsed(
        offset: lineEnd > lineStart ? lineEnd - 1 : lineStart,
      );
      return KeyEventResult.handled;
    }

    switch (key) {
      case LogicalKeyboardKey.keyH:
      case LogicalKeyboardKey.backspace:
        _moveHorizontally(controller, text, offset, lineStart, direction: -1);
        return _finishMotion();
      case LogicalKeyboardKey.keyL:
      case LogicalKeyboardKey.space:
        _moveHorizontally(
          controller,
          text,
          offset,
          lineStart,
          direction: 1,
          lineEnd: lineEnd,
        );
        return _finishMotion();
      case LogicalKeyboardKey.keyJ:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _moveVertically(controller, text, offset, 1);
        return _finishMotion();
      case LogicalKeyboardKey.keyK:
        _moveVertically(controller, text, offset, -1);
        return _finishMotion();
      case LogicalKeyboardKey.digit0:
        controller.selection = TextSelection.collapsed(offset: lineStart);
        return _finishMotion();
      case LogicalKeyboardKey.keyX:
        return _deleteCharUnderCursor(controller, text, offset, lineEnd);
      case LogicalKeyboardKey.keyD:
        if (pendingOperator == 'd') {
          pendingOperator = null;
          _deleteLine(controller, text, offset);
        } else {
          pendingOperator = 'd';
          notifyListeners();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyY:
        if (pendingOperator == 'y') {
          pendingOperator = null;
          _yankLine(text, offset);
        } else {
          pendingOperator = 'y';
          notifyListeners();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyP:
        return _pasteAfterCursor(controller, text, offset);
      case LogicalKeyboardKey.keyU:
        pendingOperator = null;
        onUndo();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyI when !shiftPressed:
        pendingOperator = null;
        setMode(VimMode.insert);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyI when shiftPressed:
        pendingOperator = null;
        controller.selection = TextSelection.collapsed(offset: lineStart);
        setMode(VimMode.insert);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyA when !shiftPressed:
        pendingOperator = null;
        controller.selection = TextSelection.collapsed(
          offset: offset < lineEnd ? offset + 1 : offset,
        );
        setMode(VimMode.insert);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyA when shiftPressed:
        pendingOperator = null;
        controller.selection = TextSelection.collapsed(offset: lineEnd);
        setMode(VimMode.insert);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyO when !shiftPressed:
        pendingOperator = null;
        _openLine(
          controller,
          text,
          splitAt: lineEnd,
          cursorOffset: lineEnd + 1,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyO when shiftPressed:
        pendingOperator = null;
        _openLine(
          controller,
          text,
          splitAt: lineStart,
          cursorOffset: lineStart,
        );
        return KeyEventResult.handled;
    }

    // Swallow printable keys so normal-mode presses never edit the text.
    final pressedCharacter = character;
    if (pressedCharacter != null &&
        pressedCharacter.isNotEmpty &&
        pressedCharacter.codeUnitAt(0) >= 0x20) {
      pendingOperator = null;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _finishMotion() {
    if (pendingOperator != null) {
      pendingOperator = null;
      notifyListeners();
    }
    return KeyEventResult.handled;
  }

  void _moveHorizontally(
    TextEditingController controller,
    String text,
    int offset,
    int lineStart, {
    required int direction,
    int? lineEnd,
  }) {
    var target = offset + direction;
    if (direction < 0) {
      target = target < lineStart ? lineStart : target;
    } else {
      final end = lineEnd ?? text.length;
      target = target > end - 1 ? offset : target;
      if (end == lineStart) {
        target = offset; // Empty line: nowhere to go.
      }
    }
    controller.selection = TextSelection.collapsed(
      offset: target.clamp(0, text.length),
    );
  }

  void _moveVertically(
    TextEditingController controller,
    String text,
    int offset,
    int direction,
  ) {
    final (lineStart, lineEnd) = lineBounds(text, offset);
    final column = offset - lineStart;

    int? targetStart;
    int targetEnd;
    if (direction > 0) {
      if (lineEnd >= text.length) {
        return;
      }
      targetStart = lineEnd + 1;
      final nextNewline = text.indexOf('\n', targetStart);
      targetEnd = nextNewline == -1 ? text.length : nextNewline;
    } else {
      if (lineStart == 0) {
        return;
      }
      targetEnd = lineStart - 1;
      final previousNewline =
          targetEnd == 0 ? -1 : text.lastIndexOf('\n', targetEnd - 1);
      targetStart = previousNewline + 1;
    }

    final targetLength = targetEnd - targetStart;
    final targetColumn = targetLength == 0 ? 0 : min(column, targetLength - 1);
    controller.selection = TextSelection.collapsed(
      offset: targetStart + targetColumn,
    );
  }

  KeyEventResult _deleteCharUnderCursor(
    TextEditingController controller,
    String text,
    int offset,
    int lineEnd,
  ) {
    pendingOperator = null;
    if (offset >= lineEnd) {
      return KeyEventResult.handled; // Nothing left on this line.
    }
    register = text[offset];
    registerIsLinewise = false;
    controller.value = TextEditingValue(
      text: text.substring(0, offset) + text.substring(offset + 1),
      selection: TextSelection.collapsed(offset: offset),
    );
    return KeyEventResult.handled;
  }

  void _deleteLine(TextEditingController controller, String text, int offset) {
    final (lineStart, lineEnd) = lineBounds(text, offset);
    final lineText = text.substring(lineStart, lineEnd);
    register = '$lineText\n';
    registerIsLinewise = true;

    final deleteEnd = lineEnd < text.length ? lineEnd + 1 : lineEnd;
    final newText = text.substring(0, lineStart) + text.substring(deleteEnd);
    var newOffset = lineStart.clamp(0, newText.length);
    if (newOffset == newText.length && newText.isNotEmpty) {
      final lastNewline = newText.lastIndexOf('\n');
      newOffset = lastNewline + 1;
    }
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }

  void _yankLine(String text, int offset) {
    final (lineStart, lineEnd) = lineBounds(text, offset);
    register = '${text.substring(lineStart, lineEnd)}\n';
    registerIsLinewise = true;
  }

  KeyEventResult _pasteAfterCursor(
    TextEditingController controller,
    String text,
    int offset,
  ) {
    pendingOperator = null;
    if (register.isEmpty) {
      return KeyEventResult.handled;
    }

    if (registerIsLinewise) {
      final (_, lineEnd) = lineBounds(text, offset);
      String newText;
      int pasteStart;
      if (lineEnd < text.length) {
        pasteStart = lineEnd + 1;
        newText = text.substring(0, pasteStart) + register + text.substring(pasteStart);
      } else if (text.isEmpty) {
        pasteStart = 0;
        newText = register;
      } else {
        // Last line without a trailing line break: join with a single '\n'
        // and drop the register's own trailing break.
        pasteStart = text.length + 1;
        final line = register.endsWith('\n')
            ? register.substring(0, register.length - 1)
            : register;
        newText = '$text\n$line';
      }
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: pasteStart.clamp(0, newText.length),
        ),
      );
      return KeyEventResult.handled;
    }

    final (lineStart, lineEnd) = lineBounds(text, offset);
    final insertAt = lineEnd > offset ? offset + 1 : offset;
    final newText = text.substring(0, insertAt) + register + text.substring(insertAt);
    final newOffset = (insertAt + register.length - 1).clamp(0, newText.length);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    return KeyEventResult.handled;
  }

  void _openLine(
    TextEditingController controller,
    String text, {
    required int splitAt,
    required int cursorOffset,
  }) {
    final newText =
        '${text.substring(0, splitAt)}\n${text.substring(splitAt)}';
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: cursorOffset.clamp(0, newText.length),
      ),
    );
    setMode(VimMode.insert);
  }

  /// Executes a submitted command-line input such as `w`, `q` or `wq`.
  void executeCommand(String input) {
    final command = input.trim();
    final body = command.startsWith(':') ? command.substring(1).trim() : command;
    pendingOperator = null;
    switch (body) {
      case 'w':
        onWrite();
      case 'q':
        onQuit(false);
      case 'q!':
        onQuit(true);
      case 'wq':
        onWriteQuit();
      default:
        onMessage(body.isEmpty ? '未输入命令' : '不支持的命令：:$body');
    }
    setMode(VimMode.normal);
  }

  /// Returns the start and end offset (exclusive) of the line containing
  /// [offset]; the end never includes the line break.
  static (int, int) lineBounds(String text, int offset) {
    final clamped = offset.clamp(0, text.length);
    final searchFrom = clamped - 1;
    final previousNewline = searchFrom >= 0
        ? text.lastIndexOf('\n', searchFrom)
        : -1;
    final start = previousNewline + 1;
    var end = text.indexOf('\n', clamped);
    if (end == -1) {
      end = text.length;
    }
    return (start, end);
  }
}
