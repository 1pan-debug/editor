import 'package:editor/document_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocumentState', () {
    test('tracks edits against the saved content', () {
      final document = DocumentState();
      addTearDown(document.dispose);

      document.updateText('hello');
      expect(document.text, 'hello');
      expect(document.isDirty, isTrue);

      document.markSaved(path: r'C:\notes.txt');
      expect(document.path, r'C:\notes.txt');
      expect(document.isDirty, isFalse);

      document.updateText('hello!');
      expect(document.isDirty, isTrue);
    });

    test('tracks file format and saved snapshots independently', () {
      final document = DocumentState();
      addTearDown(document.dispose);

      document.replaceDocument(
        text: 'saved',
        path: 'notes.txt',
        lineEnding: DocumentLineEnding.crlf,
        hasUtf8Bom: true,
      );
      document.updateText('edited');
      document.markSaved(path: 'copy.txt', savedText: 'saved');

      expect(document.path, 'copy.txt');
      expect(document.lineEnding, DocumentLineEnding.crlf);
      expect(document.hasUtf8Bom, isTrue);
      expect(document.isDirty, isTrue);
    });

    test('replacing a document resets its path and dirty state', () {
      final document = DocumentState();
      addTearDown(document.dispose);
      document
        ..replaceDocument(text: 'old', path: 'old.txt')
        ..updateText('changed')
        ..replaceDocument(text: 'new');

      expect(document.text, 'new');
      expect(document.path, isNull);
      expect(document.isDirty, isFalse);
    });

    test('notifies only when content changes', () {
      final document = DocumentState();
      addTearDown(document.dispose);
      var notifications = 0;
      document.addListener(() => notifications++);

      document
        ..updateText('')
        ..updateText('one')
        ..updateText('one');

      expect(notifications, 1);
    });
  });
}
