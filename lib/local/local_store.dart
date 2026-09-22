import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../theme/theme.dart';

/// Preference bag — mirrors Swift SwiftData `AppPrefs`.
class AppPrefs {
  String baseURL;
  String proxyCookie;
  String sessionToken;
  String role;
  bool authedCached;
  String? bindingsJSON;
  bool shuffle;
  int repeatMode;
  String lastTab;
  String? queueJSON;
  int queueIndex;
  String appearanceMode;
  String themeAccent;

  AppPrefs({
    this.baseURL = 'http://127.0.0.1:8080',
    this.proxyCookie = '',
    this.sessionToken = '',
    this.role = 'guest',
    this.authedCached = false,
    this.bindingsJSON,
    this.shuffle = false,
    this.repeatMode = 0,
    this.lastTab = 'home',
    this.queueJSON,
    this.queueIndex = -1,
    this.appearanceMode = 'system',
    this.themeAccent = 'coral',
  });
}

/// Local persistence — mirrors Swift `LocalStore`.
/// SwiftData @Model rows become key-value entries + JSON blobs in
/// shared_preferences. Home/Search/Page caches use prefixed keys with an LRU
/// timestamp side-index so pruning matches the original behavior.
class LocalStore {
  final SharedPreferences _sp;
  late final AppPrefs prefs;

  static const _kBaseURL = 'baseURL';
  static const _kProxyCookie = 'proxyCookie';
  static const _kToken = 'sessionToken';
  static const _kRole = 'role';
  static const _kAuthed = 'authedCached';
  static const _kBindings = 'bindingsJSON';
  static const _kShuffle = 'shuffle';
  static const _kRepeat = 'repeatMode';
  static const _kLastTab = 'lastTab';
  static const _kQueue = 'queueJSON';
  static const _kQueueIndex = 'queueIndex';
  static const _kAppearance = 'appearanceMode';
  static const _kAccent = 'themeAccent';
  static const _kSearchTerms = 'searchTerms'; // JSON list of {text, ts}

  static const _homePrefix = 'home:';
  static const _searchPrefix = 'search:';
  static const _pagePrefix = 'page:';

  LocalStore._(this._sp) {
    prefs = AppPrefs(
      baseURL: APIClient.normalize(_sp.getString(_kBaseURL) ?? 'http://127.0.0.1:8080'),
      proxyCookie: _sp.getString(_kProxyCookie) ?? '',
      sessionToken: _sp.getString(_kToken) ?? '',
      role: _sp.getString(_kRole) ?? 'guest',
      authedCached: _sp.getBool(_kAuthed) ?? false,
      bindingsJSON: _sp.getString(_kBindings),
      shuffle: _sp.getBool(_kShuffle) ?? false,
      repeatMode: _sp.getInt(_kRepeat) ?? 0,
      lastTab: _sp.getString(_kLastTab) ?? 'home',
      queueJSON: _sp.getString(_kQueue),
      queueIndex: _sp.getInt(_kQueueIndex) ?? -1,
      appearanceMode: _sp.getString(_kAppearance) ?? 'system',
      themeAccent: _sp.getString(_kAccent) ?? 'coral',
    );
    ThemeAccent.current = themeAccent;
  }

  static Future<LocalStore> open() async {
    final sp = await SharedPreferences.getInstance();
    return LocalStore._(sp);
  }

  // Connection ----------------------------------------------------------------

  void setBaseURL(String url) {
    prefs.baseURL = APIClient.normalize(url);
    _sp.setString(_kBaseURL, prefs.baseURL);
  }

  void setProxyCookie(String raw) {
    prefs.proxyCookie = raw.trim();
    _sp.setString(_kProxyCookie, prefs.proxyCookie);
  }

  // Session -------------------------------------------------------------------

  void setSession({required String token, Me? me}) {
    prefs.sessionToken = token;
    _sp.setString(_kToken, token);
    if (me != null) {
      prefs.authedCached = me.authed ?? false;
      prefs.role = me.role ?? 'guest';
      _sp.setBool(_kAuthed, prefs.authedCached);
      _sp.setString(_kRole, prefs.role);
      if (me.bindings != null) {
        prefs.bindingsJSON = jsonEncode(me.bindings!.map((k, v) => MapEntry(k, v.toJson())));
        _sp.setString(_kBindings, prefs.bindingsJSON!);
      }
      if (me.authed != true) {
        prefs.sessionToken = '';
        _sp.setString(_kToken, '');
      }
    } else if (token.isEmpty) {
      prefs.authedCached = false;
      prefs.role = 'guest';
      prefs.bindingsJSON = null;
      _sp.setBool(_kAuthed, false);
      _sp.setString(_kRole, 'guest');
      _sp.remove(_kBindings);
    }
  }

  Map<String, BindingSummary> loadBindings() {
    final data = prefs.bindingsJSON;
    if (data == null) return {};
    try {
      final raw = jsonDecode(data);
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), BindingSummary.fromJson((v as Map).cast<String, dynamic>())));
      }
    } catch (_) {}
    return {};
  }

  void setTab(AppTab tab) {
    prefs.lastTab = tab.name;
    _sp.setString(_kLastTab, tab.name);
  }

  // Appearance ----------------------------------------------------------------

  AppearanceMode get appearance => AppearanceMode.fromRaw(prefs.appearanceMode);

  void setAppearance(AppearanceMode mode) {
    prefs.appearanceMode = mode.name;
    _sp.setString(_kAppearance, mode.name);
  }

  ThemeAccent get themeAccent => ThemeAccent.fromRaw(prefs.themeAccent);

  void setThemeAccent(ThemeAccent accent) {
    prefs.themeAccent = accent.name;
    ThemeAccent.current = accent;
    _sp.setString(_kAccent, accent.name);
  }

  // Player queue --------------------------------------------------------------

  void setPlayer({required List<Track> queue, required int index, required bool shuffle, required int repeatMode}) {
    prefs.queueJSON = jsonEncode(queue.map((t) => t.payload()).toList());
    prefs.queueIndex = index;
    prefs.shuffle = shuffle;
    prefs.repeatMode = repeatMode;
    _sp.setString(_kQueue, prefs.queueJSON!);
    _sp.setInt(_kQueueIndex, index);
    _sp.setBool(_kShuffle, shuffle);
    _sp.setInt(_kRepeat, repeatMode);
  }

  ({List<Track> tracks, int index}) loadQueue() {
    final data = prefs.queueJSON;
    if (data == null) return (tracks: <Track>[], index: -1);
    try {
      final raw = jsonDecode(data);
      final tracks = decodeList(raw, Track.fromJson);
      final i = tracks.isEmpty ? -1 : prefs.queueIndex.clamp(0, tracks.length - 1);
      return (tracks: tracks, index: i);
    } catch (_) {
      return (tracks: <Track>[], index: -1);
    }
  }

  // Search history ------------------------------------------------------------

  void pushSearch(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    final terms = _searchTerms();
    terms.removeWhere((t) => t['text'] == text);
    terms.insert(0, {'text': text, 'ts': DateTime.now().millisecondsSinceEpoch});
    if (terms.length > 20) terms.removeRange(20, terms.length);
    _sp.setString(_kSearchTerms, jsonEncode(terms));
  }

  void removeSearch(String text) {
    final terms = _searchTerms()..removeWhere((t) => t['text'] == text);
    _sp.setString(_kSearchTerms, jsonEncode(terms));
  }

  List<String> loadSearchTerms({int limit = 30}) {
    final terms = _searchTerms();
    return terms.take(limit.clamp(1, 50)).map((t) => t['text'] as String).toList();
  }

  List<Map<String, dynamic>> _searchTerms() {
    final raw = _sp.getString(_kSearchTerms);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is List) return list.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {}
    return [];
  }

  // Generic caches (home / search / page) with LRU pruning ---------------------

  void _saveCache(String prefix, String key, String rawBody, int keep) {
    final full = '$prefix$key';
    _sp.setString(full, rawBody);
    final indexKey = '${prefix}__index';
    final index = (_sp.getStringList(indexKey) ?? [])..remove(key);
    index.insert(0, key);
    if (index.length > keep) {
      for (final stale in index.sublist(keep)) {
        _sp.remove('$prefix$stale');
      }
      index.removeRange(keep, index.length);
    }
    _sp.setStringList(indexKey, index);
  }

  String? _readCache(String prefix, String key) => _sp.getString('$prefix$key');

  void saveHomeRaw(String shelfId, String rawBody) => _saveCache(_homePrefix, shelfId, rawBody, 40);
  String? homeRaw(String shelfId) => _readCache(_homePrefix, shelfId);

  void saveSearchRaw(String key, String rawBody) => _saveCache(_searchPrefix, key, rawBody, 40);
  SearchResult? searchResult(String key) {
    final body = _readCache(_searchPrefix, key);
    if (body == null) return null;
    return APIClient.decodeCached(body, SearchResult.fromJson);
  }

  void savePageRaw(String key, String rawBody) => _saveCache(_pagePrefix, key, rawBody, 120);
  String? pageRaw(String key) => _readCache(_pagePrefix, key);
  T? decodePage<T>(String key, T Function(Map<String, dynamic>) factory) {
    final body = _readCache(_pagePrefix, key);
    if (body == null) return null;
    return APIClient.decodeCached(body, factory);
  }
}
