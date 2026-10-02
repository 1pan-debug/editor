import 'package:editor/find_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FindController', () {
    test('empty query reports no status and no matches', () {
      final controller = FindController()
        ..updateText('one two one', anchor: 0)
        ..startQuery('', anchor: 0);

      expect(controller.matches, isEmpty);
      expect(controller.currentMatch, isNull);
      expect(controller.statusText, isNull);
    });

    test('finds multiple matches with 1-based status', () {
      final controller = FindController()
        ..updateText('one two one', anchor: 0)
        ..startQuery('one', anchor: 0);

      expect(controller.matches, hasLength(2));
      expect(controller.currentMatch!.start, 0);
      expect(controller.currentMatch!.end, 3);
      expect(controller.statusText, '1/2');

      controller.findNext();
      expect(controller.currentMatch!.start, 8);
      expect(controller.statusText, '2/2');
    });

    test('find next wraps around at the last match', () {
      final controller = FindController()
        ..updateText('a a a', anchor: 0)
        ..startQuery('a', anchor: 0);

      controller.findNext();
      controller.findNext();
      expect(controller.currentMatch!.start, 4);
      expect(controller.statusText, '3/3');

      controller.findNext();
      expect(controller.currentMatch!.start, 0);
      expect(controller.statusText, '1/3');
    });

    test('find previous wraps around before the first match', () {
      final controller = FindController()
        ..updateText('a a', anchor: 0)
        ..startQuery('a', anchor: 0);

      controller.findPrevious();
      expect(controller.currentMatch!.start, 2);
      expect(controller.statusText, '2/2');

      controller.findPrevious();
      expect(controller.currentMatch!.start, 0);
      expect(controller.statusText, '1/2');
    });

    test('reports no match for a query that is absent', () {
      final controller = FindController()
        ..updateText('hello world', anchor: 0)
        ..startQuery('missing', anchor: 0);

      expect(controller.matches, isEmpty);
      expect(controller.statusText, '无匹配');
      expect(controller.currentMatch, isNull);
    });

    test('navigation is a no-op without matches', () {
      final controller = FindController()
        ..updateText('text', anchor: 0)
        ..startQuery('zzz', anchor: 0);

      controller.findNext();
      controller.findPrevious();
      expect(controller.currentMatch, isNull);
    });

    test('case insensitive matches by default and toggles', () {
      final controller = FindController()
        ..updateText('Code code CODE', anchor: 0)
        ..startQuery('code', anchor: 0);

      expect(controller.matches, hasLength(3));
      expect(controller.caseSensitive, isFalse);

      controller.setCaseSensitive(true);
      expect(controller.caseSensitive, isTrue);
      expect(controller.matches, hasLength(1));
      expect(controller.currentMatch!.start, 5);
      expect(controller.statusText, '1/1');

      controller.setCaseSensitive(false);
      expect(controller.matches, hasLength(3));
    });

    test('finds matches anywhere in the text', () {
      final controller = FindController()
        ..updateText('int print integer', anchor: 0)
        ..startQuery('int', anchor: 0);

      // Plain substring search matches everywhere "int" appears.
      expect(controller.matches.map((m) => m.start), [0, 6, 10]);
    });

    test('treats regex metacharacters in the query literally', () {
      final controller = FindController()
        ..updateText('a.c abc a+c', anchor: 0)
        ..startQuery('a.c', anchor: 0);

      expect(controller.matches, hasLength(1));
      expect(controller.currentMatch!.start, 0);
    });

    test('starts at the first match at or after the anchor', () {
      final controller = FindController()
        ..updateText('a b a b a', anchor: 0)
        ..startQuery('a', anchor: 3);

      expect(controller.currentMatch!.start, 4);
      expect(controller.statusText, '2/3');
    });

    test('text updates keep the match nearest to the current one', () {
      final controller = FindController()
        ..updateText('one two one three', anchor: 0)
        ..startQuery('one', anchor: 0);

      controller.findNext();
      expect(controller.currentMatch!.start, 8);

      controller.updateText('one two one two one three', anchor: 0);
      expect(controller.matches, hasLength(3));
      // The nearest match to start=8 stays selected.
      expect(controller.currentMatch!.start, 8);
      expect(controller.statusText, '2/3');
    });

    test('empty text yields no matches', () {
      final controller = FindController()
        ..updateText('', anchor: 0)
        ..startQuery('a', anchor: 0);

      expect(controller.matches, isEmpty);
      expect(controller.statusText, '无匹配');
    });

    test('query longer than the text yields no matches', () {
      final controller = FindController()
        ..updateText('ab', anchor: 0)
        ..startQuery('abc', anchor: 0);

      expect(controller.matches, isEmpty);
    });

    test('finds matches quickly in a large document', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 5000; i++) {
        buffer
          ..writeln('def function_$i(value):  # needle $i')
          ..writeln('    return value + $i')
          ..writeln();
      }
      final text = buffer.toString();

      final controller = FindController();
      final stopwatch = Stopwatch()..start();
      controller.updateText(text, anchor: 0);
      controller.startQuery('needle', anchor: 0);
      stopwatch.stop();

      expect(controller.matches, hasLength(5000));
      expect(controller.statusText, '1/5000');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));

      final navigationWatch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        controller.findNext();
      }
      navigationWatch.stop();
      expect(controller.currentMatch!.start, greaterThan(0));
      expect(navigationWatch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });
}
