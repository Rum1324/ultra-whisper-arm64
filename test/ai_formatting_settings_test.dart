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

  test('the engine defaults to local, also for settings saved before it existed', () {
    expect(const Settings().aiFormattingEngine, AiFormattingEngine.local);
    final legacy = const Settings().toJson()..remove('aiFormattingEngine');
    expect(Settings.fromJson(legacy).aiFormattingEngine, AiFormattingEngine.local);
  });

  test('an engine name a newer build wrote falls back to local', () {
    final future = const Settings().toJson()..['aiFormattingEngine'] = 'someday';
    expect(Settings.fromJson(future).aiFormattingEngine, AiFormattingEngine.local);
  });

  test('choosing Claude survives a save and reload', () {
    final claude = const Settings().copyWith(aiFormattingEngine: AiFormattingEngine.claude);
    expect(Settings.fromJson(claude.toJson()).aiFormattingEngine, AiFormattingEngine.claude);
  });

  test('the API key is never part of the saved settings', () {
    final json = const Settings().copyWith(aiFormattingEngine: AiFormattingEngine.claude).toJson();
    expect(json.keys.where((k) => RegExp('apikey|anthropic', caseSensitive: false).hasMatch(k)), isEmpty);
  });

  test('the backend receives the engine and the key under post', () {
    const options = PostProcessingOptions(
      aiFormatting: true,
      aiFormattingEngine: 'claude',
      anthropicApiKey: 'sk-ant-test',
    );
    expect(options.toJson()['aiFormattingEngine'], 'claude');
    expect(options.toJson()['anthropicApiKey'], 'sk-ant-test');
  });
}
