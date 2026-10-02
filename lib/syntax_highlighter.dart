import 'package:flutter/material.dart';

/// Language modes supported by the editor surface.
enum CodeLanguage { plain, cpp, python }

String languageDisplayName(CodeLanguage language) {
  return switch (language) {
    CodeLanguage.plain => '纯文本',
    CodeLanguage.cpp => 'C++',
    CodeLanguage.python => 'Python',
  };
}

/// Detects the language from a file extension; unknown files stay plain text.
CodeLanguage detectLanguageFromPath(String? path) {
  if (path == null || path.isEmpty) {
    return CodeLanguage.plain;
  }
  final name = path.split(RegExp(r'[/\\]')).last.toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot < 0) {
    return CodeLanguage.plain;
  }
  final extension = name.substring(dot);
  const cppExtensions = {
    '.c', '.cpp', '.cc', '.cxx', '.c++', '.h', '.hh', '.hxx', '.hpp',
    '.ipp', '.tpp', '.inl',
  };
  const pythonExtensions = {'.py', '.pyw'};
  if (cppExtensions.contains(extension)) {
    return CodeLanguage.cpp;
  }
  if (pythonExtensions.contains(extension)) {
    return CodeLanguage.python;
  }
  return CodeLanguage.plain;
}

/// Fixed token colors tuned for the light editor surface. All values use
/// dark 700-800 tones so they stay readable on the light background.
class SyntaxColors {
  const SyntaxColors({
    this.keyword = const Color(0xFF7B1FA2),
    this.type = const Color(0xFF0B57D0),
    this.comment = const Color(0xFF5F6368),
    this.string = const Color(0xFF188038),
    this.number = const Color(0xFFB26A00),
    this.preprocessor = const Color(0xFFC5221F),
    this.decorator = const Color(0xFFC2185B),
  });

  final Color keyword;
  final Color type;
  final Color comment;
  final Color string;
  final Color number;
  final Color preprocessor;
  final Color decorator;
}

/// Turns source text into styled [TextSpan]s with a small regex scanner.
///
/// The scanner tries each rule anchored at the current offset via
/// [RegExp.matchAsPrefix], so rules are ordered by priority: comments and
/// strings first, so keywords inside them are never matched separately.
class SyntaxHighlighter {
  const SyntaxHighlighter({this.colors = const SyntaxColors()});

  final SyntaxColors colors;

  TextStyle _style(Color color, {bool italic = false}) {
    return TextStyle(color: color, fontStyle: italic ? FontStyle.italic : null);
  }

  List<(RegExp, TextStyle)> _rulesFor(CodeLanguage language) {
    switch (language) {
      case CodeLanguage.plain:
        return const [];
      case CodeLanguage.cpp:
        return [
          (
            RegExp(r'/\*[\s\S]*?(?:\*/|$)|//[^\n]*'),
            _style(colors.comment, italic: true),
          ),
          (
            RegExp(
              r'"(?:\\.|[^"\\\n])*(?:"|(?=\n))|'
              r"'(?:\\.|[^'\\\n])*(?:'|(?=\n))",
            ),
            _style(colors.string),
          ),
          (RegExp(r'#[ \t]*[a-zA-Z_]\w*'), _style(colors.preprocessor)),
          (
            RegExp(
              r'\b(?:0[xX][0-9a-fA-F]+|(?:\d+(?:\.\d*)?|\.\d+)'
              r'(?:[eE][+-]?\d+)?)[uUlLfF]*',
            ),
            _style(colors.number),
          ),
          (
            RegExp(
              r'\b(?:alignas|alignof|and|and_eq|asm|auto|break|case|catch|'
              r'co_await|co_return|co_yield|concept|const|consteval|constexpr|'
              r'constinit|const_cast|continue|decltype|default|delete|do|'
              r'dynamic_cast|else|enum|explicit|export|extern|false|for|'
              r'friend|goto|if|inline|mutable|namespace|new|noexcept|not|'
              r'not_eq|nullptr|operator|or|or_eq|private|protected|public|'
              r'register|reinterpret_cast|requires|return|sizeof|static|'
              r'static_assert|static_cast|struct|switch|template|this|'
              r'thread_local|throw|true|try|typedef|typeid|typename|union|'
              r'using|virtual|volatile|while|xor|xor_eq)\b',
            ),
            _style(colors.keyword),
          ),
          (
            RegExp(
              r'\b(?:bool|char|char8_t|char16_t|char32_t|double|float|int|'
              r'long|short|signed|unsigned|void|wchar_t)\b',
            ),
            _style(colors.type),
          ),
        ];
      case CodeLanguage.python:
        return [
          (RegExp(r'#[^\n]*'), _style(colors.comment, italic: true)),
          (
            RegExp(
              r'(?<!\w)[rRbBuUfF]{0,2}(?:"""[\s\S]*?(?:"""|$)|'
              r"'''[\s\S]*?(?:'''|$)|"
              r'"(?:\\.|[^"\\\n])*(?:"|(?=\n))|'
              r"'(?:\\.|[^'\\\n])*(?:'|(?=\n)))",
            ),
            _style(colors.string),
          ),
          (RegExp(r'@[a-zA-Z_][\w.]*'), _style(colors.decorator)),
          (
            RegExp(
              r'\b(?:0[xX][0-9a-fA-F]+|(?:\d+(?:\.\d*)?|\.\d+)'
              r'(?:[eE][+-]?\d+)?)[jJ]?(?![\w.])',
            ),
            _style(colors.number),
          ),
          (
            RegExp(
              r'\b(?:False|None|True|and|as|assert|async|await|break|class|'
              r'continue|def|del|elif|else|except|finally|for|from|global|if|'
              r'import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|'
              r'while|with|yield)\b',
            ),
            _style(colors.keyword),
          ),
        ];
    }
  }

  /// Builds the styled spans for [text]. Plain segments inherit the editor
  /// style; recognized tokens carry their own color.
  List<TextSpan> buildSpans(String text, CodeLanguage language) {
    final rules = _rulesFor(language);
    final spans = <TextSpan>[];
    final plain = StringBuffer();
    var index = 0;
    while (index < text.length) {
      Match? match;
      TextStyle? style;
      for (final (pattern, ruleStyle) in rules) {
        final candidate = pattern.matchAsPrefix(text, index);
        if (candidate != null && candidate.end > index) {
          match = candidate;
          style = ruleStyle;
          break;
        }
      }

      if (match == null) {
        plain.write(text[index]);
        index++;
        continue;
      }

      if (plain.isNotEmpty) {
        spans.add(TextSpan(text: plain.toString()));
        plain.clear();
      }
      spans.add(TextSpan(text: match.group(0), style: style));
      index = match.end;
    }

    if (plain.isNotEmpty) {
      spans.add(TextSpan(text: plain.toString()));
    }
    return spans;
  }
}

/// A [TextEditingController] that renders syntax-highlighted spans.
///
/// The span tree is rebuilt only when the text or language actually changed,
/// so selection and cursor updates reuse the cached result.
class SyntaxHighlightingController extends TextEditingController {
  SyntaxHighlightingController({super.text, this.language = CodeLanguage.plain});

  CodeLanguage language;

  static const SyntaxHighlighter _highlighter = SyntaxHighlighter();

  String? _cachedText;
  CodeLanguage? _cachedLanguage;
  List<TextSpan>? _cachedSpans;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    if (language == CodeLanguage.plain) {
      _cachedSpans = null;
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    if (_cachedSpans == null ||
        _cachedText != text ||
        _cachedLanguage != language) {
      _cachedText = text;
      _cachedLanguage = language;
      _cachedSpans = _highlighter.buildSpans(text, language);
    }

    return TextSpan(
      style: style,
      children: _applyComposing(_cachedSpans!, text, withComposing, style),
    );
  }

  List<TextSpan> _applyComposing(
    List<TextSpan> spans,
    String text,
    bool withComposing,
    TextStyle? style,
  ) {
    if (!withComposing || !value.composing.isValid || value.composing.isCollapsed) {
      return spans;
    }

    final composingStyle = (style ?? const TextStyle()).copyWith(
      decoration: TextDecoration.underline,
    );
    final result = <TextSpan>[];
    var offset = 0;
    for (final span in spans) {
      final spanText = span.text ?? '';
      final start = offset;
      final end = offset + spanText.length;
      offset = end;

      final overlapStart = start.clamp(value.composing.start, value.composing.end);
      final overlapEnd = end.clamp(value.composing.start, value.composing.end);
      if (overlapStart == overlapEnd) {
        result.add(span);
        continue;
      }

      if (overlapStart > start) {
        result.add(TextSpan(text: spanText.substring(0, overlapStart - start)));
      }
      result.add(
        TextSpan(
          text: spanText.substring(
            overlapStart - start,
            overlapEnd - start,
          ),
          style: composingStyle,
        ),
      );
      if (overlapEnd < end) {
        result.add(TextSpan(text: spanText.substring(overlapEnd - start)));
      }
    }
    return result;
  }
}
