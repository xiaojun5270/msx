import 'package:flutter/material.dart';

/// Global brightness, updated by the root widget from the appearance setting.
/// Mirrors how SwiftUI dynamic `Color(light:dark:)` auto-resolves per trait.
class MXBrightness {
  static Brightness value = Brightness.dark;
  static bool get isDark => value == Brightness.dark;
}

Color _dyn(Color light, Color dark) => MXBrightness.isDark ? dark : light;

/// Appearance mode — mirrors Swift `AppearanceMode`.
enum AppearanceMode {
  system,
  light,
  dark;

  String get id => name;

  String get title {
    switch (this) {
      case AppearanceMode.system:
        return '跟随系统';
      case AppearanceMode.light:
        return '浅色';
      case AppearanceMode.dark:
        return '深色';
    }
  }

  ThemeMode get themeMode {
    switch (this) {
      case AppearanceMode.system:
        return ThemeMode.system;
      case AppearanceMode.light:
        return ThemeMode.light;
      case AppearanceMode.dark:
        return ThemeMode.dark;
    }
  }

  static AppearanceMode fromRaw(String? raw) => AppearanceMode.values
      .firstWhere((m) => m.name == raw, orElse: () => AppearanceMode.system);
}

/// Accent theme — mirrors Swift `ThemeAccent`.
enum ThemeAccent {
  coral,
  ocean,
  violet,
  forest,
  amber,
  rose;

  String get id => name;

  String get title {
    switch (this) {
      case ThemeAccent.coral:
        return '音乐珊瑚';
      case ThemeAccent.ocean:
        return '海岸蓝';
      case ThemeAccent.violet:
        return '暮光紫';
      case ThemeAccent.forest:
        return '森林绿';
      case ThemeAccent.amber:
        return '琥珀金';
      case ThemeAccent.rose:
        return '玫瑰红';
    }
  }

  Color get color {
    switch (this) {
      case ThemeAccent.coral:
        return const Color.fromRGBO(232, 92, 102, 1); // 0.91,0.36,0.40
      case ThemeAccent.ocean:
        return const Color.fromRGBO(46, 120, 199, 1); // 0.18,0.47,0.78
      case ThemeAccent.violet:
        return const Color.fromRGBO(115, 87, 199, 1); // 0.45,0.34,0.78
      case ThemeAccent.forest:
        return const Color.fromRGBO(43, 133, 97, 1); // 0.17,0.52,0.38
      case ThemeAccent.amber:
        return const Color.fromRGBO(204, 122, 26, 1); // 0.80,0.48,0.10
      case ThemeAccent.rose:
        return const Color.fromRGBO(186, 64, 112, 1); // 0.73,0.25,0.44
    }
  }

  Color get deepColor {
    switch (this) {
      case ThemeAccent.coral:
        return const Color.fromRGBO(148, 41, 61, 1);
      case ThemeAccent.ocean:
        return const Color.fromRGBO(20, 64, 130, 1);
      case ThemeAccent.violet:
        return const Color.fromRGBO(64, 38, 130, 1);
      case ThemeAccent.forest:
        return const Color.fromRGBO(13, 79, 56, 1);
      case ThemeAccent.amber:
        return const Color.fromRGBO(128, 64, 10, 1);
      case ThemeAccent.rose:
        return const Color.fromRGBO(112, 23, 61, 1);
    }
  }

  static ThemeAccent current = ThemeAccent.coral;

  static ThemeAccent fromRaw(String? raw) => ThemeAccent.values
      .firstWhere((a) => a.name == raw, orElse: () => ThemeAccent.coral);
}

/// Design tokens — mirrors Swift `enum MX`.
class MX {
  MX._();

  // Light follows iOS semantic system colors; dark is the Koel ink palette.
  static Color get ink =>
      _dyn(const Color(0xFFFFFFFF), const Color.fromRGBO(12, 10, 14, 1));
  static Color get panel => _dyn(const Color.fromRGBO(255, 255, 255, 0.72),
      const Color.fromRGBO(30, 26, 33, 0.68));
  static Color get line =>
      _dyn(Colors.black.withOpacity(0.10), Colors.white.withOpacity(0.12));
  static Color get mute =>
      _dyn(const Color(0xFF5E5962), const Color(0xFFC8BBB5));

  /// Semantic accent — reads the saved theme so legacy controls track the tint.
  static Color get ember => ThemeAccent.current.color;
  static Color get emberDeep => ThemeAccent.current.deepColor;
  static Color get onAccent =>
      ThemeData.estimateBrightnessForColor(ember) == Brightness.dark
          ? Colors.white
          : const Color(0xFF17151A);

  static Color get fg => _dyn(const Color(0xFF17151A), const Color(0xFFFFF7F3));
  static Color get fill =>
      _dyn(Colors.black.withOpacity(0.05), Colors.white.withOpacity(0.06));
  static Color get fillSoft =>
      _dyn(Colors.black.withOpacity(0.04), Colors.white.withOpacity(0.04));
  static Color get fillStrong =>
      _dyn(Colors.black.withOpacity(0.08), Colors.white.withOpacity(0.08));
  static Color get hairline =>
      _dyn(Colors.black.withOpacity(0.08), Colors.white.withOpacity(0.10));
  static Color get elev =>
      _dyn(Colors.black.withOpacity(0.1), Colors.white.withOpacity(0.1));
  static Color get dim =>
      _dyn(Colors.black.withOpacity(0.62), Colors.white.withOpacity(0.68));
  static Color get dimSoft =>
      _dyn(Colors.black.withOpacity(0.52), Colors.white.withOpacity(0.56));
  static const Color heroBase = Color.fromRGBO(12, 10, 14, 1);

  static const List<String> platforms = [
    'navidrome',
    'apple',
    'netease',
    'qqmusic',
    'kugou',
    'youtube',
    'source',
    'lx'
  ];

  static String label(String? id) {
    switch (id) {
      case 'navidrome':
        return '本地';
      case 'localfile':
        return '本地文件';
      case 'files':
        return '文件';
      case 'netease':
        return '网易云';
      case 'qqmusic':
        return 'QQ音乐';
      case 'kugou':
        return '酷狗';
      case 'apple':
        return 'Apple Music';
      case 'youtube':
        return 'YouTube';
      case 'source':
        return '独立音源';
      case 'lx':
        return 'LX 自定义';
      case 'catalog':
        return '曲风目录';
      case 'local':
        return '自建';
      default:
        if (id != null && id.startsWith('lx:')) return '自定义音源';
        return id ?? '';
    }
  }

  static String resolvePlatform(String? raw) {
    final text = (raw ?? '').trim().toLowerCase();
    if (text.isEmpty) return '';
    switch (text) {
      case 'navidrome':
      case 'local':
      case '本地':
      case '本地库':
      case 'nd':
        return 'navidrome';
      case 'localfile':
      case 'files':
      case '本地文件':
      case '文件':
        return 'localfile';
      case 'netease':
      case '网易云':
      case '网易':
      case 'wyy':
      case 'ne':
        return 'netease';
      case 'qqmusic':
      case 'qq':
      case 'qq音乐':
      case 'q音':
      case 'qm':
        return 'qqmusic';
      case 'kugou':
      case '酷狗':
      case 'kg':
        return 'kugou';
      case 'apple':
      case 'apple music':
      case 'applemusic':
      case 'am':
      case '苹果':
        return 'apple';
      case 'youtube':
      case 'yt':
      case '油管':
        return 'youtube';
      case 'source':
      case '独立音源':
      case '独立音乐源':
        return 'source';
      case 'lx':
      case 'lxsource':
      case 'lx-source':
      case 'lx 自定义':
      case 'lx自定义':
        return 'lx';
      default:
        return (raw ?? '').trim();
    }
  }

  static const Set<String> _urlSchemes = {
    'http',
    'https',
    'ftp',
    'file',
    'musicx'
  };

  static bool isKnownSearchPlatform(String raw) {
    final token = raw.trim();
    if (token.isEmpty) return false;
    final lower = token.toLowerCase();
    if (_urlSchemes.contains(lower)) return false;
    final resolved = resolvePlatform(token);
    if (platforms.contains(resolved) || resolved == 'localfile') return true;
    return resolved.toLowerCase() != lower;
  }

  static bool isSearchPlatformToken(String raw) {
    final token = raw.trim();
    if (token.isEmpty ||
        token.length > 32 ||
        token.contains('.') ||
        token.contains('/')) {
      return false;
    }
    if (isKnownSearchPlatform(token)) return true;
    final lower = token.toLowerCase();
    if (_urlSchemes.contains(lower)) return false;
    return RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(lower);
  }

  static ({String query, String platform}) parseSearchQuery(String raw,
      {String fallbackPlatform = ''}) {
    final trimmed = raw.trim();
    final fallback = resolvePlatform(fallbackPlatform);
    if (trimmed.isEmpty) return (query: '', platform: fallback);
    if (trimmed.contains('://')) return (query: trimmed, platform: fallback);

    if (trimmed.startsWith('@')) {
      final body = trimmed.substring(1).trim();
      final space = body.indexOf(RegExp(r'\s'));
      if (space > 0) {
        final plat = body.substring(0, space);
        final query = body.substring(space + 1).trim();
        if (isSearchPlatformToken(plat) && query.isNotEmpty) {
          return (query: query, platform: resolvePlatform(plat));
        }
      }
    }

    for (final sep in [':', '：']) {
      final range = trimmed.indexOf(sep);
      if (range >= 0) {
        final plat = trimmed.substring(0, range).trim();
        final query = trimmed.substring(range + sep.length).trim();
        if (isKnownSearchPlatform(plat) && query.isNotEmpty) {
          return (query: query, platform: resolvePlatform(plat));
        }
      }
    }

    return (query: trimmed, platform: fallback);
  }

  static String mark(String? id) {
    final raw = id?.trim() ?? '';
    switch (raw) {
      case 'navidrome':
      case 'localfile':
      case 'files':
        return '本';
      case 'netease':
        return '云';
      case 'qqmusic':
        return 'Q';
      case 'kugou':
        return '酷';
      case 'apple':
        return 'A';
      case 'youtube':
        return 'Y';
      case 'source':
        return '源';
      case 'lx':
        return 'LX';
      case 'local':
        return '自';
      default:
        return raw.isEmpty ? '?' : raw.substring(0, 1).toUpperCase();
    }
  }

  static Color tone(String? id) {
    switch (id) {
      case 'navidrome':
      case 'localfile':
      case 'files':
        return ember;
      case 'netease':
        return const Color.fromRGBO(237, 64, 64, 1);
      case 'qqmusic':
        return const Color.fromRGBO(48, 194, 125, 1);
      case 'kugou':
        return const Color.fromRGBO(31, 156, 255, 1);
      case 'apple':
        return const Color.fromRGBO(250, 46, 71, 1);
      case 'youtube':
        return const Color.fromRGBO(255, 0, 51, 1);
      case 'source':
        return const Color.fromRGBO(89, 140, 242, 1);
      case 'lx':
        return const Color.fromRGBO(166, 89, 230, 1);
      default:
        return mute;
    }
  }

  /// Platform icon — SF Symbols mapped to Material equivalents.
  static IconData icon(String? id) {
    switch (id) {
      case 'navidrome':
        return Icons.storage; // externaldrive.fill
      case 'localfile':
      case 'files':
        return Icons.folder; // folder.fill
      case 'netease':
        return Icons.cloud; // cloud.fill
      case 'qqmusic':
        return Icons.music_note;
      case 'kugou':
        return Icons.music_note_outlined; // music.quarternote.3
      case 'apple':
        return Icons.apple; // apple.logo
      case 'youtube':
        return Icons.play_circle_fill; // play.rectangle.fill
      case 'source':
        return Icons.graphic_eq; // waveform
      case 'lx':
        return Icons.tune; // slider.horizontal.3
      case 'catalog':
        return Icons.grid_view; // square.grid.2x2.fill
      case 'local':
        return Icons.account_circle; // person.crop.circle.fill
      default:
        return Icons.music_note;
    }
  }
}

/// Bottom tab — mirrors Swift `AppTab`.
enum AppTab {
  home,
  library,
  recents,
  profile,
  search;

  String get id => name;

  String get title {
    switch (this) {
      case AppTab.home:
        return '首页';
      case AppTab.library:
        return '资料库';
      case AppTab.recents:
        return '最近播放';
      case AppTab.profile:
        return '我的';
      case AppTab.search:
        return '搜索';
    }
  }

  IconData get icon {
    switch (this) {
      case AppTab.home:
        return Icons.home;
      case AppTab.library:
        return Icons.library_music;
      case AppTab.recents:
        return Icons.access_time_filled;
      case AppTab.profile:
        return Icons.account_circle;
      case AppTab.search:
        return Icons.search;
    }
  }

  static AppTab fromRaw(String? raw) =>
      AppTab.values.firstWhere((t) => t.name == raw, orElse: () => AppTab.home);
}

enum ListKind { mine, platform, chart }

enum LibrarySection { playlists, artists, albums, songs }
