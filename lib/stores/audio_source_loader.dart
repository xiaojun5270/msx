import 'dart:async';

/// A failed cache proxy must not prevent a working HTTP stream from playing.
/// The caller provides a generation check so a cancelled load cannot replace
/// a newer song while the cached attempt is timing out.
Future<T> loadAudioWithFallback<T>({
  required Future<T> Function() cached,
  required Future<T> Function() direct,
  required Future<void> Function() stop,
  required bool Function() isCurrent,
  required void Function(Object) onCacheFailure,
  Duration cacheTimeout = const Duration(seconds: 12),
  Duration directTimeout = const Duration(seconds: 20),
}) async {
  try {
    return await cached().timeout(cacheTimeout);
  } catch (error) {
    if (!isCurrent()) rethrow;
    onCacheFailure(error);
    await stop().timeout(const Duration(seconds: 3));
    if (!isCurrent()) throw StateError('Audio request superseded');
    return await direct().timeout(directTimeout);
  }
}
