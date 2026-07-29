import 'dart:convert';
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

/// Result of a bufferbloat check: how much round-trip latency increases
/// while the link is saturated with download traffic, compared to its idle
/// baseline. Fast throughput and healthy latency-under-load are independent
/// properties — this is what a plain speed test misses and what actually
/// explains a video call or game stuttering even though a download test
/// looks fine.
class BufferbloatResult {
  final bool success;
  final double? idleMs;
  final double? loadedMs;
  final double? increaseMs;
  final String grade;
  final String? error;

  const BufferbloatResult({
    required this.success,
    this.idleMs,
    this.loadedMs,
    this.increaseMs,
    this.grade = '--',
    this.error,
  });

  factory BufferbloatResult.failed(String error) =>
      BufferbloatResult(success: false, error: error);
}

/// Result of a public IP / ISP lookup.
class IpInfoResult {
  final bool success;
  final String? ip;
  final String? isp;
  final String? city;
  final String? country;
  final String? error;

  const IpInfoResult({
    required this.success,
    this.ip,
    this.isp,
    this.city,
    this.country,
    this.error,
  });

  factory IpInfoResult.failed(String error) =>
      IpInfoResult(success: false, error: error);
}

/// Real network testing logic — uses actual HTTP requests, no placeholders.
///
/// All hosts are Cloudflare-operated (`speed.cloudflare.com`, `1.1.1.1`) and
/// send `Access-Control-Allow-Origin: *`, so every probe works identically
/// on native and Flutter Web — plain hosts like google.com or proof.ovh.net
/// send no CORS headers at all and get silently blocked by the browser on
/// web regardless of network quality. The fallback host per probe exists
/// for redundancy against an outage on the primary, not for CORS.
class NetworkTester {
  // speed.cloudflare.com / 1.1.1.1 are Cloudflare-operated, CORS-enabled
  // (Access-Control-Allow-Origin: *) on every endpoint used here, so they
  // work identically on native and Flutter Web — unlike google.com or
  // proof.ovh.net (no CORS headers at all, silently blocked on web) or
  // httpbin.org (a best-effort public demo service with no uptime
  // guarantee that has been observed returning 503s).
  static final Uri _primaryPingHost =
      Uri.parse('https://speed.cloudflare.com/cdn-cgi/trace');
  static final Uri _fallbackPingHost = Uri.parse('https://1.1.1.1/cdn-cgi/trace');

  static final List<Uri> _downloadHosts = [
    Uri.parse('https://speed.cloudflare.com/__down?bytes=25000000'),
    Uri.parse('https://proof.ovh.net/files/10Mb.dat'),
  ];

  static final Uri _uploadHost = Uri.parse('https://speed.cloudflare.com/__up');

  // ipwho.is is CORS-enabled (Access-Control-Allow-Origin: *), needs no API
  // key, and returns public IP + ISP/org name in a single call — unlike
  // ipapi.co (fronted by a JS bot-challenge that blocks plain HTTP clients)
  // or Cloudflare's own /meta endpoint (silently 403s without a browser-like
  // Referer/Origin header, which is too fragile to depend on).
  static final Uri _ipInfoHost = Uri.parse('https://ipwho.is/');

  // Fallback if ipwho.is is down or rate-limited. ipify only returns the
  // bare IP (no ISP/city/country), but it's a long-standing, CORS-enabled,
  // no-key, HTTPS-only service — degraded info beats a hard failure.
  static final Uri _ipFallbackHost =
      Uri.parse('https://api.ipify.org?format=json');

  /// Sends [attempts] probes against a single reachable host and reports
  /// sent/received counts plus per-probe round-trip times.
  static Future<PingStats> testPingDetailed({int attempts = 6}) async {
    final candidates = <MapEntry<Uri, Future<void> Function(Uri)>>[
      MapEntry(_primaryPingHost,
          (uri) => http.get(uri).timeout(const Duration(seconds: 3))),
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

  /// Downloads from the first reachable host over [streams] concurrent
  /// connections and computes aggregate real throughput in Mbps. A single
  /// TCP stream's window caps out well below what fast (100+ Mbps) links can
  /// actually deliver — Speedtest/Fast.com/nPerf all measure this way for
  /// the same reason.
  static Future<SpeedResult> testDownloadSpeed({int streams = 4}) async {
    for (final url in _downloadHosts) {
      final clients = List.generate(streams, (_) => http.Client());
      try {
        final sample = await _measureParallelDownload(clients, url);
        if (sample != null) {
          final mbps = (sample.bytes * 8) / (sample.seconds * 1000000);
          return SpeedResult(
            success: true,
            mbps: mbps,
            bytes: sample.bytes,
            seconds: sample.seconds,
            source: url.host,
          );
        }
      } catch (_) {
        // try next host
      } finally {
        for (final client in clients) {
          client.close();
        }
      }
    }
    return SpeedResult.failed('All download test servers unreachable');
  }

  /// Runs one concurrent streamed download per [clients] entry against
  /// [url], summing bytes across all of them against a single shared clock.
  /// Timing starts on the first byte received on any stream (excluding
  /// connection setup) and each stream re-requests if the response body
  /// ends before [maxDuration]/[maxBytesPerStream] is reached, capped by
  /// [maxAttemptsPerStream] so a run of empty 2xx responses can't spin
  /// forever waiting for a byte that starts the clock.
  static Future<_ThroughputSample?> _measureParallelDownload(
    List<http.Client> clients,
    Uri url, {
    Duration maxDuration = const Duration(seconds: 8),
    int maxBytesPerStream = 30 * 1024 * 1024,
    int maxAttemptsPerStream = 25,
  }) async {
    final stopwatch = Stopwatch();
    int totalBytes = 0;

    Future<void> runStream(http.Client client) async {
      int attempts = 0;
      while (attempts < maxAttemptsPerStream &&
          (!stopwatch.isRunning || stopwatch.elapsed < maxDuration)) {
        attempts++;
        http.StreamedResponse response;
        try {
          response = await client
              .send(http.Request('GET', url))
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) return;

        int streamBytes = 0;
        try {
          await for (final chunk in response.stream) {
            if (!stopwatch.isRunning) stopwatch.start();
            totalBytes += chunk.length;
            streamBytes += chunk.length;
            if (streamBytes >= maxBytesPerStream ||
                stopwatch.elapsed >= maxDuration) {
              return;
            }
          }
        } catch (_) {
          return;
        }
      }
    }

    await Future.wait(clients.map(runStream));
    stopwatch.stop();

    if (totalBytes == 0 || stopwatch.elapsedMilliseconds == 0) {
      return null;
    }
    final seconds = stopwatch.elapsedMilliseconds / 1000.0;
    if (seconds <= 0) return null;
    return _ThroughputSample(totalBytes, seconds);
  }

  /// Uploads random in-memory payloads over [streams] concurrent connections
  /// and computes aggregate upload throughput in Mbps, for the same reason
  /// download is measured over multiple streams. A small untimed warm-up
  /// request absorbs the first connection's handshake before timing starts;
  /// the upload payload itself is generated once and reused across every
  /// request on every stream so the (CPU-bound) random-fill work never lands
  /// inside the measured window.
  static Future<SpeedResult> testUploadSpeed({
    int chunkBytes = 512 * 1024,
    int streams = 4,
  }) async {
    const maxDuration = Duration(seconds: 8);
    const maxAttemptsPerStream = 40;

    final warmupClient = http.Client();
    try {
      await warmupClient
          .post(
            _uploadHost,
            headers: {'Content-Type': 'application/octet-stream'},
            body: _randomPayload(8 * 1024),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return SpeedResult.failed('Could not reach upload test server');
    } finally {
      warmupClient.close();
    }

    final payload = _randomPayload(chunkBytes);
    final clients = List.generate(streams, (_) => http.Client());
    final stopwatch = Stopwatch()..start();
    int totalBytes = 0;

    Future<void> runStream(http.Client client) async {
      int attempts = 0;
      while (attempts < maxAttemptsPerStream && stopwatch.elapsed < maxDuration) {
        attempts++;
        http.Response response;
        try {
          response = await client
              .post(
                _uploadHost,
                headers: {'Content-Type': 'application/octet-stream'},
                body: payload,
              )
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) return;
        totalBytes += chunkBytes;
      }
    }

    try {
      await Future.wait(clients.map(runStream));
    } finally {
      for (final client in clients) {
        client.close();
      }
    }
    stopwatch.stop();

    if (totalBytes == 0 || stopwatch.elapsedMilliseconds <= 0) {
      return SpeedResult.failed('Upload too fast to measure');
    }

    final seconds = stopwatch.elapsedMilliseconds / 1000.0;
    final mbps = (totalBytes * 8) / (seconds * 1000000);
    return SpeedResult(
      success: true,
      mbps: mbps,
      bytes: totalBytes,
      seconds: seconds,
      source: _uploadHost.host,
    );
  }

  /// Measures how much round-trip latency increases while the link is
  /// saturated with concurrent download traffic, graded like Waveform's
  /// bufferbloat test (A+ down to F). Reuses [idlePing] — already measured
  /// moments earlier by the normal ping phase on an otherwise-idle link —
  /// as the baseline instead of re-measuring it, so idle and loaded latency
  /// come from the same host and probe method.
  static Future<BufferbloatResult> testBufferbloat({
    required PingStats idlePing,
    Duration loadDuration = const Duration(seconds: 5),
    int saturationStreams = 3,
  }) async {
    final idleMs = idlePing.avgMs;
    if (idleMs == null) {
      return BufferbloatResult.failed('No idle latency baseline available');
    }

    final saturationClients =
        List.generate(saturationStreams, (_) => http.Client());
    final pingClient = http.Client();
    final stopwatch = Stopwatch()..start();
    final loadedRtts = <int>[];

    Future<void> saturate(http.Client client) async {
      while (stopwatch.elapsed < loadDuration) {
        http.StreamedResponse response;
        try {
          response = await client
              .send(http.Request('GET', _downloadHosts.first))
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) return;
        try {
          await for (final _ in response.stream) {
            if (stopwatch.elapsed >= loadDuration) return;
          }
        } catch (_) {
          return;
        }
      }
    }

    Future<void> pingUnderLoad() async {
      while (stopwatch.elapsed < loadDuration) {
        final probe = Stopwatch()..start();
        try {
          await pingClient
              .get(_primaryPingHost)
              .timeout(const Duration(seconds: 3));
          probe.stop();
          loadedRtts.add(probe.elapsedMilliseconds);
        } catch (_) {
          probe.stop();
        }
      }
    }

    try {
      await Future.wait([
        ...saturationClients.map(saturate),
        pingUnderLoad(),
      ]);
    } finally {
      for (final client in saturationClients) {
        client.close();
      }
      pingClient.close();
    }

    if (loadedRtts.isEmpty) {
      return BufferbloatResult.failed('Could not measure latency under load');
    }

    // Median, not mean: the ping probes above share an isolate with the
    // saturation downloads, so event-loop queuing produces occasional
    // outliers that would skew an average.
    final loadedMs = _median(loadedRtts);
    final increaseMs = loadedMs - idleMs;
    return BufferbloatResult(
      success: true,
      idleMs: idleMs,
      loadedMs: loadedMs,
      increaseMs: increaseMs,
      grade: _bufferbloatGrade(increaseMs),
    );
  }

  static double _median(List<int> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid].toDouble();
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static String _bufferbloatGrade(double increaseMs) {
    if (increaseMs < 5) return 'A+';
    if (increaseMs < 30) return 'A';
    if (increaseMs < 60) return 'B';
    if (increaseMs < 200) return 'C';
    if (increaseMs < 400) return 'D';
    return 'F';
  }

  /// Looks up the device's public-facing IP address and the ISP/organization
  /// that owns it, for display alongside the local connection type. Falls
  /// back to an IP-only lookup if the primary (richer) service is
  /// unreachable or rate-limited, so a single provider outage doesn't blank
  /// out the whole field.
  static Future<IpInfoResult> testPublicIpInfo() async {
    try {
      final response = await http
          .get(_ipInfoHost)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] != false) {
          final connection = json['connection'] as Map<String, dynamic>?;
          final isp = (connection?['isp'] as String?)?.trim();
          final org = (connection?['org'] as String?)?.trim();
          return IpInfoResult(
            success: true,
            ip: json['ip'] as String?,
            isp: (isp != null && isp.isNotEmpty) ? isp : org,
            city: json['city'] as String?,
            country: json['country'] as String?,
          );
        }
      }
    } catch (_) {
      // fall through to the fallback host
    }

    try {
      final response = await http
          .get(_ipFallbackHost)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return IpInfoResult.failed('Lookup server returned ${response.statusCode}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return IpInfoResult(success: true, ip: json['ip'] as String?);
    } catch (_) {
      return IpInfoResult.failed('Could not reach IP lookup service');
    }
  }

  static Uint8List _randomPayload(int bytes) {
    final random = Random();
    final payload = Uint8List(bytes);
    for (int i = 0; i < bytes; i++) {
      payload[i] = random.nextInt(256);
    }
    return payload;
  }
}

/// Bytes transferred and the wall-clock time (excluding connection setup)
/// it took to transfer them, used to derive a throughput sample.
class _ThroughputSample {
  final int bytes;
  final double seconds;
  const _ThroughputSample(this.bytes, this.seconds);
}
