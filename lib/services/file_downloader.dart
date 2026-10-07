import 'dart:async';
import 'dart:io';

/// Lets the caller stop a download from outside it.
class DownloadCancel {
  bool _cancelled = false;
  HttpClient? _client;

  bool get isCancelled => _cancelled;

  /// The client to abort on [cancel]. A cancel that arrived first aborts it
  /// straight away.
  void attach(HttpClient client) {
    _client = client;
    if (_cancelled) client.close(force: true);
  }

  void cancel() {
    _cancelled = true;
    // Closing with force aborts the response stream mid-chunk, so a 1.6 GB
    // download stops now rather than at the next chunk boundary.
    _client?.close(force: true);
  }
}

class DownloadCancelledException implements Exception {
  @override
  String toString() => 'Download cancelled';
}

/// Downloads one large file, resumably, and verifies it before anyone sees it.
///
/// Bytes land in `<destination>.part` and are renamed into place only after
/// the SHA-256 matches. A crash, a closed laptop or a cancel leaves the
/// `.part` behind, and the next attempt resumes from it with a Range request
/// instead of starting the 1.6 GB over. A file at [destination] is therefore
/// always complete and correct — the backend never loads a truncated model.
class FileDownloader {
  FileDownloader._();

  static const _maxRedirects = 8;

  static Future<void> download({
    required Uri url,
    required String destination,
    required String sha256,
    int? expectedBytes,
    void Function(int received, int total)? onProgress,
    void Function()? onVerifying,
    DownloadCancel? cancel,
  }) async {
    final part = File('$destination.part');
    await part.parent.create(recursive: true);

    var resumeFrom = await part.exists() ? await part.length() : 0;
    final alreadyComplete = expectedBytes != null && resumeFrom == expectedBytes;

    if (!alreadyComplete) {
      if (expectedBytes != null && resumeFrom > expectedBytes) {
        await part.delete();
        resumeFrom = 0;
      }
      await _fetch(
        url: url,
        part: part,
        resumeFrom: resumeFrom,
        expectedBytes: expectedBytes,
        onProgress: onProgress,
        cancel: cancel,
      );
    }

    onVerifying?.call();
    final actual = await sha256Of(part.path);
    if (actual != sha256.toLowerCase()) {
      // Never resume from a corrupt file: the bad bytes would be kept forever.
      await part.delete();
      throw Exception('Checksum mismatch for ${url.pathSegments.last}');
    }
    await part.rename(destination);
  }

  static Future<void> _fetch({
    required Uri url,
    required File part,
    required int resumeFrom,
    required int? expectedBytes,
    required void Function(int received, int total)? onProgress,
    required DownloadCancel? cancel,
  }) async {
    final client = HttpClient()..autoUncompress = false;
    cancel?.attach(client);

    try {
      // Redirects are followed by hand. HuggingFace answers with a redirect to
      // its CDN, and the Range header has to survive that hop or a resume
      // silently becomes a full re-download.
      var target = url;
      HttpClientResponse? response;
      for (var hop = 0; hop < _maxRedirects; hop++) {
        if (cancel?.isCancelled ?? false) throw DownloadCancelledException();
        final request = await client.getUrl(target);
        request.followRedirects = false;
        if (resumeFrom > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
        }
        final candidate = await request.close();
        if (candidate.isRedirect) {
          final location = candidate.headers.value(HttpHeaders.locationHeader);
          await candidate.drain<void>();
          if (location == null) throw Exception('Redirect without a location');
          target = target.resolve(location);
          continue;
        }
        response = candidate;
        break;
      }
      if (response == null) throw Exception('Too many redirects');

      // 416: what we have already reaches the end. Let the checksum decide.
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        await response.drain<void>();
        return;
      }

      var received = resumeFrom;
      var mode = FileMode.append;
      if (response.statusCode == HttpStatus.ok) {
        // The server ignored the Range header and is sending everything.
        received = 0;
        mode = FileMode.write;
      } else if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: target);
      }

      final total = expectedBytes ??
          (response.contentLength >= 0 ? received + response.contentLength : -1);

      final sink = part.openWrite(mode: mode);
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (cancel?.isCancelled ?? false) throw DownloadCancelledException();
    } on DownloadCancelledException {
      rethrow;
    } catch (e) {
      // A forced close surfaces as whatever the socket felt like throwing.
      if (cancel?.isCancelled ?? false) throw DownloadCancelledException();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// SHA-256 via `shasum`, which hashes a gigabyte in about a second. Pure Dart
  /// hashing is several times slower and would hold the UI isolate meanwhile.
  static Future<String> sha256Of(String path) async {
    final result = await Process.run('/usr/bin/shasum', ['-a', '256', path]);
    if (result.exitCode != 0) {
      throw Exception('shasum failed: ${result.stderr}');
    }
    return (result.stdout as String).split(RegExp(r'\s+')).first.toLowerCase();
  }
}
