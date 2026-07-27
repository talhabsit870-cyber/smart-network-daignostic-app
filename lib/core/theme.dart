import 'package:flutter/material.dart';

// ── Design tokens ────────────────────────────────────────────────
class AppColors {
  static const bgTop = Color(0xFF050B16);
  static const bgBottom = Color(0xFF01030A);
  static const surface = Color(0xFF0A121F);
  static const surfaceBorder = Color(0xFF161F35);
  static const accentPrimary = Color(0xFF178F6D);
  static const accentPrimaryGlow = Color(0xFF57C79E);
  static const accentSecondary = Color(0xFF1C7FB8);
  static const coral = Color(0xFFFF6B6B);
  static const amber = Color(0xFFFBBF24);
  static const green = Color(0xFF4ADE80);
  static const textPrimary = Color(0xFFD2E4F0);
  static const textMuted = Color(0xFF57687F);
  static const unknown = Color(0xFF3A4A55);

  static const accentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [accentPrimary, accentSecondary],
  );
}

IconData connectionIcon(String label) {
  switch (label) {
    case 'Wi-Fi':
      return Icons.wifi;
    case 'Mobile Data':
      return Icons.signal_cellular_alt;
    case 'Ethernet':
      return Icons.settings_ethernet;
    case 'VPN':
      return Icons.vpn_key;
    case 'Offline':
      return Icons.wifi_off;
    default:
      return Icons.podcasts_rounded;
  }
}
