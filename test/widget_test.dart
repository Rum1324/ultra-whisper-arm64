// Widget tests for the overlay UI.
//
// The real root widget (UltraWhisperApp) spins up the backend process, hotkeys
// and the native window manager in initState, so it can't be pumped in a test.
// Instead these tests exercise AppContent — the widget tree below the root —
// against a fake AppService that only carries an AppState.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ultrawhisper/models/app_state.dart';
import 'package:ultrawhisper/models/settings.dart';
import 'package:ultrawhisper/services/app_service.dart';
import 'package:ultrawhisper/services/meeting_detector.dart';
import 'package:ultrawhisper/widgets/app_content.dart';
import 'package:ultrawhisper/widgets/floating_overlay.dart';
import 'package:ultrawhisper/widgets/thinking_orb.dart';

/// Minimal stand-in for [AppService]: holds an [AppState] and records the
/// recording calls the UI makes. Everything else routes through noSuchMethod,
/// so a member the widgets don't touch throws rather than silently no-oping.
class FakeAppService extends ChangeNotifier implements AppService {
  FakeAppService([this._state = const AppState()]);

  AppState _state;
  int startRecordingCalls = 0;
  int stopRecordingCalls = 0;

  @override
  AppState get state => _state;

  /// The overlay reads the orb's expressiveness from here.
  @override
  Settings get settings => const Settings();

  /// AppContent chooses between the dictation overlay and the meeting panel on
  /// these two, so the fake has to answer them. Idle by default: these tests
  /// are about dictation.
  @override
  MeetingCandidate? pendingMeetingPrompt;

  @override
  bool isMeetingActive = false;

  set state(AppState value) {
    _state = value;
    notifyListeners();
  }

  @override
  Future<void> startRecording() async {
    startRecordingCalls++;
  }

  @override
  Future<void> stopRecording() async {
    stopRecordingCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Widget wrap(FakeAppService service) {
  return ChangeNotifierProvider<AppService>.value(
    value: service,
    child: const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AppContent(),
    ),
  );
}

void main() {
  testWidgets('shows nothing while idle', (tester) async {
    final service = FakeAppService();

    await tester.pumpWidget(wrap(service));

    // Recording starts from the hotkey or the menu bar; the overlay only
    // appears once there is something to show.
    expect(find.byType(FloatingOverlay), findsOneWidget);
    expect(find.byType(ThinkingOrb), findsNothing);
    expect(find.text('Listening'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows the orb and the time while recording', (tester) async {
    final service = FakeAppService(
      const AppState(
        recordingState: RecordingState.recording,
        recordingDuration: Duration(seconds: 7),
      ),
    );

    await tester.pumpWidget(wrap(service));

    expect(find.byType(ThinkingOrb), findsOneWidget);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.text('0:07'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping the island stops recording', (tester) async {
    final service = FakeAppService(
      const AppState(recordingState: RecordingState.recording),
    );

    await tester.pumpWidget(wrap(service));
    await tester.tap(find.text('Listening'));
    await tester.pump();

    expect(service.stopRecordingCalls, 1);
    expect(service.startRecordingCalls, 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('says it is writing while the transcript is processed',
      (tester) async {
    final service = FakeAppService(
      const AppState(recordingState: RecordingState.processing),
    );

    await tester.pumpWidget(wrap(service));
    expect(find.text('Writing'), findsOneWidget);

    // Not a stop button any more: there is nothing left to stop.
    await tester.tap(find.text('Writing'));
    await tester.pump();
    expect(service.stopRecordingCalls, 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hides the overlay contents when the overlay is not visible',
      (tester) async {
    final service = FakeAppService(
      const AppState(
        recordingState: RecordingState.recording,
        isOverlayVisible: false,
      ),
    );

    await tester.pumpWidget(wrap(service));

    expect(find.byType(FloatingOverlay), findsOneWidget);
    expect(find.byType(ThinkingOrb), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  // The overlay window is always on screen. A waveform ticker that kept
  // running while idle rendered a frame on every display refresh: ~30% CPU
  // for an app doing nothing.
  testWidgets('stops rendering frames once idle', (tester) async {
    final service = FakeAppService(
      const AppState(recordingState: RecordingState.recording),
    );

    await tester.pumpWidget(wrap(service));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);

    service.state = const AppState();
    // pumpAndSettle times out if anything keeps scheduling frames.
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rebuilds when the service notifies a state change',
      (tester) async {
    final service = FakeAppService();

    await tester.pumpWidget(wrap(service));
    expect(find.text('Listening'), findsNothing);

    service.state = const AppState(recordingState: RecordingState.recording);
    await tester.pump();

    expect(find.text('Listening'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
