import 'package:shared_preferences/shared_preferences.dart';

/// User-configurable speed test parameters: parallel connection count and
/// test duration. Kept separate from the one-tap "Deep Test" mode — Deep
/// Test overrides duration for a single run without touching the saved
/// setting.
class TestSettings {
  static const int minStreams = 1;
  static const int maxStreams = 8;
  static const int minDurationSeconds = 5;
  static const int maxDurationSeconds = 60;

  // Must match testDownloadSpeed()/testUploadSpeed()'s own defaults in
  // network_tester.dart, so an unconfigured install behaves identically to
  // before this setting existed.
  static const int defaultStreams = 4;
  static const int defaultDurationSeconds = 8;

  final int streams;
  final int durationSeconds;

  const TestSettings({
    this.streams = defaultStreams,
    this.durationSeconds = defaultDurationSeconds,
  });

  Duration get duration => Duration(seconds: durationSeconds);

  TestSettings copyWith({int? streams, int? durationSeconds}) => TestSettings(
        streams: streams ?? this.streams,
        durationSeconds: durationSeconds ?? this.durationSeconds,
      );
}

/// Persists [TestSettings] to device storage, reusing the same
/// `shared_preferences` instance/pattern as `HistoryStore`.
class TestSettingsStore {
  static const _streamsKey = 'test_settings_streams';
  static const _durationKey = 'test_settings_duration_seconds';

  static Future<TestSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final streams = (prefs.getInt(_streamsKey) ?? TestSettings.defaultStreams)
        .clamp(TestSettings.minStreams, TestSettings.maxStreams);
    final durationSeconds =
        (prefs.getInt(_durationKey) ?? TestSettings.defaultDurationSeconds)
            .clamp(TestSettings.minDurationSeconds, TestSettings.maxDurationSeconds);
    return TestSettings(streams: streams, durationSeconds: durationSeconds);
  }

  static Future<void> save(TestSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _streamsKey,
      settings.streams.clamp(TestSettings.minStreams, TestSettings.maxStreams),
    );
    await prefs.setInt(
      _durationKey,
      settings.durationSeconds
          .clamp(TestSettings.minDurationSeconds, TestSettings.maxDurationSeconds),
    );
  }
}
