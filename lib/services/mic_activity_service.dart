import 'dart:io';
import 'dart:typed_data';

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
      playing = processes.where((p) => p['pid'] == onlyPid).toList();
      if (playing.isEmpty) return 'pid $onlyPid is not a known audio process';
    }
    if (playing.isEmpty) {
      return 'nothing is playing audio right now — start some audio and retry';
    }

    // One process at a time, never a mixdown.
    //
    // A mixdown cannot say which process contributed, and
    // `kAudioProcessPropertyIsRunningOutput` is true for anything merely
    // HOLDING an output stream — a live wallpaper, a media helper — not only
    // for something making noise. A combined tap over those reads as a
    // permission denial when the honest answer is that nothing tapped was
    // playing. That misreading cost a round trip on 2026-08-24.
    final candidates = playing.take(onlyPid != null ? 1 : 4).toList();
    final each = onlyPid != null
        ? duration
        : Duration(
            milliseconds: (duration.inMilliseconds ~/ candidates.length)
                .clamp(2000, duration.inMilliseconds),
          );

    final report = <String>[];
    var loudest = 0;
    var totalBytes = 0;

    for (final process in candidates) {
      final name = (process['name'] ?? 'pid ${process['pid']}').toString();
      final chunks = <Uint8List>[];
      final measured = await _measureOne(
        process['pid'] as int,
        each,
        (reason) => report.add('$name: CAPTURE REFUSED — $reason'),
        captured: chunks,
      );
      _writeWav(
        '${Platform.environment['HOME']}/ultrawhisper-tap-$name.wav',
        chunks,
        16000,
      );
      if (measured == null) continue;
      final (peak, bytes) = measured;
      totalBytes += bytes;
      if (peak > loudest) loudest = peak;
      report.add('$name: $bytes bytes, peak $peak'
          '${bytes == 0 ? ' (no buffers)' : peak > 32 ? ' ← AUDIO' : ' (silent)'}');
    }

    if (totalBytes == 0) {
      // Zero buffers is NOT the silence signature — a running tap delivers
      // zeroes, not nothing. It means the capture never started, so the
      // per-process lines below carry the actual reason.
      return 'NO BUFFERS — the capture never ran, which is a different fault '
          'from a denied permission (a denied tap still delivers zeroes). '
          '${report.join('; ')}';
    }
    if (loudest > 32) {
      return 'AUDIO PRESENT — permission is working. ${report.join('; ')}';
    }
    return 'SILENT — every tapped process delivered zeroes. Either the System '
        'Audio Recording permission is denied, or none of these was actually '
        'making sound (IsRunningOutput only means an output stream is open). '
        'Re-run with a pid in ~/.ultrawhisper_tap_selftest to be sure. '
        '${report.join('; ')}';
  }

  /// Tap one process and report `(peak, bytes)`, or the refusal reason.
  Future<(int, int)?> _measureOne(
    int processPid,
    Duration duration,
    void Function(String reason) onRefused, {
    List<Uint8List>? captured,
  }) async {
    var peak = 0;
    var bytes = 0;
    final previous = onSystemAudio;
    onSystemAudio = (pcm) {
      bytes += pcm.lengthInBytes;
      final magnitude = _peakOf(pcm);
      if (magnitude > peak) peak = magnitude;
      captured?.add(pcm);
    };

    final failure = await startSystemCapture([processPid]);
    if (failure != null) {
      onSystemAudio = previous;
      onRefused(failure);
      return null;
    }

    await Future<void>.delayed(duration);
    await stopSystemCapture();
    onSystemAudio = previous;
    return (peak, bytes);
  }

  /// Write captured PCM to a WAV so the result can be checked OUTSIDE the app.
  ///
  /// The whole tap investigation was derailed by trusting a peak computed in
  /// process. A file on disk can be measured independently, the same way the
  /// reference testbed's recordings were, and it either contains speech or it
  /// does not.
  static void _writeWav(String path, List<Uint8List> chunks, int sampleRate) {
    try {
      final pcmLength = chunks.fold<int>(0, (sum, c) => sum + c.lengthInBytes);
      if (pcmLength == 0) return;

      final header = ByteData(44);
      void ascii(int offset, String tag) {
        for (var i = 0; i < tag.length; i++) {
          header.setUint8(offset + i, tag.codeUnitAt(i));
        }
      }

      ascii(0, 'RIFF');
      header.setUint32(4, 36 + pcmLength, Endian.little);
      ascii(8, 'WAVE');
      ascii(12, 'fmt ');
      header.setUint32(16, 16, Endian.little);          // PCM chunk size
      header.setUint16(20, 1, Endian.little);           // format: PCM
      header.setUint16(22, 1, Endian.little);           // mono
      header.setUint32(24, sampleRate, Endian.little);
      header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
      header.setUint16(32, 2, Endian.little);           // block align
      header.setUint16(34, 16, Endian.little);          // bits per sample
      ascii(36, 'data');
      header.setUint32(40, pcmLength, Endian.little);

      final sink = File(path).openSync(mode: FileMode.write);
      sink.writeFromSync(header.buffer.asUint8List());
      for (final chunk in chunks) {
        sink.writeFromSync(chunk);
      }
      sink.closeSync();
      AppLogger.info('Wrote tap capture to $path ($pcmLength bytes PCM)');
    } catch (e) {
      AppLogger.warning('Could not write the tap capture WAV: $e');
    }
  }

  /// Loudest |sample| in a little-endian int16 PCM chunk.
  ///
  /// Reads through a [ByteData] view rather than `buffer.asInt16List`. The
  /// platform channel hands back `Uint8List` views into a larger message
  /// buffer, so `offsetInBytes` is frequently odd, and `asInt16List` throws on
  /// an unaligned offset. Inside an async method-call handler that exception is
  /// swallowed — which made a working tap report a peak of 0 for days while the
  /// byte count incremented normally, because the count happened before the
  /// throw. `getInt16` has no alignment requirement.
  static int _peakOf(Uint8List pcm) {
    final view = ByteData.sublistView(pcm);
    var peak = 0;
    for (var offset = 0; offset + 1 < pcm.lengthInBytes; offset += 2) {
      final magnitude = view.getInt16(offset, Endian.little).abs();
      if (magnitude > peak) peak = magnitude;
    }
    return peak;
  }

  /// Tap EVERYTHING for [duration] and report what arrived.
  ///
  /// Diagnostic only. Paired with a per-process measurement of an app that is
  /// definitely playing, this splits the two explanations for a silent tap
  /// that no other signal can separate: audio here but not there means the
  /// permission is fine and the process targeting is wrong; silence in both
  /// means the permission is not actually being honoured, whatever System
  /// Settings and TCC.db say.
  Future<String> measureGlobalTap({
    Duration duration = const Duration(seconds: 4),
  }) async {
    var peak = 0;
    var bytes = 0;
    final captured = <Uint8List>[];
    final previous = onSystemAudio;
    onSystemAudio = (pcm) {
      bytes += pcm.lengthInBytes;
      final magnitude = _peakOf(pcm);
      if (magnitude > peak) peak = magnitude;
      captured.add(pcm);
    };

    try {
      await _channel.invokeMethod<bool>('startGlobalCapture');
    } catch (e) {
      onSystemAudio = previous;
      return 'global tap refused: $e';
    }

    await Future<void>.delayed(duration);
    await stopSystemCapture();
    onSystemAudio = previous;
    _writeWav('${Platform.environment['HOME']}/ultrawhisper-tap-global.wav',
        captured, 16000);

    return 'global tap: $bytes bytes, peak $peak of 32767 → '
        '${peak > 32 ? "AUDIO PRESENT" : bytes == 0 ? "no buffers" : "SILENT"}';
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

  /// Start tapping [pids]. Returns null on success, else why it failed.
  ///
  /// The reason is returned rather than logged away because a refused tap and a
  /// tap that delivers digital silence look identical from the outside, and the
  /// OSStatus in this message is the only thing that separates them.
  Future<String?> startSystemCapture(List<int> pids) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('startSystemCapture', {'pids': pids});
      return ok == true ? null : 'the tap layer refused without saying why';
    } on PlatformException catch (e) {
      AppLogger.warning('Could not start system capture: ${e.code} ${e.message}');
      return '${e.code}: ${e.message}';
    } catch (e) {
      AppLogger.warning('Could not start system capture: $e');
      return '$e';
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
