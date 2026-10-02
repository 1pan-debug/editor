import 'dart:io';

import 'package:editor/document_file_service.dart';
import 'package:editor/document_state.dart';
import 'package:editor/editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edits text and supports undo and redo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(fileService: _FakeDocumentFileService())),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('未保存'), findsOneWidget);

    await tester.tap(find.byTooltip('撤销'));
    await tester.pump();
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

  testWidgets('opens a document and displays its path and content', (
    tester,
  ) async {
    final fileService = _FakeDocumentFileService()
      ..openSelection = r'C:\notes\sample.txt'
      ..documents[r'C:\notes\sample.txt'] = const OpenedDocument(
        text: 'loaded text',
        lineEnding: DocumentLineEnding.crlf,
        hasUtf8Bom: true,
      );
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(fileService: fileService)),
    );

    await tester.tap(find.byTooltip('打开文件 (Ctrl+O)'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'loaded text',
    );
    expect(find.text('sample.txt'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
  });

  testWidgets('canceling unsaved confirmation preserves the current document', (
    tester,
  ) async {
    final fileService = _FakeDocumentFileService()
      ..openSelection = 'replacement.txt'
      ..documents['replacement.txt'] = const OpenedDocument(
        text: 'replacement',
        lineEnding: DocumentLineEnding.lf,
        hasUtf8Bom: false,
      );
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(fileService: fileService)),
    );
    await tester.enterText(find.byType(TextField), 'keep this');
    await tester.pump();

    await tester.tap(find.byTooltip('打开文件 (Ctrl+O)'));
    await tester.pumpAndSettle();
    expect(find.text('有未保存的修改'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'keep this',
    );
    expect(find.text('未命名文档'), findsOneWidget);
  });

  testWidgets('can save before replacing a dirty document', (tester) async {
    final fileService = _FakeDocumentFileService()
      ..saveSelection = r'C:\notes\kept.txt';
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(fileService: fileService)),
    );
    await tester.enterText(find.byType(TextField), 'keep this');
    await tester.pump();

    await tester.tap(find.byTooltip('新建文档 (Ctrl+N)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(fileService.writtenDocuments.keys, contains(r'C:\notes\kept.txt'));
    expect(
      fileService.writtenDocuments[r'C:\notes\kept.txt']!.text,
      'keep this',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('未命名文档'), findsOneWidget);
  });

  testWidgets('saving a new document sets its path and future dirty state', (
    tester,
  ) async {
    final fileService = _FakeDocumentFileService()..saveSelection = 'new.txt';
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(fileService: fileService)),
    );
    await tester.enterText(find.byType(TextField), 'first version');
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('new.txt'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
    expect(fileService.writtenDocuments['new.txt']!.text, 'first version');

    await tester.enterText(find.byType(TextField), 'second version');
    await tester.pump();
    expect(find.text('未保存'), findsOneWidget);
  });

  testWidgets('opening a file read failure preserves the current document', (
    tester,
  ) async {
    final fileService = _FakeDocumentFileService()
      ..openSelection = 'missing.txt'
      ..readFailure = FileSystemException('File not found', 'missing.txt');
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(fileService: fileService)),
    );
    await tester.enterText(find.byType(TextField), 'unsaved text');
    await tester.pump();

    await tester.tap(find.byTooltip('打开文件 (Ctrl+O)'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'unsaved text',
    );
    expect(find.text('未保存'), findsOneWidget);
    expect(find.textContaining('文件读写失败'), findsOneWidget);
    expect(find.text('有未保存的修改'), findsNothing);
  });

  testWidgets('canceling save as leaves the document dirty and unnamed', (
    tester,
  ) async {
    final fileService = _FakeDocumentFileService();
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(fileService: fileService)),
    );
    await tester.enterText(find.byType(TextField), 'draft');
    await tester.pump();

    await tester.tap(find.byTooltip('保存 (Ctrl+S)'));
    await tester.pumpAndSettle();

    expect(fileService.lastSuggestedName, 'untitled.txt');
    expect(find.text('未命名文档'), findsOneWidget);
    expect(find.text('未保存'), findsOneWidget);
    expect(fileService.writtenDocuments, isEmpty);
  });

  testWidgets('a failed save keeps the path and dirty state', (tester) async {
    final fileService = _FakeDocumentFileService()
      ..openSelection = 'existing.txt'
      ..documents['existing.txt'] = const OpenedDocument(
        text: 'original',
        lineEnding: DocumentLineEnding.lf,
        hasUtf8Bom: false,
      )
      ..writeFailure = FileSystemException('Access denied', 'existing.txt');
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(fileService: fileService)),
    );
    await tester.tap(find.byTooltip('打开文件 (Ctrl+O)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'edited');
    await tester.pump();

    await tester.tap(find.byTooltip('保存 (Ctrl+S)'));
    await tester.pumpAndSettle();

    expect(find.text('existing.txt'), findsOneWidget);
    expect(find.text('未保存'), findsOneWidget);
    expect(find.textContaining('文件读写失败'), findsOneWidget);
  });

  testWidgets('save as writes a second copy without changing the source', (
    tester,
  ) async {
    final fileService = _FakeDocumentFileService()
      ..openSelection = 'source.txt'
      ..saveSelection = 'copy.txt'
      ..documents['source.txt'] = const OpenedDocument(
        text: 'source',
        lineEnding: DocumentLineEnding.crlf,
        hasUtf8Bom: true,
      );
    await tester.pumpWidget(
      MaterialApp(home: EditorPage(fileService: fileService)),
    );
    await tester.tap(find.byTooltip('打开文件 (Ctrl+O)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'copy');
    await tester.pump();

    await tester.tap(find.byTooltip('更多文件操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('另存为…'));
    await tester.pumpAndSettle();

    expect(fileService.lastSuggestedName, 'source.txt');
    expect(fileService.writtenDocuments['copy.txt']!.text, 'copy');
    expect(
      fileService.writtenDocuments['copy.txt']!.lineEnding,
      DocumentLineEnding.crlf,
    );
    expect(fileService.writtenDocuments['copy.txt']!.hasUtf8Bom, isTrue);
    expect(find.text('copy.txt'), findsOneWidget);
    expect(find.text('已保存'), findsOneWidget);
  });
}

class _FakeDocumentFileService implements DocumentFileService {
  String? openSelection;
  String? saveSelection;
  String? lastSuggestedName;
  Exception? readFailure;
  Exception? writeFailure;
  final Map<String, OpenedDocument> documents = {};
  final Map<String, OpenedDocument> writtenDocuments = {};

  @override
  Future<String?> pickFileToOpen() async => openSelection;

  @override
  Future<String?> pickFileToSave(String suggestedName) async {
    lastSuggestedName = suggestedName;
    return saveSelection;
  }

  @override
  Future<OpenedDocument> readDocument(String path) async {
    if (readFailure case final error?) {
      throw error;
    }
    final document = documents[path];
    if (document == null) {
      throw FileSystemException('File not found', path);
    }
    return document;
  }

  @override
  Future<void> writeDocument({
    required String path,
    required String text,
    required DocumentLineEnding lineEnding,
    required bool hasUtf8Bom,
  }) async {
    if (writeFailure case final error?) {
      throw error;
    }
    writtenDocuments[path] = OpenedDocument(
      text: text,
      lineEnding: lineEnding,
      hasUtf8Bom: hasUtf8Bom,
    );
  }
}
