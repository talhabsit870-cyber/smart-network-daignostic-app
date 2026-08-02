import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'history_entry.dart';
import 'history_export_stub.dart'
    if (dart.library.io) 'history_export_io.dart';

const _columns = [
  'timestamp',
  'connectionLabel',
  'pingMs',
  'lossPercent',
  'downloadMbps',
  'uploadMbps',
  'securityLabel',
  'verdictTitle',
  'verdict',
  'bufferbloatGrade',
  'bufferbloatIncreaseMs',
  'pathCheckSummary',
  'isDeep',
];

String buildHistoryCsv(List<HistoryEntry> entries) {
  final rows = [_columns.map(_csvField).join(',')];
  for (final entry in entries) {
    final json = entry.toJson();
    rows.add(_columns.map((c) => _csvField(json[c]?.toString() ?? '')).join(','));
  }
  return rows.join('\r\n');
}

String _csvField(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

Future<void> shareHistoryCsv(
    BuildContext context, List<HistoryEntry> entries) async {
  final messenger = ScaffoldMessenger.of(context);
  if (entries.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No history to export.')),
    );
    return;
  }
  try {
    final csv = buildHistoryCsv(entries);
    final filename =
        'netdiagnose_history_${_filenameTimestamp(DateTime.now())}.csv';
    if (await trySaveAndOpenCsvWindows(csv, filename)) return;
    final bytes = Uint8List.fromList(utf8.encode(csv));
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'text/csv',
            name: filename,
          ),
        ],
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not export scan history.')),
    );
  }
}

String _filenameTimestamp(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}${two(dt.month)}${two(dt.day)}_${two(dt.hour)}${two(dt.minute)}';
}
