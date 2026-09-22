/// Global auth snapshot shared by API + image loader + audio stream loader.
/// Mirrors Swift `AuthBox` (a process-wide singleton). Dart is single-threaded
/// per isolate so no lock is required.
class AuthBox {
  AuthBox._();
  static final AuthBox shared = AuthBox._();

  String _token = '';
  String _base = '';
  String _proxyCookie = '';

  ({String base, String token}) snapshot() => (base: _base, token: _token);

  String proxyCookieValue() => _proxyCookie;

  void set({String? base, String? token, String? proxyCookie}) {
    if (base != null) _base = base;
    if (token != null) _token = token;
    if (proxyCookie != null) _proxyCookie = proxyCookie;
  }

  /// The session cookie header value, or null when signed out.
  String? cookieHeader() => _token.isEmpty ? null : 'musix_session=$_token';

  /// Combined session + proxy cookie for arbitrary requests (images/streams).
  String? combinedCookieHeader() {
    final parts = <String>[];
    final session = cookieHeader();
    if (session != null) parts.add(session);
    if (_proxyCookie.isNotEmpty) parts.add(_proxyCookie);
    return parts.isEmpty ? null : parts.join('; ');
  }
}
