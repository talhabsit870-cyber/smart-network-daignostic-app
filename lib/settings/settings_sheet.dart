import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'test_settings.dart';

/// Modal bottom sheet letting the user adjust the saved [TestSettings]
/// (parallel stream count, test duration) before running a normal test.
/// Returns the saved settings, or null if dismissed without changes.
Future<TestSettings?> showTestSettingsSheet(
  BuildContext context,
  TestSettings current,
) {
  return showModalBottomSheet<TestSettings>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TestSettingsSheet(initial: current),
  );
}

class _TestSettingsSheet extends StatefulWidget {
  final TestSettings initial;
  const _TestSettingsSheet({required this.initial});

  @override
  State<_TestSettingsSheet> createState() => _TestSettingsSheetState();
}

class _TestSettingsSheetState extends State<_TestSettingsSheet> {
  late int _streams = widget.initial.streams;
  late int _durationSeconds = widget.initial.durationSeconds;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Test settings',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Applies to Start Test and Compare. Deep Test always runs longer, '
              'regardless of this duration.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            _buildSliderRow(
              label: 'Parallel connections',
              valueLabel: '$_streams',
              value: _streams.toDouble(),
              min: TestSettings.minStreams.toDouble(),
              max: TestSettings.maxStreams.toDouble(),
              divisions: TestSettings.maxStreams - TestSettings.minStreams,
              onChanged: (v) => setState(() => _streams = v.round()),
            ),
            const SizedBox(height: 12),
            _buildSliderRow(
              label: 'Test duration',
              valueLabel: '${_durationSeconds}s',
              value: _durationSeconds.toDouble(),
              min: TestSettings.minDurationSeconds.toDouble(),
              max: TestSettings.maxDurationSeconds.toDouble(),
              divisions:
                  TestSettings.maxDurationSeconds - TestSettings.minDurationSeconds,
              onChanged: (v) => setState(() => _durationSeconds = v.round()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentPrimary,
                ),
                onPressed: () => Navigator.of(context).pop(
                  TestSettings(streams: _streams, durationSeconds: _durationSeconds),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
            Text(valueLabel,
                style: const TextStyle(
                    color: AppColors.accentPrimaryGlow,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.accentPrimary,
            inactiveTrackColor: AppColors.surfaceBorder,
            thumbColor: AppColors.accentPrimaryGlow,
            overlayColor: AppColors.accentPrimary.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
