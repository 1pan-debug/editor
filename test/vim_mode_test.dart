import 'package:editor/vim_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Callbacks {
  int undoCalls = 0;
  int writeCalls = 0;
  int writeQuitCalls = 0;
  final List<bool> quitCalls = [];
  final List<String> messages = [];

  VimEngine buildEngine() {
    return VimEngine(
      onUndo: () => undoCalls++,
      onWrite: () => writeCalls++,
      onQuit: (force) => quitCalls.add(force),
      onWriteQuit: () => writeQuitCalls++,
      onMessage: messages.add,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VimEngine modes', () {
    test('starts in normal mode and i enters insert', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'abc')
        ..selection = const TextSelection.collapsed(offset: 0);

      expect(engine.mode, VimMode.normal);
      engine.handleKey(LogicalKeyboardKey.keyI, controller, shiftPressed: false);

      expect(engine.mode, VimMode.insert);
      expect(controller.text, 'abc');
      expect(controller.selection.extentOffset, 0);
    });

    test('a enters insert after the cursor', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'abc')
        ..selection = const TextSelection.collapsed(offset: 0);

      engine.handleKey(LogicalKeyboardKey.keyA, controller, shiftPressed: false);

      expect(engine.mode, VimMode.insert);
      expect(controller.selection.extentOffset, 1);
    });

    test('I and A move to line start and line end', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: '  ab\ncd')
        ..selection = const TextSelection.collapsed(offset: 1);

      engine.handleKey(LogicalKeyboardKey.keyI, controller, shiftPressed: true);
      expect(controller.selection.extentOffset, 0);
      expect(engine.mode, VimMode.insert);

      engine.setMode(VimMode.normal);
      engine.handleKey(LogicalKeyboardKey.keyA, controller, shiftPressed: true);
      expect(controller.selection.extentOffset, 4);
      expect(engine.mode, VimMode.insert);
    });

    test('escape returns to normal mode and moves the cursor left', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'abc')
        ..selection = const TextSelection.collapsed(offset: 2);
      engine.setMode(VimMode.insert);

      final result = engine.handleKey(
        LogicalKeyboardKey.escape,
        controller,
        shiftPressed: false,
      );

      expect(result, KeyEventResult.handled);
      expect(engine.mode, VimMode.normal);
      expect(controller.selection.extentOffset, 1);
    });

    test('escape during IME composition is ignored', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 1, end: 3),
        ),
      );
      engine.setMode(VimMode.insert);

      final result = engine.handleKey(
        LogicalKeyboardKey.escape,
        controller,
        shiftPressed: false,
      );

      expect(result, KeyEventResult.ignored);
      expect(engine.mode, VimMode.insert);
    });

    test('colon enters command mode', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'abc');

      engine.handleKey(
        LogicalKeyboardKey.colon,
        controller,
        shiftPressed: false,
      );

      expect(engine.mode, VimMode.command);
    });

    test('cancelCommand returns to normal mode', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'abc');
      engine.handleKey(
        LogicalKeyboardKey.colon,
        controller,
        shiftPressed: false,
      );

      engine.cancelCommand();

      expect(engine.mode, VimMode.normal);
    });
  });

  group('VimEngine movement', () {
    test('h and l clamp to line boundaries without wrapping', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'ab\nc')
        ..selection = const TextSelection.collapsed(offset: 0);

      engine.handleKey(LogicalKeyboardKey.keyH, controller, shiftPressed: false);
      expect(controller.selection.extentOffset, 0);

      controller.selection = const TextSelection.collapsed(offset: 1);
      engine.handleKey(LogicalKeyboardKey.keyL, controller, shiftPressed: false);
      expect(controller.selection.extentOffset, 1);

      engine.handleKey(LogicalKeyboardKey.keyH, controller, shiftPressed: false);
      expect(controller.selection.extentOffset, 0);
    });

    test('j and k keep the column and clamp to shorter lines', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'ab\nc\nxyz')
        ..selection = const TextSelection.collapsed(offset: 1);

      engine.handleKey(LogicalKeyboardKey.keyJ, controller, shiftPressed: false);
      expect(controller.selection.extentOffset, 3); // Line 'c', column 0.

      engine.handleKey(LogicalKeyboardKey.keyJ, controller, shiftPressed: false);
      expect(controller.selection.extentOffset, 5); // Line 'xyz', column 0.

      engine.handleKey(LogicalKeyboardKey.keyK, controller, shiftPressed: false);
      expect(controller.selection.extentOffset, 3);

      engine.handleKey(LogicalKeyboardKey.keyK, controller, shiftPressed: false);
      expect(controller.selection.extentOffset, 0);
    });

    test('j on the last line does not move', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'ab\nc')
        ..selection = const TextSelection.collapsed(offset: 3);

      engine.handleKey(LogicalKeyboardKey.keyJ, controller, shiftPressed: false);
      expect(controller.selection.extentOffset, 3);
    });

    test('k on the first line does not move', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'ab\nc')
        ..selection = const TextSelection.collapsed(offset: 1);

      engine.handleKey(LogicalKeyboardKey.keyK, controller, shiftPressed: false);
      expect(controller.selection.extentOffset, 1);
    });

    test('0 and dollar move to line start and last character', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: '  ab\ncd')
        ..selection = const TextSelection.collapsed(offset: 3);

      engine.handleKey(LogicalKeyboardKey.digit0, controller, shiftPressed: false);
      expect(controller.selection.extentOffset, 0);

      engine.handleKey(
        LogicalKeyboardKey.digit7,
        controller,
        shiftPressed: true,
        character: r'$',
      );
      expect(controller.selection.extentOffset, 3);
    });

    test('enter behaves like j in normal mode', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'ab\ncd')
        ..selection = const TextSelection.collapsed(offset: 1);

      engine.handleKey(
        LogicalKeyboardKey.enter,
        controller,
        shiftPressed: false,
      );

      expect(controller.selection.extentOffset, 4);
      expect(controller.text, 'ab\ncd');
    });
  });

  group('VimEngine modifications', () {
    test('x deletes the character under the cursor and fills the register', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'abc')
        ..selection = const TextSelection.collapsed(offset: 1);

      engine.handleKey(LogicalKeyboardKey.keyX, controller, shiftPressed: false);

      expect(controller.text, 'ac');
      expect(controller.selection.extentOffset, 1);
      expect(engine.register, 'b');
      expect(engine.registerIsLinewise, isFalse);
    });

    test('x does nothing on an empty line', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'ab\n')
        ..selection = const TextSelection.collapsed(offset: 3);

      engine.handleKey(LogicalKeyboardKey.keyX, controller, shiftPressed: false);

      expect(controller.text, 'ab\n');
    });

    test('dd deletes the current line into the register', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'one\ntwo\nthree')
        ..selection = const TextSelection.collapsed(offset: 6);

      engine.handleKey(LogicalKeyboardKey.keyD, controller, shiftPressed: false);
      engine.handleKey(LogicalKeyboardKey.keyD, controller, shiftPressed: false);

      expect(controller.text, 'one\nthree');
      expect(controller.selection.extentOffset, 4);
      expect(engine.register, 'two\n');
      expect(engine.registerIsLinewise, isTrue);
    });

    test('dd requires two presses and other keys clear the pending state', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'one\ntwo')
        ..selection = const TextSelection.collapsed(offset: 0);

      engine.handleKey(LogicalKeyboardKey.keyD, controller, shiftPressed: false);
      expect(engine.pendingOperator, 'd');
      expect(controller.text, 'one\ntwo');

      engine.handleKey(LogicalKeyboardKey.keyH, controller, shiftPressed: false);
      expect(engine.pendingOperator, isNull);
      expect(controller.text, 'one\ntwo');
    });

    test('yy yanks the line without changing text and p pastes below', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'one\ntwo')
        ..selection = const TextSelection.collapsed(offset: 0);

      engine.handleKey(LogicalKeyboardKey.keyY, controller, shiftPressed: false);
      engine.handleKey(LogicalKeyboardKey.keyY, controller, shiftPressed: false);
      expect(controller.text, 'one\ntwo');
      expect(engine.register, 'one\n');
      expect(engine.registerIsLinewise, isTrue);

      engine.handleKey(LogicalKeyboardKey.keyP, controller, shiftPressed: false);
      expect(controller.text, 'one\none\ntwo');
      expect(controller.selection.extentOffset, 4);
    });

    test('linewise paste on the last line adds the line below', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'one\ntwo')
        ..selection = const TextSelection.collapsed(offset: 4);
      engine.register = 'two\n';
      engine.registerIsLinewise = true;

      engine.handleKey(LogicalKeyboardKey.keyP, controller, shiftPressed: false);

      expect(controller.text, 'one\ntwo\ntwo');
      expect(controller.selection.extentOffset, 8);
    });

    test('charwise paste inserts after the cursor', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'abc')
        ..selection = const TextSelection.collapsed(offset: 0);
      engine.register = 'a';
      engine.registerIsLinewise = false;

      engine.handleKey(LogicalKeyboardKey.keyP, controller, shiftPressed: false);

      expect(controller.text, 'aabc');
      expect(controller.selection.extentOffset, 1);
    });

    test('p with an empty register does nothing', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'abc')
        ..selection = const TextSelection.collapsed(offset: 0);

      engine.handleKey(LogicalKeyboardKey.keyP, controller, shiftPressed: false);

      expect(controller.text, 'abc');
    });

    test('o opens a line below and O opens a line above', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'ab\ncd')
        ..selection = const TextSelection.collapsed(offset: 0);

      engine.handleKey(LogicalKeyboardKey.keyO, controller, shiftPressed: false);
      expect(controller.text, 'ab\n\ncd');
      expect(controller.selection.extentOffset, 3);
      expect(engine.mode, VimMode.insert);

      engine.reset();
      engine.handleKey(LogicalKeyboardKey.keyO, controller, shiftPressed: true);
      expect(controller.text, 'ab\n\n\ncd');
      expect(controller.selection.extentOffset, 3);
      expect(engine.mode, VimMode.insert);
    });

    test('u delegates to the editor undo history', () {
      final callbacks = _Callbacks();
      final engine = callbacks.buildEngine();
      final controller = TextEditingController(text: 'abc');

      engine.handleKey(LogicalKeyboardKey.keyU, controller, shiftPressed: false);

      expect(callbacks.undoCalls, 1);
    });
  });

  group('VimEngine normal-mode key swallowing', () {
    test('unknown printable keys do not edit the text', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'abc')
        ..selection = const TextSelection.collapsed(offset: 0);

      final result = engine.handleKey(
        LogicalKeyboardKey.keyQ,
        controller,
        shiftPressed: false,
        character: 'q',
      );

      expect(result, KeyEventResult.handled);
      expect(controller.text, 'abc');
    });

    test('non-printable keys pass through to the editor', () {
      final engine = _Callbacks().buildEngine();
      final controller = TextEditingController(text: 'abc');

      final result = engine.handleKey(
        LogicalKeyboardKey.arrowDown,
        controller,
        shiftPressed: false,
      );

      expect(result, KeyEventResult.ignored);
    });
  });

  group('VimEngine command line', () {
    test('w, q and wq route to their callbacks', () {
      final callbacks = _Callbacks();
      final engine = callbacks.buildEngine();

      engine.executeCommand('w');
      expect(callbacks.writeCalls, 1);

      engine.executeCommand(':q');
      expect(callbacks.quitCalls, [false]);
      expect(engine.mode, VimMode.normal);

      engine.executeCommand('wq');
      expect(callbacks.writeQuitCalls, 1);
    });

    test('q! requests a forced close', () {
      final callbacks = _Callbacks();
      final engine = callbacks.buildEngine();

      engine.executeCommand('q!');

      expect(callbacks.quitCalls, [true]);
    });

    test('unknown commands produce a message', () {
      final callbacks = _Callbacks();
      final engine = callbacks.buildEngine();

      engine.executeCommand('wqa');

      expect(callbacks.messages, ['不支持的命令：:wqa']);
    });

    test('empty commands produce a message', () {
      final callbacks = _Callbacks();
      final engine = callbacks.buildEngine();

      engine.executeCommand('  ');

      expect(callbacks.messages, ['未输入命令']);
    });
  });
}
