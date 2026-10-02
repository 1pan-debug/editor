import 'package:flutter/foundation.dart';

enum DocumentLineEnding {
  lf('\n'),
  crlf('\r\n'),
  cr('\r');

  const DocumentLineEnding(this.value);

  final String value;
}

class DocumentState extends ChangeNotifier {
  String _text = '';
  String? _path;
  String _savedText = '';
  DocumentLineEnding _lineEnding = DocumentLineEnding.lf;
  bool _hasUtf8Bom = false;

  String get text => _text;
  String? get path => _path;
  DocumentLineEnding get lineEnding => _lineEnding;
  bool get hasUtf8Bom => _hasUtf8Bom;
  bool get isDirty => _text != _savedText;

  void updateText(String text) {
    if (_text == text) {
      return;
    }

    _text = text;
    notifyListeners();
  }

  void markSaved({
    String? path,
    String? savedText,
    DocumentLineEnding? lineEnding,
    bool? hasUtf8Bom,
  }) {
    _path = path ?? _path;
    _savedText = savedText ?? _text;
    _lineEnding = lineEnding ?? _lineEnding;
    _hasUtf8Bom = hasUtf8Bom ?? _hasUtf8Bom;
    notifyListeners();
  }

  void replaceDocument({
    required String text,
    String? path,
    DocumentLineEnding lineEnding = DocumentLineEnding.lf,
    bool hasUtf8Bom = false,
  }) {
    _text = text;
    _path = path;
    _savedText = text;
    _lineEnding = lineEnding;
    _hasUtf8Bom = hasUtf8Bom;
    notifyListeners();
  }
}
