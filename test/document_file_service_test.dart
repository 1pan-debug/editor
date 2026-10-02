import 'dart:convert';
import 'dart:io';

import 'package:editor/document_file_service.dart';
import 'package:editor/document_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDirectory;
  late LocalDocumentFileService service;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('editor-files-');
    service = LocalDocumentFileService();
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test(
    'reads UTF-8, preserves BOM and normalizes detected CRLF endings',
    () async {
      final file = File(
        '${tempDirectory.path}${Platform.pathSeparator}source.txt',
      );
      await file.writeAsBytes([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('第一行\r\n第二行\r\n'),
      ]);

      final document = await service.readDocument(file.path);

      expect(document.text, '第一行\n第二行\n');
      expect(document.lineEnding, DocumentLineEnding.crlf);
      expect(document.hasUtf8Bom, isTrue);
    },
  );

  test(
    'uses the first line ending when normalizing mixed line endings',
    () async {
      final file = File(
        '${tempDirectory.path}${Platform.pathSeparator}mixed.txt',
      );
      await file.writeAsString('one\r\ntwo\nthree\r', encoding: utf8);

      final document = await service.readDocument(file.path);

      expect(document.text, 'one\ntwo\nthree\n');
      expect(document.lineEnding, DocumentLineEnding.crlf);
    },
  );

  test('saves with the original newline format and UTF-8 BOM', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}saved.txt',
    );

    await service.writeDocument(
      path: file.path,
      text: '第一行\n第二行',
      lineEnding: DocumentLineEnding.crlf,
      hasUtf8Bom: true,
    );

    expect(await file.readAsBytes(), [
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('第一行\r\n第二行'),
    ]);
  });

  test('reads an empty file as an empty UTF-8 document', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}empty.txt',
    );
    await file.create();

    final document = await service.readDocument(file.path);

    expect(document.text, isEmpty);
    expect(document.lineEnding, DocumentLineEnding.lf);
    expect(document.hasUtf8Bom, isFalse);
  });

  test('rejects invalid UTF-8 instead of replacing invalid bytes', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}invalid.txt',
    );
    await file.writeAsBytes([0xFF, 0xFE]);

    await expectLater(service.readDocument(file.path), throwsFormatException);
  });

  test('reports a missing file', () async {
    final path = '${tempDirectory.path}${Platform.pathSeparator}missing.txt';

    await expectLater(
      service.readDocument(path),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('reports a write failure when the destination directory is missing', () async {
    final path =
        '${tempDirectory.path}${Platform.pathSeparator}missing${Platform.pathSeparator}file.txt';

    await expectLater(
      service.writeDocument(
        path: path,
        text: 'content',
        lineEnding: DocumentLineEnding.lf,
        hasUtf8Bom: false,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('replaces an existing file when saving', () async {
    final file = File(
      '${tempDirectory.path}${Platform.pathSeparator}existing.txt',
    );
    await file.writeAsString('old contents');

    await service.writeDocument(
      path: file.path,
      text: 'new contents',
      lineEnding: DocumentLineEnding.lf,
      hasUtf8Bom: false,
    );

    expect(await file.readAsString(), 'new contents');
  });
}
