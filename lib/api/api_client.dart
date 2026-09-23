import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../local/app_log.dart';
import '../models/models.dart';
import 'auth_box.dart';

/// HTTP client for the Musix Hub REST API.
/// Mirrors Swift `APIClient`: session token via AuthBox, cookie injection on
/// every request, `{result:{status,data,error}}` envelope unwrapping.
class APIClient {
  String _baseURL;
  String proxyCookie = '';
  void Function(String token)? onTokenChange;
  final http.Client _http = http.Client();

  APIClient({required String baseURL}) : _baseURL = normalize(baseURL) {
    AuthBox.shared.set(base: _baseURL);
  }

  String get baseURL => _baseURL;
  set baseURL(String value) {
    _baseURL = normalize(value);
    AuthBox.shared.set(base: _baseURL);
  }

  void updateBaseURL(String raw) => baseURL = raw;

  void updateProxyCookie(String raw) {
    final trimmed = raw.trim();
    proxyCookie = trimmed;
    AuthBox.shared.set(proxyCookie: trimmed);
  }

  void setToken(String token) {
    final prev = AuthBox.shared.snapshot().token;
    AuthBox.shared.set(token: token);
    if (token != prev) onTokenChange?.call(token);
  }

  void clearToken() {
    final prev = AuthBox.shared.snapshot().token;
    AuthBox.shared.set(token: '');
    if (prev.isNotEmpty) onTokenChange?.call('');
  }

  static String normalize(String raw) {
    var s = raw.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isNotEmpty && !s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    return s;
  }

  Uri url(String path) {
    final root = normalize(_baseURL);
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse(root + p);
  }

  /// Resolve a possibly-relative resource path into an absolute URL.
  /// Mirrors Swift `absolute` incl. the music.126.net https upgrade.
  Uri? absolute(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.tryParse(_secureExternalURL(path));
    }
    return url(path);
  }

  static String _secureExternalURL(String raw) {
    if (!raw.startsWith('http://')) return raw;
    final u = Uri.tryParse(raw);
    final host = u?.host;
    if (host == null) return raw;
    if (host == 'music.126.net' || host.endsWith('.music.126.net')) {
      return 'https://${raw.substring('http://'.length)}';
    }
    return raw;
  }

  String? cookieHeader() => AuthBox.shared.cookieHeader();

  String? combinedCookieHeader() => AuthBox.shared.combinedCookieHeader();

  // Typed helpers -------------------------------------------------------------

  Future<T> getJson<T>(
      String path, T Function(Map<String, dynamic>) factory) async {
    final data = unwrapEnvelope(await _rawJson('GET', path));
    return factory(_expectMap(data));
  }

  /// GET returning the raw unwrapped `data` (may be a list or scalar).
  Future<dynamic> getData(String path) async =>
      unwrapEnvelope(await _rawJson('GET', path));

  Future<T> postJson<T>(String path, T Function(Map<String, dynamic>) factory,
      {Object? json}) async {
    final data = unwrapEnvelope(await _rawJson('POST', path, json: json));
    return factory(_expectMap(data));
  }

  Future<T> putJson<T>(String path, T Function(Map<String, dynamic>) factory,
      {Object? json}) async {
    final data = unwrapEnvelope(await _rawJson('PUT', path, json: json));
    return factory(_expectMap(data));
  }

  Future<T> deleteJson<T>(String path, T Function(Map<String, dynamic>) factory,
      {Object? json}) async {
    final data = unwrapEnvelope(await _rawJson('DELETE', path, json: json));
    return factory(_expectMap(data));
  }

  /// Void POST/PUT/DELETE — throws if the envelope reports an error.
  Future<void> post(String path, {Object? json}) =>
      _sendVoid('POST', path, json: json);
  Future<void> put(String path, {Object? json}) =>
      _sendVoid('PUT', path, json: json);
  Future<void> delete(String path) => _sendVoid('DELETE', path);

  /// GET returning the decoded `data` list mapped with a factory.
  Future<List<T>> getList<T>(
      String path, T Function(Map<String, dynamic>) factory) async {
    final data = unwrapEnvelope(await _rawJson('GET', path));
    return decodeList(data, factory);
  }

  Future<List<T>> postList<T>(
      String path, T Function(Map<String, dynamic>) factory,
      {Object? json}) async {
    final data = unwrapEnvelope(await _rawJson('POST', path, json: json));
    return decodeList(data, factory);
  }

  /// Raw envelope JSON bytes for cache storage — mirrors `getData`.
  Future<String> getRawBody(String path) async {
    final resp = await _request('GET', path);
    return resp.body;
  }

  /// Decode a cached raw body into a typed value.
  static T? decodeCached<T>(
      String body, T Function(Map<String, dynamic>) factory) {
    try {
      final data = unwrapEnvelope(jsonDecode(body));
      if (data is Map) return factory(data.cast<String, dynamic>());
    } catch (_) {}
    return null;
  }

  Future<T> upload<T>(
    String path, {
    required List<int> data,
    required String filename,
    required String mimeType,
    String fieldName = 'file',
    required T Function(Map<String, dynamic>) factory,
  }) async {
    final target = url(path);
    final req = http.MultipartRequest('POST', target);
    final cookie = combinedCookieHeader();
    if (cookie != null) req.headers['Cookie'] = cookie;
    req.files.add(http.MultipartFile.fromBytes(
      fieldName,
      data,
      filename: filename,
      contentType: _parseMedia(mimeType),
    ));
    http.StreamedResponse streamed;
    try {
      streamed = await _http.send(req);
    } catch (e) {
      throw _networkError(e, target);
    }
    final body = await streamed.stream.bytesToString();
    _ingest(streamed.headers);
    final status = streamed.statusCode;
    if (status == 401) {
      clearToken();
      throw const ApiError('未登录', status: 401);
    }
    if (status != 0 && (status < 200 || status >= 300)) {
      throw _httpError(body, status);
    }
    final decoded = unwrapEnvelope(jsonDecode(body));
    return factory(_expectMap(decoded));
  }

  // Internals -----------------------------------------------------------------

  Map<String, dynamic> _expectMap(dynamic data) {
    if (data is Map) return data.cast<String, dynamic>();
    throw const ApiError('空响应');
  }

  Future<dynamic> _rawJson(String method, String path, {Object? json}) async {
    final resp = await _request(method, path, json: json);
    return jsonDecode(resp.body);
  }

  Future<void> _sendVoid(String method, String path, {Object? json}) async {
    final resp = await _request(method, path, json: json);
    if (resp.body.isEmpty) return;
    try {
      final root = jsonDecode(resp.body);
      if (root is Map &&
          root['result'] is Map &&
          root['result']['status'] == 'error') {
        final err = root['result']['error'];
        throw ApiError(
            (err is Map ? err['message'] : null) as String? ?? '请求失败');
      }
    } on FormatException {
      // Non-JSON empty success body — ignore.
    }
  }

  Future<http.Response> _request(String method, String path,
      {Object? json}) async {
    final target = url(path);
    final started = Stopwatch()..start();
    final headers = <String, String>{};
    final cookie = combinedCookieHeader();
    if (cookie != null) headers['Cookie'] = cookie;
    Object? body;
    if (json != null) {
      headers['Content-Type'] = 'application/json';
      body = jsonEncode(json);
    }
    http.Response resp;
    try {
      final req = http.Request(method, target)..headers.addAll(headers);
      if (body is String) req.body = body;
      final streamed =
          await _http.send(req).timeout(const Duration(seconds: 30));
      resp = await http.Response.fromStream(streamed);
    } catch (e) {
      final error = _networkError(e, target);
      LocalLogStore.shared.error(
        AppLogCategory.network,
        'request.failed',
        fields: {
          'method': method,
          'path': target.path,
          'error': error.message,
          'elapsedMs': '${started.elapsedMilliseconds}',
        },
      );
      throw error;
    }
    _ingest(resp.headers);
    final status = resp.statusCode;
    if (status == 401) {
      LocalLogStore.shared.warn(
        AppLogCategory.auth,
        'request.unauthorized',
        fields: {'method': method, 'path': target.path},
      );
      clearToken();
      throw const ApiError('未登录', status: 401);
    }
    if (status != 0 && (status < 200 || status >= 300)) {
      final error = _httpError(resp.body, status);
      LocalLogStore.shared.warn(
        AppLogCategory.network,
        'request.http_error',
        fields: {
          'method': method,
          'path': target.path,
          'status': '$status',
          'error': error.message,
        },
      );
      throw error;
    }
    if (started.elapsedMilliseconds >= 2500) {
      LocalLogStore.shared.info(
        AppLogCategory.network,
        'request.slow',
        fields: {
          'method': method,
          'path': target.path,
          'elapsedMs': '${started.elapsedMilliseconds}',
        },
      );
    }
    return resp;
  }

  static ApiError _httpError(String body, int status) {
    try {
      final root = jsonDecode(body);
      if (root is Map &&
          root['result'] is Map &&
          root['result']['status'] == 'error') {
        final err = root['result']['error'];
        final msg = (err is Map ? err['message'] : null) as String?;
        return ApiError(msg ?? '请求失败 (HTTP $status)', status: status);
      }
    } catch (_) {}
    final text = body.trim();
    if (text.isNotEmpty) {
      final snippet = text.length > 160 ? text.substring(0, 160) : text;
      return ApiError('请求失败 (HTTP $status)：$snippet', status: status);
    }
    return ApiError('请求失败 (HTTP $status)', status: status);
  }

  ApiError _networkError(Object error, Uri url) {
    final host = url.host.isEmpty ? url.toString() : url.host;
    final msg = error.toString().toLowerCase();
    if (msg.contains('failed host lookup') || msg.contains('nodename')) {
      return ApiError('找不到服务器域名：$host。请检查域名 DNS 解析，或临时改用服务器 IP 地址。', status: 0);
    }
    if (msg.contains('connection refused') || msg.contains('errno = 111')) {
      return ApiError('无法连接服务器：$host。请检查端口、防火墙和服务是否已启动。', status: 0);
    }
    if (msg.contains('timeout') ||
        error is Exception && msg.contains('timed out')) {
      return ApiError('连接服务器超时：$host。请检查网络或服务器状态。', status: 0);
    }
    if (msg.contains('network is unreachable') || msg.contains('no address')) {
      return const ApiError('网络连接不可用，请检查 Wi-Fi 或蜂窝网络。', status: 0);
    }
    return ApiError(error.toString(), status: 0);
  }

  /// Extract a fresh `musix_session` from Set-Cookie and store it.
  void _ingest(Map<String, String> headers) {
    final raw = headers['set-cookie'];
    if (raw == null) return;
    final token = _parseSession(raw);
    if (token != null) setToken(token);
  }

  static String? _parseSession(String header) {
    final marker = 'musix_session=';
    final idx = header.indexOf(marker);
    if (idx < 0) return null;
    final rest = header.substring(idx + marker.length);
    final buf = StringBuffer();
    for (final ch in rest.split('')) {
      if (ch == ';' || ch == ',') break;
      buf.write(ch);
    }
    final token = buf.toString().trim();
    return token.isEmpty ? null : token;
  }

  static MediaType _parseMedia(String mime) {
    final slash = mime.indexOf('/');
    if (slash < 0) return MediaType('application', 'octet-stream');
    return MediaType(mime.substring(0, slash), mime.substring(slash + 1));
  }
}
