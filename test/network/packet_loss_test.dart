import 'package:flutter_test/flutter_test.dart';
import 'package:smart_network_diagnostic/network/network_tester.dart';

void main() {
  group('PingStats.lossPercent', () {
    test('0% loss when every probe is received', () {
      final stats = PingStats(host: 'h', sent: 6, received: 6, rttsMs: const [10, 12, 11, 9, 10, 11]);
      expect(stats.lost, 0);
      expect(stats.lossPercent, 0);
    });

    test('100% loss when every probe times out', () {
      final stats = PingStats(host: 'h', sent: 6, received: 0, rttsMs: const []);
      expect(stats.lost, 6);
      expect(stats.lossPercent, 100);
    });

    test('partial loss computes the correct percentage', () {
      final stats = PingStats(host: 'h', sent: 6, received: 4, rttsMs: const [10, 12, 11, 9]);
      expect(stats.lost, 2);
      expect(stats.lossPercent, closeTo(33.33, 0.01));
    });

    test('0 sent does not divide by zero', () {
      final stats = PingStats(host: 'h', sent: 0, received: 0, rttsMs: const []);
      expect(stats.lossPercent, 0);
    });
  });
}
