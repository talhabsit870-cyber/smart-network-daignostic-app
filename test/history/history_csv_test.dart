import 'package:flutter_test/flutter_test.dart';
import 'package:smart_network_diagnostic/diagnosis/diagnosis_engine.dart';
import 'package:smart_network_diagnostic/history/history_entry.dart';
import 'package:smart_network_diagnostic/history/history_export.dart';

HistoryEntry _entry({
  String connectionLabel = 'Wi-Fi',
  String securityLabel = 'Secure',
}) {
  return HistoryEntry(
    timestamp: DateTime(2026, 1, 1, 12, 30),
    connectionLabel: connectionLabel,
    pingMs: 20,
    lossPercent: 0,
    downloadMbps: 100,
    uploadMbps: 50,
    securityLabel: securityLabel,
    verdictTitle: 'All good',
    verdict: DiagnosisVerdict.allGood,
  );
}

void main() {
  group('buildHistoryCsv', () {
    test('header row lists all HistoryEntry fields', () {
      final csv = buildHistoryCsv([_entry()]);
      final header = csv.split('\r\n').first;
      expect(header, 'timestamp,connectionLabel,pingMs,lossPercent,'
          'downloadMbps,uploadMbps,securityLabel,verdictTitle,verdict,'
          'bufferbloatGrade,bufferbloatIncreaseMs,pathCheckSummary,isDeep');
    });

    test('row count is header + one row per entry', () {
      final csv = buildHistoryCsv([_entry(), _entry(), _entry()]);
      expect(csv.split('\r\n').length, 4);
    });

    test('escapes a field containing a comma', () {
      final csv = buildHistoryCsv([_entry(connectionLabel: 'Wi-Fi, 5GHz')]);
      final row = csv.split('\r\n')[1];
      expect(row, startsWith('2026-01-01T12:30:00.000,"Wi-Fi, 5GHz",'));
    });

    test('escapes a field containing a quote', () {
      final csv = buildHistoryCsv([_entry(securityLabel: '5" antenna')]);
      final row = csv.split('\r\n')[1];
      expect(row, contains('"5"" antenna"'));
    });
  });
}
