import 'package:flutter/material.dart';

import '../core/theme.dart' show AppColors;
import '../diagnosis/diagnosis_engine.dart';
import 'history_entry.dart';
import 'history_store.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<HistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = HistoryStore.load();
  }

  void _reload() {
    setState(() {
      _future = HistoryStore.load();
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
      case DiagnosisVerdict.deviceIssue:
        return AppColors.amber;
      case DiagnosisVerdict.inconclusive:
        return AppColors.amber;
    }
  }

  String _formatTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Scan History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear history',
            onPressed: () async {
              await HistoryStore.clear();
              _reload();
            },
          ),
        ],
      ),
      body: FutureBuilder<List<HistoryEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.violet),
            );
          }
          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(
              child: Text(
                'No scans yet — run a test to build history.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final e = entries[index];
              final verdictColor = _verdictColor(e.verdict);
              // A Border can't mix per-side colors with a borderRadius
              // (Flutter throws on paint) — so the verdict accent is a
              // separate solid strip inside a uniformly-bordered, clipped
              // card instead of a colored left BorderSide.
              return ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 4, color: verdictColor),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      e.verdictTitle,
                                      style: TextStyle(
                                        color: verdictColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      _formatTimestamp(e.timestamp),
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${e.connectionLabel} · ${e.downloadMbps.toStringAsFixed(1)} Mbps down · '
                                  '${e.uploadMbps.toStringAsFixed(1)} Mbps up · '
                                  '${e.pingMs?.toStringAsFixed(0) ?? '--'}ms ping · '
                                  '${e.lossPercent.toStringAsFixed(0)}% loss',
                                  style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  e.securityLabel,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
