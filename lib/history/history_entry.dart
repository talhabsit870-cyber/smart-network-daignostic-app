import '../diagnosis/diagnosis_engine.dart';
import '../network/network_tester.dart';

/// A compact, serializable summary of one diagnosis run — enough to show
/// in a history list without persisting full snapshot/ping detail.
class HistoryEntry {
  final DateTime timestamp;
  final String connectionLabel;
  final double? pingMs;
  final double lossPercent;
  final double downloadMbps;
  final double uploadMbps;
  final String securityLabel;
  final String verdictTitle;
  final DiagnosisVerdict verdict;
  final String? bufferbloatGrade;
  final double? bufferbloatIncreaseMs;

  const HistoryEntry({
    required this.timestamp,
    required this.connectionLabel,
    required this.pingMs,
    required this.lossPercent,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.securityLabel,
    required this.verdictTitle,
    required this.verdict,
    this.bufferbloatGrade,
    this.bufferbloatIncreaseMs,
  });

  factory HistoryEntry.fromRun({
    required String connectionLabel,
    required PingStats ping,
    required SpeedResult download,
    required SpeedResult upload,
    required String securityLabel,
    required DiagnosisResult diagnosis,
    BufferbloatResult? bufferbloat,
  }) {
    return HistoryEntry(
      timestamp: DateTime.now(),
      connectionLabel: connectionLabel,
      pingMs: ping.avgMs,
      lossPercent: ping.lossPercent,
      downloadMbps: download.success ? download.mbps : 0,
      uploadMbps: upload.success ? upload.mbps : 0,
      securityLabel: securityLabel,
      verdictTitle: diagnosis.title,
      verdict: diagnosis.verdict,
      bufferbloatGrade: bufferbloat?.success == true ? bufferbloat!.grade : null,
      bufferbloatIncreaseMs:
          bufferbloat?.success == true ? bufferbloat!.increaseMs : null,
    );
  }

  Map<String, dynamic> toJson() => {
        "timestamp": timestamp.toIso8601String(),
        "connectionLabel": connectionLabel,
        "pingMs": pingMs,
        "lossPercent": lossPercent,
        "downloadMbps": downloadMbps,
        "uploadMbps": uploadMbps,
        "securityLabel": securityLabel,
        "verdictTitle": verdictTitle,
        "verdict": verdict.name,
        "bufferbloatGrade": bufferbloatGrade,
        "bufferbloatIncreaseMs": bufferbloatIncreaseMs,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        timestamp: DateTime.parse(json["timestamp"] as String),
        connectionLabel: json["connectionLabel"] as String,
        pingMs: (json["pingMs"] as num?)?.toDouble(),
        lossPercent: (json["lossPercent"] as num).toDouble(),
        downloadMbps: (json["downloadMbps"] as num).toDouble(),
        uploadMbps: (json["uploadMbps"] as num).toDouble(),
        securityLabel: json["securityLabel"] as String,
        verdictTitle: json["verdictTitle"] as String,
        verdict: DiagnosisVerdict.values.firstWhere(
          (v) => v.name == json["verdict"],
          orElse: () => DiagnosisVerdict.inconclusive,
        ),
        bufferbloatGrade: json["bufferbloatGrade"] as String?,
        bufferbloatIncreaseMs: (json["bufferbloatIncreaseMs"] as num?)?.toDouble(),
      );
}
