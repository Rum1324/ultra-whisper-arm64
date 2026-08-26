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
import 'package:ultrawhisper/services/app_service.dart';
import 'package:ultrawhisper/services/meeting_detector.dart';
import 'package:ultrawhisper/widgets/app_content.dart';
import 'package:ultrawhisper/widgets/floating_overlay.dart';

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
  testWidgets('shows the overlay with a mic button when idle', (tester) async {
    final service = FakeAppService();

    await tester.pumpWidget(wrap(service));

    expect(find.byType(FloatingOverlay), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
    // One AnimatedContainer per waveform bar.
    expect(find.byType(AnimatedContainer), findsNWidgets(32));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping the mic button starts recording', (tester) async {
    final service = FakeAppService();

    await tester.pumpWidget(wrap(service));
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();

    expect(service.startRecordingCalls, 1);
    expect(service.stopRecordingCalls, 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows a stop button while recording and stops on tap',
      (tester) async {
    final service = FakeAppService(
      const AppState(recordingState: RecordingState.recording),
    );

    await tester.pumpWidget(wrap(service));

    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    expect(service.stopRecordingCalls, 1);
    expect(service.startRecordingCalls, 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hides the overlay contents when the overlay is not visible',
      (tester) async {
    final service = FakeAppService(const AppState(isOverlayVisible: false));

    await tester.pumpWidget(wrap(service));

    expect(find.byType(FloatingOverlay), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);
    expect(find.byType(AnimatedContainer), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rebuilds when the service notifies a state change',
      (tester) async {
    final service = FakeAppService();

    await tester.pumpWidget(wrap(service));
    expect(find.byIcon(Icons.mic), findsOneWidget);

    service.state = const AppState(recordingState: RecordingState.recording);
    await tester.pump();

    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
