import 'dart:async';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'path_check_result.dart';

/// Platform dispatch for the network path check: real `tracert`/
/// `traceroute` on desktop, a 3-point TCP-connect approximation on mobile
/// (no raw ICMP without root), unavailable elsewhere. Every entry point
/// swallows its own errors and returns a [PathCheckResult] — this must never
/// throw, since callers don't wrap it in try/catch.
class PathProbe {
  static Future<PathCheckResult> run(String host) async {
    try {
      if (Platform.isWindows) return await _runTracert(host);
      if (Platform.isMacOS || Platform.isLinux) return await _runTraceroute(host);
      if (Platform.isAndroid || Platform.isIOS) return await _runApproximatePath(host);
      return PathCheckResult.unavailable('Path check not supported on this platform.');
    } catch (_) {
      return PathCheckResult.failed('Path check failed unexpectedly.');
    }
  }

  static Future<PathCheckResult> _runTracert(String host) async {
    try {
      final result = await Process.run(
        'tracert',
        ['-d', '-h', '10', '-w', '600', host],
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      ).timeout(const Duration(seconds: 12));
      final hops = parseTracertOutput(result.stdout.toString());
      if (hops.isEmpty) {
        return PathCheckResult.failed('tracert produced no hop data.');
      }
      return PathCheckResult(
        success: true,
        method: PathCheckMethod.fullTraceroute,
        hops: hops,
      );
    } on TimeoutException {
      return PathCheckResult.failed('Path check timed out.');
    } catch (_) {
      return PathCheckResult.failed('tracert isn\'t available on this system.');
    }
  }

  static Future<PathCheckResult> _runTraceroute(String host) async {
    try {
      final result = await Process.run(
        'traceroute',
        ['-n', '-m', '15', '-q', '1', '-w', '1', host],
      ).timeout(const Duration(seconds: 12));
      final hops = parseTracerouteOutput(result.stdout.toString());
      if (hops.isEmpty) {
        return PathCheckResult.failed('traceroute produced no hop data.');
      }
      return PathCheckResult(
        success: true,
        method: PathCheckMethod.fullTraceroute,
        hops: hops,
      );
    } on TimeoutException {
      return PathCheckResult.failed('Path check timed out.');
    } catch (_) {
      return PathCheckResult.failed('traceroute isn\'t available on this system.');
    }
  }

  static Future<PathCheckResult> _runApproximatePath(String host) async {
    final hops = <PathHop>[];

    String? gatewayIp;
    try {
      final status = await Permission.locationWhenInUse.request();
      if (status.isGranted) {
        gatewayIp = await NetworkInfo().getWifiGatewayIP();
      }
    } catch (_) {
      gatewayIp = null;
    }

    if (gatewayIp != null && gatewayIp.isNotEmpty) {
      hops.add(await _probePoint(1, 'Gateway', gatewayIp, 443));
    }
    hops.add(await _probePoint(hops.length + 1, 'Public DNS', '1.1.1.1', 443));
    hops.add(await _probePoint(hops.length + 1, 'Target', host, 443));

    if (hops.every((h) => h.timedOut)) {
      return PathCheckResult.failed('Approximate path check couldn\'t reach any point.');
    }

    return PathCheckResult(
      success: true,
      method: PathCheckMethod.approximatePath,
      hops: hops,
    );
  }

  /// TCP-connect timing to [address]:[port]. A refused connection (fast
  /// RST) still means the handshake reached the box, so it counts as a real
  /// RTT measurement — only a full connect timeout is "no data".
  static Future<PathHop> _probePoint(
      int hopNumber, String label, String address, int port) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(address, port,
          timeout: const Duration(seconds: 3));
      stopwatch.stop();
      socket.destroy();
      return PathHop(
        hopNumber: hopNumber,
        label: label,
        address: address,
        rttMs: stopwatch.elapsedMilliseconds,
      );
    } on SocketException {
      stopwatch.stop();
      return PathHop(
        hopNumber: hopNumber,
        label: label,
        address: address,
        rttMs: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      return PathHop(hopNumber: hopNumber, label: label, address: address, timedOut: true);
    }
  }
}
