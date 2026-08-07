import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Web has no filesystem to save to and no external viewer to hand off to —
/// `Printing.sharePdf` triggers a direct browser download there instead of
/// an OS share sheet, so it's the right behavior on this one platform.
Future<String> saveAndOpenPdf(Uint8List bytes, String filename) async {
  await Printing.sharePdf(bytes: bytes, filename: filename);
  return filename;
}
