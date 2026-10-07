import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/websocket_messages.dart';
import '../services/app_service.dart';
import '../services/meeting_detector.dart';
import '../services/meeting_service.dart';
import '../theme/focus_theme.dart';
import 'focus_controls.dart';

/// The meeting surface: the detection prompt, then the live two-track
/// transcript.
///
/// Deliberately plain. The note itself is rendered as markdown text rather
/// than parsed into sections — the backend already returns both, and a
/// polished note view is worth doing once the capture path has been used in
/// anger. What this must get right is the two things a user cannot recover
/// from later: that recording is actually happening, and that the "them" track
/// is silent when it is.
///
/// Drawn as a Focus island: always black, whatever the system appearance,
/// because it floats over other apps.
class MeetingPanel extends StatelessWidget {
  const MeetingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, appService, child) {
        final prompt = appService.pendingMeetingPrompt;
        return _Island(
          child: prompt != null
              ? _DetectionPrompt(candidate: prompt)
              : _MeetingBody(appService: appService),
        );
      },
    );
  }
}

class _Island extends StatelessWidget {
  const _Island({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 34, 8, 8),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: const BoxDecoration(
        color: FocusIsland.ground,
        borderRadius: BorderRadius.all(FocusRadius.r26),
      ),
      child: DefaultTextStyle(
        style: FocusText.islandMeta.copyWith(fontSize: 12.5, height: 1.45),
        child: child,
      ),
    );
  }
}

class _DetectionPrompt extends StatelessWidget {
  const _DetectionPrompt({required this.candidate});
  final MeetingCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final appService = context.read<AppService>();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MEETING', style: FocusText.islandLabel),
        const SizedBox(height: 4),
        const Text('This looks like a meeting.', style: FocusText.islandNow),
        const SizedBox(height: 6),
        Text(
          '${candidate.name} is using the microphone and playing audio at the '
          'same time. Do you want to record and transcribe it?',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FocusIslandPill(
              label: 'Record',
              prominent: true,
              onPressed: appService.acceptMeetingPrompt,
            ),
            FocusIslandPill(
              label: 'Not now',
              onPressed: () => appService.dismissMeetingPrompt(),
            ),
            FocusIslandPill(
              label: 'Never for ${candidate.name}',
              onPressed: () => appService.dismissMeetingPrompt(never: true),
            ),
          ],
        ),
      ],
    );
  }
}

class _MeetingBody extends StatelessWidget {
  const _MeetingBody({required this.appService});
  final AppService appService;

  @override
  Widget build(BuildContext context) {
    final meeting = appService.meetingService;
    final target = appService.meetingTarget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            FocusLevelDot(_level(meeting)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                meeting.isRecording
                    ? 'Recording ${target?.name ?? 'the microphone only'}'
                    : _phaseLabel(meeting.phase),
                overflow: TextOverflow.ellipsis,
                style: FocusText.islandNow,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _stamp(appService.meetingDuration),
              style: FocusText.islandMeta.copyWith(fontSize: 12.5),
            ),
          ],
        ),
        if (appService.meetingSystemAudioSilent) ...[
          const SizedBox(height: 10),
          const _Notice(
            'The other side is not being captured. Grant UltraWhisper Audio '
            'Recording in System Settings › Privacy & Security, then restart '
            'the app. Your own voice is still being recorded.',
          ),
        ],
        if (meeting.error != null) ...[
          const SizedBox(height: 10),
          _Notice(meeting.error!, level: FocusLevel.risk),
        ],
        const SizedBox(height: 12),
        Expanded(child: _TranscriptView(meeting: meeting)),
        const SizedBox(height: 12),
        _Actions(appService: appService),
      ],
    );
  }

  /// The header dot. Recording that is working is calm; recording that has
  /// lost the other side needs a look; a failure is at risk; a finished
  /// meeting has nothing live left.
  FocusLevel _level(MeetingService meeting) {
    if (meeting.error != null) return FocusLevel.risk;
    if (!meeting.isRecording) return FocusLevel.offline;
    if (appService.meetingSystemAudioSilent) return FocusLevel.watch;
    return FocusLevel.calm;
  }

  static String _phaseLabel(MeetingPhase phase) => switch (phase) {
        MeetingPhase.ended => 'The meeting has ended.',
        MeetingPhase.summarizing => 'Writing notes…',
        MeetingPhase.summarized => 'Your notes are ready.',
        MeetingPhase.summaryUnavailable =>
          'The transcript is ready. Notes are unavailable.',
        _ => 'Meeting',
      };

  static String _stamp(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

class _TranscriptView extends StatelessWidget {
  const _TranscriptView({required this.meeting});
  final MeetingService meeting;

  @override
  Widget build(BuildContext context) {
    // A finished note supersedes the running transcript; until then the
    // transcript IS the feedback that capture is working.
    final summary = meeting.summary;
    if (summary != null) {
      return SingleChildScrollView(
        child: SelectableText(
          summary.markdown,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: FocusIsland.ink,
          ),
        ),
      );
    }

    final unavailable = meeting.unavailable;
    final segments = meeting.transcript;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (unavailable != null) ...[
          _Notice(unavailable.remedy ?? unavailable.detail),
          const SizedBox(height: 10),
        ],
        if (meeting.progress != null) ...[
          _Progress(progress: meeting.progress!),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: segments.isEmpty
              ? Center(
                  child: Text(
                    'Waiting for speech…',
                    style: FocusText.islandMeta.copyWith(
                      fontSize: 12.5,
                      color: FocusIsland.ink3,
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  itemCount: segments.length,
                  itemBuilder: (context, index) =>
                      _Segment(segment: segments[segments.length - 1 - index]),
                ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.segment});
  final TranscriptSegment segment;

  @override
  Widget build(BuildContext context) {
    // The speakers differ in lightness, not hue: you in full white, the other
    // side in island ink-2.
    final isMe = segment.isMe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isMe ? 'ME' : 'THEM', style: FocusText.islandLabel),
          const SizedBox(height: 1),
          Text(
            segment.text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: isMe ? FocusIsland.ink : FocusIsland.ink2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.progress});
  final SummaryProgressEvent progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.total > 0 ? progress.fraction : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${progress.stage} ${progress.completed} of ${progress.total}',
          style: FocusText.islandMeta,
        ),
        const SizedBox(height: 6),
        // Focus island track: 4px, island-fill, the bar in island ink at 85%.
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 4,
            backgroundColor: FocusIsland.fill,
            color: FocusIsland.ink.withValues(alpha: .85),
          ),
        ),
      ],
    );
  }
}

/// A status sentence with its level dot (Focus `StatusRow`, on the island).
class _Notice extends StatelessWidget {
  const _Notice(this.message, {this.level = FocusLevel.watch});
  final String message;
  final FocusLevel level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: FocusIsland.fill,
        borderRadius: BorderRadius.all(FocusRadius.r14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: FocusLevelDot(level, size: 8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: FocusIsland.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.appService});
  final AppService appService;

  @override
  Widget build(BuildContext context) {
    final meeting = appService.meetingService;

    if (meeting.isRecording) {
      return Row(
        children: [
          FocusIslandPill(
            label: 'Stop and write notes',
            prominent: true,
            onPressed: () => appService.endMeeting(),
          ),
          const SizedBox(width: 6),
          FocusIslandPill(
            label: 'Discard',
            onPressed: appService.cancelMeeting,
          ),
        ],
      );
    }

    final saved = appService.lastSavedMeetingFiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Where it went matters more than that it went: notes can be
        // regenerated, but a user who cannot find the transcript has lost it.
        if (saved.isNotEmpty) ...[
          Text(
            'Saved to ${appService.meetingSaveDirectory}',
            style: FocusText.islandMeta,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            if (meeting.canSummarize) ...[
              FocusIslandPill(
                label: meeting.summary == null ? 'Write notes' : 'Rewrite notes',
                prominent: true,
                onPressed: () => appService.summarizeMeeting(),
              ),
              const SizedBox(width: 6),
            ],
            FocusIslandPill(
              label: 'Done',
              prominent: !meeting.canSummarize,
              onPressed: appService.cancelMeeting,
            ),
          ],
        ),
      ],
    );
  }
}
