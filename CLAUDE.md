# smart_network_diagnostic (NetDiagnose)

Flutter app (Android/iOS/Linux/macOS/Web/Windows) that runs a one-tap network
diagnostic: ping latency, download speed, packet loss, and a basic WiFi
security check. App display title is "NetDiagnose"; package/applicationId is
`com.example.smart_network_diagnostic`.

## Layout

- `lib/main.dart` — entire UI (`MyApp`, `HomeScreen`) plus `NetworkTester`,
  a static-method class doing real HTTP-based checks:
  - `testPing()` — HEAD request to `https://www.google.com`, times round trip.
  - `testSpeed()` — GETs `https://proof.ovh.net/files/1Mb.dat`, computes Mbps
    from elapsed time and byte count.
  - `testPacketLoss()` — 5x HEAD requests to the same ping URL, reports
    failure rate as "packet loss %".
- `lib/security_check.dart` — `SecurityCheck.scanWiFiSecurity()`. Currently a
  **stub**: SSID is hardcoded to `"Unknown"` rather than read from the device.
  Comments in the file mark where to wire in `network_info_plus`
  (`NetworkInfo().getWifiName()`). Because SSID is always `"Unknown"`, the
  "looks public" heuristic always fires and the app always reports
  "⚠️ Unsecured / Public".
- `test/widget_test.dart` — **stale**: it's still the default Flutter counter
  template (`find.text('0')`, tapping `Icons.add`) and does not test
  `HomeScreen` or `NetworkTester`/`SecurityCheck` at all. It will fail if run,
  since the counter UI no longer exists.
- `ScanGuard/PasswordVault/180634937/` — an empty, unexplained directory
  unrelated to the Flutter app (numeric name, no file extension, dated
  2025-07-14). Not referenced by any Dart code. Leave it alone unless the user
  explains its purpose or asks for cleanup.
- `.github/modernize/java-upgrade/` — tooling scaffold (hooks/scripts for
  recording tool use), not part of the app itself.
- Standard Flutter platform folders: `android/`, `ios/`, `linux/`, `macos/`,
  `web/`, `windows/`. `build/`, `.dart_tool/` are generated/gitignored.

## Dependencies (pubspec.yaml)

`http`, `connectivity_plus`, `device_info_plus`, `battery_plus`,
`network_info_plus`, `shared_preferences` are all declared, but only `http`
is actually used in `lib/` so far — the rest are pulled in for planned
features (real SSID/connectivity detection, device info, battery status,
persisted scan history) that aren't wired up yet.

## Known gaps / likely next work

1. `SecurityCheck` doesn't actually read the WiFi SSID — needs
   `network_info_plus` wired in (import is commented out in the file).
2. `test/widget_test.dart` doesn't test real app behavior — needs rewriting
   against `HomeScreen`.
3. No persistence of diagnostic history despite `shared_preferences` being a
   dependency.
4. No use yet of `connectivity_plus`, `device_info_plus`, `battery_plus`.

## Commands

- Run: `flutter run`
- Test: `flutter test`
- Analyze: `flutter analyze`
- Get deps: `flutter pub get`
