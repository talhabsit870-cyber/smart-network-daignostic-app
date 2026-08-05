import 'package:connectivity_plus/connectivity_plus.dart';

import '../network/device_status.dart';
import '../network/network_tester.dart';

enum DiagnosisVerdict {
  allGood,
  ispIssue,
  routerIssue,
  deviceIssue,
  inconclusive,
}

/// A human-readable diagnosis: what's wrong (if anything), the numbers that
/// led to that conclusion, and what the user should do about it.
class DiagnosisResult {
  final DiagnosisVerdict verdict;
  final String title;
  final String detail;
  final String recommendation;

  const DiagnosisResult({
    required this.verdict,
    required this.title,
    required this.detail,
    required this.recommendation,
  });
}

/// One full round of network measurements, tagged with the connection type
/// that was active while they were taken.
class NetworkSnapshot {
  final String connectionLabel;
  final PingStats ping;
  final SpeedResult download;
  final SpeedResult upload;
  final DeviceStatus? deviceStatus;
  final BufferbloatResult? bufferbloat;
  final PathCheckResult? pathCheck;

  const NetworkSnapshot({
    required this.connectionLabel,
    required this.ping,
    required this.download,
    required this.upload,
    this.deviceStatus,
    this.bufferbloat,
    this.pathCheck,
  });

  bool get isSlow =>
      !download.success ||
      ping.received == 0 ||
      ping.lossPercent >= 5 ||
      (ping.avgMs ?? 0) > 150 ||
      download.mbps < 5;
}

class DiagnosisEngine {
  static String labelFor(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return 'Wi-Fi';
    if (results.contains(ConnectivityResult.mobile)) return 'Mobile Data';
    if (results.contains(ConnectivityResult.ethernet)) return 'Ethernet';
    if (results.contains(ConnectivityResult.vpn)) return 'VPN';
    if (results.isEmpty || results.contains(ConnectivityResult.none)) return 'Offline';
    return 'Unknown';
  }

  /// Single-run heuristic, strengthened with hop-level evidence from
  /// [NetworkSnapshot.pathCheck] when available. The base heuristic
  /// ([_evaluateBase]) is unchanged from before the path check existed;
  /// [_applyPathCheck] only adds evidence on top of it.
  static DiagnosisResult evaluateSingle(NetworkSnapshot snapshot) {
    final base = _evaluateBase(snapshot);
    return _applyPathCheck(base, snapshot.pathCheck);
  }

  /// Enough signal to flag a problem, not enough to pin the blame on ISP vs
  /// router with certainty — see [_applyPathCheck] for the evidence that can
  /// narrow it down further.
  static DiagnosisResult _evaluateBase(NetworkSnapshot snapshot) {
    final ping = snapshot.ping;
    final download = snapshot.download;

    // Battery saver / Low Power Mode throttles background data on mobile —
    // checked before any other verdict so it isn't mistaken for a carrier
    // problem.
    if (snapshot.connectionLabel == 'Mobile Data' &&
        snapshot.deviceStatus?.isLowPowerMode == true &&
        snapshot.isSlow) {
      return const DiagnosisResult(
        verdict: DiagnosisVerdict.deviceIssue,
        title: 'Low Power Mode is on',
        detail: 'This device is in battery saver / Low Power Mode while on '
            'Mobile Data, which throttles background data and can look '
            'identical to a real carrier problem.',
        recommendation: 'Turn off battery saver / Low Power Mode and re-run '
            'the test before blaming your mobile network.',
      );
    }

    if (ping.received == 0 && !download.success) {
      return const DiagnosisResult(
        verdict: DiagnosisVerdict.ispIssue,
        title: 'No usable connection',
        detail: 'Every ping and the download test failed to reach a server.',
        recommendation: 'Check that this device is actually online. If it is, '
            'this points to an ISP outage — contact your ISP or try mobile data.',
      );
    }

    if (ping.lossPercent >= 20 || (ping.avgMs ?? 0) > 400) {
      return DiagnosisResult(
        verdict: DiagnosisVerdict.ispIssue,
        title: 'Severe connection instability',
        detail: '${ping.lossPercent.toStringAsFixed(0)}% packet loss, '
            '${ping.avgMs?.toStringAsFixed(0) ?? '--'}ms average latency on ${snapshot.connectionLabel}.',
        recommendation: 'This level of loss/latency usually means an ISP-side '
            'problem. Contact your ISP if it persists.',
      );
    }

    if (snapshot.isSlow) {
      return DiagnosisResult(
        verdict: DiagnosisVerdict.inconclusive,
        title: 'Degraded connection detected',
        detail: '${download.success ? '${download.mbps.toStringAsFixed(1)} Mbps download' : 'download failed'}, '
            '${ping.avgMs?.toStringAsFixed(0) ?? '--'}ms ping, '
            '${ping.lossPercent.toStringAsFixed(0)}% loss on ${snapshot.connectionLabel}.',
        recommendation: 'Could be your router, your ISP, or this device. Try '
            'restarting your router, then re-run the test.',
      );
    }

    return DiagnosisResult(
      verdict: DiagnosisVerdict.allGood,
      title: 'Connection looks healthy',
      detail: '${download.mbps.toStringAsFixed(1)} Mbps down, '
          '${ping.avgMs?.toStringAsFixed(0) ?? '--'}ms ping, '
          '${ping.lossPercent.toStringAsFixed(0)}% loss.',
      recommendation: 'No action needed.',
    );
  }

  /// Additive-only: strengthens (or, in the gateway/inconclusive case,
  /// upgrades) [base] using hop-level evidence from [pathCheck]. Returns
  /// [base] verbatim when there's no usable path data, so existing
  /// behavior is unchanged whenever a path check wasn't run or failed.
  static DiagnosisResult _applyPathCheck(
      DiagnosisResult base, PathCheckResult? pathCheck) {
    if (pathCheck == null || !pathCheck.success || pathCheck.hops.isEmpty) {
      return base;
    }

    final hops = pathCheck.hops;
    final target = hops.last;
    final gatewayHops = pathCheck.method == PathCheckMethod.approximatePath
        ? hops.where((h) => h.label == 'Gateway')
        : hops.where((h) => h.hopNumber <= 2);
    final midHops =
        hops.where((h) => h != target && !gatewayHops.contains(h));

    int? minRtt(Iterable<PathHop> list) {
      final rtts = list
          .where((h) => !h.timedOut && h.rttMs != null)
          .map((h) => h.rttMs!)
          .toList();
      return rtts.isEmpty ? null : rtts.reduce((a, b) => a < b ? a : b);
    }

    final gatewayRtt = minRtt(gatewayHops);
    final midRtt = minRtt(midHops);
    final targetRtt = target.timedOut ? null : target.rttMs;

    const slowThresholdMs = 150;
    final earlyHopsClean =
        (gatewayRtt == null || gatewayRtt < slowThresholdMs) &&
            (midRtt == null || midRtt < slowThresholdMs);

    // Only the final hop is slow/unresponsive, everything before it is
    // clean -> likely the target server, not the user's network.
    if (earlyHopsClean &&
        (target.timedOut ||
            (targetRtt != null && targetRtt >= slowThresholdMs))) {
      return DiagnosisResult(
        verdict: base.verdict,
        title: base.title,
        detail: '${base.detail} Path check: the rest of the path responded '
            'quickly and only the final hop was slow — likely the target '
            'server, not your network.',
        recommendation: base.recommendation,
      );
    }

    // Latency starts right at the gateway -> local Wi-Fi/router signal.
    if (gatewayRtt != null && gatewayRtt >= slowThresholdMs) {
      final dominant = targetRtt == null || gatewayRtt >= targetRtt * 0.7;
      if (base.verdict == DiagnosisVerdict.inconclusive && dominant) {
        return DiagnosisResult(
          verdict: DiagnosisVerdict.routerIssue,
          title: 'Router issue',
          detail: '${base.detail} Path check: latency starts right at your '
              'gateway (${gatewayRtt}ms), pointing to your router/Wi-Fi '
              'rather than your ISP.',
          recommendation: 'Restart your router, move closer to it, or check '
              'for interference.',
        );
      }
      return DiagnosisResult(
        verdict: base.verdict,
        title: base.title,
        detail: '${base.detail} Path check: latency starts right at your '
            'gateway (${gatewayRtt}ms), which points toward your '
            'router/Wi-Fi.',
        recommendation: base.recommendation,
      );
    }

    // Latency appears mid-path with a clean gateway -> ISP/upstream signal.
    if (midRtt != null && midRtt >= slowThresholdMs) {
      return DiagnosisResult(
        verdict: base.verdict,
        title: base.title,
        detail: '${base.detail} Path check: latency appears mid-path '
            '(${midRtt}ms), suggesting ISP/upstream congestion rather than '
            'your local network.',
        recommendation: base.recommendation,
      );
    }

    return base;
  }
}
