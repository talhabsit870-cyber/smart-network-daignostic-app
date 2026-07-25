import 'dart:io';

/// Reads real WiFi connection details straight from the OS on platforms
/// `network_info_plus` doesn't cover. Windows in particular ships no
/// `network_info_plus` implementation at all (it's absent from
/// `windows/flutter/generated_plugin_registrant.cc`), so `getWifiName()` /
/// `getWifiBSSID()` always throw there. `netsh wlan show interfaces` gives
/// SSID, BSSID, and — unlike anything network_info_plus exposes on any
/// platform — the actual authentication type (WPA2-Personal, Open, WEP...),
/// which lets the security check confirm an unencrypted network instead of
/// just guessing from its name.
class WifiNativeLookup {
  static Future<Map<String, String>?> queryWindowsWifi() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run('netsh', ['wlan', 'show', 'interfaces'])
          .timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) return null;
      return _parse(result.stdout.toString());
    } catch (_) {
      return null;
    }
  }

  static Map<String, String>? _parse(String output) {
    String? field(String label) {
      final match = RegExp('^\\s*${RegExp.escape(label)}\\s*:\\s*(.+)\$',
              multiLine: true)
          .firstMatch(output);
      return match?.group(1)?.trim();
    }

    final state = field('State');
    if (state == null || !state.toLowerCase().contains('connected')) return null;

    final ssid = field('SSID');
    if (ssid == null || ssid.isEmpty) return null;

    final bssid = field('AP BSSID') ?? field('BSSID');
    final authentication = field('Authentication');

    return {
      'ssid': ssid,
      'bssid': ?bssid,
      'authentication': ?authentication,
    };
  }
}
