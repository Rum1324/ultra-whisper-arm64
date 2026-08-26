/// Ollama tags offered for meeting notes, and what each one costs.
///
/// Notes are the one part of UltraWhisper that is not self-contained, and the
/// model is the single biggest thing the user feels: a 35B at Q3 puts a laptop
/// under real memory pressure while it runs. So the choice is presented with
/// its size rather than as an opaque tag, and a lighter rung is always
/// available.
///
/// All of these are Unsloth Dynamic GGUFs pulled straight from HuggingFace —
/// `ollama pull <tag>` works on them directly, no Modelfile needed.
class NotesModelPreset {
  const NotesModelPreset({
    required this.label,
    required this.tag,
    required this.approxGigabytes,
    required this.note,
  });

  final String label;
  final String tag;
  final double approxGigabytes;
  final String note;

  String get pullCommand => 'ollama pull $tag';
}

const List<NotesModelPreset> kNotesModelPresets = [
  NotesModelPreset(
    label: 'Balanced',
    tag: 'hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q3_K_XL',
    approxGigabytes: 16.8,
    note: 'Best notes. Heavy — expect high memory pressure while it runs.',
  ),
  NotesModelPreset(
    label: 'Light',
    tag: 'hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL',
    approxGigabytes: 12.3,
    note: 'Same model, smaller quantisation. ~4.5 GB less memory, same speed.',
  ),
  NotesModelPreset(
    label: 'Lightest',
    tag: 'hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-IQ2_M',
    approxGigabytes: 11.5,
    note: 'For a busy machine. Extraction gets noticeably weaker below Q2.',
  ),
];

/// The preset matching [tag], or null when the user has typed their own.
NotesModelPreset? presetForTag(String tag) {
  final wanted = tag.trim();
  for (final preset in kNotesModelPresets) {
    if (preset.tag == wanted) return preset;
  }
  return null;
}
