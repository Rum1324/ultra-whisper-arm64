import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultrawhisper/models/model_catalog.dart';
import 'package:ultrawhisper/services/file_downloader.dart';
import 'package:ultrawhisper/services/hardware_probe.dart';
import 'package:ultrawhisper/services/ollama_service.dart';

/// A local stand-in for HuggingFace: serves one blob with Range support, and
/// can redirect first or ignore Range, the two things the real CDN path does.
class _BlobServer {
  _BlobServer(this.blob);

  final List<int> blob;
  late final HttpServer _server;
  bool redirectFirst = false;
  bool ignoreRange = false;
  final List<String?> rangeHeaders = [];

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}/model.bin');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final response = request.response;
      if (redirectFirst && request.uri.path == '/model.bin') {
        response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/cdn/model.bin');
        await response.close();
        return;
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      rangeHeaders.add(range);
      var start = 0;
      if (range != null && !ignoreRange) {
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        if (start >= blob.length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await response.close();
          return;
        }
        response.statusCode = HttpStatus.partialContent;
      }
      response.contentLength = blob.length - start;
      response.add(blob.sublist(start));
      await response.close();
    });
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late Directory dir;
  late _BlobServer server;
  late String sha;
  final blob = List<int>.generate(300000, (i) => Random(7).nextInt(256) ^ (i & 0xff));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('uw-download-test');
    server = _BlobServer(blob);
    await server.start();
    final source = File('${dir.path}/source.bin')..writeAsBytesSync(blob);
    sha = await FileDownloader.sha256Of(source.path);
  });

  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  group('FileDownloader', () {
    test('downloads, verifies and renames into place', () async {
      final dest = '${dir.path}/model.bin';
      await FileDownloader.download(
        url: server.url,
        destination: dest,
        sha256: sha,
        expectedBytes: blob.length,
      );
      expect(File(dest).readAsBytesSync(), blob);
      expect(File('$dest.part').existsSync(), isFalse);
    });

    test('resumes from a .part with a Range request', () async {
      final dest = '${dir.path}/model.bin';
      File('$dest.part').writeAsBytesSync(blob.sublist(0, 120000));
      await FileDownloader.download(
        url: server.url,
        destination: dest,
        sha256: sha,
        expectedBytes: blob.length,
      );
      expect(server.rangeHeaders, ['bytes=120000-']);
      expect(File(dest).readAsBytesSync(), blob);
    });

    test('keeps the Range header across a redirect', () async {
      server.redirectFirst = true;
      final dest = '${dir.path}/model.bin';
      File('$dest.part').writeAsBytesSync(blob.sublist(0, 5000));
      await FileDownloader.download(
        url: server.url,
        destination: dest,
        sha256: sha,
        expectedBytes: blob.length,
      );
      expect(server.rangeHeaders, ['bytes=5000-']);
      expect(File(dest).readAsBytesSync(), blob);
    });

    test('starts over when the server ignores Range', () async {
      server.ignoreRange = true;
      final dest = '${dir.path}/model.bin';
      File('$dest.part').writeAsBytesSync(blob.sublist(0, 5000));
      await FileDownloader.download(
        url: server.url,
        destination: dest,
        sha256: sha,
        expectedBytes: blob.length,
      );
      expect(File(dest).readAsBytesSync(), blob);
    });

    test('a complete .part is only verified, not fetched again', () async {
      final dest = '${dir.path}/model.bin';
      File('$dest.part').writeAsBytesSync(blob);
      await FileDownloader.download(
        url: server.url,
        destination: dest,
        sha256: sha,
        expectedBytes: blob.length,
      );
      expect(server.rangeHeaders, isEmpty);
      expect(File(dest).existsSync(), isTrue);
    });

    test('a checksum mismatch leaves nothing to load or resume from', () async {
      final dest = '${dir.path}/model.bin';
      await expectLater(
        FileDownloader.download(
          url: server.url,
          destination: dest,
          sha256: '0' * 64,
          expectedBytes: blob.length,
        ),
        throwsException,
      );
      expect(File(dest).existsSync(), isFalse);
      expect(File('$dest.part').existsSync(), isFalse);
    });

    test('cancel stops it and keeps the .part for a resume', () async {
      final dest = '${dir.path}/model.bin';
      final cancel = DownloadCancel()..cancel();
      await expectLater(
        FileDownloader.download(
          url: server.url,
          destination: dest,
          sha256: sha,
          expectedBytes: blob.length,
          cancel: cancel,
        ),
        throwsA(isA<DownloadCancelledException>()),
      );
      expect(File(dest).existsSync(), isFalse);
    });
  });

  group('PullProgress', () {
    test('sums layers instead of jumping back to 0% at each one', () {
      final progress = PullProgress()
        ..apply({'status': 'pulling manifest'})
        ..apply({'status': 'pulling a', 'digest': 'a', 'total': 100, 'completed': 100})
        ..apply({'status': 'pulling b', 'digest': 'b', 'total': 300, 'completed': 50});
      expect(progress.total, 400);
      expect(progress.completed, 150);
      expect(progress.isDone, isFalse);
      progress.apply({'status': 'success'});
      expect(progress.isDone, isTrue);
    });

    test('an error line throws', () {
      expect(
        () => PullProgress().apply({'error': 'pull model manifest: file does not exist'}),
        throwsException,
      );
    });

    test('a bare tag matches its :latest name', () {
      expect(OllamaService.hasModel({'llama3:latest'}, 'llama3'), isTrue);
      expect(OllamaService.hasModel({'gemma4:e4b'}, 'gemma4:e4b'), isTrue);
      expect(OllamaService.hasModel({'gemma4:e2b'}, 'gemma4:e4b'), isFalse);
    });
  });

  group('HardwareInfo', () {
    test('reads the GPU core count out of ioreg', () {
      expect(HardwareInfo.parseGpuCores('  "gpu-core-count" = 30\n  "x" = 1'), 30);
      expect(HardwareInfo.parseGpuCores(''), isNull);
    });

    test('reads available space out of df -k', () {
      const df = 'Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted on\n'
          '/dev/disk3s5 971350180 653386476 286004828 70% 3925085 2860048280 0% /System/Volumes/Data';
      expect(HardwareInfo.parseDfAvailableBytes(df), 286004828 * 1024);
      expect(HardwareInfo.parseDfAvailableBytes('garbage'), isNull);
    });

    test('memory is in the gigabytes Apple sells', () {
      const mac = HardwareInfo(chip: 'Apple M3 Max', memoryBytes: 38654705664, gpuCores: 30);
      expect(mac.memoryGb, 36);
      expect(mac.summary, 'Apple M3 Max · 36 GB memory · 30-core GPU');
    });
  });

  group('recommendSetup', () {
    HardwareInfo mac(int gb, {int? freeGb}) => HardwareInfo(
          chip: 'Apple M2',
          memoryBytes: gb * (1 << 30),
          freeDiskBytes: freeGb == null ? null : freeGb * 1000 * 1000 * 1000,
        );

    test('8 GB: the light Turbo, no AI', () {
      final r = recommendSetup(mac(8, freeGb: 200));
      expect(r.speechModelId, 'large-v3-turbo-q5_0');
      expect(r.aiFormatting, isFalse);
      expect(r.notesModelTag, isNull);
    });

    test('16 GB: full Turbo, AI left as an opt-in', () {
      final r = recommendSetup(mac(16, freeGb: 200));
      expect(r.speechModelId, 'large-v3-turbo');
      expect(r.aiFormatting, isFalse);
      expect(r.notesModelTag, isNull);
    });

    test('24 and 36 GB: Turbo plus formatting, notes stay opt-in', () {
      for (final gb in [24, 36]) {
        final r = recommendSetup(mac(gb, freeGb: 200));
        expect(r.speechModelId, 'large-v3-turbo');
        expect(r.aiFormatting, isTrue, reason: '$gb GB');
        expect(r.notesModelTag, isNull, reason: '$gb GB');
      }
    });

    test('64 GB: everything, notes on Balanced', () {
      final r = recommendSetup(mac(64, freeGb: 200));
      expect(r.aiFormatting, isTrue);
      expect(r.notesModelTag, contains('UD-Q3_K_XL'));
    });

    test('a full disk shrinks the speech model and drops the AI downloads', () {
      final r = recommendSetup(mac(64, freeGb: 6));
      expect(r.speechModelId, 'large-v3-turbo-q8_0');
      expect(r.aiFormatting, isFalse);
      expect(r.notesModelTag, isNull);
      expect(r.reason, contains('disk space is low'));
    });

    test('every recommendation names a real model', () {
      for (final gb in [8, 16, 18, 24, 32, 36, 48, 64, 128]) {
        for (final free in [1, 3, 20, 500]) {
          final r = recommendSetup(mac(gb, freeGb: free));
          expect(speechModelById(r.speechModelId), isNotNull);
          if (r.aiFormatting) expect(gb, greaterThanOrEqualTo(kMinMemoryGbForFormatting));
          if (r.notesModelTag != null) expect(gb, greaterThanOrEqualTo(kMinMemoryGbForNotes));
        }
      }
    });
  });

  group('catalog', () {
    test('ids are unique and every model carries a real checksum', () {
      expect({for (final m in kSpeechModels) m.id}.length, kSpeechModels.length);
      for (final model in kSpeechModels) {
        expect(model.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(model.url, startsWith('https://huggingface.co/'));
      }
      expect(speechModelById(kDefaultSpeechModelId), isNotNull);
    });
  });
}
