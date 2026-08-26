import 'dart:async';
import 'dart:io' show pid;

import '../utils/logger.dart';

/// A process that currently looks like a live call.
class MeetingCandidate {
  const MeetingCandidate({
    required this.pid,
    required this.name,
    this.bundleId,
  });

  final int pid;
  final String name;
  final String? bundleId;

  /// What cooldowns and the never-list are keyed on.
  ///
  /// The bundle ID when there is one, because "never ask for Discord again"
  /// must survive Discord restarting under a new pid. A pid key is the
  /// fallback and is deliberately weaker — it only lasts as long as that
  /// process does, which is the honest scope when the app cannot be named.
  String get key => bundleId ?? 'pid:$pid';

  @override
  String toString() => '$name (${bundleId ?? 'pid $pid'})';
}

/// Notices that a meeting has probably started, and says which process to tap.
///
/// The signal is app-agnostic: a real-time call is the one common situation
/// where a **single process** is simultaneously capturing the microphone and
/// playing audio. That one fact both detects the meeting and identifies the
/// "them" source, so nothing here needs a list of meeting apps to work.
///
/// What it rules out, by construction:
/// - Music or video — output only.
/// - Dictation, Voice Memos, a mic-level check — input only.
/// - Music in one app while another records — two processes, not one.
///
/// What it will occasionally fire on — OBS with mic monitoring, game voice
/// chat — is genuinely bidirectional, which is why the result is a prompt and
/// never an automatic start.
///
/// Polling is gated on microphone activity, so nothing runs at all while the
/// mic is cold. That is the cheap outer test; the per-process scan is the
/// expensive one.
class MeetingDetector {
  MeetingDetector({
    required Future<List<Map<String, dynamic>>> Function() listProcesses,
    DateTime Function()? clock,
    this.pollInterval = const Duration(seconds: 2),
    this.sustain = const Duration(seconds: 4),
    int? ownPid,
  })  : _listProcesses = listProcesses,
        _clock = clock ?? DateTime.now,
        _ownPid = ownPid ?? pid;

  final Future<List<Map<String, dynamic>>> Function() _listProcesses;
  final DateTime Function() _clock;
  final int _ownPid;

  /// How often to re-scan while the microphone is in use.
  final Duration pollInterval;

  /// How long the input+output condition must hold before prompting.
  ///
  /// Without this a notification chime landing mid-dictation would briefly make
  /// some process look bidirectional and fire a prompt.
  final Duration sustain;

  /// Apps whose bundle ID is meeting-specific enough that waiting out [sustain]
  /// adds nothing. Deliberately NOT the primary detector — a Google Meet call
  /// runs inside a browser and has no bundle ID of its own, and the
  /// input+output rule is what catches those.
  static const Set<String> knownMeetingBundleIds = {
    'us.zoom.xos',
    'com.microsoft.teams2',
    'com.cisco.webexmeetingsapp',
    'com.hnc.Discord',
    'com.tinyspeck.slackmacgap',
    'com.apple.FaceTime',
  };

  /// Master switch, mirrored from settings.
  bool enabled = true;

  /// Bundle IDs the user has said "never" to. Persisted in settings.
  Set<String> neverList = <String>{};

  /// Fired once per detection, with the process to tap for the "them" track.
  void Function(MeetingCandidate candidate)? onMeetingLikely;

  /// Set while a meeting is running or a prompt is already on screen. Polling
  /// continues (it is what notices the call ending) but nothing is emitted.
  bool suppressed = false;

  Timer? _timer;
  bool _micActive = false;
  bool _polling = false;

  /// When each candidate key was first seen bidirectional, for [sustain].
  final Map<String, DateTime> _firstSeen = <String, DateTime>{};

  /// Keys already prompted for, or dismissed with "Not now", for this session.
  final Set<String> _cooledDown = <String>{};

  bool get isRunning => _timer != null;

  /// Drive the outer gate. Cheap: this is a property listener, not a poll.
  void micActivityChanged(bool active) {
    if (_micActive == active) return;
    _micActive = active;
    if (active) {
      _start();
    } else {
      _stop();
      // A call that ended clears the sustain clocks but NOT the cooldowns —
      // "Not now" is meant to last the session, not until the next silence.
      _firstSeen.clear();
    }
  }

  void _start() {
    if (_timer != null) return;
    AppLogger.debug('MeetingDetector: mic is hot, scanning every '
        '${pollInterval.inSeconds}s');
    _timer = Timer.periodic(pollInterval, (_) => poll());
    unawaited(poll());
  }

  void _stop() {
    if (_timer == null) return;
    AppLogger.debug('MeetingDetector: mic is cold, stopping scan');
    _timer!.cancel();
    _timer = null;
  }

  /// One scan. Public so it can be driven directly in tests rather than through
  /// a real timer.
  Future<void> poll() async {
    if (!enabled || _polling) return;
    _polling = true;
    try {
      final processes = await _listProcesses();
      final now = _clock();

      final live = <String, MeetingCandidate>{};
      for (final process in processes) {
        if (process['runningInput'] != true || process['runningOutput'] != true) {
          continue;
        }
        final processPid = process['pid'];
        if (processPid is! int || processPid == _ownPid) continue;

        final bundleId = process['bundleId'] as String?;
        final candidate = MeetingCandidate(
          pid: processPid,
          name: (process['name'] ?? 'pid $processPid').toString(),
          bundleId: bundleId,
        );
        live[candidate.key] = candidate;
      }

      // Forget anything that stopped being bidirectional, so a later
      // reappearance has to earn its sustain window again.
      _firstSeen.removeWhere((key, _) => !live.containsKey(key));

      for (final entry in live.entries) {
        _firstSeen.putIfAbsent(entry.key, () => now);
        if (suppressed) continue;
        if (_cooledDown.contains(entry.key)) continue;
        if (entry.value.bundleId != null &&
            neverList.contains(entry.value.bundleId)) {
          continue;
        }

        final held = now.difference(_firstSeen[entry.key]!);
        final needed = knownMeetingBundleIds.contains(entry.value.bundleId)
            ? Duration.zero
            : sustain;
        if (held < needed) continue;

        // One prompt per app per session, whatever the user answers.
        _cooledDown.add(entry.key);
        AppLogger.info('MeetingDetector: ${entry.value} looks like a live call');
        onMeetingLikely?.call(entry.value);
        return;
      }
    } catch (e) {
      // Detection is a convenience on top of a manual path that works. It may
      // never take the app down.
      AppLogger.warning('MeetingDetector: scan failed: $e');
    } finally {
      _polling = false;
    }
  }

  /// "Not now" — stop asking about this app for the rest of the session.
  void snooze(MeetingCandidate candidate) {
    _cooledDown.add(candidate.key);
  }

  /// "Never for this app" — the caller persists the returned bundle ID.
  ///
  /// Returns null when the process has no bundle ID, in which case only a
  /// session cooldown is possible.
  String? never(MeetingCandidate candidate) {
    _cooledDown.add(candidate.key);
    final bundleId = candidate.bundleId;
    if (bundleId != null) neverList = {...neverList, bundleId};
    return bundleId;
  }

  void dispose() {
    _stop();
    onMeetingLikely = null;
  }
}
