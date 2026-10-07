import 'dart:io';

/// Where UltraWhisper keeps what it downloads.
///
/// Built from `$HOME` rather than path_provider on purpose: the settings and
/// setup windows are separate Flutter engines with no plugins registered, and
/// they need these paths too. The app is not sandboxed, so `$HOME` is the real
/// home directory.
class AppPaths {
  AppPaths._();

  static String get home => Platform.environment['HOME'] ?? '/tmp';

  /// `~/Library/Application Support/UltraWhisper`
  static String get supportDir => '$home/Library/Application Support/UltraWhisper';

  /// Whisper models chosen in setup or Settings.
  static String get modelsDir => '$supportDir/models';

  /// The app's private Ollama, when the user has none of their own.
  static String get runtimeDir => '$supportDir/runtime';

  /// Models pulled into the private Ollama. Kept apart from `~/.ollama` so
  /// removing UltraWhisper's folder removes everything it downloaded.
  static String get ollamaModelsDir => '$supportDir/ollama-models';
}
