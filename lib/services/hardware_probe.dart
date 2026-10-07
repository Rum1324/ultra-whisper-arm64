import 'dart:io';

import '../models/model_catalog.dart';
import '../models/notes_model_presets.dart';

/// What this Mac has to spend on models.
///
/// Memory is the number that matters most. Apple Silicon shares one pool
/// between CPU and GPU, so the speech model, an Ollama model and every open
/// browser tab all come out of the same gigabytes — there is no separate VRAM
/// to fill first.
class HardwareInfo {
  const HardwareInfo({
    required this.chip,
    required this.memoryBytes,
    this.gpuCores,
    this.performanceCores,
    this.efficiencyCores,
    this.freeDiskBytes,
    this.macOSVersion,
  });

  /// `Apple M3 Max`, or an Intel brand string.
  final String chip;
  final int memoryBytes;
  final int? gpuCores;
  final int? performanceCores;
  final int? efficiencyCores;
  final int? freeDiskBytes;
  final String? macOSVersion;

  bool get isAppleSilicon => chip.startsWith('Apple');

  /// In the units Apple sells: a "16 GB" Mac reports 17179869184 bytes.
  int get memoryGb => (memoryBytes / (1 << 30)).round();

  /// `Apple M3 Max · 36 GB memory · 30-core GPU`
  String get summary => [
        chip,
        '$memoryGb GB memory',
        if (gpuCores != null) '$gpuCores-core GPU',
      ].join(' · ');

  /// Everything comes from `sysctl` and `ioreg`, which answer in milliseconds
  /// and need no permission — unlike `system_profiler`, which takes a second.
  static Future<HardwareInfo> probe() async {
    Future<String> run(String exe, List<String> args) async {
      try {
        final result = await Process.run(exe, args);
        return result.exitCode == 0 ? (result.stdout as String).trim() : '';
      } catch (_) {
        return '';
      }
    }

    final chip = await run('/usr/sbin/sysctl', ['-n', 'machdep.cpu.brand_string']);
    final memory = await run('/usr/sbin/sysctl', ['-n', 'hw.memsize']);
    final pCores = await run('/usr/sbin/sysctl', ['-n', 'hw.perflevel0.physicalcpu']);
    final eCores = await run('/usr/sbin/sysctl', ['-n', 'hw.perflevel1.physicalcpu']);
    final ioreg = await run('/usr/sbin/ioreg', ['-rc', 'AGXAccelerator', '-d', '1']);
    final df = await run('/bin/df', ['-k', Platform.environment['HOME'] ?? '/']);
    final version = await run('/usr/bin/sw_vers', ['-productVersion']);

    return HardwareInfo(
      chip: chip.isEmpty ? 'Unknown Mac' : chip,
      memoryBytes: int.tryParse(memory) ?? 8 * (1 << 30),
      gpuCores: parseGpuCores(ioreg),
      performanceCores: int.tryParse(pCores),
      efficiencyCores: int.tryParse(eCores),
      freeDiskBytes: parseDfAvailableBytes(df),
      macOSVersion: version.isEmpty ? null : version,
    );
  }

  /// `"gpu-core-count" = 30` out of `ioreg -rc AGXAccelerator`.
  static int? parseGpuCores(String ioreg) {
    final match = RegExp(r'"gpu-core-count"\s*=\s*(\d+)').firstMatch(ioreg);
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// The Available column of `df -k`, in bytes.
  static int? parseDfAvailableBytes(String df) {
    final lines = df.trim().split('\n');
    if (lines.length < 2) return null;
    final fields = lines.last.trim().split(RegExp(r'\s+'));
    if (fields.length < 4) return null;
    final kb = int.tryParse(fields[3]);
    return kb == null ? null : kb * 1024;
  }
}

/// What setup preselects. The user can change every part of it.
class SetupRecommendation {
  const SetupRecommendation({
    required this.speechModelId,
    required this.aiFormatting,
    required this.notesModelTag,
    required this.reason,
  });

  /// An id from [kSpeechModels].
  final String speechModelId;

  /// Whether to download gemma4:e4b and turn AI formatting on.
  final bool aiFormatting;

  /// A tag from [kNotesModelPresets], or null to leave meeting notes off.
  final String? notesModelTag;

  /// One sentence shown under the recommendation, in plain words.
  final String reason;
}

/// Below this, AI formatting is not offered at all: gemma4:e4b holds ~3.4 GB
/// next to whisper, and on an 8 GB Mac that pushes everything else into swap.
const int kMinMemoryGbForFormatting = 16;

/// Below this, meeting notes are not offered: even the Lightest preset holds
/// ~11.5 GB while it summarizes.
const int kMinMemoryGbForNotes = 24;

/// Formatting is recommended — not merely allowed — from here: on 16 GB the
/// ~5.5 GB that whisper and gemma hold together is workable but tight next to
/// a browser, so there it stays an opt-in.
const int kRecommendFormattingFromGb = 24;

/// Notes are recommended only from here, and then Balanced. Between
/// [kMinMemoryGbForNotes] and this they are an opt-in: a 32 GB Mac can run
/// them, but recommending them would make the first download ~25 GB.
const int kRecommendNotesFromGb = 48;

/// What every recommendation leaves free on disk after downloading.
const int _diskHeadroomBytes = 5 * 1000 * 1000 * 1000;

/// The private Ollama, counted once ahead of whichever AI model needs it.
const int _ollamaRuntimeBytes = 170 * 1000 * 1000;

/// The setup a friend should start from on [hw]. Ids come from
/// [kSpeechModels]; notes tags from [kNotesModelPresets].
///
/// Memory decides, because Apple Silicon has one pool for CPU and GPU. Disk
/// only ever takes things away: nothing is recommended that would leave less
/// than 5 GB free.
SetupRecommendation recommendSetup(HardwareInfo hw) {
  final memory = hw.memoryGb;
  var disk = (hw.freeDiskBytes ?? 1 << 62) - _diskHeadroomBytes;

  bool fits(int bytes) {
    if (bytes > disk) return false;
    disk -= bytes;
    return true;
  }

  int gb(double value) => (value * 1e9).round();

  // Largest first: Turbo is what everything was tuned on, so it is the answer
  // wherever memory allows, and only disk can talk it down.
  final speechOrder = memory >= 16
      ? ['large-v3-turbo', 'large-v3-turbo-q8_0', 'large-v3-turbo-q5_0']
      : ['large-v3-turbo-q5_0'];
  final speech = speechOrder
          .map(speechModelById)
          .whereType<SpeechModel>()
          .where((model) => fits(model.bytes))
          .firstOrNull ??
      speechModelById('small-q5_1')!;

  final formatting = memory >= kRecommendFormattingFromGb &&
      fits(_ollamaRuntimeBytes + gb(kFormattingModel.downloadGb));

  final balanced = kNotesModelPresets.first;
  final notes = memory >= kRecommendNotesFromGb &&
          fits((formatting ? 0 : _ollamaRuntimeBytes) + gb(balanced.approxGigabytes))
      ? balanced.tag
      : null;

  final String reason;
  if (memory < kMinMemoryGbForFormatting) {
    reason = 'With $memory GB of memory, a light speech model keeps this Mac '
        'responsive. The AI extras need more memory than it has.';
  } else if (!formatting) {
    reason = 'Turbo runs comfortably with $memory GB. AI formatting fits too '
        'but is tight here — turn it on below if you want it.';
  } else if (notes == null) {
    reason = 'With $memory GB, this Mac runs Turbo and AI formatting together '
        'easily. Meeting notes are another ~12 GB download — add them below '
        'if you record meetings.';
  } else {
    reason = 'With $memory GB, this Mac can run everything: the most accurate '
        'speech model, AI formatting and meeting notes.';
  }

  final shrunkForDisk = memory >= 16 && speech.id != 'large-v3-turbo';
  return SetupRecommendation(
    speechModelId: speech.id,
    aiFormatting: formatting,
    notesModelTag: notes,
    reason: shrunkForDisk
        ? '$reason A smaller speech model is suggested because disk space is low.'
        : reason,
  );
}
