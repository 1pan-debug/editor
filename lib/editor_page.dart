import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'document_state.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

enum _UnsavedAction { save, discard, cancel }

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  final DocumentState _document = DocumentState();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _editorScrollController = ScrollController();
  UndoHistoryController _undoController = UndoHistoryController();
  int _editorGeneration = 0;
  int _line = 1;
  int _column = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController.addListener(_handleEditingChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController
      ..removeListener(_handleEditingChanged)
      ..dispose();
    _editorScrollController.dispose();
    _undoController.dispose();
    _document.dispose();
    super.dispose();
  }

  void _handleEditingChanged() {
    _document.updateText(_textController.text);
    _updateCursorPosition();
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件保存功能将在阶段 2 实现，当前修改仍保留。')),
          );
        }
        return false;
      case _UnsavedAction.cancel:
      case null:
        return false;
    }
  }

  Future<void> _createDocument() async {
    if (!await _confirmDiscardChanges() || !mounted) {
      return;
    }

    _document.replaceDocument(text: '');
    _textController.clear();
    _undoController.dispose();
    setState(() {
      _undoController = UndoHistoryController();
      _editorGeneration++;
      _line = 1;
      _column = 1;
    });
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
      },
      child: Actions(
        actions: {
          _CreateDocumentIntent: CallbackAction<_CreateDocumentIntent>(
            onInvoke: (_) {
              _createDocument();
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
                tooltip: '新建文档 (Ctrl+N)',
                onPressed: _createDocument,
                icon: const Icon(Icons.note_add_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              _buildToolbar(colors),
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
                  child: Scrollbar(
                    controller: _editorScrollController,
                    thumbVisibility: true,
                    child: TextField(
                      key: ValueKey(_editorGeneration),
                      controller: _textController,
                      scrollController: _editorScrollController,
                      undoController: _undoController,
                      autofocus: true,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        height: 1.6,
                        color: colors.onSurface,
                      ),
                      cursorColor: colors.primary,
                      decoration: const InputDecoration(
                        hintText: '在此输入文本…',
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
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
          const Spacer(),
          Icon(Icons.code_rounded, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '纯文本',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: colors.onSurfaceVariant),
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
