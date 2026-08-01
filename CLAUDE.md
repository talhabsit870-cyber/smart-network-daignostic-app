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
    "Test Again" is tapped. The top-bar history icon pushes `HistoryScreen`;
    a tune icon next to it opens `showTestSettingsSheet()` (see
    `lib/settings/`). A third CTA, "Deep Test", calls `_startDiagnosis(deep:
    true)`, which overrides the saved test-duration setting with a fixed
    45s (`_deepTestDuration`) and a longer 15s bufferbloat load phase
    (`_deepTestBufferbloatLoadDuration`) regardless of what's saved — the
    point of tapping it is a longer, stability-focused reading, so it
    always runs long. `_lastRunDeep` remembers whether the just-finished
    run was a Deep Test so "Test Again" repeats the same mode; the Compare
    flow (`_captureSnapshot()`) always uses the saved settings, never deep.
  - `wave_painter.dart` — `WavePainter`, the animated bottom activity
    waveform `CustomPainter` used by `HomeScreen`.
- `lib/network/` — raw network measurement.
  - `network_tester.dart` — `NetworkTester`, static-method class doing real
    HTTP-based checks, each with a CORS-friendly fallback host for Flutter
    Web:
    - `testPingDetailed()` — several probes against a reachable host,
      returns `PingStats` (sent/received/rtts, exposing loss %, min/avg/max,
      jitter).
    - `testDownloadSpeed()` / `testUploadSpeed()` — real GET/POST transfers
      over `streams` (default 4) concurrent connections for `duration`
      (default 8s), summed against a shared clock, since a single TCP
      stream caps out well below what fast links can deliver. Each stream's
      internal attempt budget scales with `duration` (`max(baseline,
      duration.inSeconds * 5)`) — otherwise a long "Deep Test" run gets
      silently cut short once streams exhaust an attempt cap sized for the
      8s default before the wall-clock duration is reached. Return
      `SpeedResult` (success, mbps, bytes, seconds, source/error).
    - `testBufferbloat({required idlePing})` — saturates the link with
      concurrent download streams while pinging, and compares that loaded
      latency (median RTT, not mean — the ping probes share an isolate with
      the saturation downloads) against `idlePing` (reused from the
      just-finished ping phase rather than re-measured). Returns
      `BufferbloatResult` (idleMs/loadedMs/increaseMs, and a Waveform-style
      A+–F `grade`). Attached to `NetworkSnapshot.bufferbloat` on solo runs
      only (not the Wi-Fi/mobile compare flow); deliberately kept out of
      `DiagnosisEngine`'s verdict/blame logic — it surfaces as its own report
      tile, not another ISP/router signal.
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
- `lib/settings/` — user-configurable speed test parameters.
  - `test_settings.dart` — `TestSettings` (streams, durationSeconds, both
    clamped — 1–8 streams, 5–60s) and `TestSettingsStore`, which persists it
    to `shared_preferences` (mirrors `HistoryStore`'s static-class/per-call
    `SharedPreferences.getInstance()` pattern rather than a second storage
    mechanism). Its defaults (4 streams, 8s) intentionally match
    `NetworkTester.testDownloadSpeed()`/`testUploadSpeed()`'s own defaults,
    so an install that never opens the settings sheet behaves identically
    to before this setting existed.
  - `settings_sheet.dart` — `showTestSettingsSheet()`, a modal bottom sheet
    with sliders for stream count and duration; saved settings apply to
    "Start Test" and "Compare Wi-Fi vs Mobile" but not "Deep Test" (see
    `lib/home/home_screen.dart`), which always overrides duration.
- `lib/history/` — diagnostic history.
  - `history_entry.dart` — `HistoryEntry`, a compact JSON-serializable
    summary of one run, including an optional bufferbloat grade/increase
    and an `isDeep` flag marking Deep Test runs (nullable/defaulted fields
    so old persisted entries without them still parse). `HistoryScreen`
    shows a "DEEP" badge next to the verdict title when set. Deep runs are
    still plotted in `TrendChart` alongside normal 8s-default runs — a
    45s-duration reading next to 8s ones is a deliberate simplification,
    not an oversight; split them out if that ever misleads a real trend.
  - `history_store.dart` — `HistoryStore` persists a capped (50) list to
    `shared_preferences` under key `diagnostic_history`.
  - `history_screen.dart` — `HistoryScreen` lists past runs newest-first
    with a clear-history action, and — once there are 2+ entries — a
    `TrendChart` above the list.
  - `trend_chart.dart` — `TrendChart`, a small `CustomPainter` line chart of
    download/upload Mbps across past runs (oldest-first; the newest-first
    `HistoryStore` order is reversed before it's handed in), plus a packet-loss
    marker row: small dots pinned to the chart's bottom edge (not a shared
    line — loss % and Mbps are different scales) at each run with nonzero
    `HistoryEntry.lossPercent`, colored amber/coral by the same severity
    threshold as `report_card.dart`'s ping tile. Only solo runs ever reach
    history (`HomeScreen._finishCompare` never calls `HistoryStore.add`), so
    the series is a single unbroken run of solo scans, not split by
    connection type.
- `lib/result/` — the diagnostic report, rendered inline on `HomeScreen`.
  - `report_card.dart` — `ReportCard`, an expandable card (verdict header +
    collapsible body) built from a solo `NetworkSnapshot`/`DiagnosisResult`
    or a compare pair; renders nothing until the first run completes.
    Replaced the old pushed `ResultScreen` page. The header's close icon
    calls `onClear` (wired to `HomeScreen._clearReport()`, which also resets
    the gauges) so a run can be dismissed without starting a new one. The
    body's "Download PDF" button builds a PDF via `report_pdf.dart` and
    hands it to `package:printing`'s share/save sheet. The details grid's
    "Latency under load" row spells out the raw idle/loaded/delta numbers
    behind the bufferbloat grade badge (`BufferbloatResult.idleMs`/
    `loadedMs`/`increaseMs`), colored by the same grade-derived
    good/borderline/bad logic as the badge.
  - `report_pdf.dart` — `buildReportPdf()`, renders the same data as
    `ReportCard` through `package:pdf`'s widget set (`pw.*`) into PDF bytes,
    including the bufferbloat grade on solo runs plus the same raw
    idle/loaded/delta numbers in the details card. Kept independent of
    `ReportCard`'s private Flutter-widget formatting helpers since it's a
    different widget tree entirely.
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
`pdf` and `printing` back the report's "Download PDF" action
(`lib/result/report_pdf.dart`, `lib/result/report_card.dart`).

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
