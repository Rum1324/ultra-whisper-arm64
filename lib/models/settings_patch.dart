import 'dart:convert';

import 'settings.dart';

/// Settings edited in the Settings window, merged with changes made elsewhere.
///
/// The Settings window is a separate engine holding its own copy, saved with
/// Save. Sending that whole copy back overwrote anything that changed after
/// the window opened: a menu bar toggle, a newly seen output device. So the
/// window sends only the fields the user changed, and the main engine applies
/// them to its current settings.

/// Top-level JSON fields of [edited] that differ from [base].
Map<String, dynamic> settingsPatch(Settings base, Settings edited) {
  final before = _json(base);
  final after = _json(edited);
  return {
    for (final key in after.keys)
      if (jsonEncode(after[key]) != jsonEncode(before[key])) key: after[key],
  };
}

/// [current] with [patch]'s fields replaced.
Settings applySettingsPatch(Settings current, Map<String, dynamic> patch) =>
    Settings.fromJson({..._json(current), ...patch});

/// The user's unsaved edits ([edited], made against [base]) moved onto
/// [latest]: fields the user touched keep their edit, the rest follow
/// [latest].
Settings rebaseSettings({
  required Settings base,
  required Settings edited,
  required Settings latest,
}) =>
    applySettingsPatch(latest, settingsPatch(base, edited));

/// Plain JSON, so nested values compare by content and decode the same way
/// whether they came from `toJson` or over a platform channel.
Map<String, dynamic> _json(Settings settings) =>
    jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>;
