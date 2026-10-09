import 'package:flutter/services.dart';

import '../utils/logger.dart';

/// The user's own Anthropic API key, kept in the macOS Keychain by
/// `KeychainHandler.swift` — never in the settings JSON, a log, or the bundle.
///
/// Only the main engine has the native channel. The settings window asks over
/// `DesktopMultiWindow.invokeMethod(0, …)` and gets back whether a key is
/// saved, never the key itself.
class AnthropicKeyStore {
  static const _channel = MethodChannel('com.ultrawhisper.keychain');

  // Read once per launch, then held in memory, so a dictation does not pay a
  // Keychain round trip. Dropped whenever the key is saved or removed.
  String? _cached;
  bool _loaded = false;

  Future<String?> read() async {
    if (_loaded) return _cached;
    try {
      _cached = await _channel.invokeMethod<String>('getAnthropicKey');
    } catch (e) {
      AppLogger.error('Keychain read failed: ${e.runtimeType}');
      _cached = null;
    }
    _loaded = true;
    return _cached;
  }

  Future<bool> hasKey() async => (await read())?.isNotEmpty ?? false;

  Future<bool> save(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setAnthropicKey', trimmed) ?? false;
      _forget();
      return ok;
    } catch (e) {
      AppLogger.error('Keychain write failed: ${e.runtimeType}');
      return false;
    }
  }

  Future<bool> delete() async {
    try {
      final ok = await _channel.invokeMethod<bool>('deleteAnthropicKey') ?? false;
      _forget();
      return ok;
    } catch (e) {
      AppLogger.error('Keychain delete failed: ${e.runtimeType}');
      return false;
    }
  }

  void _forget() {
    _cached = null;
    _loaded = false;
  }
}
