import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/websocket_messages.dart';
import '../utils/logger.dart';

/// Writes finished meetings to disk.
///
/// The transcript is the deliverable that must survive: notes need Ollama and
/// degrade to unavailable without it, but the transcript exists the moment the
/// meeting ends. So it is written first and separately — a failed or absent
/// summary must never cost the user the words that were actually said.
class TranscriptArchive {
  /// Where meetings are saved when the setting is left empty.
  static String defaultDirectory() {
    final home = Platform.environment['HOME'] ?? '';
    return path.join(home, 'Documents', 'UltraWhisper');
  }

  static String resolveDirectory(String configured) =>
      configured.trim().isEmpty ? defaultDirectory() : configured.trim();

  /// A filename-safe stem like `2026-08-25 14-32 Zoom`.
  static String _stem(DateTime when, String? title) {
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${when.year}-${two(when.month)}-${two(when.day)} '
        '${two(when.hour)}-${two(when.minute)}';
    final name = (title ?? '').trim();
    if (name.isEmpty) return '$stamp Meeting';
    // Strip what the filesystem and Finder object to, not everything
    // non-ASCII — meeting titles are routinely Japanese here.
    final safe = name.replaceAll(RegExp(r'[/\\:\x00-\x1f]'), ' ').trim();
    return safe.isEmpty ? '$stamp Meeting' : '$stamp $safe';
  }

  /// Write the transcript, and the note when one exists.
  ///
  /// Returns the paths written. Never throws: losing a meeting to an
  /// unwritable folder would be worse than losing the file, and the caller
  /// still holds everything in memory.
  static Future<List<String>> save({
    required String directory,
    required List<TranscriptSegment> transcript,
    required String transcriptText,
    String? title,
    String? noteMarkdown,
    DateTime? when,
  }) async {
    if (transcript.isEmpty && (noteMarkdown ?? '').isEmpty) return const [];

    final written = <String>[];
    try {
      final root = Directory(resolveDirectory(directory));
      if (!root.existsSync()) root.createSync(recursive: true);

      final stem = _stem(when ?? DateTime.now(), title);

      if (transcript.isNotEmpty) {
        final file = File(path.join(root.path, '$stem — transcript.md'));
        file.writeAsStringSync(
          '# ${title ?? 'Meeting'}\n\n'
          '_${(when ?? DateTime.now()).toLocal()}_\n\n'
          '$transcriptText\n',
        );
        written.add(file.path);
      }

      if ((noteMarkdown ?? '').trim().isNotEmpty) {
        final file = File(path.join(root.path, '$stem — notes.md'));
        file.writeAsStringSync('${noteMarkdown!.trim()}\n');
        written.add(file.path);
      }

      AppLogger.success('Saved meeting to ${root.path}');
    } catch (e) {
      AppLogger.error('Could not save the meeting transcript', e);
    }
    return written;
  }
}
