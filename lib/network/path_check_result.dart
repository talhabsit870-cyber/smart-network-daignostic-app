/// Model types for the network path/hop check, plus pure parsers for the
/// desktop `tracert`/`traceroute` stdout formats. Deliberately free of
/// `dart:io`/Flutter imports so it can be exported from [NetworkTester] and
/// consumed by the diagnosis engine without an import cycle, and so the
/// parsers are testable without spawning a process.
library;

/// How a [PathCheckResult] was produced.
enum PathCheckMethod {
  /// Real hop-by-hop `tracert`/`traceroute` output (desktop only).
  fullTraceroute,

  /// TCP-connect timing against a small fixed set of points (mobile only) —
  /// not real hop data, must always be presented to the user as an
  /// "approximate path check", never as "traceroute".
  approximatePath,

  /// Not attempted on this platform (web), or the platform's tool/permission
  /// wasn't available.
  unavailable,
}

/// One point on the path: either a real traceroute hop or one of the 3
/// approximate-path points.
class PathHop {
  final int hopNumber;

  /// Human label for approximate-path points (e.g. "Gateway", "Public DNS",
  /// "Target"); null for real traceroute hops.
  final String? label;

  final String? address;
  final int? rttMs;
  final bool timedOut;

  const PathHop({
    required this.hopNumber,
    this.label,
    this.address,
    this.rttMs,
    this.timedOut = false,
  });
}

class PathCheckResult {
  final bool success;
  final PathCheckMethod method;
  final List<PathHop> hops;
  final String? error;

  const PathCheckResult({
    required this.success,
    required this.method,
    this.hops = const [],
    this.error,
  });

  factory PathCheckResult.failed(String error) => PathCheckResult(
        success: false,
        method: PathCheckMethod.unavailable,
        error: error,
      );

  factory PathCheckResult.unavailable(String reason) => PathCheckResult(
        success: false,
        method: PathCheckMethod.unavailable,
        error: reason,
      );

  /// Short, history-friendly description of the result — no per-hop detail.
  String get summary {
    if (!success || hops.isEmpty) {
      return error ?? 'Path check unavailable';
    }
    final responded = hops.where((h) => !h.timedOut).length;
    if (method == PathCheckMethod.approximatePath) {
      final parts = hops
          .where((h) => !h.timedOut && h.rttMs != null)
          .map((h) => '${h.label ?? 'hop'} ${h.rttMs}ms')
          .join(', ');
      return '$responded/${hops.length} points responded'
          '${parts.isEmpty ? '' : ' ($parts)'}';
    }
    final last = hops.last;
    final target = !last.timedOut && last.rttMs != null
        ? ', target ${last.rttMs}ms'
        : '';
    return '$responded/${hops.length} hops responded$target';
  }
}

final RegExp _tracertHopLine = RegExp(
  r'^\s*(\d+)\s+(.*)$',
);

final RegExp _msToken = RegExp(r'(\d+(?:\.\d+)?)\s*ms', caseSensitive: false);

final RegExp _ipv4Token = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$');

/// Whitespace-tokenizes [rest] and returns the first token shaped like an
/// address: IPv4 dotted-decimal, or IPv6 (hex groups/colons only — `-d`/
/// `-n` disable DNS resolution, but the target/gateway may still resolve
/// over IPv6, including compressed forms like `2606:4700:7::da`, which a
/// single non-tokenized regex can't reliably bound).
String? _extractAddress(String rest) {
  for (final token in rest.trim().split(RegExp(r'\s+'))) {
    if (_ipv4Token.hasMatch(token)) return token;
    if (token.contains(':') && RegExp(r'^[0-9a-fA-F:]+$').hasMatch(token)) {
      return token;
    }
  }
  return null;
}

/// Parses `tracert -d` output (Windows). Numeric addresses only (`-d`), so
/// no DNS-name handling is required for the address itself.
List<PathHop> parseTracertOutput(String output) {
  final hops = <PathHop>[];
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    final match = _tracertHopLine.firstMatch(line);
    if (match == null) continue;
    final hopNumber = int.tryParse(match.group(1)!);
    if (hopNumber == null) continue;
    final rest = match.group(2)!;

    final timedOut = rest.contains('*') && !_msToken.hasMatch(rest);
    if (timedOut) {
      hops.add(PathHop(hopNumber: hopNumber, timedOut: true));
      continue;
    }

    final msMatches = _msToken.allMatches(rest).toList();
    if (msMatches.isEmpty) continue; // not a hop line (header/footer text)

    final rtts = msMatches
        .map((m) => double.tryParse(m.group(1)!)?.round())
        .whereType<int>()
        .toList();
    final rttMs = rtts.isEmpty
        ? null
        : rtts.reduce((a, b) => a < b ? a : b);

    hops.add(PathHop(
      hopNumber: hopNumber,
      address: _extractAddress(rest),
      rttMs: rttMs,
      timedOut: rttMs == null,
    ));
  }
  return hops;
}

final RegExp _tracerouteHopLine = RegExp(r'^\s*(\d+)\s+(.*)$');

/// Parses `traceroute -n` output (macOS/Linux). Numeric addresses only
/// (`-n`), one probe per hop (`-q 1`), so each line has at most one `ms`
/// token or a `*` timeout marker.
List<PathHop> parseTracerouteOutput(String output) {
  final hops = <PathHop>[];
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    final match = _tracerouteHopLine.firstMatch(line);
    if (match == null) continue;
    final hopNumber = int.tryParse(match.group(1)!);
    if (hopNumber == null) continue;
    final rest = match.group(2)!;

    if (rest.trim().startsWith('*')) {
      hops.add(PathHop(hopNumber: hopNumber, timedOut: true));
      continue;
    }

    final msMatch = _msToken.firstMatch(rest);
    final address = _extractAddress(rest);
    if (msMatch == null && address == null) continue; // not a hop line

    hops.add(PathHop(
      hopNumber: hopNumber,
      address: address,
      rttMs: msMatch != null ? double.tryParse(msMatch.group(1)!)?.round() : null,
      timedOut: msMatch == null,
    ));
  }
  return hops;
}
