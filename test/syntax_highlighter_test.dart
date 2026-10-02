import 'package:editor/syntax_highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle? styleOfSpanContaining(List<TextSpan> spans, String needle) {
  for (final span in spans) {
    if ((span.text ?? '').contains(needle)) {
      return span.style;
    }
  }
  return null;
}

const SyntaxColors colors = SyntaxColors();

void main() {
  group('detectLanguageFromPath', () {
    test('detects C++ files by extension', () {
      expect(detectLanguageFromPath(r'C:\src\main.cpp'), CodeLanguage.cpp);
      expect(detectLanguageFromPath('/usr/include/lib.hpp'), CodeLanguage.cpp);
      expect(detectLanguageFromPath('notes.c'), CodeLanguage.cpp);
      expect(detectLanguageFromPath('lib.H'), CodeLanguage.cpp);
    });

    test('detects Python files by extension', () {
      expect(detectLanguageFromPath(r'D:\work\app.py'), CodeLanguage.python);
      expect(detectLanguageFromPath('/home/user/tool.pyw'), CodeLanguage.python);
    });

    test('falls back to plain text for unknown or missing extensions', () {
      expect(detectLanguageFromPath('README.md'), CodeLanguage.plain);
      expect(detectLanguageFromPath('untitled'), CodeLanguage.plain);
      expect(detectLanguageFromPath(null), CodeLanguage.plain);
      expect(detectLanguageFromPath(''), CodeLanguage.plain);
    });

    test('ignores directories when matching the extension', () {
      expect(detectLanguageFromPath(r'D:\py.data\file.txt'), CodeLanguage.plain);
    });
  });

  group('C++ highlighting', () {
    const highlighter = SyntaxHighlighter();

    test('styles keywords, types, numbers and preprocessor', () {
      const text = '#include <iostream>\nint x = 42;\nif (x > 3) return 0;\n';
      final spans = highlighter.buildSpans(text, CodeLanguage.cpp);

      expect(styleOfSpanContaining(spans, '#include')!.color, colors.preprocessor);
      expect(styleOfSpanContaining(spans, 'int')!.color, colors.type);
      expect(styleOfSpanContaining(spans, '42')!.color, colors.number);
      expect(styleOfSpanContaining(spans, 'if')!.color, colors.keyword);
      expect(styleOfSpanContaining(spans, 'return')!.color, colors.keyword);
      expect(styleOfSpanContaining(spans, 'iostream'), isNull);
      expect(styleOfSpanContaining(spans, '(x > 3)'), isNull);
    });

    test('styles line and multi-line comments as single spans', () {
      const text = '// line\nint a;\n/* block\nstill block */ int b;\n';
      final spans = highlighter.buildSpans(text, CodeLanguage.cpp);

      final lineComment = spans.singleWhere((s) => s.text == '// line');
      expect(lineComment.style!.color, colors.comment);

      final block = spans
          .singleWhere((s) => (s.text ?? '').contains('still block'));
      expect(block.style!.color, colors.comment);
      expect(block.text, contains('/* block'));
      expect(block.text, contains('*/'));

      // Keywords inside the comment are not styled separately.
      expect(spans.where((s) => s.text == 'block'), isEmpty);
    });

    test('styles strings with escapes and does not style keywords inside', () {
      const text = 'const char* s = "a\\"b\\n if";\n';
      final spans = highlighter.buildSpans(text, CodeLanguage.cpp);

      final stringSpan = spans.singleWhere((s) => (s.text ?? '').startsWith('"'));
      expect(stringSpan.style!.color, colors.string);
      expect(stringSpan.text, '"a\\"b\\n if"');
      expect(spans.where((s) => s.text == 'if'), isEmpty);
    });

    test('unterminated string ends at the line break', () {
      const text = 'char* s = "oops\nint next;\n';
      final spans = highlighter.buildSpans(text, CodeLanguage.cpp);

      final stringSpan = spans.singleWhere(
        (s) => s.style?.color == colors.string,
      );
      expect(stringSpan.text, '"oops');
    });

    test('does not treat digits inside identifiers as numbers', () {
      const text = 'int x1 = 1;\n';
      final spans = highlighter.buildSpans(text, CodeLanguage.cpp);

      expect(styleOfSpanContaining(spans, 'x1'), isNull);
      final numberSpan = spans.firstWhere((s) => s.text == '1');
      expect(numberSpan.style!.color, colors.number);
    });
  });

  group('Python highlighting', () {
    const highlighter = SyntaxHighlighter();

    test('styles keywords, decorators and numbers', () {
      const text = '@decorator\ndef main(n):\n    if n > 0x2A and True:\n'
          '        return None\n';
      final spans = highlighter.buildSpans(text, CodeLanguage.python);

      expect(styleOfSpanContaining(spans, '@decorator')!.color, colors.decorator);
      expect(styleOfSpanContaining(spans, 'def')!.color, colors.keyword);
      expect(styleOfSpanContaining(spans, 'and')!.color, colors.keyword);
      expect(styleOfSpanContaining(spans, 'True')!.color, colors.keyword);
      expect(styleOfSpanContaining(spans, 'None')!.color, colors.keyword);
      expect(styleOfSpanContaining(spans, '0x2A')!.color, colors.number);
      expect(styleOfSpanContaining(spans, 'main'), isNull);
    });

    test('keeps multi-line strings as one span', () {
      const text = 's = """first\nsecond if\nthird"""\nvalue = 1\n';
      final spans = highlighter.buildSpans(text, CodeLanguage.python);

      final stringSpan = spans.singleWhere(
        (s) => (s.text ?? '').contains('second'),
      );
      expect(stringSpan.style!.color, colors.string);
      expect(stringSpan.text, '"""first\nsecond if\nthird"""');
      // 'if' inside the string is not styled as a keyword.
      expect(spans.where((s) => s.text == 'if'), isEmpty);
    });

    test('supports string prefixes without matching identifiers', () {
      const text = 'a = r"raw"\nb = f"fmt {x}"\noffer = 1\n';
      final spans = highlighter.buildSpans(text, CodeLanguage.python);

      final raw = spans.singleWhere((s) => s.text == 'r"raw"');
      expect(raw.style!.color, colors.string);
      final formatted = spans.singleWhere((s) => s.text == 'f"fmt {x}"');
      expect(formatted.style!.color, colors.string);
      expect(styleOfSpanContaining(spans, 'offer'), isNull);
    });

    test('unterminated triple string extends to end of text', () {
      const text = 's = """never closed\nmore';
      final spans = highlighter.buildSpans(text, CodeLanguage.python);

      final stringSpan = spans.singleWhere(
        (s) => s.style?.color == colors.string,
      );
      expect(stringSpan.text, '"""never closed\nmore');
    });

    test('does not style keywords inside comments', () {
      const text = '# if return class\nvalue = 1\n';
      final spans = highlighter.buildSpans(text, CodeLanguage.python);

      final comment = spans.singleWhere((s) => (s.text ?? '').startsWith('#'));
      expect(comment.style!.color, colors.comment);
      expect(spans.where((s) => s.text == 'if'), isEmpty);
    });
  });

  group('plain text', () {
    test('produces unstyled spans', () {
      const text = 'def if "string" # not code\n';
      final spans = const SyntaxHighlighter().buildSpans(
        text,
        CodeLanguage.plain,
      );

      expect(spans, hasLength(1));
      expect(spans.single.text, text);
      expect(spans.single.style, isNull);
    });
  });

  group('performance', () {
    test('highlights a large document quickly', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 2000; i++) {
        buffer
          ..writeln('def function_$i(value):  # comment $i')
          ..writeln('    text = "value $i"')
          ..writeln('    if value > $i and value != 0:')
          ..writeln('        return value * 2')
          ..writeln();
      }
      final text = buffer.toString();
      expect(text.split('\n'), hasLength(10001));

      final stopwatch = Stopwatch()..start();
      final spans = const SyntaxHighlighter().buildSpans(
        text,
        CodeLanguage.python,
      );
      stopwatch.stop();

      expect(
        spans.any(
          (s) => s.style?.color == colors.keyword && s.text == 'def',
        ),
        isTrue,
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('SyntaxHighlightingController', () {
    testWidgets('highlights after edits and re-caches per text', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(controller: SyntaxHighlightingController()),
          ),
        ),
      );

      final controller = tester.widget<TextField>(
        find.byType(TextField),
      ).controller! as SyntaxHighlightingController;
      controller.language = CodeLanguage.python;

      controller.text = 'def f(): pass';
      final first = controller.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        style: const TextStyle(),
        withComposing: false,
      );
      expect(
        first.children!.whereType<TextSpan>().any((s) => s.text == 'def' && s.style != null),
        isTrue,
      );

      controller.text = 'x = 1  # note';
      final second = controller.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        style: const TextStyle(),
        withComposing: false,
      );
      expect(
        second.children!.whereType<TextSpan>().any(
          (s) => (s.text ?? '').contains('# note') && s.style != null,
        ),
        isTrue,
      );
    });

    testWidgets('plain language keeps composing underline behavior', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(controller: SyntaxHighlightingController()),
          ),
        ),
      );

      final controller = tester.widget<TextField>(
        find.byType(TextField),
      ).controller! as SyntaxHighlightingController;
      controller.text = 'hello';

      final span = controller.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        style: const TextStyle(),
        withComposing: false,
      );
      expect(span.children, isNull);
      expect(span.text, 'hello');
    });
  });
}
