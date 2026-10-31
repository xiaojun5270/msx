import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'session_store.dart';

/// Session-backed recommendation feed shared by the home card and callers
/// that need the full "猜你喜欢" list. The home shelf endpoint is only a
/// display fallback; recommendation paging always uses `/api/guess-you-like`.
///
/// The stored list applies the played filter: tracks that appear in the
/// server play history (`/api/me/history`) are kept and never-played
/// recommendations are dropped. If the history cannot be fetched the filter
/// is disabled instead of emptying the feed. `loadFirst(loadAll: true)`
/// keeps requesting 24-track pages sequentially until the server snapshot
/// is exhausted.
///
/// Radio playback ([fetchRandom]) deliberately ignores the played filter and
/// roams the full server pool, one fresh random request per song.
class GuessFeed extends ChangeNotifier {
  final SessionStore session;

  List<Track> tracks = [];
  List<GuessYouLikeSource> sources = [];
  bool loading = false;
  bool loadingMore = false;
  bool swapping = false;
  bool hasMore = false;
  int nextOffset = 0;
  int? total;
  String? generatedAt;
  String? error;
  String? notice;
  bool _active = true;

  Set<String> _playedKeys = {};
  bool _playedLoaded = false;
  bool _playedAvailable = false;
  static const int _historyPageLimit = 100;
  static const int _historyMaxPages = 40;
  static const int _maxChainedPages = 50;

  GuessFeed(this.session);

  List<Track> filtered(String platform) => platform == 'all'
      ? List.unmodifiable(tracks)
      : tracks.where((track) => track.platform == platform).toList();

  List<String> get platforms => {
        ...sources.map((source) => source.platform),
        ...tracks.map((track) => track.platform),
      }.where((platform) => platform.isNotEmpty).toList()
        ..sort();

  /// Collect every track key from the server play history. A failed fetch
  /// disables the played filter for this feed instance instead of dropping
  /// every recommendation.
  Future<void> _ensurePlayedKeys() async {
    if (_playedLoaded) return;
    _playedLoaded = true;
    final keys = <String>{};
    try {
      var offset = 0;
      for (var page = 0; page < _historyMaxPages; page++) {
        final box = await session.api.getJson(
          '/api/me/history?kind=track&limit=$_historyPageLimit&offset=$offset',
          HistoryPayload.fromJson,
        );
        final rows = box.items ?? box.tracks ?? const <Track>[];
        for (final track in rows) {
          if (track.id.isNotEmpty) keys.add(track.key);
        }
        if (rows.length < _historyPageLimit) break;
        offset += rows.length;
      }
      _playedKeys = keys;
      _playedAvailable = true;
    } catch (_) {
      _playedKeys = keys;
      _playedAvailable = false;
    }
  }

  Future<bool> loadFirst({bool loadAll = false}) async {
    if (loading || swapping || tracks.isNotEmpty) return tracks.isNotEmpty;
    loading = true;
    error = null;
    notice = null;
    _notify();
    try {
      await _ensurePlayedKeys();
      final page = await _request(offset: 0);
      _applyFirst(page);
      if (loadAll && hasMore && tracks.isNotEmpty) {
        await _loadRemaining();
      }
      return tracks.isNotEmpty;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<bool> loadMore() async {
    if (loading || loadingMore || swapping || !hasMore) return false;
    return _loadMorePage();
  }

  /// Keeps requesting the next page until the server runs out, so the feed
  /// ends up with the whole snapshot one 24-track request at a time.
  Future<void> _loadRemaining() async {
    for (var page = 0; page < _maxChainedPages && hasMore && _active; page++) {
      if (swapping) return;
      await _loadMorePage();
    }
  }

  Future<bool> _loadMorePage() async {
    loadingMore = true;
    error = null;
    _notify();
    final offset = nextOffset;
    try {
      final page = await _request(offset: offset, exclude: _keys);
      final fresh = _fresh(page.tracks, _keys);
      tracks = [...tracks, ...fresh];
      _advance(page, offset);
      return fresh.isNotEmpty;
    } catch (e) {
      error = e.toString();
      return false;
    } finally {
      loadingMore = false;
      _notify();
    }
  }

  Future<bool> refresh({String platform = 'all'}) async {
    if (loading || loadingMore || swapping) return false;
    swapping = true;
    error = null;
    notice = null;
    _notify();
    final excluded = _keys;
    try {
      await _ensurePlayedKeys();
      final page = await _request(
        offset: 0,
        exclude: excluded,
        platform: platform,
      );
      final fresh = _fresh(
        page.tracks,
        excluded,
        platform: platform == 'all' ? null : platform,
      );
      if (fresh.isEmpty) {
        notice = '暂时没有新的推荐，已保留当前列表。';
        return false;
      }
      if (platform == 'all') {
        tracks = fresh;
        sources = page.sources;
        total = page.total;
        nextOffset = page.nextOffset ?? fresh.length;
        hasMore = page.hasMore && nextOffset > 0;
      } else {
        tracks = [
          ...tracks.where((track) => track.platform != platform),
          ...fresh,
        ];
        sources = [
          ...sources.where((source) => source.platform != platform),
          ...page.sources.where((source) => source.platform == platform),
        ];
      }
      generatedAt = page.generatedAt ?? generatedAt;
      return true;
    } catch (e) {
      notice = '换一批失败，已保留当前列表，请稍后重试。';
      error = e.toString();
      return false;
    } finally {
      swapping = false;
      _notify();
    }
  }

  Set<String> get _keys => tracks.map((track) => track.key).toSet();

  int? _poolTotal;

  /// Radio-style pick: fetch one random track from the FULL server
  /// recommendation pool (the played filter does not apply here), freshly
  /// requested from the recommendation endpoint. Tries a few random offsets
  /// first, then sweeps the whole snapshot as a fallback. [avoidKeys]
  /// (queue contents + current track) are never returned so the radio does
  /// not repeat a song it already queued this session.
  Future<Track?> fetchRandom({Set<String> avoidKeys = const {}}) async {
    final rng = Random();
    for (var attempt = 0; attempt < 4; attempt++) {
      final total = _poolTotal;
      try {
        final offset =
            total != null && total > 24 ? rng.nextInt(total - 24 + 1) : 0;
        final page = await _request(offset: offset);
        if (page.total != null) _poolTotal = page.total;
        final fresh = _radioCandidates(page.tracks, avoidKeys);
        if (fresh.isNotEmpty) {
          return fresh[rng.nextInt(fresh.length)];
        }
      } catch (_) {
        break;
      }
    }
    try {
      final candidates = <Track>[];
      var offset = 0;
      for (var page = 0; page < 12; page++) {
        final p = await _request(offset: offset, exclude: avoidKeys);
        if (p.total != null) _poolTotal = p.total;
        candidates.addAll(_radioCandidates(p.tracks, avoidKeys));
        if (!p.hasMore) break;
        final nextOffset = p.nextOffset ?? offset + p.tracks.length;
        if (nextOffset <= offset) break;
        offset = nextOffset;
      }
      if (candidates.isEmpty) return null;
      return candidates[rng.nextInt(candidates.length)];
    } catch (_) {
      return null;
    }
  }

  List<Track> _radioCandidates(Iterable<Track> rows, Set<String> avoidKeys) {
    final seen = <String>{...avoidKeys};
    return rows
        .where((track) => track.id.isNotEmpty && track.title.isNotEmpty)
        .where((track) => seen.add(track.key))
        .toList();
  }

  Future<GuessYouLikePayload> _request({
    required int offset,
    Set<String> exclude = const {},
    String platform = 'all',
  }) {
    final query = <String>[
      'limit=24',
      'offset=$offset',
      if (platform != 'all' && platform.isNotEmpty)
        'platform=${Uri.encodeQueryComponent(platform)}',
      if (exclude.isNotEmpty)
        'exclude=${Uri.encodeQueryComponent((exclude.toList()..sort()).join(','))}',
    ].join('&');
    return session.api.getJson(
      '/api/guess-you-like?$query',
      GuessYouLikePayload.fromJson,
    );
  }

  List<Track> _fresh(
    Iterable<Track> rows,
    Set<String> excluded, {
    String? platform,
  }) {
    final seen = {...excluded};
    return rows
        .where((track) => track.id.isNotEmpty && track.title.isNotEmpty)
        .where((track) => platform == null || track.platform == platform)
        .where((track) => !_playedAvailable || _playedKeys.contains(track.key))
        .where((track) => seen.add(track.key))
        .toList();
  }

  void _applyFirst(GuessYouLikePayload page) {
    final fresh = _fresh(page.tracks, const {});
    tracks = fresh;
    sources = page.sources;
    total = page.total;
    generatedAt = page.generatedAt;
    nextOffset = page.nextOffset ?? page.tracks.length;
    hasMore = page.hasMore && nextOffset > 0;
  }

  void _advance(GuessYouLikePayload page, int offset) {
    nextOffset = page.nextOffset ?? offset + page.tracks.length;
    hasMore = page.hasMore && nextOffset > offset;
    generatedAt = page.generatedAt ?? generatedAt;
  }

  void _notify() {
    if (_active) notifyListeners();
  }

  @override
  void dispose() {
    _active = false;
    super.dispose();
  }
}
