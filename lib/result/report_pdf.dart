import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../diagnosis/diagnosis_engine.dart';
import '../network/network_tester.dart';

/// Renders the same data shown in [ReportCard] as a one-page PDF, for the
/// report's "Download PDF" action. Kept independent of [ReportCard]'s
/// private formatting helpers since `pdf`'s widget set (`pw.*`) is a
/// different tree entirely from Flutter's own widgets. Colors below mirror
/// `lib/core/theme.dart`'s `AppColors` values directly (not just "inspired
/// by") so the PDF reads as the same product as the in-app report.
class _Palette {
  static final bg = PdfColor.fromInt(0xFF050B16);
  static final surface = PdfColor.fromInt(0xFF0A121F);
  static final surfaceBorder = PdfColor.fromInt(0xFF161F35);
  static final accentPrimary = PdfColor.fromInt(0xFF178F6D);
  static final accentPrimaryGlow = PdfColor.fromInt(0xFF57C79E);
  static final accentSecondary = PdfColor.fromInt(0xFF1C7FB8);
  static final coral = PdfColor.fromInt(0xFFFF6B6B);
  static final amber = PdfColor.fromInt(0xFFFBBF24);
  static final green = PdfColor.fromInt(0xFF4ADE80);
  static final textPrimary = PdfColor.fromInt(0xFFD2E4F0);
  static final textMuted = PdfColor.fromInt(0xFF8CA0B8);
}

/// Blends [base] toward [_Palette.surface] by [amount] (0 = surface, 1 =
/// base) and returns a fully **opaque** color. Used instead of [_alpha] for
/// any card that has body text sitting on top of it: some PDF viewers/print
/// pipelines flatten transparency against a white backdrop, which silently
/// washes out light text (like [_Palette.textPrimary]) painted over an
/// alpha-blended fill. A precomputed opaque blend can't be flattened wrong.
PdfColor _tint(PdfColor base, double amount) {
  double lerp(double a, double b) => a + (b - a) * amount;
  return PdfColor(
    lerp(_Palette.surface.red, base.red),
    lerp(_Palette.surface.green, base.green),
    lerp(_Palette.surface.blue, base.blue),
  );
}

/// [security]'s 'color' entry is a Flutter [Color] (from `Colors.*`), not a
/// [PdfColor] — the two packages each define their own color type.
PdfColor _fromFlutterColor(Color c) => PdfColor(c.r, c.g, c.b, c.a);

/// The security label (and a couple of diagnosis strings elsewhere in the
/// app) leads with an emoji glyph for the in-app UI. The PDF's base fonts
/// have no emoji glyphs at all, so those characters were rendering as
/// broken/missing-glyph boxes in the exported file. Stripping them here
/// keeps the emoji in the live UI while keeping the PDF clean.
final _emojiPattern = RegExp(
  r'[\u{2600}-\u{27BF}\u{1F000}-\u{1FFFF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}\u{FE0F}]',
  unicode: true,
);
String _stripEmoji(String s) => s.replaceAll(_emojiPattern, '').trim();

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
  final verdictColor = _verdictColor(diagnosis.verdict);

  final pageTheme = pw.PageTheme(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    buildBackground: (context) => pw.FullPage(
      ignoreMargins: true,
      child: pw.Container(color: _Palette.bg),
    ),
  );

  doc.addPage(
    pw.Page(
      pageTheme: pageTheme,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header(diagnosisContext, timestamp),
          pw.SizedBox(height: 16),
          pw.Row(children: [
            pw.Expanded(
                child: pw.Container(height: 3, color: _Palette.accentPrimary)),
            pw.Expanded(
                child:
                    pw.Container(height: 3, color: _Palette.accentSecondary)),
          ]),
          pw.SizedBox(height: 20),
          _verdictBanner(diagnosis, verdictColor),
          pw.SizedBox(height: 12),
          _recommendationCallout(diagnosis.recommendation),
          pw.SizedBox(height: 22),
          _sectionLabel('Metrics'),
          pw.SizedBox(height: 8),
          isCompare
              ? _compareCard(primary, secondary)
              : _soloCard(primary, security),
          pw.SizedBox(height: 22),
          _sectionLabel('Details'),
          pw.SizedBox(height: 8),
          _detailsCard(primary, ipInfo),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _header(String diagnosisContext, DateTime? timestamp) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('NetDiagnose',
              style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: _Palette.textPrimary)),
          pw.SizedBox(height: 3),
          pw.Text('NETWORK DIAGNOSTIC REPORT',
              style: pw.TextStyle(
                  fontSize: 9,
                  color: _Palette.accentPrimaryGlow,
                  letterSpacing: 1.4)),
        ],
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(diagnosisContext,
              style: pw.TextStyle(fontSize: 10, color: _Palette.textMuted)),
          pw.SizedBox(height: 3),
          pw.Text(_formatTimestamp(timestamp),
              style: pw.TextStyle(fontSize: 10, color: _Palette.textMuted)),
        ],
      ),
    ],
  );
}

pw.Widget _verdictBanner(DiagnosisResult diagnosis, PdfColor color) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      color: _tint(color, 0.16),
      borderRadius: pw.BorderRadius.circular(10),
      border: pw.Border.all(color: _tint(color, 0.55), width: 1),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 9,
              height: 9,
              decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
            ),
            pw.SizedBox(width: 8),
            pw.Text(_stripEmoji(diagnosis.title),
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(_stripEmoji(diagnosis.detail),
            style: pw.TextStyle(
                fontSize: 11, color: _Palette.textPrimary, lineSpacing: 2)),
      ],
    ),
  );
}

pw.Widget _recommendationCallout(String recommendation) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: _tint(_Palette.accentSecondary, 0.14),
      borderRadius: pw.BorderRadius.circular(10),
      border: pw.Border.all(color: _tint(_Palette.accentSecondary, 0.4)),
    ),
    child: pw.Text(_stripEmoji(recommendation),
        style: pw.TextStyle(
            fontSize: 11, color: _Palette.textPrimary, lineSpacing: 2)),
  );
}

pw.Widget _sectionLabel(String text) {
  return pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: _Palette.textMuted,
        letterSpacing: 1.2),
  );
}

pw.Widget _card(List<pw.Widget> rows) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 14),
    decoration: pw.BoxDecoration(
      color: _Palette.surface,
      borderRadius: pw.BorderRadius.circular(12),
      border: pw.Border.all(color: _Palette.surfaceBorder),
    ),
    child: pw.Column(children: rows),
  );
}

pw.Widget _metricRow(String label, String value, PdfColor valueColor,
    {bool last = false}) {
  return pw.Column(children: [
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(fontSize: 10.5, color: _Palette.textMuted)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: valueColor)),
        ],
      ),
    ),
    if (!last) pw.Divider(color: _Palette.surfaceBorder, height: 1, thickness: 0.5),
  ]);
}

pw.Widget _soloCard(NetworkSnapshot primary, Map<String, dynamic>? security) {
  final securityColor = security == null
      ? _Palette.textMuted
      : _fromFlutterColor(security['color'] as Color);
  final securityLabel =
      security == null ? 'Not checked' : _stripEmoji(security['label'] as String);
  return _card([
    _metricRow('Connection', primary.connectionLabel, _Palette.textPrimary),
    _metricRow('Download', _formatSpeed(primary.download), _speedColor(primary.download)),
    _metricRow('Upload', _formatSpeed(primary.upload), _speedColor(primary.upload)),
    _metricRow('Ping', _formatPing(primary.ping), _lossColor(primary.ping)),
    _metricRow('Packet loss', '${primary.ping.lossPercent.toStringAsFixed(0)}%',
        _lossColor(primary.ping)),
    _metricRow('Security', securityLabel, securityColor, last: true),
  ]);
}

pw.Widget _compareCard(NetworkSnapshot primary, NetworkSnapshot secondary) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: _compareSnapshotCard('Run 1', primary)),
      pw.SizedBox(width: 12),
      pw.Expanded(child: _compareSnapshotCard('Run 2', secondary)),
    ],
  );
}

pw.Widget _compareSnapshotCard(String label, NetworkSnapshot snap) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      color: _Palette.surface,
      borderRadius: pw.BorderRadius.circular(12),
      border: pw.Border.all(color: _Palette.surfaceBorder),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label.toUpperCase(),
            style: pw.TextStyle(
                fontSize: 8,
                color: _Palette.accentPrimaryGlow,
                letterSpacing: 1.2,
                fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(snap.connectionLabel,
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _Palette.textPrimary)),
        pw.SizedBox(height: 10),
        pw.Text(_formatSpeed(snap.download),
            style: pw.TextStyle(
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
                color: _speedColor(snap.download))),
        pw.Text('Mbps down', style: pw.TextStyle(fontSize: 8.5, color: _Palette.textMuted)),
        pw.SizedBox(height: 8),
        pw.Text(_formatSpeed(snap.upload),
            style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _speedColor(snap.upload))),
        pw.Text('Mbps up', style: pw.TextStyle(fontSize: 8.5, color: _Palette.textMuted)),
        pw.SizedBox(height: 8),
        pw.Text(_formatPing(snap.ping),
            style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: _lossColor(snap.ping))),
        pw.Text('ping', style: pw.TextStyle(fontSize: 8.5, color: _Palette.textMuted)),
      ],
    ),
  );
}

pw.Widget _detailsCard(NetworkSnapshot primary, IpInfoResult? ipInfo) {
  final ping = primary.ping;
  final device = primary.deviceStatus;
  final rows = <(String, String)>[
    if (ping.received > 0) ('Ping range', '${ping.minMs}–${ping.maxMs} ms'),
    if (ping.jitterMs != null) ('Jitter', '${ping.jitterMs!.toStringAsFixed(0)} ms'),
    if (ipInfo != null && ipInfo.success && ipInfo.ip != null) ('Public IP', ipInfo.ip!),
    if (ipInfo != null && ipInfo.success && ipInfo.isp != null) ('ISP', ipInfo.isp!),
    if (ipInfo != null && ipInfo.success)
      ('Location', [ipInfo.city, ipInfo.country].whereType<String>().join(', ')),
    if (ipInfo != null && !ipInfo.success) ('IP lookup', 'Failed'),
    if (device != null) ('Device', device.deviceLabel),
    if (device?.batteryPercent != null)
      (
        'Battery',
        device!.isLowPowerMode == true
            ? '${device.batteryPercent}% (Low Power Mode)'
            : '${device.batteryPercent}%',
      ),
  ]..removeWhere((row) => row.$2.isEmpty);

  if (rows.isEmpty) {
    return pw.SizedBox.shrink();
  }

  return _card([
    for (var i = 0; i < rows.length; i++)
      _metricRow(rows[i].$1, rows[i].$2, _Palette.textPrimary, last: i == rows.length - 1),
  ]);
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

PdfColor _speedColor(SpeedResult r) {
  if (!r.success) return _Palette.coral;
  if (r.mbps < 5) return _Palette.amber;
  return _Palette.green;
}

PdfColor _lossColor(PingStats p) {
  if (p.received == 0 || p.lossPercent >= 20) return _Palette.coral;
  if (p.lossPercent > 0) return _Palette.amber;
  return _Palette.green;
}

PdfColor _verdictColor(DiagnosisVerdict verdict) {
  switch (verdict) {
    case DiagnosisVerdict.allGood:
      return _Palette.green;
    case DiagnosisVerdict.ispIssue:
      return _Palette.coral;
    case DiagnosisVerdict.routerIssue:
    case DiagnosisVerdict.mobileIssue:
    case DiagnosisVerdict.deviceIssue:
    case DiagnosisVerdict.inconclusive:
      return _Palette.amber;
  }
}
