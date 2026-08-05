import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wifi_native_stub.dart' if (dart.library.io) 'wifi_native_io.dart';

/// Keyword fragments in an SSID that commonly indicate a public/open
/// network (coffee shops, hotels, airports, guest networks, etc). This is a
/// name heuristic, not a read of the actual encryption/security protocol —
/// no Flutter plugin exposes that cross-platform (Android/iOS/Linux/macOS/
/// Web/Windows) without adding native, platform-specific scanning code.
const List<String> _publicSsidKeywords = [
  "public",
  "free",
  "hotel",
  "cafe",
  "coffee",
  "guest",
  "airport",
  "hotspot",
  "open",
  "wifi",
  "wi-fi",
];

/// Scans the current WiFi connection for security concerns:
///  - a spoofed / "evil twin" access point (same SSID, unexpected new BSSID)
///  - a likely public/open network based on its name
/// and returns a result map for display + an optional pop-up warning.
class SecurityCheck {
  static const _trustStoreKey = 'known_wifi_bssids';

  Future<Map<String, dynamic>> scanWiFiSecurity() async {
    // Prefer a native OS-level read (currently: Windows via `netsh`), which
    // reports the real authentication type, not just an SSID-name guess.
    // network_info_plus has no Windows implementation at all, so on that
    // platform SSID/BSSID would otherwise never resolve.
    final native = await WifiNativeLookup.queryWindowsWifi();

    String? ssid = native?['ssid'];
    String? bssid = native?['bssid'];
    final String? authentication = native?['authentication'];

    if (ssid == null) {
      ssid = await _resolveSsid();
      bssid = ssid != null ? await _resolveBssid() : null;
    }

    if (ssid == null) {
      return {
        "label": "❓ Unable to verify",
        "color": Colors.grey,
        "advice": kIsWeb
            ? "Browsers don't allow web pages to read the WiFi network "
                "name, for privacy reasons — this check isn't available "
                "running in a browser. Open the app on Android, iOS, "
                "macOS, or Windows to enable it."
            : "Couldn't read the WiFi network name — location "
                "permission may be denied, or this device isn't on WiFi. "
                "Grant location access to enable this check.",
        "threats": <String>[],
        "hasThreat": false,
        "isSpoofed": false,
        "ssid": null,
        "bssid": null,
      };
    }

    final threats = <String>[];

    bool isSpoofed = false;
    if (bssid != null) {
      isSpoofed = await _checkForSpoofing(ssid, bssid);
      if (isSpoofed) {
        threats.add(
          'The access point serving "$ssid" has a different hardware '
          'address (BSSID) than the one this device connected to before. '
          'This can mean a rogue "evil twin" hotspot is impersonating a '
          'trusted network — or simply that your router was replaced, or '
          'you\'re near a different access point on a multi-router/mesh '
          'network. If this is unexpected, avoid logging into anything '
          'sensitive and verify with venue staff or your network admin.',
        );
      }
    }

    final bool confirmedOpen =
        authentication != null && authentication.toLowerCase().contains('open');
    final bool confirmedWeak =
        authentication != null && authentication.toUpperCase().contains('WEP');

    if (confirmedOpen) {
      threats.add(
        'Confirmed by this device\'s WiFi adapter (not just guessed from the '
        'name): "$ssid" uses no encryption at all (authentication: '
        '"$authentication"). Anyone nearby can read unencrypted traffic on '
        'this network. Avoid banking or logins, and use a VPN.',
      );
    } else if (confirmedWeak) {
      threats.add(
        'Confirmed by this device\'s WiFi adapter: "$ssid" uses WEP '
        'encryption ("$authentication"), which is broken and can be cracked '
        'in minutes. Treat this network as effectively unsecured.',
      );
    } else {
      final String normalized = ssid.toLowerCase();
      final bool looksPublic =
          _publicSsidKeywords.any((k) => normalized.contains(k));
      if (looksPublic) {
        threats.add(
          'The network name "$ssid" suggests a public or open hotspot. On '
          'public WiFi, other devices on the same network can potentially '
          'intercept traffic (packet sniffing), redirect you to fake login '
          'pages, or run man-in-the-middle attacks. Avoid banking or '
          'entering passwords, and use a VPN if possible.',
        );
      }
    }

    if (threats.isEmpty) {
      final String encryptionNote = authentication != null
          ? 'Encryption confirmed: $authentication.'
          : 'Note: actual encryption strength can\'t be verified from this app.';
      return {
        "label": "✅ No risk flags detected",
        "color": Colors.green,
        "advice": 'Connected to "$ssid". Its name doesn\'t match known '
            'public-network patterns and its access point hasn\'t changed '
            'unexpectedly. $encryptionNote',
        "threats": <String>[],
        "hasThreat": false,
        "isSpoofed": false,
        "ssid": ssid,
        "bssid": bssid,
      };
    }

    final bool confirmedUnsecured = confirmedOpen || confirmedWeak;
    return {
      "label": isSpoofed
          ? "🚨 Possible spoofed network"
          : (confirmedUnsecured ? "🚨 Unsecured network" : "⚠️ Public / open network"),
      "color": (isSpoofed || confirmedUnsecured) ? Colors.red : Colors.orange,
      "advice": threats.join('\n\n'),
      "threats": threats,
      "hasThreat": true,
      "isSpoofed": isSpoofed,
      "ssid": ssid,
      "bssid": bssid,
    };
  }

  /// Compares [bssid] against the set of BSSIDs previously seen for [ssid].
  /// First time an SSID is seen, its BSSID is trusted automatically. Returns
  /// true (flagging possible spoofing) only when the SSID is already known
  /// under a different BSSID.
  Future<bool> _checkForSpoofing(String ssid, String bssid) async {
    final prefs = await SharedPreferences.getInstance();
    final store = _loadTrustStore(prefs);

    final known = store[ssid];
    if (known == null || known.isEmpty) {
      store[ssid] = [bssid];
      await _saveTrustStore(prefs, store);
      return false;
    }

    if (known.contains(bssid)) return false;

    // Unknown BSSID for a known SSID — flagged, but not auto-trusted here;
    // the user can trust it explicitly via [trustCurrentNetwork].
    return true;
  }

  /// Adds [bssid] to the trusted set for [ssid], e.g. after the user
  /// confirms a spoof warning was a false positive (new router, roaming
  /// between mesh access points).
  static Future<void> trustCurrentNetwork(String ssid, String bssid) async {
    final prefs = await SharedPreferences.getInstance();
    final store = _loadTrustStore(prefs);
    final known = store.putIfAbsent(ssid, () => []);
    if (!known.contains(bssid)) known.add(bssid);
    await _saveTrustStore(prefs, store);
  }

  static Map<String, List<String>> _loadTrustStore(SharedPreferences prefs) {
    final raw = prefs.getString(_trustStoreKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, List<String>.from(value as List)),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveTrustStore(
      SharedPreferences prefs, Map<String, List<String>> store) async {
    await prefs.setString(_trustStoreKey, jsonEncode(store));
  }

  /// Reads the connected WiFi SSID, requesting location permission first —
  /// required by Android/iOS before the OS will hand back a real network
  /// name. Returns null if the SSID can't be determined (permission denied,
  /// not on WiFi, hidden network, or platform not supported).
  Future<String?> _resolveSsid() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) return null;

      String? ssid = await NetworkInfo().getWifiName();
      if (ssid == null) return null;

      // Some platforms wrap the SSID in surrounding quotes.
      if (ssid.startsWith('"') && ssid.endsWith('"') && ssid.length >= 2) {
        ssid = ssid.substring(1, ssid.length - 1);
      }

      if (ssid.isEmpty ||
          ssid == "<unknown ssid>" ||
          ssid.toLowerCase() == "unknown") {
        return null;
      }
      return ssid;
    } catch (_) {
      // Permission API or plugin may be unimplemented on this platform
      // (e.g. Linux/Windows) — treat as unresolvable rather than crashing.
      return null;
    }
  }

  /// Reads the connected access point's BSSID (hardware address). May be
  /// null even when SSID resolves — some OS versions additionally require
  /// location services to be turned on system-wide, or restrict BSSID
  /// access further than SSID access. Spoof detection simply can't run
  /// without it; that's treated as "no signal", never as "safe".
  Future<String?> _resolveBssid() async {
    try {
      final bssid = await NetworkInfo().getWifiBSSID();
      if (bssid == null || bssid.isEmpty) return null;
      final normalized = bssid.toLowerCase();
      if (normalized == "02:00:00:00:00:00" || normalized == "00:00:00:00:00:00") {
        // Placeholder BSSID some platforms return when access is restricted.
        return null;
      }
      return bssid;
    } catch (_) {
      return null;
    }
  }
}
