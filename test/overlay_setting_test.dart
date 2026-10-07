import 'package:flutter_test/flutter_test.dart';
import 'package:ultrawhisper/models/settings.dart';

void main() {
  test('the island shows by default, including for settings saved before '
      'the toggle existed', () {
    expect(const Settings().showDictationOverlay, isTrue);
    final old = const Settings().toJson()..remove('showDictationOverlay');
    expect(Settings.fromJson(old).showDictationOverlay, isTrue);
  });

  test('turning the island off survives a save and reload', () {
    final off = const Settings().copyWith(showDictationOverlay: false);
    expect(Settings.fromJson(off.toJson()).showDictationOverlay, isFalse);
  });
}
