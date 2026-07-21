import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Result of a batch of latency probes against a single host: how many
/// were sent, how many came back, and the round-trip time of each success —
/// from which loss %, min/avg/max latency and jitter are all derived.
class PingStats {
  final String host;
  final int sent;
  final int received;
  final List<int> rttsMs;

  const PingStats({
    required this.host,
    required this.sent,
    required this.received,
    required this.rttsMs,
  });

  int get lost => sent - received;
  double get lossPercent => sent == 0 ? 0 : (lost / sent) * 100;

  int? get minMs => rttsMs.isEmpty ? null : rttsMs.reduce(min);
  int? get maxMs => rttsMs.isEmpty ? null : rttsMs.reduce(max);
  double? get avgMs =>
      rttsMs.isEmpty ? null : rttsMs.reduce((a, b) => a + b) / rttsMs.length;

  /// Average absolute difference between consecutive RTTs.
  double? get jitterMs {
    if (rttsMs.length < 2) return null;
    double total = 0;
    for (int i = 1; i < rttsMs.length; i++) {
      total += (rttsMs[i] - rttsMs[i - 1]).abs();
    }
    return total / (rttsMs.length - 1);
  }

  static PingStats unreachable(int attempts) =>
      PingStats(host: 'unreachable', sent: attempts, received: 0, rttsMs: const []);
}

/// Result of a download/upload throughput measurement.
class SpeedResult {
  final bool success;
  final double mbps;
  final int bytes;
  final double seconds;
  final String? source;
  final String? error;

  const SpeedResult({
    required this.success,
    this.mbps = 0,
    this.bytes = 0,
    this.seconds = 0,
    this.source,
    this.error,
  });

  factory SpeedResult.failed(String error) =>
      SpeedResult(success: false, error: error);
}

/// Real network testing logic — uses actual HTTP requests, no placeholders.
///
/// Every probe tries a direct, fast host first (works great on Android/iOS/
/// desktop) and falls back to a CORS-open host if that fails — on Flutter
/// Web, direct cross-origin requests to hosts like google.com are blocked
/// by the browser before they ever reach the network, so without a
/// CORS-friendly fallback every test silently fails on web.
class NetworkTester {
  static final Uri _primaryPingHost = Uri.parse('https://www.google.com');
  static final Uri _fallbackPingHost = Uri.parse('https://httpbin.org/get');

  static final List<Uri> _downloadHosts = [
    Uri.parse('https://proof.ovh.net/files/1Mb.dat'),
    Uri.parse('https://httpbin.org/bytes/1000000'),
  ];

  static final Uri _uploadHost = Uri.parse('https://httpbin.org/post');

  /// Sends [attempts] probes against a single reachable host and reports
  /// sent/received counts plus per-probe round-trip times.
  static Future<PingStats> testPingDetailed({int attempts = 6}) async {
    final candidates = <MapEntry<Uri, Future<void> Function(Uri)>>[
      MapEntry(_primaryPingHost,
          (uri) => http.head(uri).timeout(const Duration(seconds: 3))),
      MapEntry(_fallbackPingHost,
          (uri) => http.get(uri).timeout(const Duration(seconds: 3))),
    ];

    Uri? host;
    Future<void> Function(Uri)? probe;
    final rtts = <int>[];
    int sent = 0;
    int received = 0;

    for (final candidate in candidates) {
      sent++;
      final stopwatch = Stopwatch()..start();
      try {
        await candidate.value(candidate.key);
        stopwatch.stop();
        host = candidate.key;
        probe = candidate.value;
        received++;
        rtts.add(stopwatch.elapsedMilliseconds);
        break;
      } catch (_) {
        stopwatch.stop();
      }
    }

    if (host == null || probe == null) {
      return PingStats.unreachable(sent);
    }

    for (int i = 1; i < attempts; i++) {
      sent++;
      final stopwatch = Stopwatch()..start();
      try {
        await probe(host);
        stopwatch.stop();
        received++;
        rtts.add(stopwatch.elapsedMilliseconds);
      } catch (_) {
        stopwatch.stop();
      }
    }

    return PingStats(host: host.host, sent: sent, received: received, rttsMs: rtts);
  }

  /// Downloads a known-size file from the first reachable host and computes
  /// real throughput in Mbps.
  static Future<SpeedResult> testDownloadSpeed() async {
    for (final url in _downloadHosts) {
      final stopwatch = Stopwatch()..start();
      try {
        final response = await http.get(url).timeout(const Duration(seconds: 20));
        stopwatch.stop();

        final bytes = response.bodyBytes.length;
        final seconds = stopwatch.elapsedMilliseconds / 1000.0;
        if (seconds <= 0 || bytes == 0) continue;

        final mbps = (bytes * 8) / (seconds * 1000000);
        return SpeedResult(
          success: true,
          mbps: mbps,
          bytes: bytes,
          seconds: seconds,
          source: url.host,
        );
      } catch (_) {
        stopwatch.stop();
      }
    }
    return SpeedResult.failed('All download test servers unreachable');
  }

  /// Uploads a random in-memory payload and computes real upload throughput
  /// in Mbps from the elapsed time.
  static Future<SpeedResult> testUploadSpeed({int bytesToSend = 512 * 1024}) async {
    final random = Random();
    final payload = Uint8List(bytesToSend);
    for (int i = 0; i < bytesToSend; i++) {
      payload[i] = random.nextInt(256);
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await http
          .post(
            _uploadHost,
            headers: {'Content-Type': 'application/octet-stream'},
            body: payload,
          )
          .timeout(const Duration(seconds: 20));
      stopwatch.stop();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return SpeedResult.failed('Upload server returned ${response.statusCode}');
      }

      final seconds = stopwatch.elapsedMilliseconds / 1000.0;
      if (seconds <= 0) return SpeedResult.failed('Upload too fast to measure');

      final mbps = (bytesToSend * 8) / (seconds * 1000000);
      return SpeedResult(
        success: true,
        mbps: mbps,
        bytes: bytesToSend,
        seconds: seconds,
        source: _uploadHost.host,
      );
    } catch (_) {
      stopwatch.stop();
      return SpeedResult.failed('Could not reach upload test server');
    }
  }
}
