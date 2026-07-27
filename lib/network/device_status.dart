import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Local device context captured alongside a network run. Not a network
/// metric — used to catch two false positives a pure ping/throughput
/// reading can't: a "slow mobile network" that's actually OS battery-saver
/// throttling background data, and a download reading capped by a weak
/// device rather than the link itself.
///
/// Uses `defaultTargetPlatform` rather than `dart:io`'s `Platform` — this
/// file is imported from `main.dart`, which is reachable on Flutter Web,
/// and `dart:io` doesn't compile under dart2js/DDC.
class DeviceStatus {
  final int? batteryPercent;
  final bool? isLowPowerMode;
  final String deviceLabel;

  const DeviceStatus({
    this.batteryPercent,
    this.isLowPowerMode,
    required this.deviceLabel,
  });

  static Future<DeviceStatus> capture() async {
    final battery = await _readBattery();
    final label = await _readDeviceLabel();
    return DeviceStatus(
      batteryPercent: battery.$1,
      isLowPowerMode: battery.$2,
      deviceLabel: label,
    );
  }

  // battery_plus has no Linux or Web implementation, and can still throw on
  // supported platforms if the OS denies the read — treated as "no signal"
  // rather than crashing the diagnosis flow.
  static Future<(int?, bool?)> _readBattery() async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return (null, null);
    }
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      final lowPower = await battery.isInBatterySaveMode;
      return (level, lowPower);
    } catch (_) {
      return (null, null);
    }
  }

  static Future<String> _readDeviceLabel() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await plugin.webBrowserInfo;
        return info.browserName.name;
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await plugin.androidInfo;
          return '${info.manufacturer} ${info.model}';
        case TargetPlatform.iOS:
          final info = await plugin.iosInfo;
          return info.modelName;
        case TargetPlatform.windows:
          final info = await plugin.windowsInfo;
          return '${info.productName} (${info.computerName})';
        case TargetPlatform.macOS:
          final info = await plugin.macOsInfo;
          return info.modelName;
        case TargetPlatform.linux:
          final info = await plugin.linuxInfo;
          return info.prettyName;
        default:
          return 'Unknown device';
      }
    } catch (_) {
      return 'Unknown device';
    }
  }
}
