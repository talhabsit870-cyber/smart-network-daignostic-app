import 'package:flutter/material.dart';

import '../core/theme.dart' show AppColors;
import '../diagnosis/diagnosis_engine.dart';

/// Health of one hop in the Signal Path — mirrors [DiagnosisVerdict] but as
/// a per-node state rather than a single overall verdict.
enum ChainState { healthy, warning, faulty, unknown }

class ChainNode {
  final String label;
  final IconData icon;
  final ChainState state;
  const ChainNode(this.label, this.icon, this.state);
}

/// Turns DiagnosisEngine's verdict into a visual fault chain — Device →
/// Router/Signal → ISP/Carrier → Internet — instead of leaving the root
/// cause as prose only. Node states err on what each verdict actually
/// proves: e.g. a router-issue verdict comes from compare(), which means
/// the mobile run already confirmed the ISP/Internet are reachable, so
/// those hops are marked healthy rather than merely "not blamed".
class SignalPath extends StatelessWidget {
  final DiagnosisResult diagnosis;
  final String diagnosisContext; // 'Wi-Fi' or 'Mobile Data'

  const SignalPath({
    super.key,
    required this.diagnosis,
    required this.diagnosisContext,
  });

  List<ChainNode> _chainNodes() {
    final isMobile = diagnosisContext == 'Mobile Data';
    final localLabel = isMobile ? 'Signal' : 'Router';
    final localIcon = isMobile ? Icons.cell_tower_rounded : Icons.router_rounded;
    final providerLabel = isMobile ? 'Carrier' : 'ISP';

    var device = ChainState.healthy;
    var local = ChainState.healthy;
    var provider = ChainState.healthy;
    var internet = ChainState.healthy;

    switch (diagnosis.verdict) {
      case DiagnosisVerdict.allGood:
        break;
      case DiagnosisVerdict.deviceIssue:
        device = ChainState.faulty;
        local = ChainState.unknown;
        provider = ChainState.unknown;
        internet = ChainState.unknown;
        break;
      case DiagnosisVerdict.routerIssue:
        local = ChainState.faulty;
        break;
      case DiagnosisVerdict.mobileIssue:
        local = ChainState.faulty;
        provider = ChainState.unknown;
        break;
      case DiagnosisVerdict.ispIssue:
        provider = ChainState.faulty;
        internet = ChainState.faulty;
        break;
      case DiagnosisVerdict.inconclusive:
        local = ChainState.warning;
        provider = ChainState.warning;
        internet = ChainState.warning;
        break;
    }

    return [
      ChainNode('Device', Icons.devices_rounded, device),
      ChainNode(localLabel, localIcon, local),
      ChainNode(providerLabel, Icons.cloud_outlined, provider),
      ChainNode('Internet', Icons.public_rounded, internet),
    ];
  }

  Color _stateColor(ChainState state) {
    switch (state) {
      case ChainState.healthy:
        return AppColors.green;
      case ChainState.warning:
        return AppColors.amber;
      case ChainState.faulty:
        return AppColors.coral;
      case ChainState.unknown:
        return AppColors.unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _chainNodes();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          for (int i = 0; i < nodes.length; i++) ...[
            if (i > 0) _connector(nodes[i - 1].state, nodes[i].state),
            _node(nodes[i]),
          ],
        ],
      ),
    );
  }

  Widget _node(ChainNode node) {
    final color = _stateColor(node.state);
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(node.icon, color: color, size: 17),
          ),
          const SizedBox(height: 6),
          Text(
            node.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _connector(ChainState from, ChainState to) {
    Color color;
    if (from == ChainState.faulty || to == ChainState.faulty) {
      color = AppColors.coral;
    } else if (from == ChainState.warning || to == ChainState.warning) {
      color = AppColors.amber;
    } else if (from == ChainState.unknown || to == ChainState.unknown) {
      color = AppColors.unknown;
    } else {
      color = AppColors.green;
    }
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Container(height: 2, color: color.withValues(alpha: 0.7)),
      ),
    );
  }
}
