import 'package:connectivity_plus/connectivity_plus.dart';

import 'device_status.dart';
import 'network_tester.dart';

enum DiagnosisVerdict {
  allGood,
  ispIssue,
  routerIssue,
  mobileIssue,
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

  const NetworkSnapshot({
    required this.connectionLabel,
    required this.ping,
    required this.download,
    required this.upload,
    this.deviceStatus,
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

  /// Single-run heuristic. Enough signal to flag a problem, not enough to
  /// pin the blame on ISP vs router — that needs [compare].
  static DiagnosisResult evaluateSingle(NetworkSnapshot snapshot) {
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
            'problem. Run "Compare Wi-Fi vs Mobile" to confirm before calling your ISP.',
      );
    }

    if (snapshot.isSlow) {
      return DiagnosisResult(
        verdict: DiagnosisVerdict.inconclusive,
        title: 'Degraded connection detected',
        detail: '${download.success ? '${download.mbps.toStringAsFixed(1)} Mbps download' : 'download failed'}, '
            '${ping.avgMs?.toStringAsFixed(0) ?? '--'}ms ping, '
            '${ping.lossPercent.toStringAsFixed(0)}% loss on ${snapshot.connectionLabel}.',
        recommendation: 'Could be your router, your ISP, or this device. Tap '
            '"Compare Wi-Fi vs Mobile" to run the same test on the other '
            'connection and pinpoint the cause.',
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

  /// Compares a Wi-Fi run and a Mobile Data run and assigns blame per the
  /// classic ISP/Router/Device rule table:
  /// Wi-Fi slow + Mobile fast -> router issue.
  /// Both slow -> ISP issue.
  /// Mobile slow + Wi-Fi fast -> mobile network issue.
  static DiagnosisResult compare(NetworkSnapshot a, NetworkSnapshot b) {
    final wifi = a.connectionLabel == 'Wi-Fi'
        ? a
        : (b.connectionLabel == 'Wi-Fi' ? b : null);
    final mobile = a.connectionLabel == 'Mobile Data'
        ? a
        : (b.connectionLabel == 'Mobile Data' ? b : null);

    if (wifi == null || mobile == null) {
      return DiagnosisResult(
        verdict: DiagnosisVerdict.inconclusive,
        title: 'Need one Wi-Fi run and one Mobile Data run',
        detail: 'Got "${a.connectionLabel}" and "${b.connectionLabel}" — '
            'both tests used the same connection type.',
        recommendation: 'Switch this device to the other connection type '
            'between runs and try again.',
      );
    }

    final wifiSlow = wifi.isSlow;
    final mobileSlow = mobile.isSlow;

    if (wifiSlow && !mobileSlow) {
      return DiagnosisResult(
        verdict: DiagnosisVerdict.routerIssue,
        title: 'Router issue',
        detail: 'Wi-Fi is slow (${wifi.download.mbps.toStringAsFixed(1)} Mbps, '
            '${wifi.ping.lossPercent.toStringAsFixed(0)}% loss) but mobile data '
            'is fine (${mobile.download.mbps.toStringAsFixed(1)} Mbps).',
        recommendation: 'Restart your router, move closer to it, or check for '
            'interference. Your ISP connection itself is fine.',
      );
    }

    if (wifiSlow && mobileSlow) {
      return DiagnosisResult(
        verdict: DiagnosisVerdict.ispIssue,
        title: 'ISP issue',
        detail: 'Both Wi-Fi (${wifi.download.mbps.toStringAsFixed(1)} Mbps) and '
            'mobile data (${mobile.download.mbps.toStringAsFixed(1)} Mbps) are slow or unstable.',
        recommendation: 'This points to an outage or congestion upstream of '
            'your router. Contact your ISP.',
      );
    }

    if (mobileSlow && !wifiSlow) {
      final lowPower = mobile.deviceStatus?.isLowPowerMode == true;
      return DiagnosisResult(
        verdict: DiagnosisVerdict.mobileIssue,
        title: 'Mobile network issue',
        detail: 'Mobile data (${mobile.download.mbps.toStringAsFixed(1)} Mbps) is slow '
            'but Wi-Fi (${wifi.download.mbps.toStringAsFixed(1)} Mbps) is fine.'
            '${lowPower ? ' This device was in battery saver / Low Power Mode '
                'during the mobile run — that alone can throttle data and mimic '
                'a carrier issue.' : ''}',
        recommendation: lowPower
            ? 'Turn off Low Power Mode / battery saver and re-run before '
                'concluding it\'s carrier congestion.'
            : 'Likely weak cellular signal or carrier congestion — '
                'not a home network problem.',
      );
    }

    return DiagnosisResult(
      verdict: DiagnosisVerdict.allGood,
      title: 'Both connections look healthy',
      detail: 'Wi-Fi (${wifi.download.mbps.toStringAsFixed(1)} Mbps) and mobile data '
          '(${mobile.download.mbps.toStringAsFixed(1)} Mbps) both perform within normal range.',
      recommendation: 'No action needed.',
    );
  }
}
