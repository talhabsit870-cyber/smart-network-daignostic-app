import 'package:flutter/material.dart';

// ── Design tokens ────────────────────────────────────────────────
class AppColors {
  static const bgTop = Color(0xFF000000);
  static const bgBottom = Color(0xFF000000);
  static const surface = Color(0xFF0D0D0D);
  static const surfaceBorder = Color(0xFF1A3A52);
  static const violet = Color(0xFF38BDF8);
  static const violetGlow = Color(0xFF7DD3FC);
  static const magenta = Color(0xFF22D3EE);
  static const coral = Color(0xFFFF6B6B);
  static const amber = Color(0xFFFBBF24);
  static const green = Color(0xFF4ADE80);
  static const textPrimary = Color(0xFFF3EFFF);
  static const textMuted = Color(0xFF7A93A3);
  static const unknown = Color(0xFF3A4A55);
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
