# smart_network_diagnostic (NetDiagnose)

Flutter app (Android/iOS/Linux/macOS/Web/Windows) that runs a one-tap network
diagnostic: ping latency, download/upload speed, packet loss, jitter, a WiFi
security check, connection-type detection, ISP/router/mobile fault diagnosis,
and scan history. App display title is "NetDiagnose"; package/applicationId
is `com.example.smart_network_diagnostic`.

## Layout

`lib/` is organized by feature module (flat, lowercase folders — no nested
`features/` wrapper). `lib/main.dart` is now just the entry point
(`void main() => runApp(const MyApp())`); `lib/app.dart` holds `MyApp`
(root `MaterialApp`).

- `lib/core/theme.dart` — shared design tokens: `AppColors` and
  `connectionIcon()`. Extracted out of the old `main.dart` specifically so
  screens/widgets in other modules (`home`, `history`, `result`) don't have
  to import the app entry point just to reach a color constant.
- `lib/home/` — the launcher screen, now also the report screen.
  - `home_screen.dart` — `HomeScreen`/`_HomeScreenState`. Orchestrates the
    other modules: runs download/upload/ping tests, calls `SecurityCheck`
    and `DiagnosisEngine`, saves each run via `HistoryStore`, hosts the
    dual download/upload gauge row (each animated by its own
    `AnimationController`), and renders the finished run's `ReportCard`
    inline below the CTAs — no separate results page/navigation. The
    report auto-expands on completion and collapses again the moment
    "Test Again" is tapped. The top-bar history icon pushes `HistoryScreen`.
  - `wave_painter.dart` — `WavePainter`, the animated bottom activity
    waveform `CustomPainter` used by `HomeScreen`.
- `lib/network/` — raw network measurement.
  - `network_tester.dart` — `NetworkTester`, static-method class doing real
    HTTP-based checks, each with a CORS-friendly fallback host for Flutter
    Web:
    - `testPingDetailed()` — several probes against a reachable host,
      returns `PingStats` (sent/received/rtts, exposing loss %, min/avg/max,
      jitter).
    - `testDownloadSpeed()` / `testUploadSpeed()` — real GET/POST transfers,
      return `SpeedResult` (success, mbps, bytes, seconds, source/error).
    - `testPublicIpInfo()` — public IP + ISP/city/country via `ipwho.is`
      (no key, CORS-enabled); falls back to `api.ipify.org` (IP only) if
      `ipwho.is` is unreachable or rate-limited, so a single provider outage
      only degrades the result instead of blanking it.
  - `device_status.dart` — `DeviceStatus.capture()` reads local device
    context via `battery_plus` (battery %, Low Power Mode) and
    `device_info_plus` (device/OS label), all best-effort and null-safe on
    unsupported platforms (`battery_plus` has no Linux/Web backend).
    Attached to `NetworkSnapshot.deviceStatus` and consumed by
    `DiagnosisEngine` for the Low Power Mode caveat below; also shown as a
    context line in `HomeScreen`'s stats panel. Not a performance dashboard —
    deliberately scoped to the one thing that changes a network verdict.
- `lib/diagnosis/diagnosis_engine.dart` — `DiagnosisEngine`:
  - `labelFor(List<ConnectivityResult>)` — maps `connectivity_plus` results to
    "Wi-Fi" / "Mobile Data" / "Ethernet" / "VPN" / "Offline". Already wired
    in and displayed in the bottom bar of `HomeScreen`.
  - `evaluateSingle(NetworkSnapshot)` — single-run heuristic verdict. Checks
    `NetworkSnapshot.deviceStatus?.isLowPowerMode` first on Mobile Data runs,
    so battery-saver throttling isn't mistaken for a carrier problem.
  - `compare(NetworkSnapshot, NetworkSnapshot)` — Wi-Fi vs mobile run
    comparison, assigns blame to ISP/router/mobile network; also appends a
    Low Power Mode caveat to a "mobile network issue" verdict when
    applicable.
- `lib/security/` — WiFi security check.
  - `security_check.dart` — `SecurityCheck.scanWiFiSecurity()` prefers a
    native OS-level read (`wifi_native_io.dart`, currently Windows via
    `netsh wlan show interfaces`) since `network_info_plus` has no Windows
    backend at all and, unlike `network_info_plus` on any platform, `netsh`
    also reports the actual authentication type (confirms open/WEP networks
    instead of guessing from the SSID). Falls back to `network_info_plus` +
    `Permission.locationWhenInUse` (via `permission_handler`) otherwise, since
    Android/iOS withhold the real SSID without location permission. If the
    SSID can't be resolved (permission denied, not on WiFi, hidden network) it
    reports "❓ Unable to verify" rather than defaulting to a public-network
    warning. Requires the manifest/plist permission entries below.
  - `wifi_native_stub.dart` — no-op non-Windows counterpart to
    `wifi_native_io.dart`, selected via a conditional import
    (`'wifi_native_stub.dart' if (dart.library.io) 'wifi_native_io.dart'`).
- `lib/history/` — diagnostic history.
  - `history_entry.dart` — `HistoryEntry`, a compact JSON-serializable
    summary of one run.
  - `history_store.dart` — `HistoryStore` persists a capped (50) list to
    `shared_preferences` under key `diagnostic_history`.
  - `history_screen.dart` — `HistoryScreen` lists past runs newest-first
    with a clear-history action.
- `lib/result/` — the diagnostic report, rendered inline on `HomeScreen`.
  - `report_card.dart` — `ReportCard`, an expandable card (verdict header +
    collapsible body) built from a solo `NetworkSnapshot`/`DiagnosisResult`
    or a compare pair; renders nothing until the first run completes.
    Replaced the old pushed `ResultScreen` page.
  - `signal_path.dart` — `SignalPath`, the per-hop fault-chain
    visualization widget.
  - `speed_gauge.dart` — `SpeedGauge`, the needle gauge widget (used twice
    on `HomeScreen`, for download and upload).
- `test/widget_test.dart` — targets `HomeScreen` (via `MyApp` from
  `lib/app.dart`); assertions match the idle UI text (`Download`, `Upload`
  gauge labels, `Ready to test`, `Start Test`, `Compare Wi-Fi vs Mobile`).
- `ScanGuard/PasswordVault/180634937/` — an empty, unexplained directory
  unrelated to the Flutter app (numeric name, no file extension, dated
  2025-07-14). Not referenced by any Dart code. Leave it alone unless the user
  explains its purpose or asks for cleanup.
- `.github/modernize/java-upgrade/` — tooling scaffold (hooks/scripts for
  recording tool use), not part of the app itself.
- Standard Flutter platform folders: `android/`, `ios/`, `linux/`, `macos/`,
  `web/`, `windows/`. `build/`, `.dart_tool/` are generated/gitignored.

## Dependencies (pubspec.yaml)

`http`, `connectivity_plus`, `network_info_plus`, `shared_preferences`,
`permission_handler`, `device_info_plus`, and `battery_plus` are all
actively used (the latter two via `lib/network/device_status.dart`).

## Platform permissions

- Android (`android/app/src/main/AndroidManifest.xml`): `ACCESS_WIFI_STATE`,
  `ACCESS_NETWORK_STATE`, `ACCESS_FINE_LOCATION` — required for
  `network_info_plus` to return a real SSID instead of null. `INTERNET` is
  now declared here too (previously only in the debug/profile manifests,
  which meant release builds would have silently failed every HTTP-based
  test).
- iOS (`ios/Runner/Info.plist`): `NSLocationWhenInUseUsageDescription` — same
  reason; also required for the runtime permission prompt.

## Known gaps / likely next work

1. SSID resolution (`network_info_plus` path) and the Windows `netsh` path
   in `lib/security/wifi_native_io.dart` can't be manually verified on this dev
   machine (Windows, no Android/iOS hardware attached) — confirm on actual
   devices that the location-permission prompt appears, a real SSID (not
   "Unknown") comes back, and `netsh` parsing holds up against real driver
   output.
2. `testPublicIpInfo()`'s fallback (`api.ipify.org`) only returns a bare IP,
   no ISP/city/country — acceptable degraded behavior, not a full second
   data source.

## Commands

- Run: `flutter run`
- Test: `flutter test`
- Analyze: `flutter analyze`
- Get deps: `flutter pub get`

## Commit conventions

Subject line only — no commit body/description text, and no
`Co-Authored-By:` trailer.
