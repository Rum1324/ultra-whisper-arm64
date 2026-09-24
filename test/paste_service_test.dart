import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultrawhisper/services/paste_service.dart';

/// The clipboard is the paste mechanism, so what matters is not what it holds
/// during the paste but what it holds once the paste is done — that is the only
/// state the user ever sees.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const keystrokeChannel = MethodChannel('com.glassywhisper.keystroke');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  String? clipboard;
  late List<String> keystrokes;

  setUp(() {
    clipboard = 'something the user copied by hand';
    keystrokes = [];

    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return clipboard == null ? null : {'text': clipboard};
      }
      return null;
    });

    messenger.setMockMethodCallHandler(keystrokeChannel, (call) async {
      switch (call.method) {
        case 'hasAccessibilityPermission':
          return true;
        case 'sendKeystroke':
          keystrokes.add((call.arguments as Map)['keystroke'] as String);
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(keystrokeChannel, null);
  });

  test('the transcript is left on the clipboard by default', () async {
    await PasteService().performPasteAction('hello world');

    expect(keystrokes, ['cmd+v']);
    expect(clipboard, 'hello world');

    // The restore used to be scheduled 500ms out, so a synchronous assertion
    // would have passed even with the bug. Outlast the timer.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(clipboard, 'hello world');
  });

  test('the previous clipboard comes back when keeping is off', () async {
    await PasteService().performPasteAction(
      'hello world',
      keepOnClipboard: false,
    );

    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(clipboard, 'something the user copied by hand');
  });
}
