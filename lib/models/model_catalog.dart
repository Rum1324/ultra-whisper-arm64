import 'notes_model_presets.dart';

/// A whisper model the app can download, and what it costs to run.
///
/// Sizes and checksums are HuggingFace's own LFS metadata for
/// `ggerganov/whisper.cpp` (checked 2026-10-06), so a download is verified
/// against the publisher rather than against a copy we made.
class SpeechModel {
  const SpeechModel({
    required this.id,
    required this.label,
    required this.fileName,
    required this.bytes,
    required this.sha256,
    required this.accuracy,
    required this.speed,
    required this.note,
  });

  /// Stored in Settings. Never renamed: an installed copy is found by it.
  final String id;
  final String label;
  final String fileName;
  final int bytes;
  final String sha256;

  /// 1–5, relative to the others in this list. Shown as dots.
  final int accuracy;
  final int speed;
  final String note;

  String get url =>
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$fileName';

  /// Roughly what whisper holds in memory while it runs: the weights plus
  /// ~0.5 GB of compute buffers. On Apple Silicon that memory is shared with
  /// everything else the user has open.
  double get approxMemoryGb => bytes / 1e9 + 0.5;
}

/// Turbo is the model every behaviour in this app was tuned on — the VAD
/// threshold, the repetition guards, the Japanese punctuation pass. The
/// quantized Turbos are the same network with smaller weights; Small is the
/// fallback for a machine that cannot spare the memory, and is noticeably
/// weaker on Japanese.
const List<SpeechModel> kSpeechModels = [
  SpeechModel(
    id: 'large-v3-turbo',
    label: 'Turbo',
    fileName: 'ggml-large-v3-turbo.bin',
    bytes: 1624555275,
    sha256: '1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69',
    accuracy: 5,
    speed: 3,
    note: 'Best accuracy in English and Japanese. What UltraWhisper is tuned on.',
  ),
  SpeechModel(
    id: 'large-v3-turbo-q8_0',
    label: 'Turbo, compressed',
    fileName: 'ggml-large-v3-turbo-q8_0.bin',
    bytes: 874188075,
    sha256: '317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1',
    accuracy: 5,
    speed: 4,
    note: 'Practically the same results in about half the memory.',
  ),
  SpeechModel(
    id: 'large-v3-turbo-q5_0',
    label: 'Turbo, light',
    fileName: 'ggml-large-v3-turbo-q5_0.bin',
    bytes: 574041195,
    sha256: '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
    accuracy: 4,
    speed: 4,
    note: 'Right for 8 GB Macs. Occasional slips on names and rare words.',
  ),
  SpeechModel(
    id: 'small-q5_1',
    label: 'Small',
    fileName: 'ggml-small-q5_1.bin',
    bytes: 190085487,
    sha256: 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
    accuracy: 2,
    speed: 5,
    note: 'Fastest and smallest. Clearly weaker, especially for Japanese.',
  ),
];

const String kDefaultSpeechModelId = 'large-v3-turbo';

SpeechModel? speechModelById(String id) {
  for (final model in kSpeechModels) {
    if (model.id == id) return model;
  }
  return null;
}

/// A model pulled through Ollama for one of the optional AI features.
class OllamaModelChoice {
  const OllamaModelChoice({
    required this.tag,
    required this.label,
    required this.downloadGb,
    required this.memoryGb,
    required this.note,
  });

  final String tag;
  final String label;

  /// What `ollama pull` fetches, as `ollama list` reports it.
  final double downloadGb;

  /// What it holds while it runs. Smaller than the download for gemma4:e4b,
  /// whose vision and audio towers are fetched but never loaded for text.
  final double memoryGb;
  final String note;
}

/// The dictation formatter's model. Chosen by measurement — see
/// `backend/dictation_formatter.py` — so it is not user-selectable.
const OllamaModelChoice kFormattingModel = OllamaModelChoice(
  tag: 'gemma4:e4b',
  label: 'Gemma 4 E4B',
  downloadGb: 9.6,
  memoryGb: 3.4,
  note: 'Removes fillers, fixes punctuation, writes numbers as digits. '
      'Adds about a second per dictation.',
);

/// The meeting-notes presets, in the same shape as [kFormattingModel].
List<OllamaModelChoice> get kNotesModelChoices => [
      for (final preset in kNotesModelPresets)
        OllamaModelChoice(
          tag: preset.tag,
          label: preset.label,
          downloadGb: preset.approxGigabytes,
          memoryGb: preset.approxGigabytes,
          note: preset.note,
        ),
    ];
