import 'package:flutter_test/flutter_test.dart';
import 'package:ultrawhisper/models/settings.dart';
import 'package:ultrawhisper/models/settings_patch.dart';

void main() {
  const opened = Settings();

  test('an untouched window patches nothing', () {
    expect(settingsPatch(opened, opened), isEmpty);
  });

  test('the patch holds only what the user changed', () {
    final edited = opened.copyWith(duckVolumeDuringRecording: false);
    expect(settingsPatch(opened, edited), {'duckVolumeDuringRecording': false});
  });

  test('saving a window opened before a menu bar toggle keeps the toggle', () {
    // Settings opens; AI formatting is switched off from the menu bar; the
    // user changes ducking in the window and clicks Save.
    final menuToggled = opened.copyWith(aiFormatting: false);
    final edited = opened.copyWith(duckVolumeDuringRecording: false);

    final saved = applySettingsPatch(menuToggled, settingsPatch(opened, edited));

    expect(saved.aiFormatting, isFalse);
    expect(saved.duckVolumeDuringRecording, isFalse);
  });

  test('a device seen while the window was open survives Save', () {
    const device = AudioDevicePref(
      uid: 'BuiltInSpeakerDevice',
      name: 'MacBook Pro Speakers',
      isBluetooth: false,
      skipDuck: false,
    );
    final mainNow = opened.copyWith(audioDevicePrefs: [device]);
    final edited = opened.copyWith(aiFormatting: false);

    final saved = applySettingsPatch(mainNow, settingsPatch(opened, edited));

    expect(saved.audioDevicePrefs.single.uid, device.uid);
    expect(saved.aiFormatting, isFalse);
  });

  group('rebase onto a pushed change', () {
    test('untouched fields follow the push', () {
      final latest = opened.copyWith(aiFormatting: false);
      final shown = rebaseSettings(base: opened, edited: opened, latest: latest);
      expect(shown.aiFormatting, isFalse);
    });

    test("the user's unsaved edit wins over the push", () {
      final edited = opened.copyWith(aiFormatting: false);
      final latest = opened.copyWith(aiFormatting: true, duckVolumeDuringRecording: false);

      final shown = rebaseSettings(base: opened, edited: edited, latest: latest);

      expect(shown.aiFormatting, isFalse);
      expect(shown.duckVolumeDuringRecording, isFalse);
    });

    test('after a rebase, Save sends only the unsaved edit', () {
      final edited = opened.copyWith(duckVolumeDuringRecording: false);
      final latest = opened.copyWith(aiFormatting: false);

      final shown = rebaseSettings(base: opened, edited: edited, latest: latest);

      expect(settingsPatch(latest, shown), {'duckVolumeDuringRecording': false});
    });
  });
}
