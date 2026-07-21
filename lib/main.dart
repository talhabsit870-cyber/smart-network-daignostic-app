import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'diagnosis_engine.dart';
import 'network_tester.dart';
import 'security_check.dart';

void main() => runApp(const MyApp());

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
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NetDiagnose',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

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
  String _speedLabel = "--";
  String _connectionLabel = "--";

  SpeedResult? _upload;
  PingStats? _ping;
  Map<String, dynamic>? _security;
  DiagnosisResult? _diagnosis;

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
  }

  @override
  void dispose() {
    _needleController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Future<NetworkSnapshot> _captureSnapshot() async {
    final download = await NetworkTester.testDownloadSpeed();
    final upload = await NetworkTester.testUploadSpeed();
    final ping = await NetworkTester.testPingDetailed();
    final connectivity = await Connectivity().checkConnectivity();
    return NetworkSnapshot(
      connectionLabel: DiagnosisEngine.labelFor(connectivity),
      ping: ping,
      download: download,
      upload: upload,
    );
  }

  Future<void> _startDiagnosis() async {
    setState(() {
      _isDiagnosing = true;
      _speedValue = 0;
      _speedLabel = "--";
      _upload = null;
      _ping = null;
      _security = null;
      _diagnosis = null;
    });

    final download = await NetworkTester.testDownloadSpeed();
    if (mounted) {
      setState(() {
        _speedLabel =
            download.success ? "${download.mbps.toStringAsFixed(1)} Mbps" : "Failed";
      });
      _needleController.forward(from: 0);
      _speedValue = download.success ? download.mbps.clamp(0, 100) : 0;
    }

    final upload = await NetworkTester.testUploadSpeed();
    if (mounted) setState(() => _upload = upload);

    final ping = await NetworkTester.testPingDetailed();
    if (mounted) setState(() => _ping = ping);

    final security = await SecurityCheck().scanWiFiSecurity();
    final connectivity = await Connectivity().checkConnectivity();
    final connectionLabel = DiagnosisEngine.labelFor(connectivity);

    final snapshot = NetworkSnapshot(
      connectionLabel: connectionLabel,
      ping: ping,
      download: download,
      upload: upload,
    );

    if (mounted) {
      setState(() {
        _security = security;
        _connectionLabel = connectionLabel;
        _diagnosis = DiagnosisEngine.evaluateSingle(snapshot);
        _isDiagnosing = false;
      });
    }
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.violet),
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
    setState(() {
      _isComparing = false;
      _diagnosis = result;
    });
  }

  Color _verdictColor(DiagnosisVerdict verdict) {
    switch (verdict) {
      case DiagnosisVerdict.allGood:
        return AppColors.green;
      case DiagnosisVerdict.ispIssue:
        return AppColors.coral;
      case DiagnosisVerdict.routerIssue:
      case DiagnosisVerdict.mobileIssue:
        return AppColors.amber;
      case DiagnosisVerdict.inconclusive:
        return AppColors.amber;
    }
  }

  IconData _connectionIcon(String label) {
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

  String _formatSpeed(SpeedResult? r) {
    if (r == null) return "--";
    if (!r.success) return "Failed";
    return "${r.mbps.toStringAsFixed(1)} Mbps";
  }

  Color _speedColor(SpeedResult? r) {
    if (r == null) return AppColors.textMuted;
    if (!r.success) return AppColors.coral;
    if (r.mbps < 5) return AppColors.amber;
    return AppColors.green;
  }

  String _formatPingShort(PingStats? p) {
    if (p == null) return "--";
    if (p.received == 0) return "Unreachable";
    return "${p.avgMs!.toStringAsFixed(0)} ms";
  }

  String _formatPingDetail(PingStats? p) {
    if (p == null) return "";
    if (p.received == 0) return "No probes returned";
    return "min ${p.minMs}ms · max ${p.maxMs}ms · jitter "
        "${p.jitterMs?.toStringAsFixed(0) ?? '0'}ms · via ${p.host}";
  }

  String _formatLossShort(PingStats? p) {
    if (p == null) return "--";
    return "${p.lossPercent.toStringAsFixed(0)}%";
  }

  String _formatLossDetail(PingStats? p) {
    if (p == null) return "";
    return "${p.received}/${p.sent} probes received";
  }

  Color _lossColor(PingStats? p) {
    if (p == null) return AppColors.textMuted;
    if (p.lossPercent >= 20) return AppColors.coral;
    if (p.lossPercent > 0) return AppColors.amber;
    return AppColors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              children: [
                _buildTopBar(),
                const SizedBox(height: 28),
                _buildGaugeWithCards(),
                const SizedBox(height: 16),
                _buildStatsPanel(),
                const SizedBox(height: 12),
                _buildBottomBar(),
                if (_diagnosis != null) ...[
                  const SizedBox(height: 16),
                  _buildDiagnosisCard(),
                ],
                const SizedBox(height: 20),
                _buildWave(),
                const SizedBox(height: 24),
                _buildScanButton(),
                const SizedBox(height: 12),
                _buildCompareButton(),
              ],
            ),
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
            Icon(Icons.blur_on, color: AppColors.violetGlow, size: 22),
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
        const Icon(Icons.settings_outlined, color: AppColors.textMuted, size: 20),
      ],
    );
  }

  Widget _buildGaugeWithCards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _sideCard("PING", _formatPingShort(_ping), Icons.bolt_rounded),
              const SizedBox(height: 12),
              _sideCard("PACKET LOSS", _formatLossShort(_ping),
                  Icons.grain_rounded,
                  valueColor: _lossColor(_ping)),
            ],
          ),
        ),
        Expanded(
          flex: 5,
          child: AnimatedBuilder(
            animation: _needleController,
            builder: (context, child) {
              final animatedValue =
                  _speedValue * Curves.easeOutCubic.transform(_needleController.value);
              return CustomPaint(
                painter: _GaugePainter(value: animatedValue, maxValue: 100),
                child: SizedBox(
                  height: 200,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isDiagnosing && _speedLabel == "--"
                                ? "…"
                                : animatedValue.toStringAsFixed(1),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            "Mbps down",
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              letterSpacing: 2,
                            ),
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
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _sideCard(
                "SECURITY",
                _security == null ? "Not checked" : _security!['label'] as String,
                Icons.shield_outlined,
                valueColor: _security == null
                    ? AppColors.textMuted
                    : _security!['color'] as Color,
              ),
              const SizedBox(height: 12),
              _sideCard("UPLOAD", _formatSpeed(_upload), Icons.upload_rounded,
                  valueColor: _speedColor(_upload)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sideCard(String label, String value, IconData icon,
      {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.violetGlow, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsPanel() {
    if (_ping == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_formatPingDetail(_ping),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 4),
          Text(_formatLossDetail(_ping),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(_connectionIcon(_connectionLabel),
                  color: AppColors.violetGlow, size: 16),
              const SizedBox(width: 8),
              Text(_connectionLabel,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
          Text(
            _speedLabel,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosisCard() {
    final diagnosis = _diagnosis!;
    final color = _verdictColor(diagnosis.verdict);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.troubleshoot, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  diagnosis.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(diagnosis.detail,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            diagnosis.recommendation,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWave() {
    return SizedBox(
      height: 40,
      child: AnimatedBuilder(
        animation: _waveController,
        builder: (context, child) {
          return CustomPaint(
            painter: _WavePainter(
              phase: _waveController.value * 2 * math.pi,
              isActive: busy,
            ),
            size: const Size(double.infinity, 40),
          );
        },
      ),
    );
  }

  bool get busy => _isDiagnosing || _isComparing;

  Widget _buildScanButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: busy ? null : _startDiagnosis,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.violet,
          disabledBackgroundColor: AppColors.surfaceBorder,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(27),
          ),
          elevation: 8,
          shadowColor: AppColors.violetGlow,
        ),
        child: Text(
          _isDiagnosing ? "Testing..." : "Start Test",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildCompareButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: busy ? null : _startCompare,
        icon: const Icon(Icons.compare_arrows, color: AppColors.violetGlow),
        label: Text(
          _isComparing ? "Comparing..." : "Compare Wi-Fi vs Mobile",
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.surfaceBorder),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

/// Speedometer-style arc gauge with a glowing needle, similar to
/// commercial speed test apps — but reused here to represent throughput.
class _GaugePainter extends CustomPainter {
  final double value;
  final double maxValue;

  _GaugePainter({required this.value, required this.maxValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 30);
    final radius = size.width / 2 - 10;

    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    final trackPaint = Paint()
      ..color = const Color(0xFF14202B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle, false, trackPaint);

    final progress = (value / maxValue).clamp(0.0, 1.0);
    final progressPaint = Paint()
      ..shader = const SweepGradient(
        colors: [AppColors.violet, AppColors.magenta],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAngle * progress, false, progressPaint);

    // Needle
    final needleAngle = startAngle + sweepAngle * progress;
    final needleEnd = Offset(
      center.dx + (radius - 20) * math.cos(needleAngle),
      center.dy + (radius - 20) * math.sin(needleAngle),
    );
    final needlePaint = Paint()
      ..color = AppColors.violetGlow
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleEnd, needlePaint);
    canvas.drawCircle(center, 5, Paint()..color = AppColors.violetGlow);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.value != value;
}

/// Bottom activity wave — animates while a scan is in progress, sits flat
/// at rest. Echoes the audio-waveform footer from the reference design.
class _WavePainter extends CustomPainter {
  final double phase;
  final bool isActive;

  _WavePainter({required this.phase, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.violet.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final amplitude = isActive ? 12.0 : 3.0;
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height / 2 +
          amplitude * math.sin((x / size.width * 4 * math.pi) + phase);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => true;
}
