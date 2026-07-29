import 'package:flutter/material.dart';

import '../core/cta_button.dart';
import '../core/theme.dart' show AppColors, connectionIcon;
import '../diagnosis/diagnosis_engine.dart';
import '../network/network_tester.dart';
import 'signal_path.dart';

/// The full diagnostic report, rendered in place on [HomeScreen] instead of
/// a separate pushed page. Collapses to a one-line verdict strip via
/// [expanded]/[onToggleExpanded] so re-running a test doesn't mean
/// scrolling past a full report every time. Renders nothing until the first
/// run completes ([diagnosis] null). [secondary] is only set for a compare
/// run; [security]/[ipInfo] are only collected on a solo run.
class ReportCard extends StatelessWidget {
  final DateTime? timestamp;
  final String diagnosisContext;
  final NetworkSnapshot? primary;
  final NetworkSnapshot? secondary;
  final Map<String, dynamic>? security;
  final IpInfoResult? ipInfo;
  final DiagnosisResult? diagnosis;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onRunAgain;

  const ReportCard({
    super.key,
    required this.timestamp,
    required this.diagnosisContext,
    required this.primary,
    this.secondary,
    this.security,
    this.ipInfo,
    required this.diagnosis,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onRunAgain,
  });

  bool get isCompare => secondary != null;

  @override
  Widget build(BuildContext context) {
    final diagnosis = this.diagnosis;
    final primary = this.primary;
    if (diagnosis == null || primary == null) {
      return const SizedBox.shrink();
    }

    final color = _verdictColor(diagnosis.verdict);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: expanded ? color.withValues(alpha: 0.35) : AppColors.surfaceBorder,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(_verdictIcon(diagnosis.verdict), color: color, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diagnosis.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          expanded
                              ? '$diagnosisContext · ${_formatTimestamp(timestamp)}'
                              : _collapsedSummary(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
            crossFadeState:
                expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(color: AppColors.surfaceBorder, height: 1),
                  const SizedBox(height: 14),
                  if (isCompare) _buildCompareHero() else _buildTileRow(),
                  const SizedBox(height: 16),
                  SignalPath(
                      diagnosis: diagnosis, diagnosisContext: diagnosisContext),
                  const SizedBox(height: 16),
                  _sectionLabel('Diagnosis'),
                  const SizedBox(height: 8),
                  _buildDiagnosisCard(diagnosis),
                  const SizedBox(height: 16),
                  _sectionLabel('Details'),
                  const SizedBox(height: 8),
                  _buildDetailsGrid(primary),
                  const SizedBox(height: 16),
                  PrimaryCtaButton(
                    label: 'Test Again',
                    height: 48,
                    onPressed: onRunAgain,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _collapsedSummary() {
    if (isCompare) return diagnosisContext;
    final primary = this.primary!;
    return '${_formatSpeed(primary.download)} down · ${_formatPingShort(primary.ping)}';
  }

  // ── Compare hero ─────────────────────────────────────────────────

  Widget _buildCompareHero() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _snapshotCard(primary!)),
        const SizedBox(width: 12),
        Expanded(child: _snapshotCard(secondary!)),
      ],
    );
  }

  Widget _snapshotCard(NetworkSnapshot snap) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(connectionIcon(snap.connectionLabel),
                  color: AppColors.accentPrimaryGlow, size: 16),
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
    final primary = this.primary!;
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
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Icon(icon, color: AppColors.accentPrimaryGlow, size: 18),
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

  // ── Section scaffolding ──────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  // ── Diagnosis ────────────────────────────────────────────────────

  Widget _buildDiagnosisCard(DiagnosisResult diagnosis) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(diagnosis.detail,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accentSecondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.accentSecondary.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    color: AppColors.accentSecondary, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    diagnosis.recommendation,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Details grid ─────────────────────────────────────────────────

  Widget _buildDetailsGrid(NetworkSnapshot primary) {
    final ping = primary.ping;
    final device = primary.deviceStatus;
    final ipInfo = this.ipInfo;
    final rows = <(String, String)>[
      if (ping.received > 0) ('Ping range', '${ping.minMs}–${ping.maxMs} ms'),
      if (ping.jitterMs != null) ('Jitter', '${ping.jitterMs!.toStringAsFixed(0)} ms'),
      if (ipInfo != null && ipInfo.success && ipInfo.ip != null)
        ('Public IP', ipInfo.ip!),
      if (ipInfo != null && ipInfo.success && ipInfo.isp != null) ('ISP', ipInfo.isp!),
      if (ipInfo != null && ipInfo.success)
        (
          'Location',
          [ipInfo.city, ipInfo.country].whereType<String>().join(', '),
        ),
      if (ipInfo != null && !ipInfo.success) ('IP lookup', 'Failed'),
      if (device != null) ('Device', device.deviceLabel),
      if (device?.batteryPercent != null)
        (
          'Battery',
          device!.isLowPowerMode == true
              ? '${device.batteryPercent}% · Low Power Mode'
              : '${device.batteryPercent}%',
        ),
    ]..removeWhere((row) => row.$2.isEmpty);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          for (final row in rows) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(row.$1,
                      style:
                          const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  Text(row.$2,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (row != rows.last)
              const Divider(color: AppColors.surfaceBorder, height: 1),
          ],
        ],
      ),
    );
  }
}

// ── Formatting helpers ────────────────────────────────────────────

String _formatTimestamp(DateTime? dt) {
  if (dt == null) return '--';
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
