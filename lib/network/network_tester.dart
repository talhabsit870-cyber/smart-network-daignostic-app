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

  /// Downloads from the first reachable host and computes real throughput
  /// in Mbps, sustaining the transfer over a time window (not just one
  /// fixed-size shot) so that DNS/TLS/TCP-slow-start overhead doesn't
  /// dominate the measurement on higher-bandwidth or higher-latency links.
  static Future<SpeedResult> testDownloadSpeed() async {
    for (final url in _downloadHosts) {
      final client = http.Client();
      try {
        final sample = await _measureStreamedDownload(client, url);
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
        client.close();
      }
    }
    return SpeedResult.failed('All download test servers unreachable');
  }

  /// Repeatedly (re)requests [url] on [client], streaming the response body
  /// and timing only from the first received byte (excluding connection
  /// setup) so the measurement reflects sustained transfer speed rather
  /// than handshake overhead. Stops once enough time and data have been
  /// sampled, capped by [maxDuration]/[maxBytes] so fast links don't pull
  /// down excessive data.
  static Future<_ThroughputSample?> _measureStreamedDownload(
    http.Client client,
    Uri url, {
    Duration minDuration = const Duration(seconds: 3),
    Duration maxDuration = const Duration(seconds: 10),
    int minBytes = 3 * 1024 * 1024,
    int maxBytes = 20 * 1024 * 1024,
    int maxAttempts = 25,
  }) async {
    final stopwatch = Stopwatch();
    int totalBytes = 0;
    int attempts = 0;

    while (attempts < maxAttempts &&
        (!stopwatch.isRunning || stopwatch.elapsed < maxDuration)) {
      attempts++;
      http.StreamedResponse response;
      try {
        response = await client
            .send(http.Request('GET', url))
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        break;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) break;

      bool enoughData = false;
      try {
        await for (final chunk in response.stream) {
          if (!stopwatch.isRunning) stopwatch.start();
          totalBytes += chunk.length;
          if (totalBytes >= maxBytes ||
              stopwatch.elapsed >= maxDuration ||
              (stopwatch.elapsed >= minDuration && totalBytes >= minBytes)) {
            enoughData = true;
            break;
          }
        }
      } catch (_) {
        break;
      }

      if (enoughData) break;
    }

    if (totalBytes == 0 || !stopwatch.isRunning && stopwatch.elapsedMilliseconds == 0) {
      return null;
    }
    final seconds = stopwatch.elapsedMilliseconds / 1000.0;
    if (seconds <= 0) return null;
    return _ThroughputSample(totalBytes, seconds);
  }

  /// Uploads random in-memory payloads and computes real upload throughput
  /// in Mbps. A small untimed warm-up request absorbs the connection
  /// handshake first, then timed payloads are sent back-to-back over the
  /// same (kept-alive) connection until a sustained sample is collected.
  static Future<SpeedResult> testUploadSpeed({int chunkBytes = 512 * 1024}) async {
    const minDuration = Duration(seconds: 3);
    const maxDuration = Duration(seconds: 10);
    const maxAttempts = 20;

    final client = http.Client();
    try {
      try {
        await client
            .post(
              _uploadHost,
              headers: {'Content-Type': 'application/octet-stream'},
              body: _randomPayload(8 * 1024),
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        return SpeedResult.failed('Could not reach upload test server');
      }

      final stopwatch = Stopwatch();
      int totalBytes = 0;
      int attempts = 0;

      while (attempts < maxAttempts && stopwatch.elapsed < maxDuration) {
        attempts++;
        stopwatch.start();
        http.Response response;
        try {
          response = await client
              .post(
                _uploadHost,
                headers: {'Content-Type': 'application/octet-stream'},
                body: _randomPayload(chunkBytes),
              )
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          break;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) break;
        totalBytes += chunkBytes;
        if (stopwatch.elapsed >= minDuration) break;
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
    } finally {
      client.close();
    }
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
