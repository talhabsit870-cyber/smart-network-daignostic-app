import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;

import '../core/cta_button.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../diagnosis/diagnosis_engine.dart';
import '../history/history_entry.dart';
import '../history/history_screen.dart';
import '../history/history_store.dart';
import '../network/device_status.dart';
import '../network/network_tester.dart';
import '../result/report_card.dart';
import '../result/speed_gauge.dart';
import '../security/security_check.dart';
import 'wave_painter.dart';

/// Duration used for the one-tap "Deep Test" mode, regardless of the user's
/// saved test-duration setting — a stability-focused reading is the whole
/// point of tapping it, so it always runs long.
const _deepTestDuration = Duration(seconds: 20);
const _deepTestBufferbloatLoadDuration = Duration(seconds: 12);
const _simpleTestDuration = Duration(seconds: 8);
const _simpleBufferbloatLoadDuration = Duration(seconds: 5);

/// Deep Test's whole point is a longer, stability-focused reading — but
/// without this, its ping phase ran the exact same fixed 6 probes as Simple
/// Test, so "deep" bought it nothing extra on the one number (latency)
/// that's cheapest to sample more of. More probes means less influence from
/// any single lucky/unlucky RTT on the reported avg/jitter.
const _simplePingAttempts = 6;
const _deepPingAttempts = 15;

/// Download, upload, ping, and bufferbloat run sequentially (see
/// `_startDiagnosis`) so none of them contend for bandwidth with another —
/// only the lightweight, non-bandwidth tail (security scan, path check, IP
/// lookup) runs concurrently, after throughput is already measured. So the
/// true total is genuinely close to the sum of every phase's own duration,
/// plus this rough allowance for that tail and the quick ping probes.
const _otherPhasesEstimate = Duration(seconds: 8);

Duration get _simpleTotalEstimate =>
    _simpleTestDuration * 2 + _simpleBufferbloatLoadDuration + _otherPhasesEstimate;
Duration get _deepTotalEstimate =>
    _deepTestDuration * 2 + _deepTestBufferbloatLoadDuration + _otherPhasesEstimate;

/// The launcher screen: idle dial, connection badge, Start Test CTA, and —
/// once a run finishes — the full report ([ReportCard]) inline below,
/// expandable in place instead of pushed to its own page.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  bool _isDiagnosing = false;
  double _speedValue = 0; // Mbps, drives the download needle
  double _uploadValue = 0; // Mbps, drives the upload needle
  String _phaseLabel = "Ready to test";
  String _connectionLabel = "--";
  String? _wifiSsid;

  NetworkSnapshot? _primarySnapshot;
  Map<String, dynamic>? _security;
  IpInfoResult? _ipInfo;
  DiagnosisResult? _diagnosis;
  DateTime? _resultTimestamp;
  String _diagnosisContext = '';
  bool _reportExpanded = false;
  bool _lastRunDeep = false;
  bool _cancelRequested = false;
  int _elapsedSeconds = 0;
  Timer? _elapsedTimer;
  CancelToken? _cancelToken;

  late final AnimationController _needleController;
  late final AnimationController _uploadNeedleController;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _needleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _uploadNeedleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _refreshConnectionLabel();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _needleController.dispose();
    _uploadNeedleController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Future<void> _refreshConnectionLabel() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() => _connectionLabel = DiagnosisEngine.labelFor(connectivity));
    }
  }

  Future<void> _startDiagnosis({bool deep = false}) async {
    final duration = deep ? _deepTestDuration : _simpleTestDuration;
    final bufferbloatLoad =
        deep ? _deepTestBufferbloatLoadDuration : _simpleBufferbloatLoadDuration;
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    final durationHint = ' (~${duration.inSeconds}s)';

    _elapsedTimer?.cancel();
    setState(() {
      _isDiagnosing = true;
      _cancelRequested = false;
      _lastRunDeep = deep;
      _speedValue = 0;
      _uploadValue = 0;
      _elapsedSeconds = 0;
      _phaseLabel = "Testing download…$durationHint";
    });
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });

    // Ping, download, upload, and bufferbloat each need the link to
    // themselves — measuring any of them while another is also pulling
    // bandwidth (as a fully concurrent run briefly did) makes every number
    // read artificially low, since they're competing for the same capacity.
    // This is why Ookla/Speedtest.net run ping → download → upload as
    // separate, non-overlapping phases instead of all at once; bufferbloat
    // additionally needs its *own* uncontested idle baseline before
    // anything saturates the link, or the idle-vs-loaded comparison is
    // meaningless. Only the lightweight, non-bandwidth phases (security
    // scan, path check, IP lookup) run concurrently, after throughput is
    // already measured, since they don't affect its accuracy.
    final download = await NetworkTester.testDownloadSpeed(
        duration: duration, cancelToken: cancelToken);
    if (_bailIfCancelled()) return;
    if (mounted) {
      _needleController.forward(from: 0);
      setState(() {
        _speedValue = download.success ? download.mbps : 0;
        _phaseLabel = "Testing upload…$durationHint";
      });
    }

    final upload = await NetworkTester.testUploadSpeed(
        duration: duration, cancelToken: cancelToken);
    if (_bailIfCancelled()) return;
    if (mounted) {
      _uploadNeedleController.forward(from: 0);
      setState(() {
        _uploadValue = upload.success ? upload.mbps : 0;
        _phaseLabel = "Testing latency…";
      });
    }

    final ping = await NetworkTester.testPingDetailed(
      attempts: deep ? _deepPingAttempts : _simplePingAttempts,
      cancelToken: cancelToken,
    );
    if (_bailIfCancelled()) return;
    if (mounted) setState(() => _phaseLabel = "Testing latency under load…");

    final bufferbloat = await NetworkTester.testBufferbloat(
      idlePing: ping,
      loadDuration: bufferbloatLoad,
      cancelToken: cancelToken,
    );
    if (_bailIfCancelled()) return;
    if (mounted) setState(() => _phaseLabel = "Checking security, path & IP…");

    final securityFuture = SecurityCheck().scanWiFiSecurity();
    final pathFuture = NetworkTester.testNetworkPath();
    final ipFuture = NetworkTester.testPublicIpInfo();

    final security = await securityFuture;
    if (_bailIfCancelled()) return;
    if (mounted) setState(() => _wifiSsid = security['ssid'] as String?);

    final pathCheck = await pathFuture;
    if (_bailIfCancelled()) return;

    final ipInfo = await ipFuture;
    if (_bailIfCancelled()) return;
    if (mounted) setState(() => _phaseLabel = "Diagnosing…");

    final deviceStatus = await DeviceStatus.capture();
    final connectivity = await Connectivity().checkConnectivity();
    final connectionLabel = DiagnosisEngine.labelFor(connectivity);

    final snapshot = NetworkSnapshot(
      connectionLabel: connectionLabel,
      ping: ping,
      download: download,
      upload: upload,
      deviceStatus: deviceStatus,
      bufferbloat: bufferbloat,
      pathCheck: pathCheck,
    );

    final diagnosis = DiagnosisEngine.evaluateSingle(snapshot);

    await HistoryStore.add(HistoryEntry.fromRun(
      connectionLabel: connectionLabel,
      ping: ping,
      download: download,
      upload: upload,
      securityLabel: security['label'] as String,
      diagnosis: diagnosis,
      bufferbloat: bufferbloat,
      pathCheck: pathCheck,
      isDeep: deep,
    ));

    _elapsedTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _connectionLabel = connectionLabel;
      _isDiagnosing = false;
      _phaseLabel = "Ready to test";
      _primarySnapshot = snapshot;
      _security = security;
      _ipInfo = ipInfo;
      _diagnosis = diagnosis;
      _resultTimestamp = DateTime.now();
      _diagnosisContext = connectionLabel;
      _reportExpanded = true;
    });

    if (security['hasThreat'] == true) {
      _showSecurityWarning(security);
    }
  }

  /// Checks the cancel flag between test phases and, if set, resets to idle
  /// without saving history or showing a report. [_stopDiagnosis] already
  /// force-closes every in-flight HTTP connection via [_cancelToken], so
  /// whatever phase was running throws/returns almost immediately instead of
  /// running out its full duration — this just does the final state reset
  /// once that phase's `await` actually resolves.
  bool _bailIfCancelled() {
    if (!_cancelRequested) return false;
    _elapsedTimer?.cancel();
    _cancelToken = null;
    if (mounted) {
      setState(() {
        _isDiagnosing = false;
        _cancelRequested = false;
        _phaseLabel = "Ready to test";
        _speedValue = 0;
        _uploadValue = 0;
      });
    }
    return true;
  }

  void _stopDiagnosis() {
    // Freeze the timer and abort every in-flight request immediately —
    // don't wait for the current phase to finish on its own.
    _elapsedTimer?.cancel();
    _cancelToken?.cancel();
    setState(() {
      _cancelRequested = true;
      _phaseLabel = "Stopping…";
    });
  }

  void _showSecurityWarning(Map<String, dynamic> security) {
    final bool isSpoofed = security['isSpoofed'] as bool;
    final String? ssid = security['ssid'] as String?;
    final String? bssid = security['bssid'] as String?;
    final Color color = security['color'] as Color;
    final List<String> threats = List<String>.from(security['threats'] as List);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Icon(isSpoofed ? Icons.warning_amber_rounded : Icons.wifi_off_rounded,
                color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                security['label'] as String,
                style: TextStyle(color: color, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: threats
                .map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(t,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 13)),
                    ))
                .toList(),
          ),
        ),
        actions: [
          if (isSpoofed && ssid != null && bssid != null)
            TextButton(
              onPressed: () async {
                await SecurityCheck.trustCurrentNetwork(ssid, bssid);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Trust this network'),
            ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.accentPrimary),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _onRunAgain() => _runTest(deep: _lastRunDeep);

  /// Clears the previous run's report — if there is one — before starting a
  /// new one, so a stale report never stays visible while a fresh run is in
  /// progress. Both the top CTA row and the ReportCard's internal "Test
  /// Again" button go through this instead of calling `_startDiagnosis`
  /// directly.
  void _runTest({required bool deep}) {
    if (_diagnosis != null) {
      setState(() {
        _primarySnapshot = null;
        _security = null;
        _ipInfo = null;
        _diagnosis = null;
        _resultTimestamp = null;
        _diagnosisContext = '';
        _reportExpanded = false;
      });
    }
    _startDiagnosis(deep: deep);
  }

  void _clearReport() {
    setState(() {
      _primarySnapshot = null;
      _security = null;
      _ipInfo = null;
      _diagnosis = null;
      _resultTimestamp = null;
      _diagnosisContext = '';
      _reportExpanded = false;
      _speedValue = 0;
      _uploadValue = 0;
      _phaseLabel = "Ready to test";
    });
  }

  bool get busy => _isDiagnosing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          // ConstrainedBox + SingleChildScrollView instead of Spacer: fills
          // the screen with spaceBetween on viewports tall enough for the
          // (now larger) gauge, but scrolls instead of overflowing on
          // shorter ones rather than hard-erroring.
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: AppBody(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildTopBar(),
                          const SizedBox(height: 16),
                          _buildLivePanel(),
                          const SizedBox(height: 16),
                          _buildWave(),
                          const SizedBox(height: 20),
                          if (busy) ...[
                            PrimaryCtaButton(
                              icon: Icons.stop_circle_outlined,
                              label: _cancelRequested ? "Stopping..." : "Stop Test",
                              onPressed: _cancelRequested ? null : _stopDiagnosis,
                            ),
                          ] else ...[
                            PrimaryCtaButton(
                              label: _diagnosis != null
                                  ? "Test Again"
                                  : "Start Test (~${_simpleTotalEstimate.inSeconds}s)",
                              onPressed: () => _runTest(deep: false),
                            ),
                            const SizedBox(height: 10),
                            SecondaryCtaButton(
                              icon: Icons.speed,
                              label: "Deep Test (~${_deepTotalEstimate.inSeconds}s)",
                              onPressed: () => _runTest(deep: true),
                            ),
                          ],
                          if (_diagnosis != null) const SizedBox(height: 20),
                          ReportCard(
                            timestamp: _resultTimestamp,
                            diagnosisContext: _diagnosisContext,
                            primary: _primarySnapshot,
                            security: _security,
                            ipInfo: _ipInfo,
                            diagnosis: _diagnosis,
                            expanded: _reportExpanded,
                            isDeep: _lastRunDeep,
                            onToggleExpanded: () =>
                                setState(() => _reportExpanded = !_reportExpanded),
                            onRunAgain: _onRunAgain,
                            onClear: _clearReport,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: const [
            Icon(Icons.blur_on, color: AppColors.accentPrimaryGlow, size: 22),
            SizedBox(width: 8),
            Text(
              "NetDiagnose",
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.history,
                    color: AppColors.accentPrimaryGlow, size: 20),
                tooltip: 'Scan history',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Groups the connection badge, both gauges, and the phase label into a
  /// single bordered panel — one "live status" module instead of loose
  /// elements floating on the background.
  Widget _buildLivePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildConnectionBadge(),
          const SizedBox(height: 18),
          _buildGaugeRow(),
          const SizedBox(height: 14),
          Text(
            _phaseLabel,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              letterSpacing: 1,
            ),
          ),
          if (busy) ...[
            const SizedBox(height: 4),
            Text(
              _formatElapsed(_elapsedSeconds),
              style: const TextStyle(
                color: AppColors.accentPrimaryGlow,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _connectionBadgeLabel() {
    if (_connectionLabel == "Wi-Fi" && _wifiSsid != null && _wifiSsid!.isNotEmpty) {
      return _wifiSsid!;
    }
    return _connectionLabel;
  }

  Widget _buildConnectionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(connectionIcon(_connectionLabel),
              color: AppColors.accentPrimaryGlow, size: 16),
          const SizedBox(width: 8),
          Text(_connectionBadgeLabel(),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildGaugeRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gaugeSize = (constraints.maxWidth * 0.42).clamp(150.0, 190.0);
        return Row(
          children: [
            Expanded(
              child: _buildGaugeCard(
                label: 'Download',
                size: gaugeSize,
                controller: _needleController,
                value: _speedValue,
                maxValue: 100,
                color: AppColors.accentPrimaryGlow,
              ),
            ),
            SizedBox(
              height: gaugeSize * 0.8,
              child: const VerticalDivider(
                  color: AppColors.surfaceBorder, width: 1, thickness: 1),
            ),
            Expanded(
              child: _buildGaugeCard(
                label: 'Upload',
                size: gaugeSize,
                controller: _uploadNeedleController,
                value: _uploadValue,
                maxValue: 100,
                color: AppColors.accentSecondary,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGaugeCard({
    required String label,
    required double size,
    required AnimationController controller,
    required double value,
    required double maxValue,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final animatedValue =
                value * Curves.easeOutCubic.transform(controller.value);
            return SpeedGauge(value: animatedValue, size: size, maxValue: maxValue);
          },
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
      ],
    );
  }

  Widget _buildWave() {
    return SizedBox(
      height: 40,
      child: AnimatedBuilder(
        animation: _waveController,
        builder: (context, child) {
          return CustomPaint(
            painter: WavePainter(
              phase: _waveController.value * 2 * math.pi,
              isActive: busy,
            ),
            size: const Size(double.infinity, 40),
          );
        },
      ),
    );
  }
}
