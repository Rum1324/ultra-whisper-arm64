import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultrawhisper/models/websocket_messages.dart';
import 'package:ultrawhisper/services/transcript_archive.dart';

TranscriptSegment seg(String speaker, String text) =>
    TranscriptSegment(t0: 0, t1: 1, speaker: speaker, text: text);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('uw-archive-'));
  tearDown(() => temp.deleteSync(recursive: true));

  final when = DateTime(2026, 8, 25, 14, 32);

  test('writes the transcript even when there is no note', () async {
    final written = await TranscriptArchive.save(
      directory: temp.path,
      transcript: [seg('me', 'hello'), seg('them', 'hi')],
      transcriptText: '[00:00:00] Me: hello\n[00:00:00] Them: hi',
      title: 'Zoom',
      when: when,
    );

    expect(written, hasLength(1));
    final file = File(written.single);
    expect(file.existsSync(), isTrue);
    expect(file.path, contains('2026-08-25 14-32 Zoom'));
    expect(file.readAsStringSync(), contains('Them: hi'));
  });

  test('writes both files when a note exists', () async {
    final written = await TranscriptArchive.save(
      directory: temp.path,
      transcript: [seg('me', 'hello')],
      transcriptText: 'Me: hello',
      title: 'Meet',
      noteMarkdown: '# Notes\n- did a thing',
      when: when,
    );

    expect(written, hasLength(2));
    expect(written.where((p) => p.endsWith('transcript.md')), hasLength(1));
    expect(written.where((p) => p.endsWith('notes.md')), hasLength(1));
  });

  test('an empty meeting writes nothing', () async {
    expect(
      await TranscriptArchive.save(
        directory: temp.path,
        transcript: const [],
        transcriptText: '',
        when: when,
      ),
      isEmpty,
    );
    expect(temp.listSync(), isEmpty);
  });

  test('creates the directory when it does not exist', () async {
    final nested = '${temp.path}/a/b/c';
    final written = await TranscriptArchive.save(
      directory: nested,
      transcript: [seg('me', 'hi')],
      transcriptText: 'Me: hi',
      when: when,
    );
    expect(written, hasLength(1));
    expect(Directory(nested).existsSync(), isTrue);
  });

  test('an unwritable directory is survived, not thrown', () async {
    // Losing the file is bad; losing the meeting because saving threw is worse.
    expect(
      await TranscriptArchive.save(
        directory: '/System/nope/definitely-not-writable',
        transcript: [seg('me', 'hi')],
        transcriptText: 'Me: hi',
        when: when,
      ),
      isEmpty,
    );
  });

  test('path separators in a title cannot escape the folder', () async {
    final written = await TranscriptArchive.save(
      directory: temp.path,
      transcript: [seg('me', 'hi')],
      transcriptText: 'Me: hi',
      title: '../../etc/passwd',
      when: when,
    );
    expect(written, hasLength(1));
    expect(File(written.single).parent.path, temp.path);
  });

  test('a non-ASCII title is kept, not stripped', () async {
    final written = await TranscriptArchive.save(
      directory: temp.path,
      transcript: [seg('me', 'hi')],
      transcriptText: 'Me: hi',
      title: '定例ミーティング',
      when: when,
    );
    expect(written.single, contains('定例ミーティング'));
  });

  test('an empty configured directory resolves to the default', () {
    expect(TranscriptArchive.resolveDirectory('  '),
        TranscriptArchive.defaultDirectory());
    expect(TranscriptArchive.resolveDirectory('/tmp/x'), '/tmp/x');
  });
}
