import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/auth_box.dart';
import '../local/local_store.dart';
import '../models/models.dart';

/// Connection + authentication state — mirrors Swift `SessionStore`.
class SessionStore extends ChangeNotifier {
  final LocalStore local;
  late final APIClient api;

  String _baseURL;
  String _proxyCookie;
  bool ready = false;
  bool authed = false;
  String? accountId;
  bool setupRequired = false;
  String role = 'guest';
  String nickname = 'Musix';
  String? avatarUrl;
  String? headerThumb;
  Map<String, BindingSummary> bindings = {};
  String? notice;

  SessionStore({required this.local})
      : _baseURL = APIClient.normalize(local.prefs.baseURL),
        _proxyCookie = local.prefs.proxyCookie {
    api = APIClient(baseURL: _baseURL);
    api.updateProxyCookie(local.prefs.proxyCookie);
    AuthBox.shared.set(proxyCookie: local.prefs.proxyCookie);
    api.onTokenChange = _handleSessionTokenChange;
    _restore();
  }

  String get baseURL => _baseURL;
  set baseURL(String value) {
    final changed = APIClient.normalize(_baseURL) != APIClient.normalize(value);
    _baseURL = value;
    if (changed) accountId = null;
    local.setBaseURL(value);
    api.updateBaseURL(value);
    notifyListeners();
  }

  String get proxyCookie => _proxyCookie;
  set proxyCookie(String value) {
    _proxyCookie = value;
    local.setProxyCookie(value);
    api.updateProxyCookie(value);
    notifyListeners();
  }

  void _restore() {
    final token = local.prefs.sessionToken;
    api.setToken(token);
    if (token.isEmpty || !local.prefs.authedCached) return;
    authed = true;
    role = local.prefs.role;
    bindings = local.loadBindings();
    ready = true;
  }

  void apply(Me me) {
    authed = me.authed ?? false;
    accountId = authed ? me.accountId : null;
    setupRequired = me.setupRequired ?? false;
    role = me.role ?? 'guest';
    nickname = me.nickname ?? 'Musix';
    avatarUrl = me.avatarUrl;
    headerThumb = me.headerThumb;
    bindings = me.bindings ?? {};
    if (authed) {
      local.setSession(token: AuthBox.shared.snapshot().token, me: me);
    } else {
      api.clearToken();
      local.setSession(token: '', me: me);
    }
    notifyListeners();
  }

  Future<void> bootstrap() async {
    try {
      final me = await api.getJson('/api/me', Me.fromJson);
      apply(me);
    } catch (e) {
      if ((e is ApiError && e.status == 401) || !authed) {
        _clearAuthenticationPreservingConnection();
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> login({required String password}) async {
    api.updateBaseURL(_baseURL);
    final path = setupRequired ? '/api/auth/setup' : '/api/auth/login';
    final me = await api.postJson(path, Me.fromJson, json: {'password': password});
    apply(me);
  }

  Future<void> refreshBindings() async {
    try {
      final box = await api.getJson('/api/me/bindings', BindingsBox.fromJson);
      bindings = box.bindings ?? bindings;
      local.setSession(
        token: AuthBox.shared.snapshot().token,
        me: Me(setupRequired: setupRequired, authed: authed, role: role, bindings: bindings),
      );
      notifyListeners();
    } catch (_) {}
  }

  /// Local-only logout — mirrors Swift `logout()`.
  Future<void> logout() async {
    api.clearToken();
    local.setSession(token: '', me: null);
    authed = false;
    accountId = null;
    role = 'guest';
    nickname = 'Musix';
    avatarUrl = null;
    headerThumb = null;
    bindings = {};
    notifyListeners();
  }

  /// Cache-first page fetch — mirrors Swift `fetchPage`.
  Future<T?> fetchPage<T>(String path, {required String cacheKey, required T Function(Map<String, dynamic>) factory}) async {
    try {
      final body = await api.getRawBody(path);
      final value = APIClient.decodeCached(body, factory);
      local.savePageRaw(cacheKey, body);
      return value ?? peekPage(cacheKey, factory);
    } catch (_) {
      return local.decodePage(cacheKey, factory);
    }
  }

  T? peekPage<T>(String key, T Function(Map<String, dynamic>) factory) =>
      local.decodePage(key, factory);

  void _handleSessionTokenChange(String token) {
    if (AuthBox.shared.snapshot().token != token) return;
    if (local.prefs.sessionToken == token) return;
    local.setSession(token: token, me: null);
  }

  void _clearAuthenticationPreservingConnection() {
    api.clearToken();
    local.setSession(token: '', me: null);
    authed = false;
    accountId = null;
    role = 'guest';
    nickname = 'Musix';
    avatarUrl = null;
    headerThumb = null;
    bindings = {};
  }
}
