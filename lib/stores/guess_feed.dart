import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'session_store.dart';

/// Session-backed recommendation feed shared by the home card and callers
/// that need the full "猜你喜欢" list. The home shelf endpoint is only a
/// display fallback; recommendation paging always uses `/api/guess-you-like`.
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

  GuessFeed(this.session);

  List<Track> filtered(String platform) => platform == 'all'
      ? List.unmodifiable(tracks)
      : tracks.where((track) => track.platform == platform).toList();

  List<String> get platforms => {
        ...sources.map((source) => source.platform),
        ...tracks.map((track) => track.platform),
      }.where((platform) => platform.isNotEmpty).toList()
        ..sort();

  Future<bool> loadFirst() async {
    if (loading || swapping || tracks.isNotEmpty) return tracks.isNotEmpty;
    loading = true;
    error = null;
    notice = null;
    _notify();
    try {
      final page = await _request(offset: 0);
      _applyFirst(page);
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
    loadingMore = true;
    error = null;
    _notify();
    final offset = nextOffset;
    try {
      final page = await _request(offset: offset, exclude: _keys);
      final fresh = _fresh(page.tracks, _keys);
      tracks = [...tracks, ...fresh];
      _advance(page, offset, fresh.isNotEmpty);
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

  void _advance(GuessYouLikePayload page, int offset, bool added) {
    nextOffset = page.nextOffset ?? offset + page.tracks.length;
    hasMore = page.hasMore && nextOffset > offset && added;
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
