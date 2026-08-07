import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Saves [bytes] to the app's documents directory as [filename] and opens it
/// directly in the platform's default PDF viewer, instead of routing through
/// an OS share sheet.
Future<String> saveAndOpenPdf(Uint8List bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(file.path);
  return file.path;
}
