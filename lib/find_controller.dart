import 'package:flutter/foundation.dart';

class FindMatch {
  const FindMatch({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is FindMatch && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Computes and tracks find matches for the current document text.
///
/// The controller only owns the query, the case option and the match list;
/// the caller supplies the document text via [updateText] and mirrors the
/// current match into the editor selection.
class FindController extends ChangeNotifier {
  String _text = '';
  String _query = '';
  bool _caseSensitive = false;
  List<FindMatch> _matches = const [];
  int _currentIndex = 0;
  int _actionVersion = 0;

  String get query => _query;
  bool get caseSensitive => _caseSensitive;
  List<FindMatch> get matches => List.unmodifiable(_matches);

  /// Increments on explicit find actions (new query, case toggle, navigation)
  /// but not on passive [updateText] calls, so the editor can tell when the
  /// selection should follow the current match.
  int get actionVersion => _actionVersion;

  FindMatch? get currentMatch =>
      _currentIndex < _matches.length ? _matches[_currentIndex] : null;

  /// Status shown in the find bar: null for an empty query, otherwise the
  /// 1-based position such as `2/5`, or `无匹配` when nothing matched.
  String? get statusText {
    if (_query.isEmpty) {
      return null;
    }
    if (_matches.isEmpty) {
      return '无匹配';
    }
    return '${_currentIndex + 1}/${_matches.length}';
  }

  /// Replaces the document text and recomputes matches, keeping the match
  /// nearest to the previous one (falling back to [anchor]).
  void updateText(String text, {int anchor = 0}) {
    _text = text;
    _recompute(anchor: currentMatch?.start ?? anchor);
    notifyListeners();
  }

  /// Starts a new query, jumping to the first match at/after [anchor].
  void startQuery(String query, {int anchor = 0}) {
    _query = query;
    _actionVersion++;
    _recompute(anchor: anchor);
    notifyListeners();
  }

  void setCaseSensitive(bool value) {
    if (_caseSensitive == value) {
      return;
    }
    _caseSensitive = value;
    _actionVersion++;
    _recompute(anchor: currentMatch?.start ?? 0);
    notifyListeners();
  }

  void findNext() {
    if (_matches.isEmpty) {
      return;
    }
    _actionVersion++;
    _currentIndex = (_currentIndex + 1) % _matches.length;
    notifyListeners();
  }

  void findPrevious() {
    if (_matches.isEmpty) {
      return;
    }
    _actionVersion++;
    _currentIndex =
        (_currentIndex - 1 + _matches.length) % _matches.length;
    notifyListeners();
  }

  void _recompute({required int anchor}) {
    if (_query.isEmpty || _text.isEmpty) {
      _matches = const [];
      _currentIndex = 0;
      return;
    }

    final pattern = RegExp(
      _escapeRegex(_query),
      caseSensitive: _caseSensitive,
    );
    _matches = [
      for (final match in pattern.allMatches(_text))
        if (match.start != match.end)
          FindMatch(start: match.start, end: match.end),
    ];
    _currentIndex = _indexForAnchor(anchor);
  }

  int _indexForAnchor(int anchor) {
    if (_matches.isEmpty) {
      return 0;
    }
    for (var index = 0; index < _matches.length; index++) {
      if (_matches[index].start >= anchor) {
        return index;
      }
    }
    return 0;
  }

  String _escapeRegex(String query) {
    return query.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (match) {
      return '\\${match[0]}';
    });
  }
}
