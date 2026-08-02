import 'dart:io';

/// Windows' native share sheet (`DataTransferManager`, used by `share_plus`)
/// is unreliable for unpackaged desktop builds — it frequently fails with
/// "We couldn't show you all the ways you could share." `package:printing`
/// sidesteps this on Windows by writing to a temp file and shell-opening it
/// instead of sharing; do the same here for the CSV export rather than
/// relying on the native share UI.
Future<bool> trySaveAndOpenCsvWindows(String csv, String filename) async {
  if (!Platform.isWindows) return false;
  final file = File('${Directory.systemTemp.path}\\$filename');
  await file.writeAsString(csv);
  await Process.start('explorer.exe', [file.path]);
  return true;
}
