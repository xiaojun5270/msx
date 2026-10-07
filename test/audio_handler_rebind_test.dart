import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musix/stores/audio_handler.dart';
import 'package:musix/stores/player_store.dart';

class _Engine implements AudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  Duration position = Duration.zero;
  @override
  Duration get bufferedPosition => const Duration(seconds: 40);
  @override
  double get speed => 1;
  void emit() => events.add(PlaybackEvent());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store extends ChangeNotifier implements PlayerStore {
  @override
  AudioPlayer engine;
  final changes = StreamController<AudioPlayer>.broadcast(sync: true);
  _Store(this.engine);
  @override
  Stream<AudioPlayer> get engineChanges => changes.stream;
  @override
  bool get favorited => false;
  @override
  Stream<bool> get favoriteChanges => const Stream.empty();
  @override
  Stream<MediaItem?> get mediaItemChanges => const Stream.empty();
  void replace(AudioPlayer next) {
    engine = next;
    changes.add(next);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
      'lock-screen state follows the replacement engine and ignores retired events',
      () async {
    final old = _Engine();
    final next = _Engine();
    final store = _Store(old);
    final handler = MusixAudioHandler(store);
    old.emit();
    expect(
        handler.playbackState.value.processingState, AudioProcessingState.idle);
    store.replace(next);
    next.playing = true;
    next.processingState = ProcessingState.ready;
    next.position = const Duration(seconds: 12);
    next.emit();
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.updatePosition,
        const Duration(seconds: 12));
    old.emit();
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.updatePosition,
        const Duration(seconds: 12));
    await old.events.close();
    await next.events.close();
    await store.changes.close();
    store.dispose();
  });
}
