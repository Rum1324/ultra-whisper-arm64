import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/websocket_messages.dart';
import '../services/app_service.dart';
import '../services/meeting_detector.dart';
import '../services/meeting_service.dart';

/// The meeting surface: the detection prompt, then the live two-track
/// transcript.
///
/// Deliberately plain. The note itself is rendered as markdown text rather
/// than parsed into sections — the backend already returns both, and a
/// polished note view is worth doing once the capture path has been used in
/// anger. What this must get right is the two things a user cannot recover
/// from later: that recording is actually happening, and that the "them" track
/// is silent when it is.
class MeetingPanel extends StatelessWidget {
  const MeetingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, appService, child) {
        final prompt = appService.pendingMeetingPrompt;
        return _Glass(
          child: prompt != null
              ? _DetectionPrompt(candidate: prompt)
              : _MeetingBody(appService: appService),
        );
      },
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 34, 8, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
      ),
      child: child,
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
        const Text(
          'Looks like a meeting',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          '${candidate.name} is using the microphone and playing audio at the '
          'same time. Record and transcribe it?',
          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.75)),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: appService.acceptMeetingPrompt,
              child: const Text('Record'),
            ),
            TextButton(
              onPressed: () => appService.dismissMeetingPrompt(),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => appService.dismissMeetingPrompt(never: true),
              child: Text('Never for ${candidate.name}'),
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
            Icon(
              meeting.isRecording ? Icons.fiber_manual_record : Icons.stop_circle_outlined,
              size: 14,
              color: meeting.isRecording ? Colors.redAccent : Colors.white70,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                meeting.isRecording
                    ? 'Recording ${target?.name ?? 'microphone only'}'
                    : _phaseLabel(meeting.phase),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
            Text(
              _stamp(appService.meetingDuration),
              style: TextStyle(
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        if (appService.meetingSystemAudioSilent) ...[
          const SizedBox(height: 8),
          const _Notice(
            'The other side is not being captured. Grant UltraWhisper Audio '
            'Recording in System Settings › Privacy & Security, then restart '
            'the app. Your own voice is still being recorded.',
          ),
        ],
        if (meeting.error != null) ...[
          const SizedBox(height: 8),
          _Notice(meeting.error!),
        ],
        const SizedBox(height: 10),
        Expanded(child: _TranscriptView(meeting: meeting)),
        const SizedBox(height: 10),
        _Actions(appService: appService),
      ],
    );
  }

  static String _phaseLabel(MeetingPhase phase) => switch (phase) {
        MeetingPhase.ended => 'Meeting ended',
        MeetingPhase.summarizing => 'Writing notes…',
        MeetingPhase.summarized => 'Notes ready',
        MeetingPhase.summaryUnavailable => 'Transcript ready — notes unavailable',
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
          style: const TextStyle(fontSize: 12, height: 1.45, color: Colors.white),
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
          const SizedBox(height: 8),
        ],
        if (meeting.progress != null) ...[
          _Progress(progress: meeting.progress!),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: segments.isEmpty
              ? Center(
                  child: Text(
                    'Waiting for speech…',
                    style: TextStyle(
                        fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
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
    final isMe = segment.isMe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.white),
          children: [
            TextSpan(
              text: isMe ? 'Me  ' : 'Them  ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isMe ? Colors.lightBlueAccent : Colors.tealAccent,
              ),
            ),
            TextSpan(text: segment.text),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.progress});
  final SummaryProgressEvent progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${progress.stage} ${progress.completed}/${progress.total}',
          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress.total > 0 ? progress.fraction : null,
          minHeight: 3,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.amber.withValues(alpha: 0.12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 11, height: 1.4, color: Colors.amberAccent),
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
          Expanded(
            child: FilledButton.icon(
              onPressed: () => appService.endMeeting(),
              icon: const Icon(Icons.stop, size: 16),
              label: const Text('Stop & write notes'),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: appService.cancelMeeting,
            child: const Text('Discard'),
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
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.55),
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            if (meeting.canSummarize)
              Expanded(
                child: FilledButton(
                  onPressed: () => appService.summarizeMeeting(),
                  child: Text(
                    meeting.summary == null ? 'Write notes' : 'Rewrite notes',
                  ),
                ),
              )
            else
              const Expanded(child: SizedBox.shrink()),
            const SizedBox(width: 8),
            TextButton(
              onPressed: appService.cancelMeeting,
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }
}
