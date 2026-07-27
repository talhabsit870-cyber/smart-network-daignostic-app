import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
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
import '../result/result_screen.dart';
import '../result/speed_gauge.dart';
import '../security/security_check.dart';
import 'wave_painter.dart';

/// The launcher screen: idle dial, connection badge, Start/Compare — the
/// live test ritual happens here, but the full report lives on its own
/// page ([ResultScreen]) so this screen never grows past "ready to test".
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  bool _isDiagnosing = false;
  bool _isComparing = false;
  double _speedValue = 0; // Mbps, drives the needle
  String _phaseLabel = "Ready to test";
  String _connectionLabel = "--";

  late final AnimationController _needleController;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _needleController = AnimationController(
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
    _needleController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Future<void> _refreshConnectionLabel() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() => _connectionLabel = DiagnosisEngine.labelFor(connectivity));
    }
  }

  Future<NetworkSnapshot> _captureSnapshot() async {
    final download = await NetworkTester.testDownloadSpeed();
    final upload = await NetworkTester.testUploadSpeed();
    final ping = await NetworkTester.testPingDetailed();
    final connectivity = await Connectivity().checkConnectivity();
    final deviceStatus = await DeviceStatus.capture();
    return NetworkSnapshot(
      connectionLabel: DiagnosisEngine.labelFor(connectivity),
      ping: ping,
      download: download,
      upload: upload,
      deviceStatus: deviceStatus,
    );
  }

  Future<void> _startDiagnosis() async {
    setState(() {
      _isDiagnosing = true;
      _speedValue = 0;
      _phaseLabel = "Testing download…";
    });

    final download = await NetworkTester.testDownloadSpeed();
    if (mounted) {
      _needleController.forward(from: 0);
      setState(() {
        _speedValue = download.success ? download.mbps.clamp(0, 100) : 0;
        _phaseLabel = "Testing upload…";
      });
    }

    final upload = await NetworkTester.testUploadSpeed();
    if (mounted) setState(() => _phaseLabel = "Testing latency…");

    final ping = await NetworkTester.testPingDetailed();
    if (mounted) setState(() => _phaseLabel = "Checking security & diagnosing…");

    final security = await SecurityCheck().scanWiFiSecurity();
    final ipInfo = await NetworkTester.testPublicIpInfo();
    final deviceStatus = await DeviceStatus.capture();
    final connectivity = await Connectivity().checkConnectivity();
    final connectionLabel = DiagnosisEngine.labelFor(connectivity);

    final snapshot = NetworkSnapshot(
      connectionLabel: connectionLabel,
      ping: ping,
      download: download,
      upload: upload,
      deviceStatus: deviceStatus,
    );

    final diagnosis = DiagnosisEngine.evaluateSingle(snapshot);

    await HistoryStore.add(HistoryEntry.fromRun(
      connectionLabel: connectionLabel,
      ping: ping,
      download: download,
      upload: upload,
      securityLabel: security['label'] as String,
      diagnosis: diagnosis,
    ));

    if (!mounted) return;
    setState(() {
      _connectionLabel = connectionLabel;
      _isDiagnosing = false;
      _phaseLabel = "Ready to test";
    });

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultScreen(
        timestamp: DateTime.now(),
        diagnosisContext: connectionLabel,
        primary: snapshot,
        security: security,
        ipInfo: ipInfo,
        diagnosis: diagnosis,
        onRunAgain: () {
          Navigator.of(context).pop();
          _startDiagnosis();
        },
      ),
    ));

    if (mounted && security['hasThreat'] == true) {
      _showSecurityWarning(security);
    }
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

  Future<void> _startCompare() async {
    setState(() => _isComparing = true);
    final baseline = await _captureSnapshot();
    setState(() => _isComparing = false);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('First run captured',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Captured on ${baseline.connectionLabel}: '
          '${baseline.download.success ? '${baseline.download.mbps.toStringAsFixed(1)} Mbps down' : 'download failed'}, '
          '${baseline.ping.avgMs?.toStringAsFixed(0) ?? '--'}ms ping.\n\n'
          'Now switch this device to a different connection (toggle Wi-Fi off '
          'for mobile data, or back on) and tap Continue to run the second test.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.accentPrimary),
            onPressed: () {
              Navigator.of(ctx).pop();
              _finishCompare(baseline);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _finishCompare(NetworkSnapshot baseline) async {
    setState(() => _isComparing = true);
    final second = await _captureSnapshot();
    final result = DiagnosisEngine.compare(baseline, second);
    final diagnosisContext =
        result.verdict == DiagnosisVerdict.mobileIssue ? 'Mobile Data' : 'Wi-Fi';

    if (!mounted) return;
    setState(() => _isComparing = false);

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultScreen(
        timestamp: DateTime.now(),
        diagnosisContext: diagnosisContext,
        primary: baseline,
        secondary: second,
        diagnosis: result,
        onRunAgain: () {
          Navigator.of(context).pop();
          _startCompare();
        },
      ),
    ));
  }

  bool get busy => _isDiagnosing || _isComparing;

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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildTopBar(),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildConnectionBadge(),
                              const SizedBox(height: 24),
                              _buildGauge(),
                              const SizedBox(height: 12),
                              Text(
                                _phaseLabel,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildWave(),
                              const SizedBox(height: 24),
                              PrimaryCtaButton(
                                label: _isDiagnosing ? "Testing..." : "Start Test",
                                onPressed: busy ? null : _startDiagnosis,
                              ),
                              const SizedBox(height: 12),
                              SecondaryCtaButton(
                                icon: Icons.compare_arrows,
                                label: _isComparing
                                    ? "Comparing..."
                                    : "Compare Wi-Fi vs Mobile",
                                onPressed: busy ? null : _startCompare,
                              ),
                            ],
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
    );
  }

  Widget _buildConnectionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(connectionIcon(_connectionLabel),
              color: AppColors.accentPrimaryGlow, size: 16),
          const SizedBox(width: 8),
          Text(_connectionLabel,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildGauge() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gaugeSize = (constraints.maxWidth * 0.72).clamp(200.0, 275.0);
        return AnimatedBuilder(
          animation: _needleController,
          builder: (context, child) {
            final animatedValue = _speedValue *
                Curves.easeOutCubic.transform(_needleController.value);
            return SpeedGauge(
                value: animatedValue, size: gaugeSize, unitLabel: 'Mbps down');
          },
        );
      },
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
