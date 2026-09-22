import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import 'session_store.dart';

/// Search mode — mirrors Swift `SpotlightSearchState.Mode`.
enum SearchMode { suggestions, platform, share }

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

/// The Spotlight-style search state machine. Mirrors Swift
/// `SpotlightSearchState`: debounced local search, an inline platform preview,
/// target discovery, a share-link resolver, and paged remote results — all
/// gated on the request identity staying current.
class SearchStore extends ChangeNotifier {
  SearchStore({required this.session, String? activityKey})
      : _activityKey = activityKey {
    if (activityKey != null) {
      final raw = session.local.pageRaw(activityKey);
      if (raw != null) {
        try {
          _activity = SearchActivity.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {}
      }
    }
  }

  final SessionStore session;
  final String? _activityKey;
  static const _pageSize = 40;
  static final _urlPattern = RegExp(r'https?://\S+', caseSensitive: false);

  String query = '';
  SearchMode mode = SearchMode.suggestions;
  SearchResult? localResult;
  SearchResult? remoteResult;
  List<SearchTarget> targets = [];
  bool localLoading = false;
  bool remoteLoading = false;
  bool targetsLoading = false;
  String? localError;
  String? remoteError;
  String? targetsError;
  SearchActivity _activity = SearchActivity();
  SearchResult? preview;
  SearchTarget? previewTarget;
  bool previewLoading = false;
  SearchTarget? platformTarget;

  int _revision = 0;
  int _previewRevision = 0;
  int _targetsRevision = 0;
  int? _nextOffset;
  bool _active = true;
  Timer? _debounce;
  Timer? _previewTimer;

  SearchActivity get activity => _activity;
  String get trimmedQuery => query.trim();
  bool get isShareLink => _urlPattern.hasMatch(trimmedQuery);
  bool get canLoadMore =>
      _active && _nextOffset != null && !remoteLoading && mode == SearchMode.platform &&
      !targetsLoading && targetsError == null && platformTarget != null && targets.contains(platformTarget);

  List<SearchTarget> get _ordered {
    final recent = _activity.recentTargetIds
        .map((id) => targets.where((t) => t.id == id).firstOrNull)
        .whereType<SearchTarget>()
        .toList();
    final recentIds = recent.map((t) => t.id).toSet();
    return [...recent, ...targets.where((t) => !recentIds.contains(t.id))];
  }

  List<SearchTarget> get suggestedTargets => _ordered.take(3).toList();
  List<SearchTarget> get remainingTargets => _ordered.skip(3).toList();
  SearchTarget? get defaultTarget => _ordered.firstOrNull;

  void _saveActivity() {
    if (_activityKey == null) return;
    session.local.savePageRaw(_activityKey, jsonEncode(_activity.toJson()));
  }

  // ---- Public actions --------------------------------------------------------

  void resume() {
    _active = true;
    loadTargets();
    if (mode != SearchMode.suggestions || trimmedQuery.isEmpty) return;
    if (localResult == null && localError == null) {
      retryLocal();
    } else if (preview == null) {
      _schedulePreview();
    }
  }

  void edit(String text) {
    if (text == query) return;
    query = text;
    mode = SearchMode.suggestions;
    _invalidate(clearLocal: true);
    _startLocal(delayed: true);
    notifyListeners();
  }

  void submitDefault() {
    if (isShareLink) {
      resolveShare();
      return;
    }
    final t = defaultTarget;
    if (t != null) {
      selectTarget(t);
      return;
    }
    _recordAction();
    if (mode == SearchMode.suggestions && localResult == null) retryLocal();
  }

  void openHistory(String text) {
    edit(text);
    _recordAction();
  }

  void removeHistory(String text) {
    if (!_active) return;
    _activity.remove(text);
    _saveActivity();
    notifyListeners();
  }

  void retryLocal() {
    mode = SearchMode.suggestions;
    _invalidate(clearLocal: true);
    _startLocal(delayed: false);
    notifyListeners();
  }

  void loadTargets() {
    if (!_active) return;
    _targetsRevision++;
    final ticket = _targetsRevision;
    targetsLoading = true;
    targetsError = null;
    notifyListeners();
    () async {
      try {
        final raw = await session.api.getRawBody('/api/search/targets');
        if (!_acceptTargets(ticket)) return;
        final snap = APIClient.decodeCached(raw, SearchTargetSnapshot.fromJson);
        final seen = <String>{};
        targets = (snap?.targets ?? [])
            .where((t) => t.isAvailable && seen.add(t.id))
            .toList();
        if (mode == SearchMode.platform && !targets.contains(platformTarget)) {
          backToSuggestions();
          remoteError = '该搜索目标已不可用，请选择其他平台。';
        }
        if (mode == SearchMode.suggestions && preview == null && trimmedQuery.isNotEmpty) {
          _schedulePreview();
        }
      } catch (e) {
        if (!_acceptTargets(ticket)) return;
        targets = [];
        if (mode == SearchMode.platform) _cancelSearch();
        targetsError = '$e';
      }
      targetsLoading = false;
      notifyListeners();
    }();
  }

  void selectTarget(SearchTarget target) {
    if (targetsLoading || targetsError != null) return;
    _invalidate(clearLocal: false);
    if (!_active || trimmedQuery.isEmpty) {
      notifyListeners();
      return;
    }
    if (!target.isAvailable || !targets.contains(target)) {
      mode = SearchMode.suggestions;
      remoteError = '该搜索目标已不可用，请刷新平台列表。';
      notifyListeners();
      return;
    }
    mode = SearchMode.platform;
    platformTarget = target;
    _recordAction(targetId: target.id);
    _startRemote(offset: 0);
    notifyListeners();
  }

  void resolveShare() {
    _invalidate(clearLocal: false);
    if (!_active || trimmedQuery.isEmpty) {
      notifyListeners();
      return;
    }
    mode = SearchMode.share;
    _recordAction();
    _startRemote(offset: 0);
    notifyListeners();
  }

  void retryRemote() {
    switch (mode) {
      case SearchMode.suggestions:
        return;
      case SearchMode.platform:
        if (platformTarget != null) selectTarget(platformTarget!);
        return;
      case SearchMode.share:
        resolveShare();
        return;
    }
  }

  void loadMore() {
    if (!canLoadMore || _nextOffset == null) return;
    _startRemote(offset: _nextOffset!);
  }

  void backToSuggestions() {
    mode = SearchMode.suggestions;
    platformTarget = null;
    _invalidate(clearLocal: false);
    if (localResult == null) {
      _startLocal(delayed: false);
    } else {
      _schedulePreview();
    }
    notifyListeners();
  }

  void leave() {
    _active = false;
    _cancelSearch();
    _cancelPreview();
    _targetsRevision++;
    targetsLoading = false;
  }

  void recordActionExternal({String? targetId}) => _recordAction(targetId: targetId);

  // ---- Internal --------------------------------------------------------------

  void _recordAction({String? targetId}) {
    if (!_active || trimmedQuery.isEmpty) return;
    _activity.record(query, targetId: targetId);
    _saveActivity();
  }

  void _cancelSearch() {
    _debounce?.cancel();
    _revision++;
    localLoading = false;
    remoteLoading = false;
  }

  void _cancelPreview() {
    _previewTimer?.cancel();
    _previewRevision++;
    previewLoading = false;
  }

  void _invalidate({required bool clearLocal}) {
    _cancelSearch();
    _cancelPreview();
    preview = null;
    previewTarget = null;
    localError = null;
    remoteError = null;
    remoteResult = null;
    _nextOffset = null;
    if (clearLocal) localResult = null;
  }

  bool _accept(int ticket) => _active && _revision == ticket;
  bool _acceptPreview(int ticket) => _active && _previewRevision == ticket;
  bool _acceptTargets(int ticket) => _active && _targetsRevision == ticket;

  void _startLocal({required bool delayed}) {
    if (!_active || trimmedQuery.isEmpty) return;
    final ticket = _revision;
    final path = _path('/api/search/local', {'q': trimmedQuery, 'limit': '12', 'offset': '0'});
    localLoading = true;
    _debounce?.cancel();
    void run() async {
      try {
        if (!_accept(ticket)) return;
        final raw = await session.api.getRawBody(path);
        if (!_accept(ticket)) return;
        final result = APIClient.decodeCached(raw, SearchResult.fromJson);
        localError = result?.errorMessage;
        localResult = result?.errorMessage == null ? result : null;
      } catch (e) {
        if (!_accept(ticket)) return;
        localError = '$e';
      }
      localLoading = false;
      notifyListeners();
      _schedulePreview();
    }

    if (delayed) {
      _debounce = Timer(const Duration(milliseconds: 200), run);
    } else {
      run();
    }
  }

  void _schedulePreview() {
    _cancelPreview();
    if (!_active || mode != SearchMode.suggestions || trimmedQuery.isEmpty || isShareLink) return;
    final ticket = _previewRevision;
    _previewTimer = Timer(const Duration(milliseconds: 300), () => _runPreview(ticket));
  }

  void _runPreview(int ticket) async {
    if (!_acceptPreview(ticket) || mode != SearchMode.suggestions) return;
    final target = defaultTarget;
    if (target == null) return;
    final path = _path('/api/search/platform',
        {'q': trimmedQuery, 'target': target.id, 'types': 'track', 'limit': '3', 'offset': '0'});
    previewLoading = true;
    notifyListeners();
    try {
      final raw = await session.api.getRawBody(path);
      previewLoading = false;
      if (!_acceptPreview(ticket) || mode != SearchMode.suggestions) return;
      final result = APIClient.decodeCached(raw, SearchResult.fromJson);
      if (result?.errorMessage == null && (result?.tracks ?? []).isNotEmpty) {
        preview = result;
        previewTarget = target;
      } else {
        preview = null;
        previewTarget = null;
      }
    } catch (_) {
      previewLoading = false;
      if (!_acceptPreview(ticket)) return;
      preview = null;
      previewTarget = null;
    }
    notifyListeners();
  }

  void _startRemote({required int offset}) {
    if (!_active || trimmedQuery.isEmpty) return;
    final String path;
    switch (mode) {
      case SearchMode.suggestions:
        return;
      case SearchMode.platform:
        final target = platformTarget;
        if (target == null || !targets.contains(target) || !target.isAvailable) return;
        path = _path('/api/search/platform', {
          'q': trimmedQuery,
          'target': target.id,
          'types': 'track,playlist,album,artist',
          'limit': '$_pageSize',
          'offset': '$offset',
        });
        break;
      case SearchMode.share:
        path = _path('/api/search/share', {'q': trimmedQuery});
        break;
    }
    final ticket = _revision;
    remoteLoading = true;
    remoteError = null;
    notifyListeners();
    () async {
      try {
        if (!_accept(ticket)) return;
        final raw = await session.api.getRawBody(path);
        if (!_accept(ticket)) return;
        final page = APIClient.decodeCached(raw, SearchResult.fromJson);
        remoteError = page?.errorMessage;
        if (remoteError != null && (page?.isEmpty ?? true)) {
          remoteLoading = false;
          notifyListeners();
          return;
        }
        SearchResult? merged = page;
        if (offset > 0 && remoteResult != null && page != null) {
          merged = _mergePage(remoteResult!, page);
        }
        remoteResult = merged;
        if (mode == SearchMode.platform && page?.hasMore == true) {
          final candidate = page?.nextOffset ?? offset + _pageSize;
          _nextOffset = candidate > offset ? candidate : null;
        } else {
          _nextOffset = null;
        }
      } catch (e) {
        if (!_accept(ticket)) return;
        remoteError = '$e';
      }
      remoteLoading = false;
      notifyListeners();
    }();
  }

  static SearchResult _mergePage(SearchResult prev, SearchResult page) {
    List<T> merge<T>(List<T>? a, List<T>? b, String Function(T) key) {
      final seen = <String>{};
      return <T>[...(a ?? <T>[]), ...(b ?? <T>[])]
          .where((e) => seen.add(key(e)))
          .toList();
    }

    return SearchResult(
      rawQuery: page.rawQuery,
      intent: page.intent,
      parsed: page.parsed,
      sections: page.sections,
      tracks: merge(prev.tracks, page.tracks, (t) => t.key),
      playlists: merge(prev.playlists, page.playlists,
          (p) => '${p.platform ?? 'local'}::${p.listKind ?? ''}::${p.id}'),
      albums: merge(prev.albums, page.albums, (a) => '${a.platform}::${a.id}'),
      artists: merge(prev.artists, page.artists, (a) => '${a.platform}::${a.id}'),
      offset: page.offset,
      limit: page.limit,
      hasMore: page.hasMore,
      nextOffset: page.nextOffset,
      errors: page.errors,
    );
  }

  static String _path(String endpoint, Map<String, String> query) {
    final sorted = query.keys.toList()..sort();
    final qs = sorted
        .map((k) => '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(query[k]!).replaceAll('+', '%2B')}')
        .join('&');
    return qs.isEmpty ? endpoint : '$endpoint?$qs';
  }

  @override
  void dispose() {
    leave();
    super.dispose();
  }
}
