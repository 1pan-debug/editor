import 'dart:io' show FileSystemException;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'document_state.dart';
import 'document_file_service.dart';
import 'editor_surface.dart';
import 'find_bar.dart';
import 'find_controller.dart';
import 'syntax_highlighter.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.fileService});

  final DocumentFileService? fileService;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

enum _UnsavedAction { save, discard, cancel }

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  late final DocumentFileService _fileService =
      widget.fileService ?? LocalDocumentFileService();
  final DocumentState _document = DocumentState();
  final SyntaxHighlightingController _textController =
      SyntaxHighlightingController();
  final ScrollController _editorScrollController = ScrollController();
  UndoHistoryController _undoController = UndoHistoryController();
  final FocusNode _editorFocusNode = FocusNode(debugLabel: 'editor_field');
  final FindController _findController = FindController();
  bool _isFindBarVisible = false;
  int _editorGeneration = 0;
  int _line = 1;
  int _column = 1;
  bool _isFileOperationInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController.addListener(_handleEditingChanged);
    _findController.addListener(_syncFindSelection);
    _findController.updateText('');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController
      ..removeListener(_handleEditingChanged)
      ..dispose();
    _editorFocusNode.dispose();
    _findController
      ..removeListener(_syncFindSelection)
      ..dispose();
    _editorScrollController.dispose();
    _undoController.dispose();
    _document.dispose();
    super.dispose();
  }

  void _handleEditingChanged() {
    _document.updateText(_textController.text);
    _findController.updateText(_textController.text);
    _updateCursorPosition();
  }

  int _appliedFindActionVersion = 0;

  /// Moves the editor selection to the current find match after an explicit
  /// find action. Text updates only refresh the match list so the user's own
  /// cursor and selection are never hijacked while typing.
  void _syncFindSelection() {
    if (_findController.actionVersion == _appliedFindActionVersion) {
      return;
    }
    _appliedFindActionVersion = _findController.actionVersion;

    final match = _findController.currentMatch;
    if (match == null || !mounted) {
      return;
    }

    _textController.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
    _scrollToOffset(match.start);
    _updateCursorPosition();
  }

  static const double _editorFontSize = 14;
  static const double _editorLineHeightFactor = 1.6;

  void _scrollToOffset(int offset) {
    if (!_editorScrollController.hasClients) {
      return;
    }

    final text = _textController.text;
    final clampedOffset = offset.clamp(0, text.length);
    var lineIndex = 0;
    for (var i = 0; i < clampedOffset; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        lineIndex++;
      }
    }

    final lineExtent = _editorFontSize * _editorLineHeightFactor;
    final targetTop = lineIndex * lineExtent;
    final currentOffset = _editorScrollController.offset;
    final viewportExtent = _editorScrollController.position.viewportDimension;
    final margin = lineExtent * 2;

    double? target;
    if (targetTop - currentOffset < margin) {
      target = targetTop - margin;
    } else if (currentOffset + viewportExtent - (targetTop + lineExtent) <
        margin) {
      target = targetTop + lineExtent + margin - viewportExtent;
    }
    if (target == null) {
      return;
    }

    _editorScrollController.jumpTo(
      target.clamp(0.0, _editorScrollController.position.maxScrollExtent),
    );
  }

  void _updateCursorPosition() {
    final selection = _textController.selection;
    if (!selection.isValid) {
      return;
    }

    final offset = selection.extentOffset.clamp(0, _textController.text.length);
    final beforeCursor = _textController.text.substring(0, offset);
    final lines = beforeCursor.split('\n');
    final line = lines.length;
    final column = lines.last.length + 1;
    if (line == _line && column == _column) {
      return;
    }

    setState(() {
      _line = line;
      _column = column;
    });
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_document.isDirty) {
      return true;
    }

    final action = await showDialog<_UnsavedAction>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('有未保存的修改'),
        content: const Text('此文档的修改尚未保存。要如何处理？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _UnsavedAction.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _UnsavedAction.discard),
            child: const Text('放弃修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _UnsavedAction.save),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    switch (action) {
      case _UnsavedAction.discard:
        return true;
      case _UnsavedAction.save:
        final saved = _isFileOperationInProgress
            ? await _saveDocument()
            : await _runFileOperation(_saveDocument);
        return saved && !_document.isDirty;
      case _UnsavedAction.cancel:
      case null:
        return false;
    }
  }

  Future<void> _createDocument() async {
    if (_isFileOperationInProgress ||
        !await _confirmDiscardChanges() ||
        !mounted) {
      return;
    }

    _replaceDocument(
      const OpenedDocument(
        text: '',
        lineEnding: DocumentLineEnding.lf,
        hasUtf8Bom: false,
      ),
    );
  }

  void _replaceDocument(OpenedDocument opened, {String? path}) {
    _undoController.dispose();
    _textController.language = detectLanguageFromPath(path);
    _document.replaceDocument(
      text: opened.text,
      path: path,
      lineEnding: opened.lineEnding,
      hasUtf8Bom: opened.hasUtf8Bom,
    );
    _textController.value = TextEditingValue(
      text: opened.text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _findController.updateText(opened.text, anchor: 0);
    setState(() {
      _undoController = UndoHistoryController();
      _editorGeneration++;
      _line = 1;
      _column = 1;
    });
  }

  final GlobalKey<FindBarState> _findBarKey = GlobalKey<FindBarState>();

  void _openFind() {
    if (!mounted) {
      return;
    }
    final selection = _textController.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final selected = selection.textInside(_textController.text);
      if (selected.isNotEmpty && !selected.contains('\n')) {
        _findController.startQuery(selected, anchor: selection.start);
      }
    }
    setState(() => _isFindBarVisible = true);
    _findBarKey.currentState?.focusQueryField();
  }

  void _closeFind() {
    if (!mounted) {
      return;
    }
    setState(() => _isFindBarVisible = false);
    _editorFocusNode.requestFocus();
  }

  Future<bool> _runFileOperation(Future<bool> Function() operation) async {
    if (_isFileOperationInProgress || !mounted) {
      return false;
    }

    setState(() => _isFileOperationInProgress = true);
    try {
      return await operation();
    } on Exception catch (error) {
      if (mounted) {
        _showFileError(error);
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isFileOperationInProgress = false);
      }
    }
  }

  Future<bool> _openDocument() async {
    final path = await _fileService.pickFileToOpen();
    if (path == null) {
      return false;
    }

    final opened = await _fileService.readDocument(path);
    if (!await _confirmDiscardChanges() || !mounted) {
      return false;
    }

    _replaceDocument(opened, path: path);
    return true;
  }

  Future<bool> _saveDocument() async {
    final path =
        _document.path ?? await _fileService.pickFileToSave(_suggestedFileName);
    if (path == null) {
      return false;
    }

    final text = _document.text;
    final lineEnding = _document.lineEnding;
    final hasUtf8Bom = _document.hasUtf8Bom;
    await _fileService.writeDocument(
      path: path,
      text: text,
      lineEnding: lineEnding,
      hasUtf8Bom: hasUtf8Bom,
    );

    if (!mounted) {
      return false;
    }

    _document.markSaved(
      path: path,
      savedText: text,
      lineEnding: lineEnding,
      hasUtf8Bom: hasUtf8Bom,
    );
    _showMessage('已保存到 $path');
    return true;
  }

  Future<bool> _saveAsDocument() async {
    final path = await _fileService.pickFileToSave(_suggestedFileName);
    if (path == null) {
      return false;
    }

    final text = _document.text;
    final lineEnding = _document.lineEnding;
    final hasUtf8Bom = _document.hasUtf8Bom;
    await _fileService.writeDocument(
      path: path,
      text: text,
      lineEnding: lineEnding,
      hasUtf8Bom: hasUtf8Bom,
    );

    if (!mounted) {
      return false;
    }

    _document.markSaved(
      path: path,
      savedText: text,
      lineEnding: lineEnding,
      hasUtf8Bom: hasUtf8Bom,
    );
    _showMessage('已另存为 $path');
    return true;
  }

  String get _suggestedFileName {
    final path = _document.path;
    if (path == null || path.isEmpty) {
      return 'untitled.txt';
    }
    return path.split(RegExp(r'[/\\]')).last;
  }

  void _showFileError(Exception error) {
    final message = switch (error) {
      FormatException() => '文件不是有效的 UTF-8 文本，未打开以避免内容损坏。',
      FileSystemException() => '文件读写失败：${error.toString()}',
      PlatformException() => '文件操作失败：${error.message ?? error.code}',
      _ => '文件操作失败：$error',
    };
    _showMessage(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final canExit = await _confirmDiscardChanges();
    return canExit ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _CreateDocumentIntent(),
        SingleActivator(LogicalKeyboardKey.keyO, control: true):
            _OpenDocumentIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _SaveDocumentIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _FindIntent(),
        SingleActivator(LogicalKeyboardKey.f3): _FindNextIntent(),
        SingleActivator(LogicalKeyboardKey.f3, shift: true):
            _FindPreviousIntent(),
      },
      child: Actions(
        actions: {
          _CreateDocumentIntent: CallbackAction<_CreateDocumentIntent>(
            onInvoke: (_) {
              _createDocument();
              return null;
            },
          ),
          _OpenDocumentIntent: CallbackAction<_OpenDocumentIntent>(
            onInvoke: (_) {
              _runFileOperation(_openDocument);
              return null;
            },
          ),
          _SaveDocumentIntent: CallbackAction<_SaveDocumentIntent>(
            onInvoke: (_) {
              _runFileOperation(_saveDocument);
              return null;
            },
          ),
          _FindIntent: CallbackAction<_FindIntent>(
            onInvoke: (_) {
              _openFind();
              return null;
            },
          ),
          _FindNextIntent: CallbackAction<_FindNextIntent>(
            onInvoke: (_) {
              _findController.findNext();
              return null;
            },
          ),
          _FindPreviousIntent: CallbackAction<_FindPreviousIntent>(
            onInvoke: (_) {
              _findController.findPrevious();
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: colors.surfaceContainerLowest,
          appBar: AppBar(
            titleSpacing: 24,
            title: AnimatedBuilder(
              animation: _document,
              builder: (context, _) => Row(
                children: [
                  Text(
                    _document.path == null
                        ? '未命名文档'
                        : _document.path!.split(RegExp(r'[/\\]')).last,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_document.isDirty) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.circle, size: 8, color: colors.primary),
                  ],
                ],
              ),
            ),
            actions: [
              IconButton(
                tooltip: '打开文件 (Ctrl+O)',
                onPressed: _isFileOperationInProgress
                    ? null
                    : () => _runFileOperation(_openDocument),
                icon: const Icon(Icons.folder_open_outlined),
              ),
              IconButton(
                tooltip: '保存 (Ctrl+S)',
                onPressed: _isFileOperationInProgress
                    ? null
                    : () => _runFileOperation(_saveDocument),
                icon: const Icon(Icons.save_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: '更多文件操作',
                enabled: !_isFileOperationInProgress,
                onSelected: (value) {
                  if (value == 'saveAs') {
                    _runFileOperation(_saveAsDocument);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'saveAs',
                    child: ListTile(
                      leading: Icon(Icons.drive_file_rename_outline),
                      title: Text('另存为…'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: '新建文档 (Ctrl+N)',
                onPressed: _isFileOperationInProgress ? null : _createDocument,
                icon: const Icon(Icons.note_add_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              _buildToolbar(colors),
              if (_isFindBarVisible)
                FindBar(
                  key: _findBarKey,
                  controller: _findController,
                  onClose: _closeFind,
                ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: EditorSurface(
                    key: ValueKey(_editorGeneration),
                    controller: _textController,
                    scrollController: _editorScrollController,
                    undoController: _undoController,
                    focusNode: _editorFocusNode,
                  ),
                ),
              ),
              _buildStatusBar(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(ColorScheme colors) {
    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: _undoController,
            builder: (context, value, _) => IconButton(
              tooltip: '撤销',
              onPressed: value.canUndo ? _undoController.undo : null,
              icon: const Icon(Icons.undo_rounded),
            ),
          ),
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: _undoController,
            builder: (context, value, _) => IconButton(
              tooltip: '重做',
              onPressed: value.canRedo ? _undoController.redo : null,
              icon: const Icon(Icons.redo_rounded),
            ),
          ),
          const VerticalDivider(indent: 12, endIndent: 12, width: 24),
          IconButton(
            tooltip: '全选',
            onPressed: () {
              _textController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _textController.text.length,
              );
            },
            icon: const Icon(Icons.select_all_rounded),
          ),
          IconButton(
            tooltip: '查找 (Ctrl+F)',
            onPressed: _openFind,
            icon: const Icon(Icons.search_rounded),
          ),
          const Spacer(),
          PopupMenuButton<CodeLanguage>(
            tooltip: '选择语言模式',
            initialValue: _textController.language,
            onSelected: (language) {
              setState(() => _textController.language = language);
            },
            itemBuilder: (context) => [
              for (final language in CodeLanguage.values)
                PopupMenuItem(
                  value: language,
                  child: Text(languageDisplayName(language)),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.code_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, _) => Text(
                      languageDisplayName(_textController.language),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildStatusBar(ColorScheme colors) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Text(
            '行 $_line，列 $_column',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _document,
            builder: (context, _) => Text(
              _document.isDirty ? '未保存' : '已保存',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _document.isDirty
                    ? colors.primary
                    : colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateDocumentIntent extends Intent {
  const _CreateDocumentIntent();
}

class _OpenDocumentIntent extends Intent {
  const _OpenDocumentIntent();
}

class _SaveDocumentIntent extends Intent {
  const _SaveDocumentIntent();
}

class _FindIntent extends Intent {
  const _FindIntent();
}

class _FindNextIntent extends Intent {
  const _FindNextIntent();
}

class _FindPreviousIntent extends Intent {
  const _FindPreviousIntent();
}
