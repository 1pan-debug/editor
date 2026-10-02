import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'find_controller.dart';

/// Document find bar shown below the toolbar while a search is active.
class FindBar extends StatefulWidget {
  const FindBar({super.key, required this.controller, required this.onClose});

  final FindController controller;
  final VoidCallback onClose;

  @override
  State<FindBar> createState() => FindBarState();

  static const Key queryFieldKey = Key('find_query_field');
}

class FindBarState extends State<FindBar> {
  late final TextEditingController _queryController;
  late final FocusNode _queryFocusNode;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.controller.query);
    _queryFocusNode = FocusNode(debugLabel: 'find_query_field');
  }

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  /// Moves focus back to the query input, e.g. when Ctrl+F is pressed again.
  void focusQueryField() {
    _queryFocusNode.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isShiftPressed) {
      widget.controller.findPrevious();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Focus(
              onKeyEvent: _handleKey,
              child: TextField(
                key: FindBar.queryFieldKey,
                controller: _queryController,
                focusNode: _queryFocusNode,
                autofocus: true,
                maxLines: 1,
                textInputAction: TextInputAction.search,
                onChanged: _handleQueryChanged,
                onSubmitted: (_) {
                  widget.controller.findNext();
                  _queryFocusNode.requestFocus();
                },
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '查找内容',
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) => Text(
                widget.controller.statusText ?? '',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _buildCaseToggle(colors),
          _buildNavigationButton(
            tooltip: '查找上一个 (Shift+Enter)',
            icon: Icons.keyboard_arrow_up_rounded,
            onPressed: widget.controller.findPrevious,
          ),
          _buildNavigationButton(
            tooltip: '查找下一个 (Enter)',
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: widget.controller.findNext,
          ),
          IconButton(
            tooltip: '关闭查找 (Esc)',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  void _handleQueryChanged(String value) {
    widget.controller.startQuery(value, anchor: _anchorForQueryChange());
  }

  int _anchorForQueryChange() {
    final match = widget.controller.currentMatch;
    return match?.start ?? 0;
  }

  Widget _buildCaseToggle(ColorScheme colors) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => IconButton(
        tooltip: '区分大小写',
        isSelected: widget.controller.caseSensitive,
        onPressed: () => widget.controller.setCaseSensitive(
          !widget.controller.caseSensitive,
        ),
        icon: Text(
          'Aa',
          style: TextStyle(
            fontSize: 15,
            fontWeight: widget.controller.caseSensitive
                ? FontWeight.w700
                : FontWeight.w500,
            color: widget.controller.caseSensitive
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => IconButton(
        tooltip: tooltip,
        onPressed: widget.controller.matches.isEmpty ? null : onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
