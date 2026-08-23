import 'package:flutter/services.dart';

import '../utils/logger.dart';

/// Bridge to the macOS Core Audio tap layer.
///
/// Supplies the "them" half of a meeting recording — the meeting app's own
/// output, captured per-process — plus the microphone-activity signal used to
/// notice that a call has started or ended.
///
/// Everything here degrades rather than throws. Meeting capture sits on top of
/// a dictation path that already works, and no failure in this file may cost
/// the user that.
class MicActivityService {
  static const MethodChannel _channel =
      MethodChannel('com.ultrawhisper.mic_activity');
  static const MethodChannel _events =
      MethodChannel('com.ultrawhisper.mic_activity_events');

  /// PCM int16, mono, 16 kHz, already converted native-side.
  void Function(Uint8List pcm)? onSystemAudio;

  /// Fired when a capture has produced nothing but digital silence for a while.
  ///
  /// This is the permission signal. macOS does not fail an unauthorized tap; it
  /// returns silence, so this is the only way to tell a denied permission from
  /// a meeting nobody spoke in.
  void Function()? onSystemAudioSilent;

  /// Fired when anything on the system starts or stops using the default input.
  void Function(bool active)? onMicActivityChanged;

  bool _listening = false;

  void startListening() {
    if (_listening) return;
    _listening = true;
    _events.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'systemAudio':
          final data = call.arguments;
          if (data is Uint8List) onSystemAudio?.call(data);
          break;
        case 'systemAudioSilent':
          AppLogger.warning(
            'System audio capture is silent — the System Audio Recording '
            'permission is probably missing.',
          );
          onSystemAudioSilent?.call();
          break;
        case 'micActivityChanged':
          final active = call.arguments;
          if (active is bool) onMicActivityChanged?.call(active);
          break;
      }
      return null;
    });
  }

  /// Surface the System Audio Recording prompt without recording anything.
  ///
  /// Returns false when the tap could not even be created — an old macOS, or a
  /// hard denial. True only means creation succeeded, which is not proof of
  /// authorization; see [onSystemAudioSilent].
  Future<bool> preflightPermission() async {
    try {
      final ok = await _channel.invokeMethod<bool>('preflightAudioPermission');
      AppLogger.debug('Audio tap preflight: ${ok == true ? "created" : "refused"}');
      return ok ?? false;
    } on PlatformException catch (e) {
      AppLogger.warning('Audio tap preflight unavailable: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      AppLogger.warning('Audio tap preflight failed: $e');
      return false;
    }
  }

  /// Capture briefly from whatever is currently playing and report what arrived.
  ///
  /// Exists because tap creation succeeding proves nothing: an unauthorized tap
  /// is created happily and then returns digital silence. The only way to know
  /// the permission actually works is to point it at a process that IS making
  /// noise and look at the samples. Env-gated, so it never runs in normal use.
  Future<String> runSelfTest({
    Duration duration = const Duration(seconds: 5),
    int? onlyPid,
  }) async {
    final processes = await listAudioProcesses();
    if (processes.isEmpty) return 'no audio processes visible';

    var playing = processes.where((p) => p['runningOutput'] == true).toList();
    if (onlyPid != null) {
      // Tapping one known-good process rather than everything that happens to
      // be playing. A mixdown spanning several processes cannot show which of
      // them contributed, and a protected one could plausibly zero the mix.
      playing = processes.where((p) => p['pid'] == onlyPid).toList();
      if (playing.isEmpty) return 'pid $onlyPid is not a known audio process';
    }
    if (playing.isEmpty) {
      return 'nothing is playing audio right now — start some audio and retry';
    }

    var peak = 0;
    var bytes = 0;
    final previous = onSystemAudio;
    onSystemAudio = (pcm) {
      bytes += pcm.length;
      final view = pcm.buffer.asInt16List(pcm.offsetInBytes, pcm.length ~/ 2);
      for (final sample in view) {
        final magnitude = sample.abs();
        if (magnitude > peak) peak = magnitude;
      }
    };

    final names = playing.map((p) => p['name'] ?? p['pid']).join(', ');
    final started = await startSystemCapture(
      playing.map((p) => p['pid'] as int).toList(),
    );
    if (!started) {
      onSystemAudio = previous;
      return 'capture refused for: $names';
    }

    await Future<void>.delayed(duration);
    await stopSystemCapture();
    onSystemAudio = previous;

    if (bytes == 0) return 'tapped $names but no buffers arrived at all';
    final verdict = peak > 32
        ? 'AUDIO PRESENT — permission is working'
        : 'SILENT — created and delivered $bytes bytes of zeroes, '
            'which is what a denied System Audio Recording permission looks like';
    return 'tapped $names: $bytes bytes, peak |sample| = $peak of 32767 → $verdict';
  }

  /// Whether screen-capture access is authorized right now.
  ///
  /// The only trustworthy permission signal for system audio: Core Audio taps
  /// cannot be asked, they just return silence when denied.
  Future<bool> screenCaptureAuthorized() async {
    try {
      return await _channel.invokeMethod<bool>('screenCaptureAuthorized') ?? false;
    } catch (e) {
      AppLogger.warning('screenCaptureAuthorized failed: $e');
      return false;
    }
  }

  /// Trigger the system prompt. The grant only applies from the next launch.
  Future<bool> requestScreenCaptureAccess() async {
    try {
      return await _channel.invokeMethod<bool>('requestScreenCaptureAccess') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Measure whether the ScreenCaptureKit path hears anything, as a control
  /// against the Core Audio tap path returning silence.
  Future<String> measureScreenCaptureKit({double seconds = 5}) async {
    try {
      final r = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'measureScreenCaptureKitAudio',
        {'seconds': seconds},
      );
      if (r == null) return 'no result';
      final peak = (r['peak'] as num?)?.toDouble() ?? 0;
      final bytes = r['bytes'] ?? 0;
      return 'SCK: $bytes bytes, peak=${peak.toStringAsFixed(6)} → '
          '${peak > 0.0001 ? "AUDIO PRESENT" : "silent"}';
    } catch (e) {
      return 'SCK failed: $e';
    }
  }

  /// Every process Core Audio knows about. A process only appears once it has
  /// played audio at least once, so this is worth re-reading rather than caching.
  Future<List<Map<String, dynamic>>> listAudioProcesses() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listAudioProcesses');
      return (raw ?? [])
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (e) {
      AppLogger.warning('Could not list audio processes: $e');
      return const [];
    }
  }

  Future<bool> startSystemCapture(List<int> pids) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('startSystemCapture', {'pids': pids});
      return ok ?? false;
    } catch (e) {
      AppLogger.warning('Could not start system capture: $e');
      return false;
    }
  }

  Future<void> stopSystemCapture() async {
    try {
      await _channel.invokeMethod('stopSystemCapture');
    } catch (e) {
      AppLogger.warning('Could not stop system capture: $e');
    }
  }

  Future<bool> isMicActive() async {
    try {
      return await _channel.invokeMethod<bool>('isMicActive') ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> startMicMonitoring() async {
    try {
      await _channel.invokeMethod('startMicMonitoring');
    } catch (e) {
      AppLogger.warning('Could not monitor mic activity: $e');
    }
  }

  Future<void> stopMicMonitoring() async {
    try {
      await _channel.invokeMethod('stopMicMonitoring');
    } catch (e) {
      AppLogger.warning('Could not stop mic monitoring: $e');
    }
  }
}
