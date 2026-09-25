import 'package:home_widget/home_widget.dart';

/// Home-screen widget bridge — mirrors Swift `WidgetBridge`.
/// Writes the current playback snapshot into the shared widget store and asks
/// the OS to refresh the AppWidget. The Android widget layout + provider are
/// wired in task #12; this keeps a single call surface the player can use now.
class WidgetBridge {
  static const _appGroup = 'group.app.altman.musix';
  static const _androidWidget = 'NowPlayingWidgetProvider';

  static bool _configured = false;

  static void _ensureConfigured() {
    if (_configured) return;
    _configured = true;
    HomeWidget.setAppGroupId(_appGroup);
  }

  /// Persist the current playback state and (optionally) reload the widget.
  static Future<void> savePlayback(PlaybackSnapshot snap, {bool reload = true}) async {
    _ensureConfigured();
    try {
      await HomeWidget.saveWidgetData<String>('np_title', snap.title);
      await HomeWidget.saveWidgetData<String>('np_artist', snap.artist);
      await HomeWidget.saveWidgetData<String>('np_album', snap.album ?? '');
      await HomeWidget.saveWidgetData<String>('np_cover', snap.coverUrl ?? '');
      await HomeWidget.saveWidgetData<bool>('np_playing', snap.playing);
      await HomeWidget.saveWidgetData<bool>('np_favorited', snap.favorited);
      await HomeWidget.saveWidgetData<int>('np_elapsed', (snap.elapsed * 1000).round());
      await HomeWidget.saveWidgetData<int>('np_duration', (snap.duration * 1000).round());
      await HomeWidget.saveWidgetData<int>('np_updated', snap.updatedAt.millisecondsSinceEpoch);
      if (reload) {
        await HomeWidget.updateWidget(androidName: _androidWidget);
      }
    } catch (_) {
      // Widgets are best-effort; never let a widget failure break playback.
    }
  }

  static Future<void> clearPlayback() async {
    _ensureConfigured();
    try {
      await HomeWidget.saveWidgetData<String>('np_title', '');
      await HomeWidget.saveWidgetData<bool>('np_playing', false);
      await HomeWidget.updateWidget(androidName: _androidWidget);
    } catch (_) {}
  }
}

/// Mirrors Swift `WidgetBridge.PlaybackSnapshot`.
class PlaybackSnapshot {
  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final bool playing;
  final bool favorited;
  final double elapsed;
  final double duration;
  final DateTime updatedAt;

  const PlaybackSnapshot({
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    required this.playing,
    required this.favorited,
    required this.elapsed,
    required this.duration,
    required this.updatedAt,
  });
}
