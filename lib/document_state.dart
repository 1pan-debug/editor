import 'package:flutter/foundation.dart';

class DocumentState extends ChangeNotifier {
  String _text = '';
  String? _path;
  String _savedText = '';

  String get text => _text;
  String? get path => _path;
  bool get isDirty => _text != _savedText;

  void updateText(String text) {
    if (_text == text) {
      return;
    }

    _text = text;
    notifyListeners();
  }

  void markSaved({String? path}) {
    _path = path ?? _path;
    _savedText = _text;
    notifyListeners();
  }

  void replaceDocument({required String text, String? path}) {
    _text = text;
    _path = path;
    _savedText = text;
    notifyListeners();
  }
}
