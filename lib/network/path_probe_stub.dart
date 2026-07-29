import 'path_check_result.dart';

/// No-op fallback used on platforms where `dart:io` isn't available (Web).
/// The real implementation lives in `path_probe_io.dart`.
class PathProbe {
  static Future<PathCheckResult> run(String host) async =>
      PathCheckResult.unavailable('Path check isn\'t available on web.');
}
