import 'package:flutter/material.dart';

import '../core/pdf_opener_stub.dart' if (dart.library.io) '../core/pdf_opener_io.dart';
import 'history_entry.dart';
import 'history_pdf.dart';

Future<void> exportHistoryPdf(
    BuildContext context, List<HistoryEntry> entries) async {
  final messenger = ScaffoldMessenger.of(context);
  if (entries.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No history to export.')),
    );
    return;
  }
  try {
    final bytes = await buildHistoryPdf(entries);
    await saveAndOpenPdf(bytes, 'netdiagonesscanhistory.pdf');
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not export scan history.')),
    );
  }
}
