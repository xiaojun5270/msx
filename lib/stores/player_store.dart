import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../api/api_client.dart';
import '../api/source_management.dart';
import '../models/models.dart';
import 'session_store.dart';
import 'ui_store.dart';
import 'widget_bridge.dart';

/// The playback engine — mirrors Swift `PlayerStore`.
///
/// The Swift original drives `AVPlayer` through a custom
/// `StreamResourceLoader` that hand-feeds byte ranges (needed because AVPlayer
/// cannot attach cookies to a redirected media request). On Android,
/// ExoPlayer (via just_audio) performs range requests, format sniffing, and
/// buffering natively and accepts per-request headers, so the whole
/// `StreamResourceLoader` layer collapses into passing the resolved URL plus a
/// `Cookie` header to `setAudioSource`. Everything above that — server session
/// lifecycle, intent polling, retained-session reuse, preheat, source handoff,
/// recovery, telemetry, lyrics — is ported faithfully.
class PlayerStore extends ChangeNotifier {
  // ---- Observable state (mirrors the Swift @Observable properties) ----------
  List<Track> queue = [];
  int index = -1;
  bool playing = false;
  bool loading = false;
  PlaybackSourceProgress sourceProgress =
      PlaybackSourceProgress(phase: PlaybackSourcePhase.idle);
  double current = 0;
  double duration = 0;
  bool shuffle = false;
  int repeatMode = 0;
  bool nowPlayingOpen = false;
  bool favorited = false;
  bool trial = false;
  String? selectedSourceKey;
  String? sourceKind;
  String? sourcePlatform;
  List<LyricLine> lyrics = [];
  int lyricIndex = 0;
  double volume = 1;

  /// The user is dragging the scrubber. While true the position stream does not
  /// update `current`, to avoid the thumb jumping. Mirrors Swift `isSeeking`.
  bool isSeeking = false;

  Track? get track => (index >= 0 && index < queue.length) ? queue[index] : null;

  /// Open/close the full Now Playing surface. Mirrors the Swift
  /// `nowPlayingOpen` binding used by RootView's fullScreenCover.
  void setNowPlayingOpen(bool open) {
    if (nowPlayingOpen == open) return;
    nowPlayingOpen = open;
    notifyListeners();
  }

  // ---- Engine + bridges ------------------------------------------------------
  AudioPlayer _av = AudioPlayer();
  AudioPlayer get engine => _av;

  final StreamController<MediaItem?> _mediaItemCtrl =
      StreamController<MediaItem?>.broadcast();
  final StreamController<bool> _favoriteCtrl =
      StreamController<bool>.broadcast();
  Stream<MediaItem?> get mediaItemChanges => _mediaItemCtrl.stream;
  Stream<bool> get favoriteChanges => _favoriteCtrl.stream;

  final List<StreamSubscription> _engineSubs = [];

  SessionStore? _session;
  UIStore? _ui;

  // ---- Internal bookkeeping (mirrors Swift private state) --------------------
  int _token = 0;
  int _listenReportedForToken = -1;
  int _controlRevision = 0;
  String? _playbackIntentID;
  String? _playbackSessionID;
  bool _wantsPlayback = false;
  List<int> _shuffleSeq = [];
  String? _recordingCorrespondence;
  String? _activeLocalFileID;
  final Set<String> _failedLocalPlaybackFileIDs = {};
  bool _usedLocalFileFallback = false;
  bool _recovering = false;
  String? _loadedTrackKey;
  Uri? _loadedURL;
  Map<String, String> _loadedHeaders = const {};
  int _lyricsToken = 0;
  DateTime _lastHeartbeatAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Preheat -------------------------------------------------------------------
  int _preheatRevision = 0;
  String? _candidatePreheatKey;
  String? _warmPreheatKey;
  String? _preheatPlayingAcknowledgedIntentID;
  bool _observedPreheatPlaying = false;
  Future<PlaybackTelemetryReceipt?>? _telemetryTail;

  // Retained-session reuse ----------------------------------------------------
  final Map<String, _RetainedPlayback> _retained = {};
  final Map<String, Timer> _retainedExpiry = {};

  void _setWantsPlayback(bool value) {
    if (_wantsPlayback != value) _controlRevision += 1;
    _wantsPlayback = value;
  }

  // ---------------------------------------------------------------------------
  // Binding + engine observation
  // ---------------------------------------------------------------------------

  void bind({required SessionStore session, required UIStore ui}) {
    _session = session;
    _ui = ui;
    if (queue.isEmpty) {
      final snap = session.local.loadQueue();
      queue = snap.tracks;
      index = snap.index;
      shuffle = session.local.prefs.shuffle;
      repeatMode = session.local.prefs.repeatMode;
      _rebuildShuffle(anchor: index);
    }
    _attachEngineListeners();
    _applyVolume();
    _syncPlaybackState();
    notifyListeners();
  }

  void _attachEngineListeners() {
    for (final s in _engineSubs) {
      s.cancel();
    }
    _engineSubs.clear();

    _engineSubs.add(_av.positionStream.listen((pos) {
      if (isSeeking || loading) return;
      final secs = pos.inMilliseconds / 1000.0;
      if ((secs - current).abs() >= 0.05) {
        current = secs;
        _syncLyric();
        notifyListeners();
      }
      _heartbeatIfNeeded();
      _maybeReportListen();
    }));

    _engineSubs.add(_av.durationStream.listen((d) {
      if (d == null) return;
      final secs = d.inMilliseconds / 1000.0;
      if (secs.isFinite && (secs - duration).abs() >= 0.05) {
        duration = secs;
        notifyListeners();
      }
    }));

    _engineSubs.add(_av.playerStateStream.listen((state) {
      _syncPlaybackState();
      if (state.processingState == ProcessingState.completed) {
        _onEnded();
      }
    }));
  }

  /// True only when the engine is actually playing or buffering a real item.
  /// Mirrors Swift `isActivelyPlaying` (AVPlayer `timeControlStatus`).
  bool get _isActivelyPlaying {
    final st = _av.processingState;
    if (st == ProcessingState.idle || st == ProcessingState.completed) {
      return false;
    }
    if (st == ProcessingState.ready) return _av.playing;
    // loading / buffering: only "active" if we have a source and want to play.
    return _av.playing && _wantsPlayback;
  }

  bool get _needsReloadToPlay {
    final st = _av.processingState;
    return st == ProcessingState.idle || st == ProcessingState.completed;
  }

  void _syncPlaybackState() {
    final live = _isActivelyPlaying;
    if (live) {
      if (!_observedPreheatPlaying) {
        _observedPreheatPlaying = true;
        _ensurePreheatCandidates();
      }
      _promoteWarmWindowIfNeeded();
    } else if (_observedPreheatPlaying) {
      _stopPreheat();
    }

    if (sourceProgress.phase != PlaybackSourcePhase.failed) {
      if (live) {
        sourceProgress = PlaybackSourceProgress(phase: PlaybackSourcePhase.playing);
      } else if (!loading && _av.processingState != ProcessingState.idle) {
        final buffering = _wantsPlayback &&
            _av.processingState == ProcessingState.buffering;
        sourceProgress = PlaybackSourceProgress(
            phase: buffering ? PlaybackSourcePhase.buffering : PlaybackSourcePhase.ready);
      }
    }

    if (playing != live) {
      playing = live;
      _publishNowPlaying();
    }
    notifyListeners();
  }

  void _setSourceProgress(PlaybackSourcePhase phase, {String? detail}) {
    sourceProgress = PlaybackSourceProgress(phase: phase, detail: detail);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Transport commands
  // ---------------------------------------------------------------------------

  Future<void> requestPlay() async {
    if (loading) return;
    if (track == null || index < 0 || index >= queue.length) return;
    if (_isActivelyPlaying) return;
    await toggle();
  }

  /// Synchronous pause entry point used by the UI mini-player.
  void requestPause() {
    if (loading) return;
    if (!_isActivelyPlaying && !playing) return;
    _controlRevision += 1;
    _stopPreheat();
    _setWantsPlayback(false);
    _av.pause();
    _syncPlaybackState();
    _publishNowPlaying();
  }

  Future<void> requestPauseAsync() async => requestPause();

  Future<void> toggle() async {
    _controlRevision += 1;
    if (track == null || index < 0 || index >= queue.length) return;
    if (loading) {
      _cancelLoading();
      return;
    }
    if (_isActivelyPlaying) {
      _stopPreheat();
      _setWantsPlayback(false);
      await _av.pause();
      _syncPlaybackState();
      _publishNowPlaying();
      return;
    }
    if (_needsReloadToPlay) {
      await _playAt(index, position: current, recover: true);
      return;
    }
    _setWantsPlayback(true);
    final generation = _token;
    unawaited(_av.play());
    if (generation != _token || !_wantsPlayback) return;
    _syncPlaybackState();
    _publishNowPlaying();
  }

  void seek(double t) {
    final upper = duration > 0 ? duration : double.maxFinite;
    final target = t.clamp(0.0, upper);
    _av.seek(Duration(milliseconds: (target * 1000).round()));
    current = target.toDouble();
    _syncLyric();
    _publishNowPlaying();
    notifyListeners();
  }

  void seekBy(double offset) {
    if (track == null) return;
    seek(current + offset);
  }

  Future<void> prev() async {
    if (current > 3) {
      seek(0);
      return;
    }
    if (queue.isEmpty) return;
    if (shuffle) {
      final pos = _shuffleSeq.indexOf(index);
      if (pos > 0) {
        await _playAt(_shuffleSeq[pos - 1]);
        return;
      }
    }
    await _playAt((index - 1 + queue.length) % queue.length);
  }

  Future<void> next() async => _advance(fromEnd: false);

  void setVolume(double v) {
    volume = v.clamp(0.0, 1.0);
    _applyVolume();
    notifyListeners();
  }

  void _applyVolume() => _av.setVolume(volume);

  void toggleShuffle() {
    shuffle = !shuffle;
    _rebuildShuffle(anchor: index);
    _persist();
    _preheatQueueDidChange();
    notifyListeners();
  }

  void cycleRepeat() {
    repeatMode = (repeatMode + 1) % 3;
    _persist();
    _preheatQueueDidChange();
    notifyListeners();
  }

  void _cancelLoading() {
    if (!loading) return;
    final intentID = _playbackIntentID;
    final sessionID = _playbackSessionID;
    _token += 1;
    loading = false;
    _setWantsPlayback(false);
    playing = false;
    _av.pause();
    _av.stop();
    _loadedTrackKey = null;
    _playbackIntentID = null;
    _playbackSessionID = null;
    _setSourceProgress(PlaybackSourcePhase.idle);
    final session = _session;
    if (session != null) {
      () async {
        if (intentID != null) {
          await session.api.delete('/api/playback/intents/$intentID').catchError((_) {});
        }
        if (sessionID != null) {
          await session.api.delete('/api/playback/sessions/$sessionID').catchError((_) {});
        }
      }();
    }
    _publishNowPlaying();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Queue operations
  // ---------------------------------------------------------------------------

  Future<void> playNow(Track item) async {
    if (await _reuseCurrentPlaybackIfPossible(item, restart: true)) return;
    final i = queue.indexWhere((t) => t.key == item.key);
    if (i >= 0) {
      await _playAt(i);
      return;
    }
    if (index >= 0 && index < queue.length) {
      queue.insert(index + 1, item);
      _rebuildShuffle();
      await _playAt(index + 1);
    } else {
      queue.add(item);
      _rebuildShuffle();
      await _playAt(queue.length - 1);
    }
  }

  void playNext(Track item) {
    if (index >= 0 && index < queue.length) {
      queue.insert(index + 1, item);
    } else {
      queue.add(item);
      if (index < 0) _playAt(queue.length - 1);
    }
    _rebuildShuffle();
    _persist();
    _preheatQueueDidChange();
    _ui?.notify('已加入下一首');
    notifyListeners();
  }

  void enqueue(Track item) {
    queue.add(item);
    _ui?.notify('已加入播放列表');
    if (index < 0) _playAt(queue.length - 1);
    _rebuildShuffle();
    _persist();
    _preheatQueueDidChange();
    notifyListeners();
  }

  Future<void> replaceQueue(List<Track> tracks, {required int start, PlaySource? source}) async {
    final items = tracks.where((t) => t.title.isNotEmpty || t.id.isNotEmpty).toList();
    if (items.isEmpty) return;
    final i = start.clamp(0, items.length - 1);
    final reuses = _canReuseCurrentPlayback(items[i]);
    queue = items;
    index = i;
    _rebuildShuffle(anchor: i);
    _persist();
    notifyListeners();
    if (reuses) {
      _preheatQueueDidChange();
      await _reuseCurrentPlaybackIfPossible(items[i], restart: true);
    } else {
      await _playAt(i);
    }
    await _recordSource(source);
  }

  Future<void> jumpTo(int idx) async {
    if (idx < 0 || idx >= queue.length) return;
    if (await _reuseCurrentPlaybackIfPossible(queue[idx], restart: true)) return;
    await _playAt(idx);
  }

  Future<void> removeAt(int idx) async {
    if (idx < 0 || idx >= queue.length) return;
    if (idx == index) {
      queue.removeAt(idx);
      if (queue.isEmpty) {
        index = -1;
        _token += 1;
        await _av.stop();
        _loadedTrackKey = null;
        playing = false;
        _setSourceProgress(PlaybackSourcePhase.idle);
      } else {
        index = idx.clamp(0, queue.length - 1);
        await _playAt(index);
      }
    } else {
      queue.removeAt(idx);
      if (idx < index) index -= 1;
    }
    _rebuildShuffle(anchor: index);
    _persist();
    _preheatQueueDidChange();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Reuse of a still-healthy playback for repeated selection of the same track
  // ---------------------------------------------------------------------------

  bool _canReuseCurrentPlayback(Track item) {
    if (loading) return false;
    if (_loadedTrackKey != item.key) return false;
    if (_av.processingState == ProcessingState.idle) return false;
    if (_needsReloadToPlay) return false;
    return true;
  }

  Future<bool> _reuseCurrentPlaybackIfPossible(Track item, {required bool restart}) async {
    if (!_canReuseCurrentPlayback(item)) return false;
    final generation = _token;
    if (restart) {
      await _av.seek(Duration.zero);
      if (generation != _token || !_canReuseCurrentPlayback(item)) return false;
      current = 0;
      _syncLyric();
      notifyListeners();
    }
    if (_isActivelyPlaying) {
      _publishNowPlaying(progressOnly: true);
      return true;
    }
    _setWantsPlayback(true);
    unawaited(_av.play());
    if (generation != _token || !_wantsPlayback || !_canReuseCurrentPlayback(item)) return false;
    _syncPlaybackState();
    _publishNowPlaying();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Retained-session reuse (quick A → B → A switches)
  // ---------------------------------------------------------------------------

  void _retainCurrentPlaybackIfPossible() {
    if (loading) return;
    final key = _loadedTrackKey;
    final url = _loadedURL;
    if (key == null || url == null) return;
    if (_av.processingState == ProcessingState.idle ||
        _av.processingState == ProcessingState.completed) return;
    final retained = _RetainedPlayback(
      trackKey: key,
      url: url,
      headers: _loadedHeaders,
      intentID: _playbackIntentID,
      sessionID: _playbackSessionID,
      selectedSourceKey: selectedSourceKey,
      sourceKind: sourceKind,
      sourcePlatform: sourcePlatform,
      recordingCorrespondence: _recordingCorrespondence,
      trial: trial,
      duration: duration,
      createdAt: DateTime.now(),
    );
    _insertRetainedPlayback(retained);
  }

  void _insertRetainedPlayback(_RetainedPlayback playback) {
    final stale = _retained.values
        .where((p) => !PlaybackSessionReusePolicy.isFresh(p.createdAt))
        .toList();
    for (final entry in stale) {
      _removeRetainedPlayback(entry.trackKey, expectedCreatedAt: entry.createdAt, discard: true);
    }
    final replaced = _retained[playback.trackKey];
    _retained[playback.trackKey] = playback;
    if (replaced != null && replaced.url != playback.url) {
      _discardRetainedPlayback(replaced);
    }
    _retainedExpiry.remove(playback.trackKey)?.cancel();
    _retainedExpiry[playback.trackKey] = Timer(PlaybackSessionReusePolicy.lifetime, () {
      _removeRetainedPlayback(playback.trackKey, expectedCreatedAt: playback.createdAt, discard: true);
    });
    final overflow = _retained.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final excess = _retained.length - PlaybackSessionReusePolicy.capacity;
    for (var i = 0; i < excess && i < overflow.length; i++) {
      _removeRetainedPlayback(overflow[i].trackKey,
          expectedCreatedAt: overflow[i].createdAt, discard: true);
    }
  }

  _RetainedPlayback? _takeRetainedPlayback(Track track) {
    final retained = _retained.remove(track.key);
    if (retained == null) return null;
    _retainedExpiry.remove(track.key)?.cancel();
    if (!PlaybackSessionReusePolicy.isFresh(retained.createdAt)) {
      _discardRetainedPlayback(retained);
      return null;
    }
    return retained;
  }

  void _removeRetainedPlayback(String key, {DateTime? expectedCreatedAt, required bool discard}) {
    final retained = _retained[key];
    if (retained == null) return;
    if (expectedCreatedAt != null && retained.createdAt != expectedCreatedAt) return;
    _retained.remove(key);
    _retainedExpiry.remove(key)?.cancel();
    if (discard) _discardRetainedPlayback(retained);
  }

  void _discardRetainedPlayback(_RetainedPlayback playback) {
    final session = _session;
    if (session == null) return;
    final intentID = playback.intentID;
    final sessionID = playback.sessionID;
    if (intentID == null && sessionID == null) return;
    () async {
      if (intentID != null) {
        await session.api.delete('/api/playback/intents/$intentID').catchError((_) {});
      }
      if (sessionID != null) {
        await session.api.delete('/api/playback/sessions/$sessionID').catchError((_) {});
      }
    }();
  }

  Future<bool> _restoreRetainedPlayback(_RetainedPlayback retained,
      {required int idx, required double position, required bool autoplay}) async {
    final session = _session;
    if (session == null || idx < 0 || idx >= queue.length || retained.trackKey != queue[idx].key) {
      _discardRetainedPlayback(retained);
      return false;
    }
    _stopPreheat();
    _retainCurrentPlaybackIfPossible();
    _token += 1;
    final mine = _token;
    index = idx;
    _recovering = false;
    _setWantsPlayback(autoplay);
    loading = false;
    _lyricsToken += 1;
    _playbackIntentID = retained.intentID;
    _playbackSessionID = retained.sessionID;
    selectedSourceKey = retained.selectedSourceKey;
    sourceKind = retained.sourceKind;
    sourcePlatform = retained.sourcePlatform;
    _recordingCorrespondence = retained.recordingCorrespondence;
    trial = retained.trial;
    duration = retained.duration;
    current = PlaybackSessionReusePolicy.playbackPosition(
        requested: position, duration: retained.duration);
    lyrics = [];
    _setSourceProgress(PlaybackSourcePhase.ready);
    try {
      await _av.setAudioSource(
        AudioSource.uri(retained.url, headers: retained.headers),
        initialPosition: Duration(milliseconds: (current * 1000).round()),
      );
    } catch (_) {
      _discardRetainedPlayback(retained);
      return false;
    }
    if (mine != _token) return true;
    _loadedTrackKey = retained.trackKey;
    _loadedURL = retained.url;
    _loadedHeaders = retained.headers;
    _applyVolume();
    if (autoplay) {
      if (mine != _token) return true;
      unawaited(_av.play());
    }
    _syncPlaybackState();
    _publishNowPlaying();
    if (autoplay) await _recordHistory(queue[idx]);
    await _loadLyrics(queue[idx]);
    _persist();
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Playback session lifecycle — the core of the engine
  // ---------------------------------------------------------------------------

  /// Only an explicit, natively decodable local path may bypass a playback
  /// session. `?id=` intentionally hides the real extension; it is often a
  /// FLAC/.flc import and must go through the server session so the server can
  /// return its AAC/M4A playback representation. Mirrors Swift.
  static bool _libraryFileDirectPlayable(String raw, Track track) {
    final decoded = Uri.decodeFull(raw);
    if (!decoded.contains('/api/library/file?') || !decoded.contains('path=')) return false;
    final haystack = '$decoded ${track.id} ${track.title}'.toLowerCase();
    if (['.flac', '.flc', '.ogg', '.opus', '.ape', '.wma'].any(haystack.contains)) {
      return false;
    }
    return ['.mp3', '.m4a', '.aac', '.wav', '.mp4'].any(haystack.contains);
  }

  static Map<String, String> _playbackHeaders(String? cookie) {
    final headers = <String, String>{
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      'Icy-MetaData': '0',
    };
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;
    return headers;
  }

  Future<void> _playAt(int idx, {double position = 0, bool autoplay = true, bool recover = false}) async {
    final session = _session;
    if (session == null || idx < 0 || idx >= queue.length) return;

    // Recovery deliberately bypasses the retained item: a failed/expired
    // transport must be rebuilt instead of being restored repeatedly.
    if (!recover) {
      final retained = _takeRetainedPlayback(queue[idx]);
      if (retained != null &&
          await _restoreRetainedPlayback(retained, idx: idx, position: position, autoplay: autoplay)) {
        return;
      }
    }
    _stopPreheat();
    _retainCurrentPlaybackIfPossible();
    index = idx;
    final row = queue[idx];
    _token += 1;
    final mine = _token;
    if (!recover) {
      _recovering = false;
      _failedLocalPlaybackFileIDs.clear();
      _usedLocalFileFallback = false;
    }
    _recovering = recover;

    var deadline = DateTime.now().add(const Duration(minutes: 15));
    final oldIntent = _playbackIntentID;
    final oldSession = _playbackSessionID;
    final intentID = _uuid();
    _playbackIntentID = intentID;
    _playbackSessionID = null;
    _setWantsPlayback(autoplay);
    _lyricsToken += 1;
    loading = true;
    await _av.pause();
    playing = false;
    current = position;
    duration = row.duration;
    trial = false;
    selectedSourceKey = null;
    sourceKind = null;
    sourcePlatform = null;
    _activeLocalFileID = null;
    _setSourceProgress(PlaybackSourcePhase.resolving);
    lyrics = [];
    notifyListeners();
    _publishNowPlaying();

    String? createdSessionID;
    void acceptDeadline(PlaybackSessionResponse result) {
      if (result.playIntentId != null && result.playIntentId != intentID) {
        throw const ApiError('音源会话已失效，请重试');
      }
      final raw = result.autoWaitUntil;
      if (raw != null) {
        final until = DateTime.tryParse(raw);
        if (until != null) {
          final secs = until.difference(DateTime.now()).inMilliseconds / 1000.0;
          deadline = DateTime.now().add(Duration(milliseconds: (secs.clamp(1, 900) * 1000).round()));
        }
      }
    }

    try {
      final retainsOldTransport = _retained.values.any((p) =>
          (p.intentID != null && p.intentID == oldIntent) ||
          (p.sessionID != null && p.sessionID == oldSession));
      if (!retainsOldTransport) {
        if (oldIntent != null) {
          await session.api.delete('/api/playback/intents/$oldIntent').catchError((_) {});
        }
        if (oldSession != null) {
          await session.api.delete('/api/playback/sessions/$oldSession').catchError((_) {});
        }
      }
      if (mine != _token) return;

      final Uri playURL;
      final rawStream = row.streamUrl;
      if (!recover &&
          rawStream != null &&
          _libraryFileDirectPlayable(rawStream, row) &&
          session.api.absolute(rawStream) != null) {
        sourceKind = 'local_replacement';
        sourcePlatform = 'localfile';
        selectedSourceKey = 'localfile::${row.id}';
        playURL = session.api.absolute(rawStream)!;
      } else {
        var result = await session.api.createPlaybackSession(row, intentId: intentID, recover: recover);
        createdSessionID = result.sessionId;
        acceptDeadline(result);
        if (result.isWaiting) {
          _setSourceProgress(PlaybackSourcePhase.preparing,
              detail: PlaybackSourceProgress.preparationDetail(status: result.status, reason: result.reason));
        }
        while (result.isWaiting && DateTime.now().isBefore(deadline) && mine == _token) {
          await Future.delayed(const Duration(milliseconds: 400));
          if (mine != _token || !DateTime.now().isBefore(deadline)) break;
          result = await session.api.pollPlaybackIntent(intentID);
          createdSessionID = result.sessionId;
          acceptDeadline(result);
          if (result.isWaiting) {
            _setSourceProgress(PlaybackSourcePhase.preparing,
                detail: PlaybackSourceProgress.preparationDetail(status: result.status, reason: result.reason));
          }
        }
        if (mine != _token) {
          await session.api.delete('/api/playback/intents/$intentID').catchError((_) {});
          if (result.sessionId != null) {
            await session.api.delete('/api/playback/sessions/${result.sessionId}').catchError((_) {});
          }
          return;
        }
        if (!DateTime.now().isBefore(deadline)) throw const ApiError('播放准备超时，请重试');
        _playbackSessionID = result.sessionId;
        sourceKind = result.sourceKind;
        sourcePlatform = result.sourcePlatform;
        _activeLocalFileID = result.fileId;
        trial = result.isPreview;
        _recordingCorrespondence = result.recordingCorrespondence;
        if (result.sourcePlatform != null && result.sourceTrackId != null) {
          selectedSourceKey = '${result.sourcePlatform}::${result.sourceTrackId}';
        }
        final resolved = result.streamUrl == null ? null : session.api.absolute(result.streamUrl);
        final okTransport = !result.hasTransport || result.playbackKind == 'http';
        if (result.status != 'ready' || !okTransport || resolved == null) {
          loading = false;
          _setWantsPlayback(false);
          final message = result.hasTransport
              ? '此音源传输方式暂不支持，请选择其他完整音源'
              : '${result.reason ?? '音源准备中'}，请重试播放或换源';
          _setSourceProgress(PlaybackSourcePhase.failed, detail: message);
          await session.api.delete('/api/playback/intents/$intentID').catchError((_) {});
          if (result.sessionId != null) {
            await session.api.delete('/api/playback/sessions/${result.sessionId}').catchError((_) {});
          }
          if (mine != _token) return;
          _ui?.notify(message);
          notifyListeners();
          return;
        }
        playURL = resolved;
      }

      final headers = _playbackHeaders(session.api.combinedCookieHeader());
      final playDeadline = DateTime.now().add(const Duration(seconds: 20));
      _setSourceProgress(PlaybackSourcePhase.connecting);
      _setSourceProgress(PlaybackSourcePhase.buffering);
      final loadedDuration = await _av
          .setAudioSource(
            AudioSource.uri(playURL, headers: headers),
            initialPosition: position > 0
                ? Duration(milliseconds: (position * 1000).round())
                : Duration.zero,
          )
          .timeout(playDeadline.difference(DateTime.now()));
      if (mine != _token) return;
      _loadedTrackKey = row.key;
      _loadedURL = playURL;
      _loadedHeaders = headers;
      if (loadedDuration != null) {
        final d = loadedDuration.inMilliseconds / 1000.0;
        if (d.isFinite && d > 0) duration = d;
      }
      _applyVolume();

      if (_wantsPlayback) {
        unawaited(_av.play());
        if (mine != _token) return;
      } else {
        await _av.pause();
      }
      loading = false;
      _syncPlaybackState();
      _publishNowPlaying();
      _loadArtwork(row);
      await Future.wait<void>([
        _refreshFavorite(row),
        if (_wantsPlayback) _recordHistory(row) else Future<void>.value(),
        _loadLyrics(row),
      ]);
      _persist();
      notifyListeners();
    } catch (error) {
      await session.api.delete('/api/playback/intents/$intentID').catchError((_) {});
      if (createdSessionID != null) {
        await session.api.delete('/api/playback/sessions/$createdSessionID').catchError((_) {});
      }
      if (mine == _token && !recover && autoplay) {
        await _playAt(idx, position: position, autoplay: true, recover: true);
        return;
      }
      if (mine == _token) {
        await _av.stop();
        _loadedTrackKey = null;
        _loadedURL = null;
        _playbackIntentID = null;
        _playbackSessionID = null;
      }
      if (mine != _token) return;
      loading = false;
      _setWantsPlayback(false);
      playing = false;
      final message = _describeError(error);
      _setSourceProgress(PlaybackSourcePhase.failed, detail: message);
      _ui?.openSource(row);
      _ui?.notify(message);
      notifyListeners();
    }
  }

  String _describeError(Object error) {
    if (error is ApiError) return error.message;
    final msg = error.toString();
    if (msg.contains('TimeoutException')) return '播放准备超时，请重试';
    if (error is PlayerException) return '音源接口返回了无法播放的数据，请重试';
    if (error is PlayerInterruptedException) return '播放被中断，请重试';
    return '无法打开音频';
  }

  // ---------------------------------------------------------------------------
  // End-of-track advance + recovery
  // ---------------------------------------------------------------------------

  Future<void> _onEnded() async {
    final position = current;
    final itemDuration = duration;
    if (!SourceEndPolicy.isNaturalEnd(
      position: position,
      itemDuration: itemDuration,
      trackDuration: duration,
      loading: loading,
      trial: trial,
    )) {
      return;
    }
    playing = false;
    _maybeReportListen(completed: true);
    if (repeatMode == 1) {
      await _playAt(index);
      return;
    }
    await _advance(fromEnd: true);
  }

  Future<void> _advance({required bool fromEnd}) async {
    if (queue.isEmpty) return;
    if (shuffle) {
      final pos = _shuffleSeq.indexOf(index);
      if (pos >= 0) {
        if (pos + 1 < _shuffleSeq.length) {
          await _playAt(_shuffleSeq[pos + 1]);
          return;
        }
        if (repeatMode == 2) {
          await _playAt(_shuffleSeq[0]);
          return;
        }
        if (fromEnd) {
          playing = false;
          _publishNowPlaying();
          notifyListeners();
        }
        return;
      }
    }
    if (index + 1 < queue.length) {
      await _playAt(index + 1);
      return;
    }
    if (repeatMode == 2) {
      await _playAt(0);
      return;
    }
    if (fromEnd) {
      playing = false;
      await _av.pause();
      _publishNowPlaying();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Source switching (apply a picked candidate to the current track)
  // ---------------------------------------------------------------------------

  Future<SourceApplyReceipt> applySource(Track candidate, Track original, {int? version}) async {
    final session = _session;
    if (session == null) throw const ApiError('未登录', status: 401);
    final wasCurrent = track?.key == original.key;
    final outcome = await session.api.applySource(
        original: original, candidate: candidate, version: version);
    if (!outcome.canRebuildSession) {
      return SourceApplyReceipt(outcome: outcome, switchResult: SourceSwitchResult.notRequested);
    }
    if (track?.key != original.key) {
      return SourceApplyReceipt(
          outcome: outcome,
          switchResult: wasCurrent ? SourceSwitchResult.cancelled : SourceSwitchResult.notRequested);
    }
    // Rebuild the session for the current track at its current position. On
    // Android a fresh setAudioSource is cheap and avoids the dual-engine
    // handoff complexity AVFoundation needed.
    final idx = index;
    final position = current;
    await _playAt(idx, position: position, autoplay: true);
    if (track?.key != original.key) {
      return SourceApplyReceipt(outcome: outcome, switchResult: SourceSwitchResult.cancelled);
    }
    if (loading) {
      return SourceApplyReceipt(outcome: outcome, switchResult: SourceSwitchResult.pending);
    }
    return SourceApplyReceipt(
        outcome: outcome,
        switchResult: (playing || _wantsPlayback) ? SourceSwitchResult.switched : SourceSwitchResult.failed);
  }

  // ---------------------------------------------------------------------------
  // Favorites / history / listens
  // ---------------------------------------------------------------------------

  Future<void> toggleFavorite([Track? item]) async {
    final session = _session;
    final row = item ?? track;
    if (session == null || row == null) return;
    try {
      final data = await session.api.postJson('/api/my/favorites/toggle', FavToggle.fromJson, json: row.payload());
      final on = data.favorited ?? data.has ?? false;
      if (row.key == track?.key) {
        favorited = on;
        _favoriteCtrl.add(on);
        _publishNowPlaying();
      }
      _ui?.notify(on ? '已收藏' : '已取消收藏');
      notifyListeners();
    } catch (e) {
      _ui?.notify(_describeError(e));
    }
  }

  Future<void> addToPlaylist(String id, Track row) async {
    final session = _session;
    if (session == null) return;
    try {
      await session.api.post('/api/my/playlists/$id/tracks', json: row.payload());
      _ui?.notify('已加入歌单');
    } catch (e) {
      _ui?.notify(_describeError(e));
    }
  }

  Future<void> _refreshFavorite(Track row) async {
    final session = _session;
    if (session == null) return;
    final encP = Uri.encodeQueryComponent(row.platform);
    final encI = Uri.encodeQueryComponent(row.id);
    try {
      final data = await session.api
          .getJson('/api/my/favorites/has?platform=$encP&id=$encI', FavToggle.fromJson);
      if (track?.key != row.key) return;
      favorited = data.has ?? data.favorited ?? false;
      _favoriteCtrl.add(favorited);
      _publishNowPlaying();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _recordHistory(Track row) async {
    await _session?.api.post('/api/me/history', json: row.payload()).catchError((_) {});
  }

  Future<void> _recordSource(PlaySource? source) async {
    if (source == null || source.id.isEmpty || source.platform.isEmpty) return;
    await _session?.api.post('/api/me/history', json: source.payload()).catchError((_) {});
  }

  void _maybeReportListen({bool completed = false}) {
    if (trial || _token == _listenReportedForToken) return;
    final row = track;
    if (row == null) return;
    final durationMs = duration > 0 ? (duration * 1000).round() : (row.durationMs ?? 0).round();
    final positionMs = (current * 1000).round();
    final half = durationMs > 0 ? (durationMs / 2).clamp(0, 240000).toDouble() : 240000.0;
    if (!completed && positionMs < half) return;
    _listenReportedForToken = _token;
    _recordListen(row, positionMs: positionMs, durationMs: durationMs, completed: completed);
  }

  Future<void> _recordListen(Track row, {required int positionMs, required int durationMs, required bool completed}) async {
    final payload = row.payload();
    payload['positionMs'] = positionMs;
    payload['durationMs'] = durationMs;
    payload['completed'] = completed;
    await _session?.api.post('/api/me/listens', json: payload).catchError((_) {});
  }

  // ---------------------------------------------------------------------------
  // Lyrics
  // ---------------------------------------------------------------------------

  Future<void> _loadLyrics(Track row) async {
    _lyricsToken += 1;
    final mine = _lyricsToken;
    final session = _session;
    if (session == null) return;
    final qs = <String, String>{'title': row.title, 'artists': row.artistText};
    if (row.album != null) qs['album'] = row.album!;
    final query = qs.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final encP = Uri.encodeComponent(row.platform);
    final encI = Uri.encodeComponent(row.id);
    try {
      final box = await session.api
          .getJson('/api/tracks/$encP/$encI/lyrics?$query', LyricsBox.fromJson);
      if (mine != _lyricsToken || track?.key != row.key) return;
      lyrics = box.lines ?? [];
      _syncLyric();
      notifyListeners();
    } catch (_) {}
  }

  void _syncLyric() {
    final ms = current * 1000;
    var next = 0;
    for (var i = 0; i < lyrics.length; i++) {
      if ((lyrics[i].timeMs ?? 0) <= ms) next = i;
    }
    if (next != lyricIndex) {
      lyricIndex = next;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Preheat (server-side source preparation for upcoming tracks)
  // ---------------------------------------------------------------------------

  ({APIClient api, String intentID, String sessionID, List<Track> tracks})? _preheatContext() {
    final session = _session;
    if (_av.processingState != ProcessingState.ready || !_av.playing || _wantsPlayback == false || loading) {
      return null;
    }
    final intentID = _playbackIntentID;
    final sessionID = _playbackSessionID;
    if (session == null || intentID == null || sessionID == null) return null;
    final order = shuffle ? _shuffleSeq : List<int>.generate(queue.length, (i) => i);
    final upcoming = PlaybackPreheatPolicy.upcoming(order: order, current: index, repeatMode: repeatMode);
    final tracks = upcoming.where((i) => i >= 0 && i < queue.length).map((i) => queue[i]).toList();
    if (tracks.isEmpty) return null;
    return (api: session.api, intentID: intentID, sessionID: sessionID, tracks: tracks);
  }

  bool _isCurrentPreheat({required int revision, required String intentID, required String key, required bool warm}) {
    return revision == _preheatRevision &&
        _playbackIntentID == intentID &&
        _wantsPlayback &&
        _av.playing &&
        _av.processingState == ProcessingState.ready &&
        (warm ? _warmPreheatKey == key : _candidatePreheatKey == key);
  }

  Future<PlaybackTelemetryReceipt?> _sendPlaybackTelemetry(
      {required APIClient api, required String intentID, required String sessionID, required String state}) {
    final previous = _telemetryTail;
    final task = () async {
      await previous;
      try {
        return await api.postJson('/api/playback/telemetry', PlaybackTelemetryReceipt.fromJson,
            json: {'playIntentId': intentID, 'sessionId': sessionID, 'state': state});
      } catch (_) {
        return null;
      }
    }();
    _telemetryTail = task;
    return task;
  }

  Future<bool> _acknowledgePreheatPlaying(
      {required APIClient api, required String intentID, required String sessionID, required int revision}) async {
    if (_preheatPlayingAcknowledgedIntentID == intentID) return true;
    final receipt = await _sendPlaybackTelemetry(api: api, intentID: intentID, sessionID: sessionID, state: 'playing');
    if (receipt?.accepted != true ||
        revision != _preheatRevision ||
        _playbackIntentID != intentID ||
        !_wantsPlayback ||
        !_av.playing) {
      return false;
    }
    _preheatPlayingAcknowledgedIntentID = intentID;
    return true;
  }

  void _ensurePreheatCandidates() {
    final context = _preheatContext();
    if (context == null) return;
    final key = '${context.intentID}:${context.tracks.map((t) => t.key).join('|')}';
    if (key == _candidatePreheatKey) return;
    _preheatRevision += 1;
    final revision = _preheatRevision;
    _candidatePreheatKey = key;
    _warmPreheatKey = null;
    () async {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!_isCurrentPreheat(revision: revision, intentID: context.intentID, key: key, warm: false)) return;
        if (!await _acknowledgePreheatPlaying(
            api: context.api, intentID: context.intentID, sessionID: context.sessionID, revision: revision)) {
          return;
        }
        try {
          final receipt = await context.api.postJson('/api/playback/preheat', PlaybackPreheatReceipt.fromJson, json: {
            'playIntentId': context.intentID,
            'mode': 'candidates',
            'tracks': context.tracks.map((t) => t.identityPayload()).toList(),
          });
          if (!_isCurrentPreheat(revision: revision, intentID: context.intentID, key: key, warm: false)) return;
          if (receipt.reason == 'inactive_intent' || receipt.reason == 'inactive_session') {
            _stopPreheat();
          }
          return;
        } catch (_) {
          if (attempt >= 2) return;
          await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
        }
      }
    }();
  }

  void _promoteWarmWindowIfNeeded() {
    final context = _preheatContext();
    if (context == null) return;
    final nearingEnd = duration > 0 && duration - current <= 30;
    final limit = nearingEnd
        ? PlaybackPreheatPolicy.candidateLimit
        : PlaybackPreheatPolicy.baselineWarmWindow;
    final warmTracks = PlaybackPreheatPolicy.warmWindow(context.tracks, limit: limit);
    if (warmTracks.isEmpty) return;
    final key = '${context.intentID}:${warmTracks.map((t) => t.key).join('|')}';
    if (key == _warmPreheatKey) return;
    final revision = _preheatRevision;
    _warmPreheatKey = key;
    () async {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!_isCurrentPreheat(revision: revision, intentID: context.intentID, key: key, warm: true)) return;
        if (!await _acknowledgePreheatPlaying(
            api: context.api, intentID: context.intentID, sessionID: context.sessionID, revision: revision)) {
          return;
        }
        try {
          final receipt = await context.api.postJson('/api/playback/preheat', PlaybackPreheatReceipt.fromJson, json: {
            'playIntentId': context.intentID,
            'mode': 'warm_window',
            'tracks': warmTracks.map((t) => t.identityPayload()).toList(),
          });
          if (!_isCurrentPreheat(revision: revision, intentID: context.intentID, key: key, warm: true)) return;
          if (receipt.reason == 'inactive_intent' || receipt.reason == 'inactive_session') {
            _stopPreheat();
          }
          return;
        } catch (_) {
          if (attempt >= 2) return;
          await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
        }
      }
    }();
  }

  void _preheatQueueDidChange() {
    if (!_observedPreheatPlaying) return;
    _ensurePreheatCandidates();
  }

  void _stopPreheat() {
    _preheatRevision += 1;
    _candidatePreheatKey = null;
    _warmPreheatKey = null;
    _preheatPlayingAcknowledgedIntentID = null;
    _observedPreheatPlaying = false;
    final session = _session;
    final intentID = _playbackIntentID;
    final sessionID = _playbackSessionID;
    if (session == null || intentID == null || sessionID == null) return;
    _sendPlaybackTelemetry(api: session.api, intentID: intentID, sessionID: sessionID, state: 'paused');
  }

  // ---------------------------------------------------------------------------
  // Now Playing (lock screen / notification) + widget bridge
  // ---------------------------------------------------------------------------

  void _publishNowPlaying({bool progressOnly = false}) {
    final row = track;
    if (row == null) {
      _mediaItemCtrl.add(null);
      WidgetBridge.clearPlayback();
      return;
    }
    if (!progressOnly) {
      final api = _session?.api;
      final artUri = api?.absolute(row.cover);
      _mediaItemCtrl.add(MediaItem(
        id: row.key,
        title: row.title,
        artist: row.artistText,
        album: row.album,
        duration: duration > 0 ? Duration(milliseconds: (duration * 1000).round()) : null,
        artUri: artUri,
      ));
    }
    _publishPlaybackWidget();
  }

  void _loadArtwork(Track row) {
    // just_audio + audio_service render artwork from MediaItem.artUri; the
    // media item is (re)published on track change. Nothing to precompute.
    _publishNowPlaying();
  }

  DateTime _lastWidgetReloadAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool? _lastWidgetPlaying;
  String? _lastWidgetTrackKey;

  void _publishPlaybackWidget({bool reload = true}) {
    final session = _session;
    final row = track;
    if (row == null) {
      WidgetBridge.clearPlayback();
      _lastWidgetPlaying = null;
      _lastWidgetTrackKey = null;
      return;
    }
    String? cover;
    final raw = row.cover;
    if (raw != null && raw.isNotEmpty) {
      if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('data:')) {
        cover = raw;
      } else {
        final base = session?.baseURL ?? '';
        if (base.isNotEmpty) cover = base + (raw.startsWith('/') ? raw : '/$raw');
      }
    }
    final snap = PlaybackSnapshot(
      title: row.title,
      artist: row.artistText,
      album: row.album,
      coverUrl: cover,
      playing: playing,
      favorited: favorited,
      elapsed: current,
      duration: duration,
      updatedAt: DateTime.now(),
    );
    final trackChanged = _lastWidgetTrackKey != row.key;
    final playingChanged = _lastWidgetPlaying != snap.playing;
    _lastWidgetTrackKey = row.key;
    _lastWidgetPlaying = snap.playing;
    final stale = DateTime.now().difference(_lastWidgetReloadAt).inSeconds >= 45;
    final shouldReload = reload || trackChanged || playingChanged || (snap.playing && stale);
    if (shouldReload) _lastWidgetReloadAt = DateTime.now();
    WidgetBridge.savePlayback(snap, reload: shouldReload);
  }

  // ---------------------------------------------------------------------------
  // Persistence + shuffle + heartbeat + lifecycle
  // ---------------------------------------------------------------------------

  void _persist() {
    _session?.local.setPlayer(queue: queue, index: index, shuffle: shuffle, repeatMode: repeatMode);
  }

  void _rebuildShuffle({int? anchor}) {
    final a = anchor ?? index;
    final n = queue.length;
    if (!shuffle || n <= 1) {
      _shuffleSeq = n > 0 ? List<int>.generate(n, (i) => i) : [];
      return;
    }
    final rest = List<int>.generate(n, (i) => i).where((i) => i != a).toList();
    for (var i = rest.length - 1; i >= 1; i--) {
      final j = (DateTime.now().microsecondsSinceEpoch + i) % (i + 1);
      final tmp = rest[i];
      rest[i] = rest[j];
      rest[j] = tmp;
    }
    _shuffleSeq = a >= 0 ? [a, ...rest] : rest;
  }

  void _heartbeatIfNeeded() {
    if (!playing && !loading) return;
    final now = DateTime.now();
    if (now.difference(_lastHeartbeatAt).inSeconds < 5) return;
    _lastHeartbeatAt = now;
  }

  static int _uuidCounter = 0;
  static String _uuid() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'intent-$now-${_uuidCounter++}';
  }

  @override
  void dispose() {
    for (final s in _engineSubs) {
      s.cancel();
    }
    for (final t in _retainedExpiry.values) {
      t.cancel();
    }
    _mediaItemCtrl.close();
    _favoriteCtrl.close();
    _av.dispose();
    super.dispose();
  }
}

/// A recently detached playback whose server session may be reused for a quick
/// A → B → A switch. Mirrors the Swift `RetainedPlayback` struct. Because
/// just_audio cannot hand a prepared source between player instances, we retain
/// the resolved stream URL + headers instead of a live player item and re-issue
/// `setAudioSource`, which still avoids resolving a fresh server session.
class _RetainedPlayback {
  final String trackKey;
  final Uri url;
  final Map<String, String> headers;
  final String? intentID;
  final String? sessionID;
  final String? selectedSourceKey;
  final String? sourceKind;
  final String? sourcePlatform;
  final String? recordingCorrespondence;
  final bool trial;
  final double duration;
  final DateTime createdAt;

  _RetainedPlayback({
    required this.trackKey,
    required this.url,
    required this.headers,
    required this.intentID,
    required this.sessionID,
    required this.selectedSourceKey,
    required this.sourceKind,
    required this.sourcePlatform,
    required this.recordingCorrespondence,
    required this.trial,
    required this.duration,
    required this.createdAt,
  });
}
