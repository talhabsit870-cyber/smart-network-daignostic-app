import 'package:http/http.dart' as http;

/// Lets a caller abort in-flight [NetworkTester] operations immediately.
/// Dart has no way to cancel an in-flight `Future` directly — closing the
/// `http.Client` a pending request is using makes that request throw right
/// away instead, which every `NetworkTester` method already catches
/// internally and returns its normal (failed/degraded) result for. So
/// "cancel" here means "close every client this run has opened."
class CancelToken {
  bool _cancelled = false;
  final List<http.Client> _clients = [];

  bool get isCancelled => _cancelled;

  /// Registers [client] so [cancel] closes it. If already cancelled, closes
  /// it immediately instead — covers the case where a phase starts a fresh
  /// client just as (or after) cancellation was requested.
  void track(http.Client client) {
    if (_cancelled) {
      client.close();
      return;
    }
    _clients.add(client);
  }

  void cancel() {
    _cancelled = true;
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
  }
}
