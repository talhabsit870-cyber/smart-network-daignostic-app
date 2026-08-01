import 'diagnosis_engine.dart';

enum ReadinessStatus { good, borderline, poor }

/// A plain-language verdict for one everyday activity, derived from an
/// already-completed [NetworkSnapshot] — read-only interpretation, no new
/// measurements.
class ActivityReadiness {
  final String activity;
  final ReadinessStatus status;
  final String reason;

  const ActivityReadiness({
    required this.activity,
    required this.status,
    required this.reason,
  });
}

int _severity(ReadinessStatus status) {
  switch (status) {
    case ReadinessStatus.good:
      return 0;
    case ReadinessStatus.borderline:
      return 1;
    case ReadinessStatus.poor:
      return 2;
  }
}

ReadinessStatus _worseOf(ReadinessStatus a, ReadinessStatus b) =>
    _severity(a) >= _severity(b) ? a : b;

/// A metric that's within 15% below its threshold is borderline rather than
/// a hard cliff straight to poor.
const _borderlineBand = 0.85;

/// [higherIsBetter] true: good when value >= threshold (e.g. Mbps).
/// [higherIsBetter] false: good when value < threshold (e.g. ping ms).
ReadinessStatus _thresholdStatus(double? value, double threshold,
    {bool higherIsBetter = true}) {
  if (value == null) return ReadinessStatus.poor;
  if (higherIsBetter) {
    if (value >= threshold) return ReadinessStatus.good;
    if (value >= threshold * _borderlineBand) return ReadinessStatus.borderline;
    return ReadinessStatus.poor;
  } else {
    if (value < threshold) return ReadinessStatus.good;
    if (value < threshold / _borderlineBand) return ReadinessStatus.borderline;
    return ReadinessStatus.poor;
  }
}

class _ThresholdRule {
  final String activity;
  final double Function(NetworkSnapshot) metric;
  final double threshold;
  final String metricLabel;

  const _ThresholdRule({
    required this.activity,
    required this.metric,
    required this.threshold,
    required this.metricLabel,
  });
}

final List<_ThresholdRule> _thresholdRules = [
  _ThresholdRule(
    activity: 'HD streaming',
    metric: (s) => s.download.mbps,
    threshold: 5,
    metricLabel: 'download',
  ),
  _ThresholdRule(
    activity: '4K streaming',
    metric: (s) => s.download.mbps,
    threshold: 25,
    metricLabel: 'download',
  ),
  _ThresholdRule(
    activity: 'Large file downloads / cloud backup',
    metric: (s) => s.download.mbps,
    threshold: 20,
    metricLabel: 'download',
  ),
  _ThresholdRule(
    activity: 'Multiple 4K streams simultaneously',
    metric: (s) => s.download.mbps,
    threshold: 75,
    metricLabel: 'download',
  ),
];

ActivityReadiness _evaluateThresholdRule(
    _ThresholdRule rule, NetworkSnapshot snapshot) {
  final value = rule.metric(snapshot);
  final status = _thresholdStatus(value, rule.threshold);
  final reason = status == ReadinessStatus.good
      ? '${rule.metricLabel} ${value.toStringAsFixed(1)} Mbps — '
          'meets the ${rule.threshold.toStringAsFixed(0)} Mbps needed'
      : '${rule.metricLabel} ${value.toStringAsFixed(1)} Mbps — '
          'below the ${rule.threshold.toStringAsFixed(0)} Mbps '
          'threshold this needs';
  return ActivityReadiness(
      activity: rule.activity, status: status, reason: reason);
}

/// Bufferbloat only shows up under load, so a grade of C or worse pulls the
/// activity's status down to at least [ReadinessStatus.borderline] (D/F to
/// [ReadinessStatus.poor]) even when idle ping looks fine.
ReadinessStatus _bufferbloatFloor(NetworkSnapshot snapshot) {
  if (snapshot.bufferbloat?.success != true) return ReadinessStatus.good;
  switch (snapshot.bufferbloat!.grade) {
    case 'A+':
    case 'A':
    case 'B':
      return ReadinessStatus.good;
    case 'C':
      return ReadinessStatus.borderline;
    default:
      return ReadinessStatus.poor;
  }
}

ActivityReadiness _evaluateVideoCalls(NetworkSnapshot snapshot) {
  const uploadThreshold = 3.0;
  const pingThreshold = 150.0;
  final upload = snapshot.upload.mbps;
  final ping = snapshot.ping.avgMs;

  final uploadStatus = _thresholdStatus(upload, uploadThreshold);
  final pingStatus =
      _thresholdStatus(ping, pingThreshold, higherIsBetter: false);
  var status = _worseOf(uploadStatus, pingStatus);

  var reason = status == ReadinessStatus.good
      ? 'upload ${upload.toStringAsFixed(1)} Mbps, ping ${ping?.toStringAsFixed(0) ?? '--'}ms'
      : (_severity(uploadStatus) >= _severity(pingStatus)
          ? 'upload ${upload.toStringAsFixed(1)} Mbps — below the '
              '${uploadThreshold.toStringAsFixed(0)} Mbps video calls need'
          : 'ping ${ping?.toStringAsFixed(0) ?? '--'}ms — above the '
              '${pingThreshold.toStringAsFixed(0)}ms threshold video calls need');

  final bufferbloatFloor = _bufferbloatFloor(snapshot);
  if (_severity(bufferbloatFloor) > _severity(status)) {
    status = bufferbloatFloor;
    reason = 'bufferbloat under load (grade ${snapshot.bufferbloat!.grade}) '
        'can cause call stutter even though idle ping looks fine';
  }

  return ActivityReadiness(
    activity: 'Video calls (Zoom/Teams/FaceTime)',
    status: status,
    reason: reason,
  );
}

ActivityReadiness _evaluateGaming(NetworkSnapshot snapshot) {
  const pingThreshold = 50.0;
  const jitterThreshold = 15.0;
  const lossThreshold = 1.0;
  final ping = snapshot.ping.avgMs;
  final jitter = snapshot.ping.jitterMs;
  final loss = snapshot.ping.lossPercent;

  final pingStatus =
      _thresholdStatus(ping, pingThreshold, higherIsBetter: false);
  final jitterStatus =
      _thresholdStatus(jitter, jitterThreshold, higherIsBetter: false);
  final lossStatus =
      _thresholdStatus(loss, lossThreshold, higherIsBetter: false);
  var status = _worseOf(_worseOf(pingStatus, jitterStatus), lossStatus);

  var reason = status == ReadinessStatus.good
      ? 'ping ${ping?.toStringAsFixed(0) ?? '--'}ms, jitter '
          '${jitter?.toStringAsFixed(0) ?? '--'}ms, ${loss.toStringAsFixed(1)}% loss'
      : _worstGamingReason(
          pingStatus, jitterStatus, lossStatus, ping, jitter, loss,
          pingThreshold, jitterThreshold, lossThreshold);

  final bufferbloatFloor = _bufferbloatFloor(snapshot);
  if (_severity(bufferbloatFloor) > _severity(status)) {
    status = bufferbloatFloor;
    reason = 'bufferbloat under load (grade ${snapshot.bufferbloat!.grade}) '
        '— latency spikes badly the moment anything else uses the connection';
  }

  return ActivityReadiness(
    activity: 'Competitive online gaming',
    status: status,
    reason: reason,
  );
}

String _worstGamingReason(
  ReadinessStatus pingStatus,
  ReadinessStatus jitterStatus,
  ReadinessStatus lossStatus,
  double? ping,
  double? jitter,
  double loss,
  double pingThreshold,
  double jitterThreshold,
  double lossThreshold,
) {
  final candidates = [
    (
      pingStatus,
      'ping ${ping?.toStringAsFixed(0) ?? '--'}ms — above the '
          '${pingThreshold.toStringAsFixed(0)}ms threshold gaming needs',
    ),
    (
      jitterStatus,
      'jitter ${jitter?.toStringAsFixed(0) ?? '--'}ms — above the '
          '${jitterThreshold.toStringAsFixed(0)}ms threshold gaming needs',
    ),
    (
      lossStatus,
      'packet loss ${loss.toStringAsFixed(1)}% — above the '
          '${lossThreshold.toStringAsFixed(0)}% threshold gaming needs',
    ),
  ];
  candidates.sort((a, b) => _severity(b.$1).compareTo(_severity(a.$1)));
  return candidates.first.$2;
}

/// Full activity-readiness rundown for a completed [NetworkSnapshot] — pure
/// interpretation of already-computed metrics, no new measurements.
List<ActivityReadiness> evaluateActivityReadiness(NetworkSnapshot snapshot) {
  return [
    _evaluateThresholdRule(_thresholdRules[0], snapshot),
    _evaluateThresholdRule(_thresholdRules[1], snapshot),
    _evaluateVideoCalls(snapshot),
    _evaluateGaming(snapshot),
    _evaluateThresholdRule(_thresholdRules[2], snapshot),
    _evaluateThresholdRule(_thresholdRules[3], snapshot),
  ];
}
