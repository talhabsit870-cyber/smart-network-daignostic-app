/// No-op fallback used on platforms where `dart:io` isn't available (Web).
Future<bool> trySaveAndOpenCsvWindows(String csv, String filename) async =>
    false;
