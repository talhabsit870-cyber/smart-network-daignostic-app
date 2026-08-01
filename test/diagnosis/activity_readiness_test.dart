import 'package:flutter_test/flutter_test.dart';
import 'package:smart_network_diagnostic/diagnosis/activity_readiness.dart';
import 'package:smart_network_diagnostic/diagnosis/diagnosis_engine.dart';
import 'package:smart_network_diagnostic/network/network_tester.dart';

NetworkSnapshot _snapshot({
  required double downloadMbps,
  required double uploadMbps,
  required List<int> rttsMs,
  int sent = 10,
  int received = 10,
}) {
  return NetworkSnapshot(
    connectionLabel: 'Wi-Fi',
    ping: PingStats(host: 'test', sent: sent, received: received, rttsMs: rttsMs),
    download: SpeedResult(success: true, mbps: downloadMbps),
    upload: SpeedResult(success: true, mbps: uploadMbps),
  );
}

ActivityReadiness _find(List<ActivityReadiness> items, String activity) =>
    items.firstWhere((i) => i.activity == activity);

void main() {
  group('evaluateActivityReadiness', () {
    test('a clearly-good connection is good across the board', () {
      final snapshot = _snapshot(
        downloadMbps: 100,
        uploadMbps: 50,
        rttsMs: [18, 20, 19, 21, 20],
      );
      final items = evaluateActivityReadiness(snapshot);
      for (final item in items) {
        expect(item.status, ReadinessStatus.good, reason: item.activity);
      }
    });

    test('a clearly-poor connection is poor across the board', () {
      final snapshot = _snapshot(
        downloadMbps: 0.5,
        uploadMbps: 0.2,
        rttsMs: [300, 340, 260, 310],
        sent: 10,
        received: 6,
      );
      final items = evaluateActivityReadiness(snapshot);
      for (final item in items) {
        expect(item.status, ReadinessStatus.poor, reason: item.activity);
      }
    });

    test('download just inside the 15% band below the HD streaming '
        'threshold is borderline, not poor', () {
      // Threshold is 5 Mbps; 4.5 Mbps is within 15% of it (>= 4.25).
      final snapshot = _snapshot(
        downloadMbps: 4.5,
        uploadMbps: 50,
        rttsMs: [18, 20, 19, 21, 20],
      );
      final items = evaluateActivityReadiness(snapshot);
      expect(_find(items, 'HD streaming').status, ReadinessStatus.borderline);
    });

    test('bufferbloat grade F downgrades gaming even with good raw ping', () {
      final snapshot = NetworkSnapshot(
        connectionLabel: 'Wi-Fi',
        ping: const PingStats(
            host: 'test', sent: 10, received: 10, rttsMs: [18, 20, 19, 21, 20]),
        download: const SpeedResult(success: true, mbps: 100),
        upload: const SpeedResult(success: true, mbps: 50),
        bufferbloat: const BufferbloatResult(
            success: true, idleMs: 20, loadedMs: 900, increaseMs: 880, grade: 'F'),
      );
      final items = evaluateActivityReadiness(snapshot);
      expect(_find(items, 'Competitive online gaming').status, ReadinessStatus.poor);
    });
  });
}
