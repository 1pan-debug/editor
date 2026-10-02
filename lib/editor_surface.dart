import 'package:flutter/material.dart';

class EditorSurface extends StatelessWidget {
  const EditorSurface({
    super.key,
    required this.controller,
    required this.undoController,
    required this.scrollController,
  });

  final TextEditingController controller;
  final UndoHistoryController undoController;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scrollbar(
      controller: scrollController,
      thumbVisibility: true,
      child: TextField(
        controller: controller,
        scrollController: scrollController,
        undoController: undoController,
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
    );
  }
}
