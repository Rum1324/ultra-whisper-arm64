enum RecordingState {
  idle,
  recording,
  processing,
  error
}

enum AudioSource {
  microphone,
  systemAudio
}

class AppState {
  final RecordingState recordingState;
  final AudioSource audioSource;
  final String? partialText;
  final String? finalText;
  final String? errorMessage;
  final Duration recordingDuration;
  final double audioLevel;
  final bool isOverlayVisible;
  final bool isPartialTextVisible;
  final bool isSettingsWindowOpen;
  
  const AppState({
    this.recordingState = RecordingState.idle,
    this.audioSource = AudioSource.microphone,
    this.partialText,
    this.finalText,
    this.errorMessage,
    this.recordingDuration = Duration.zero,
    this.audioLevel = 0.0,
    this.isOverlayVisible = true,
    this.isPartialTextVisible = false,
    this.isSettingsWindowOpen = false,
  });
  
  AppState copyWith({
    RecordingState? recordingState,
    AudioSource? audioSource,
    String? partialText,
    String? finalText,
    String? errorMessage,
    Duration? recordingDuration,
    double? audioLevel,
    bool? isOverlayVisible,
    bool? isPartialTextVisible,
    bool? isSettingsWindowOpen,
  }) {
    return AppState(
      recordingState: recordingState ?? this.recordingState,
      audioSource: audioSource ?? this.audioSource,
      partialText: partialText ?? this.partialText,
      finalText: finalText ?? this.finalText,
      errorMessage: errorMessage ?? this.errorMessage,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      audioLevel: audioLevel ?? this.audioLevel,
      isOverlayVisible: isOverlayVisible ?? this.isOverlayVisible,
      isPartialTextVisible: isPartialTextVisible ?? this.isPartialTextVisible,
      isSettingsWindowOpen: isSettingsWindowOpen ?? this.isSettingsWindowOpen,
    );
  }
}