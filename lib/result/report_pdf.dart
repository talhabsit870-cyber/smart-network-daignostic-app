import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../diagnosis/diagnosis_engine.dart';
import '../network/network_tester.dart';

/// Renders the same data shown in [ReportCard] as a one-page PDF, for the
/// report's "Download PDF" action. Kept independent of [ReportCard]'s
/// private formatting helpers since `pdf`'s widget set (`pw.*`) is a
/// different tree entirely from Flutter's own widgets.
Future<Uint8List> buildReportPdf({
  required DateTime? timestamp,
  required String diagnosisContext,
  required NetworkSnapshot primary,
  NetworkSnapshot? secondary,
  Map<String, dynamic>? security,
  IpInfoResult? ipInfo,
  required DiagnosisResult diagnosis,
}) async {
  final doc = pw.Document();
  final isCompare = secondary != null;

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('NetDiagnose Report',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('$diagnosisContext · ${_formatTimestamp(timestamp)}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 20),
          pw.Text(diagnosis.title,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(diagnosis.detail, style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 10),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border.all(color: PdfColors.blue200),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(diagnosis.recommendation,
                style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.SizedBox(height: 24),
          pw.Text('Metrics',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          isCompare
              ? _compareTable(primary, secondary)
              : _soloTable(primary, security),
          pw.SizedBox(height: 24),
          pw.Text('Details',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          _detailsTable(primary, ipInfo),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _soloTable(NetworkSnapshot primary, Map<String, dynamic>? security) {
  return _table([
    ['Metric', 'Value'],
    ['Connection', primary.connectionLabel],
    ['Download', _formatSpeed(primary.download)],
    ['Upload', _formatSpeed(primary.upload)],
    ['Ping', _formatPing(primary.ping)],
    ['Packet loss', '${primary.ping.lossPercent.toStringAsFixed(0)}%'],
    ['Security', security == null ? 'Not checked' : security['label'] as String],
  ]);
}

pw.Widget _compareTable(NetworkSnapshot primary, NetworkSnapshot secondary) {
  return _table([
    ['Metric', 'Run 1', 'Run 2'],
    ['Connection', primary.connectionLabel, secondary.connectionLabel],
    ['Download', _formatSpeed(primary.download), _formatSpeed(secondary.download)],
    ['Upload', _formatSpeed(primary.upload), _formatSpeed(secondary.upload)],
    ['Ping', _formatPing(primary.ping), _formatPing(secondary.ping)],
  ]);
}

pw.Widget _detailsTable(NetworkSnapshot primary, IpInfoResult? ipInfo) {
  final ping = primary.ping;
  final device = primary.deviceStatus;
  final rows = <List<String>>[
    ['Field', 'Value'],
    if (ping.received > 0) ['Ping range', '${ping.minMs}–${ping.maxMs} ms'],
    if (ping.jitterMs != null) ['Jitter', '${ping.jitterMs!.toStringAsFixed(0)} ms'],
    if (ipInfo != null && ipInfo.success && ipInfo.ip != null)
      ['Public IP', ipInfo.ip!],
    if (ipInfo != null && ipInfo.success && ipInfo.isp != null) ['ISP', ipInfo.isp!],
    if (ipInfo != null && ipInfo.success)
      [
        'Location',
        [ipInfo.city, ipInfo.country].whereType<String>().join(', '),
      ],
    if (ipInfo != null && !ipInfo.success) ['IP lookup', 'Failed'],
    if (device != null) ['Device', device.deviceLabel],
    if (device?.batteryPercent != null)
      [
        'Battery',
        device!.isLowPowerMode == true
            ? '${device.batteryPercent}% (Low Power Mode)'
            : '${device.batteryPercent}%',
      ],
  ]..removeWhere((row) => row.length > 1 && row[1].isEmpty);
  return _table(rows);
}

pw.Widget _table(List<List<String>> rows) {
  return pw.TableHelper.fromTextArray(
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
    headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
    cellStyle: const pw.TextStyle(fontSize: 10),
    cellPadding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    data: rows,
  );
}

String _formatTimestamp(DateTime? dt) {
  if (dt == null) return '--';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}

String _formatSpeed(SpeedResult r) {
  if (!r.success) return 'Failed';
  return '${r.mbps.toStringAsFixed(1)} Mbps';
}

String _formatPing(PingStats p) {
  if (p.received == 0) return 'Unreachable';
  return '${p.avgMs!.toStringAsFixed(0)} ms';
}
