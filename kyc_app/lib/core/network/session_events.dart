import 'package:rxdart/rxdart.dart';

/// Broadcasts "the session can no longer be refreshed" from the network layer to the
/// AuthBloc without the interceptor depending on presentation code.
class SessionEvents {
  final PublishSubject<void> _expired = PublishSubject<void>();

  Stream<void> get onSessionExpired => _expired.stream;

  void notifyExpired() {
    if (!_expired.isClosed) _expired.add(null);
  }

  Future<void> dispose() => _expired.close();
}
