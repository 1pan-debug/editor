import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'document_state.dart';

class OpenedDocument {
  const OpenedDocument({
    required this.text,
    required this.lineEnding,
    required this.hasUtf8Bom,
  });

  final String text;
  final DocumentLineEnding lineEnding;
  final bool hasUtf8Bom;
}

abstract interface class DocumentFileService {
  Future<String?> pickFileToOpen();

  Future<String?> pickFileToSave(String suggestedName);

  Future<OpenedDocument> readDocument(String path);

  Future<void> writeDocument({
    required String path,
    required String text,
    required DocumentLineEnding lineEnding,
    required bool hasUtf8Bom,
  });
}

class LocalDocumentFileService implements DocumentFileService {
  static const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];

  @override
  Future<String?> pickFileToOpen() async {
    final file = await openFile();
    return file?.path;
  }

  @override
  Future<String?> pickFileToSave(String suggestedName) async {
    final location = await getSaveLocation(suggestedName: suggestedName);
    return location?.path;
  }

  @override
  Future<OpenedDocument> readDocument(String path) async {
    final bytes = await File(path).readAsBytes();
    final hasUtf8Bom =
        bytes.length >= _utf8Bom.length &&
        bytes[0] == _utf8Bom[0] &&
        bytes[1] == _utf8Bom[1] &&
        bytes[2] == _utf8Bom[2];
    final contentBytes = hasUtf8Bom ? bytes.sublist(_utf8Bom.length) : bytes;
    final decodedText = utf8.decode(contentBytes);
    final lineEnding = _detectLineEnding(decodedText);
    final text = decodedText.replaceAll(RegExp(r'\r\n|\r|\n'), '\n');

    return OpenedDocument(
      text: text,
      lineEnding: lineEnding,
      hasUtf8Bom: hasUtf8Bom,
    );
  }

  @override
  Future<void> writeDocument({
    required String path,
    required String text,
    required DocumentLineEnding lineEnding,
    required bool hasUtf8Bom,
  }) async {
    final fileText = text.replaceAll('\n', lineEnding.value);
    final content = utf8.encode(fileText);
    final bytes = hasUtf8Bom ? [..._utf8Bom, ...content] : content;
    final target = File(path);
    final temporaryFile = File(
      '$path.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporaryFile.writeAsBytes(bytes, flush: true);
      await temporaryFile.rename(target.path);
    } on FileSystemException {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      rethrow;
    }
  }

  DocumentLineEnding _detectLineEnding(String text) {
    final match = RegExp(r'\r\n|\r|\n').firstMatch(text);
    return switch (match?.group(0)) {
      '\r\n' => DocumentLineEnding.crlf,
      '\r' => DocumentLineEnding.cr,
      '\n' => DocumentLineEnding.lf,
      _ => DocumentLineEnding.lf,
    };
  }
}
