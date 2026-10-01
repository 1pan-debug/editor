import 'package:editor/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edits text and supports undo and redo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('未保存'), findsOneWidget);

    await tester.tap(find.byTooltip('撤销'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('已保存'), findsOneWidget);

    await tester.tap(find.byTooltip('重做'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'hello',
    );
  });

  testWidgets('shows the current line and column', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.enterText(find.byType(TextField), 'one\ntwo');
    await tester.pump();

    expect(find.text('行 2，列 4'), findsOneWidget);
  });

  testWidgets('protects dirty content before starting a new document', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.enterText(find.byType(TextField), 'keep me');
    await tester.pump();

    await tester.tap(find.byTooltip('新建文档 (Ctrl+N)'));
    await tester.pumpAndSettle();
    expect(find.text('有未保存的修改'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'keep me',
    );

    await tester.tap(find.byTooltip('新建文档 (Ctrl+N)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('已保存'), findsOneWidget);
    final undoButton = find.ancestor(
      of: find.byTooltip('撤销'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(undoButton).onPressed, isNull);
  });

  testWidgets('save choice keeps edits when file saving is not available yet', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EditorPage()));
    await tester.enterText(find.byType(TextField), 'keep me');
    await tester.pump();

    await tester.tap(find.byTooltip('新建文档 (Ctrl+N)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'keep me',
    );
    expect(find.textContaining('文件保存功能将在阶段 2 实现'), findsOneWidget);
  });
}
