/// No-op fallback used on platforms where `dart:io` isn't available (Web).
/// The real implementation lives in `wifi_native_io.dart`.
class WifiNativeLookup {
  static Future<Map<String, String>?> queryWindowsWifi() async => null;
}
