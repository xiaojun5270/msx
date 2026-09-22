import 'json.dart';

/// Mirrors Swift `Me`.
class Me {
  final bool? setupRequired;
  final bool? authed;
  final String? accountId;
  final String? role;
  final String? nickname;
  final String? avatarUrl;
  final String? headerThumb;
  final String? platform;
  final Map<String, BindingSummary>? bindings;

  const Me({
    this.setupRequired,
    this.authed,
    this.accountId,
    this.role,
    this.nickname,
    this.avatarUrl,
    this.headerThumb,
    this.platform,
    this.bindings,
  });

  factory Me.fromJson(Map<String, dynamic> c) => Me(
        setupRequired: asBool(c['setupRequired']),
        authed: asBool(c['authed']),
        accountId: asString(c['accountId']),
        role: asString(c['role']),
        nickname: asString(c['nickname']),
        avatarUrl: asString(c['avatarUrl']),
        headerThumb: asString(c['headerThumb']),
        platform: asString(c['platform']),
        bindings: _bindings(c['bindings']),
      );

  static Map<String, BindingSummary>? _bindings(dynamic v) {
    final m = asMap(v);
    if (m == null) return null;
    return m.map((k, val) =>
        MapEntry(k, BindingSummary.fromJson(asMap(val) ?? {})));
  }

  Map<String, dynamic> toJson() => {
        if (setupRequired != null) 'setupRequired': setupRequired,
        if (authed != null) 'authed': authed,
        if (accountId != null) 'accountId': accountId,
        if (role != null) 'role': role,
        if (nickname != null) 'nickname': nickname,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (headerThumb != null) 'headerThumb': headerThumb,
        if (bindings != null)
          'bindings': bindings!.map((k, v) => MapEntry(k, v.toJson())),
      };
}

class BindingProfile {
  final String? nickname;
  final String? avatarUrl;
  final String? headerThumb;
  const BindingProfile({this.nickname, this.avatarUrl, this.headerThumb});
  factory BindingProfile.fromJson(Map<String, dynamic> c) => BindingProfile(
        nickname: asString(c['nickname']),
        avatarUrl: asString(c['avatarUrl']),
        headerThumb: asString(c['headerThumb']),
      );
  Map<String, dynamic> toJson() => {
        if (nickname != null) 'nickname': nickname,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (headerThumb != null) 'headerThumb': headerThumb,
      };
}

class BindingSummary {
  final bool? bound;
  final bool? configured;
  final String? nickname;
  final String? username;
  final String? avatarUrl;
  final String? headerThumb;
  final String? error;
  final BindingProfile? profile;

  const BindingSummary({
    this.bound,
    this.configured,
    this.nickname,
    this.username,
    this.avatarUrl,
    this.headerThumb,
    this.error,
    this.profile,
  });

  String get displayName =>
      profile?.nickname ?? nickname ?? username ?? '已绑定';
  String? get avatar => profile?.avatarUrl ?? avatarUrl;
  String? get header => profile?.headerThumb ?? headerThumb ?? avatar;

  factory BindingSummary.fromJson(Map<String, dynamic> c) => BindingSummary(
        bound: asBool(c['bound']),
        configured: asBool(c['configured']),
        nickname: asString(c['nickname']),
        username: asString(c['username']),
        avatarUrl: asString(c['avatarUrl']),
        headerThumb: asString(c['headerThumb']),
        error: asString(c['error']),
        profile: asMap(c['profile']) != null
            ? BindingProfile.fromJson(asMap(c['profile'])!)
            : null,
      );

  Map<String, dynamic> toJson() => {
        if (bound != null) 'bound': bound,
        if (configured != null) 'configured': configured,
        if (nickname != null) 'nickname': nickname,
        if (username != null) 'username': username,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (headerThumb != null) 'headerThumb': headerThumb,
        if (error != null) 'error': error,
        if (profile != null) 'profile': profile!.toJson(),
      };
}

class BindingsBox {
  final Map<String, BindingSummary>? bindings;
  const BindingsBox({this.bindings});
  factory BindingsBox.fromJson(Map<String, dynamic> c) =>
      BindingsBox(bindings: Me._bindings(c['bindings']));
}

/// Mirrors Swift `FavToggle`.
class FavToggle {
  final bool? favorited;
  final bool? has;
  const FavToggle({this.favorited, this.has});
  factory FavToggle.fromJson(Map<String, dynamic> c) =>
      FavToggle(favorited: asBool(c['favorited']), has: asBool(c['has']));
}

/// Mirrors Swift `LyricsBox` / `LyricLine`.
class LyricsBox {
  final List<LyricLine>? lines;
  final String? source;
  const LyricsBox({this.lines, this.source});
  factory LyricsBox.fromJson(Map<String, dynamic> c) => LyricsBox(
        lines: c['lines'] is List ? decodeList(c['lines'], LyricLine.fromJson) : null,
        source: asString(c['source']),
      );
}

class LyricLine {
  final double? timeMs;
  final String? text;
  const LyricLine({this.timeMs, this.text});
  factory LyricLine.fromJson(Map<String, dynamic> c) =>
      LyricLine(timeMs: asDouble(c['timeMs']), text: asString(c['text']));
}
