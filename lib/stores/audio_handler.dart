import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'player_store.dart';

/// Bridges [PlayerStore] to the OS media session (lock screen / notification /
/// bluetooth). Mirrors the role of Swift `NowPlaying` (`MPNowPlayingSession` +
/// `MPRemoteCommandCenter`). The store owns the [AudioPlayer]; this handler only
/// forwards transport commands and broadcasts the current [MediaItem] +
/// [PlaybackState] derived from the store's engine.
class MusixAudioHandler extends BaseAudioHandler {
  final PlayerStore player;

  /// Custom control id for the "收藏" (favorite) button on the notification.
  static const _favoriteAction = 'toggleFavorite';

  MusixAudioHandler(this.player) {
    player.engine.playbackEventStream.listen((_) => _broadcastState());
    player.favoriteChanges.listen((_) => _broadcastState());
    player.mediaItemChanges.listen((item) {
      mediaItem.add(item);
      _broadcastState();
    });
  }

  void _broadcastState() {
    final engine = player.engine;
    final playing = engine.playing;
    final favorited = player.favorited;
    const processingMap = {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    };
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.custom(
          androidIcon: favorited
              ? 'drawable/ic_favorite_filled'
              : 'drawable/ic_favorite_border',
          label: favorited ? '取消收藏' : '收藏',
          name: _favoriteAction,
        ),
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingMap[engine.processingState]!,
      playing: playing,
      updatePosition: engine.position,
      bufferedPosition: engine.bufferedPosition,
      speed: engine.speed,
    ));
  }

  @override
  Future<void> play() => player.requestPlay();

  @override
  Future<void> pause() async => player.requestPause();

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.prev();

  @override
  Future<void> seek(Duration position) async =>
      player.seek(position.inMilliseconds / 1000.0);

  @override
  Future<void> stop() async {
    await player.requestPauseAsync();
    await super.stop();
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == _favoriteAction) {
      await player.toggleFavorite();
    }
  }
}
