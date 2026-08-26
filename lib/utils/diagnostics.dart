import 'dart:io';

/// Launch-time diagnostic switches, driven by sentinel files in $HOME.
///
/// Sentinel files rather than environment variables: macOS attributes a
/// permission to the *responsible* process, so the app has to be launched by
/// Finder or `open` for any permission test to mean anything, and neither of
/// those passes an environment through.
class Diagnostics {
  static bool _sentinel(String name) {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return false;
      return File('$home/$name').existsSync();
    } catch (_) {
      // A diagnostic that cannot read its own switch must not take the app down.
      return false;
    }
  }

  /// Measure the Core Audio tap on launch and write the verdict to a file.
  static bool get tapSelfTest =>
      Platform.environment['ULTRAWHISPER_TAP_SELFTEST'] == '1' ||
      _sentinel('.ultrawhisper_tap_selftest');
}
