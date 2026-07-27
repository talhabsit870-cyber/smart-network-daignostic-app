import 'package:flutter/material.dart';

import '../core/theme.dart' show AppColors, connectionIcon;
import '../diagnosis/diagnosis_engine.dart';
import '../network/device_status.dart';
import '../network/network_tester.dart';
import 'signal_path.dart';
import 'speed_gauge.dart';

/// The full report for one diagnostic run — pushed as its own page once a
/// scan (or a Wi-Fi vs Mobile compare) finishes, instead of growing the
/// launcher screen into a live results dashboard. [secondary] is only set
/// for a compare run; [security]/[ipInfo] are only collected on a solo run.
class ResultScreen extends StatelessWidget {
  final DateTime timestamp;
  final String diagnosisContext;
  final NetworkSnapshot primary;
  final NetworkSnapshot? secondary;
  final Map<String, dynamic>? security;
  final IpInfoResult? ipInfo;
  final DiagnosisResult diagnosis;
  final VoidCallback onRunAgain;

  const ResultScreen({
    super.key,
    required this.timestamp,
    required this.diagnosisContext,
    required this.primary,
    this.secondary,
    this.security,
    this.ipInfo,
    required this.diagnosis,
    required this.onRunAgain,
  });

  bool get isCompare => secondary != null;

  @override
  Widget build(BuildContext context) {
    final color = _verdictColor(diagnosis.verdict);
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textPrimary,
        title: Text(isCompare ? 'Comparison Result' : 'Test Result'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_verdictIcon(diagnosis.verdict), color: color, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    diagnosis.title,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(_formatTimestamp(timestamp),
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 18),
              if (isCompare) _buildCompareHero() else _buildSoloHero(),
              const SizedBox(height: 18),
              if (!isCompare) ...[
                _buildTileRow(),
                const SizedBox(height: 16),
              ],
              SignalPath(diagnosis: diagnosis, diagnosisContext: diagnosisContext),
              const SizedBox(height: 12),
              _buildDiagnosisCard(color),
              const SizedBox(height: 12),
              _buildFooter(),
              const SizedBox(height: 24),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────

  Widget _buildSoloHero() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _metricRing(
          label: 'DOWNLOAD',
          icon: Icons.download_rounded,
          result: primary.download,
          color: AppColors.violet,
        ),
        _metricRing(
          label: 'UPLOAD',
          icon: Icons.upload_rounded,
          result: primary.upload,
          color: AppColors.magenta,
        ),
      ],
    );
  }

  Widget _metricRing({
    required String label,
    required IconData icon,
    required SpeedResult result,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        result.success
            ? SpeedGauge(value: result.mbps, size: 163)
            : SizedBox(
                width: 163,
                height: 163,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.coral, width: 2),
                  ),
                  child: const Center(
                    child: Text('Failed',
                        style: TextStyle(
                            color: AppColors.coral,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ],
        ),
      ],
    );
  }

  Widget _buildCompareHero() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _snapshotCard(primary)),
        const SizedBox(width: 12),
        Expanded(child: _snapshotCard(secondary!)),
      ],
    );
  }

  Widget _snapshotCard(NetworkSnapshot snap) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              Icon(connectionIcon(snap.connectionLabel),
                  color: AppColors.violetGlow, size: 16),
              const SizedBox(width: 6),
              Text(snap.connectionLabel,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Text(_formatSpeed(snap.download),
              style: TextStyle(
                  color: _speedColor(snap.download),
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
          const Text('Mbps down',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
          const SizedBox(height: 8),
          Text(_formatSpeed(snap.upload),
              style: TextStyle(
                  color: _speedColor(snap.upload),
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const Text('Mbps up',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
          const SizedBox(height: 8),
          Text(_formatPingShort(snap.ping),
              style: TextStyle(
                  color: _lossColor(snap.ping),
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          const Text('ping',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }

  // ── PRTG-style sensor tiles ──────────────────────────────────────

  Widget _buildTileRow() {
    return Row(
      children: [
        Expanded(
          child: _tile("PING", _formatPingShort(primary.ping), Icons.bolt_rounded,
              _lossColor(primary.ping)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tile("PACKET LOSS", _formatLossShort(primary.ping),
              Icons.grain_rounded, _lossColor(primary.ping)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tile(
            "SECURITY",
            security == null ? "Not checked" : security!['label'] as String,
            Icons.shield_outlined,
            security == null
                ? AppColors.textMuted
                : security!['color'] as Color,
          ),
        ),
      ],
    );
  }

  Widget _tile(String label, String value, IconData icon, Color statusColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Icon(icon, color: AppColors.violetGlow, size: 18),
              const SizedBox(height: 8),
              Text(
                value,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      letterSpacing: 1)),
            ],
          ),
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: [
                  BoxShadow(
                      color: statusColor.withValues(alpha: 0.6), blurRadius: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Diagnosis ────────────────────────────────────────────────────

  Widget _buildDiagnosisCard(Color color) {
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
          Text(diagnosis.detail,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            diagnosis.recommendation,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final ping = primary.ping;
    final lines = <String>[
      if (ping.received > 0)
        "min ${ping.minMs}ms · max ${ping.maxMs}ms · jitter "
            "${ping.jitterMs?.toStringAsFixed(0) ?? '0'}ms · via ${ping.host}",
      if (ipInfo != null) _formatIpInfo(ipInfo),
      if (primary.deviceStatus != null) _formatDeviceStatus(primary.deviceStatus),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
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
          for (final line in lines) ...[
            Text(line,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            if (line != lines.last) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.surfaceBorder),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
            child: const Text('Done',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: onRunAgain,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.violet,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              elevation: 6,
              shadowColor: AppColors.violetGlow,
            ),
            child: const Text('Test Again',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}

// ── Formatting helpers ────────────────────────────────────────────

String _formatTimestamp(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
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

String _formatLossShort(PingStats? p) {
  if (p == null) return "--";
  return "${p.lossPercent.toStringAsFixed(0)}%";
}

Color _lossColor(PingStats? p) {
  if (p == null) return AppColors.textMuted;
  if (p.received == 0 || p.lossPercent >= 20) return AppColors.coral;
  if (p.lossPercent > 0) return AppColors.amber;
  return AppColors.green;
}

String _formatIpInfo(IpInfoResult? info) {
  if (info == null) return "";
  if (!info.success) return "IP/ISP lookup failed";
  final ip = info.ip ?? "unknown IP";
  final isp = info.isp ?? "unknown ISP";
  final place = [info.city, info.country].whereType<String>().join(', ');
  return place.isEmpty ? "$ip · $isp" : "$ip · $isp · $place";
}

String _formatDeviceStatus(DeviceStatus? status) {
  if (status == null) return "";
  final parts = <String>[status.deviceLabel];
  if (status.batteryPercent != null) {
    parts.add(
      status.isLowPowerMode == true
          ? "${status.batteryPercent}% battery (Low Power Mode)"
          : "${status.batteryPercent}% battery",
    );
  }
  return parts.join(' · ');
}

Color _verdictColor(DiagnosisVerdict verdict) {
  switch (verdict) {
    case DiagnosisVerdict.allGood:
      return AppColors.green;
    case DiagnosisVerdict.ispIssue:
      return AppColors.coral;
    case DiagnosisVerdict.routerIssue:
    case DiagnosisVerdict.mobileIssue:
    case DiagnosisVerdict.deviceIssue:
    case DiagnosisVerdict.inconclusive:
      return AppColors.amber;
  }
}

IconData _verdictIcon(DiagnosisVerdict verdict) {
  switch (verdict) {
    case DiagnosisVerdict.allGood:
      return Icons.check_circle_outline_rounded;
    case DiagnosisVerdict.ispIssue:
      return Icons.cloud_off_rounded;
    case DiagnosisVerdict.routerIssue:
      return Icons.router_rounded;
    case DiagnosisVerdict.mobileIssue:
      return Icons.signal_cellular_alt_rounded;
    case DiagnosisVerdict.deviceIssue:
      return Icons.battery_alert_rounded;
    case DiagnosisVerdict.inconclusive:
      return Icons.help_outline_rounded;
  }
}
