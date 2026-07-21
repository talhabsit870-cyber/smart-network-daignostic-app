import 'package:flutter/material.dart';
// Add to pubspec.yaml: connectivity_plus, network_info_plus
// import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:network_info_plus/network_info_plus.dart';

/// Detects whether the current WiFi connection looks like an open/public
/// network and returns a warning label + color for display in the UI.
class SecurityCheck {
  Future<Map<String, dynamic>> scanWiFiSecurity() async {
    // --- Once network_info_plus is added, replace this block with: ---
    // final info = NetworkInfo();
    // final ssid = await info.getWifiName() ?? "Unknown";
    // ------------------------------------------------------------------
    const String ssid = "Unknown"; // placeholder until plugin is wired in

    final bool looksPublic = ssid.toLowerCase().contains("public") ||
        ssid.toLowerCase().contains("free") ||
        ssid.toLowerCase().contains("hotel") ||
        ssid.toLowerCase().contains("cafe") ||
        ssid == "Unknown";

    if (looksPublic) {
      return {
        "label": "⚠️ Unsecured / Public",
        "color": Colors.orange,
        "advice":
            "This looks like an open or public network. Avoid entering "
                "passwords or banking details; use a VPN if possible.",
      };
    }

    return {
      "label": "✅ Secured",
      "color": Colors.green,
      "advice": "Network appears private and encrypted.",
    };
  }
}