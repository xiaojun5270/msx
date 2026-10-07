import 'dart:async';

/// Load native HTTP with a bounded wait. Discard a timed-out engine without
/// awaiting stop() on that same blocked engine. Reject late results as well.
Future<T> loadDirectAudio<T>({
  required Future<T> Function() load,
  required bool Function() isCurrent,
  required void Function() onTimeout,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (!isCurrent()) throw StateError('Audio request superseded');
  try {
    final value = await load().timeout(timeout);
    if (!isCurrent()) throw StateError('Audio request superseded');
    return value;
  } on TimeoutException {
    if (isCurrent()) onTimeout();
    rethrow;
  }
}
