import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'history_entry.dart';

/// Security labels (and some verdict titles) lead with an emoji glyph for
/// the in-app UI. The PDF's base fonts have no emoji glyphs at all, so those
/// characters render as broken/missing-glyph boxes in the exported file —
/// same fix as `report_pdf.dart`'s `_stripEmoji`.
final _emojiPattern = RegExp(
  r'[\u{2600}-\u{27BF}\u{1F000}-\u{1FFFF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}\u{FE0F}]',
  unicode: true,
);
String _stripEmoji(String s) => s.replaceAll(_emojiPattern, '').trim();

/// Renders the full scan history as a one-table PDF report, replacing the
/// old CSV share export — mirrors `report_pdf.dart`'s color treatment so it
/// reads as the same product.
class _Palette {
  static final bg = PdfColor.fromInt(0xFF050B16);
  static final surface = PdfColor.fromInt(0xFF0A121F);
  static final surfaceBorder = PdfColor.fromInt(0xFF161F35);
  static final accentPrimary = PdfColor.fromInt(0xFF178F6D);
  static final accentPrimaryGlow = PdfColor.fromInt(0xFF57C79E);
  static final accentSecondary = PdfColor.fromInt(0xFF1C7FB8);
  static final textPrimary = PdfColor.fromInt(0xFFD2E4F0);
  static final textMuted = PdfColor.fromInt(0xFF8CA0B8);
}

Future<Uint8List> buildHistoryPdf(List<HistoryEntry> entries) async {
  final doc = pw.Document();

  final pageTheme = pw.PageTheme(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(28),
    buildBackground: (context) => pw.FullPage(
      ignoreMargins: true,
      child: pw.Container(color: _Palette.bg),
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageTheme: pageTheme,
      build: (context) => [
        _header(entries.length),
        pw.SizedBox(height: 16),
        pw.Row(children: [
          pw.Expanded(
              child: pw.Container(height: 3, color: _Palette.accentPrimary)),
          pw.Expanded(
              child: pw.Container(height: 3, color: _Palette.accentSecondary)),
        ]),
        pw.SizedBox(height: 18),
        _table(entries),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header(int count) {
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
          pw.Text('SCAN HISTORY',
              style: pw.TextStyle(
                  fontSize: 9,
                  color: _Palette.accentPrimaryGlow,
                  letterSpacing: 1.4)),
        ],
      ),
      pw.Text('$count scan${count == 1 ? '' : 's'}',
          style: pw.TextStyle(fontSize: 10, color: _Palette.textMuted)),
    ],
  );
}

pw.Widget _table(List<HistoryEntry> entries) {
  const headers = [
    'Date',
    'Connection',
    'Down',
    'Up',
    'Ping',
    'Loss',
    'Bufferbloat',
    'Security',
    'Verdict',
  ];

  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: [
      for (final e in entries)
        [
          _formatTimestamp(e.timestamp),
          e.connectionLabel + (e.isDeep ? ' (Deep)' : ''),
          '${e.downloadMbps.toStringAsFixed(1)} Mbps',
          '${e.uploadMbps.toStringAsFixed(1)} Mbps',
          e.pingMs != null ? '${e.pingMs!.toStringAsFixed(0)} ms' : '--',
          '${e.lossPercent.toStringAsFixed(0)}%',
          e.bufferbloatGrade ?? '--',
          _stripEmoji(e.securityLabel),
          _stripEmoji(e.verdictTitle),
        ],
    ],
    headerStyle: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: _Palette.textMuted),
    headerDecoration: pw.BoxDecoration(color: _Palette.surface),
    cellStyle: pw.TextStyle(fontSize: 9, color: _Palette.textPrimary),
    cellHeight: 24,
    border: pw.TableBorder.all(color: _Palette.surfaceBorder, width: 0.5),
    cellAlignments: {
      for (var i = 0; i < headers.length; i++) i: pw.Alignment.centerLeft,
    },
  );
}

String _formatTimestamp(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
}
