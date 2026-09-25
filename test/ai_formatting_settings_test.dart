import 'package:flutter_test/flutter_test.dart';
import 'package:ultrawhisper/models/settings.dart';
import 'package:ultrawhisper/models/websocket_messages.dart';

void main() {
  test('settings saved before AI formatting existed turn it on', () {
    // A settings blob from v0.8.x has no aiFormatting key at all.
    final legacy = const Settings().toJson()..remove('aiFormatting');
    expect(Settings.fromJson(legacy).aiFormatting, isTrue);
  });

  test('turning AI formatting off survives a save and reload', () {
    final off = const Settings().copyWith(aiFormatting: false);
    expect(Settings.fromJson(off.toJson()).aiFormatting, isFalse);
  });

  test('the backend receives the flag under post.aiFormatting', () {
    const options = PostProcessingOptions(aiFormatting: true);
    expect(options.toJson()['aiFormatting'], isTrue);
  });

  test('the wire default is off, so an omitted flag never waits on Ollama', () {
    expect(PostProcessingOptions.fromJson(const {}).aiFormatting, isFalse);
  });
}
