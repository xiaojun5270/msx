import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../local/local_store.dart';
import '../models/models.dart';
import '../theme/route.dart';
import '../theme/theme.dart';

/// Transient UI state — mirrors Swift `UIStore`.
class UIStore extends ChangeNotifier {
  String toast = '';
  bool queueOpen = false;
  bool sourceOpen = false;
  Track? sourceTrack;
  bool organizationOpen = false;
  List<Track> organizationTracks = [];
  bool pickerOpen = false;
  Track? pickerTrack;

  AppRoute? pendingRoute;
  AppRoute? _recentRoute;
  Timer? _recentRouteTimer;
  Timer? _toastTimer;

  AppearanceMode appearance = AppearanceMode.system;
  ThemeAccent themeAccent = ThemeAccent.coral;
  String backgroundImageUrls = '';
  String? backgroundImageUrl;
  int _backgroundIndex = -1;

  void notify(String text) {
    toast = text;
    _toastTimer?.cancel();
    notifyListeners();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      toast = '';
      notifyListeners();
    });
  }

  void openQueue() {
    queueOpen = true;
    notifyListeners();
  }

  void openSource(Track track) {
    sourceTrack = track;
    sourceOpen = true;
    notifyListeners();
  }

  void openPicker(Track track) {
    pickerTrack = track;
    pickerOpen = true;
    notifyListeners();
  }

  void openOrganization(List<Track> tracks) {
    organizationTracks = tracks;
    organizationOpen = true;
    notifyListeners();
  }

  /// Coalesce duplicate navigation intents — mirrors Swift `open(_:)`.
  void open(AppRoute route) {
    if (pendingRoute == route || _recentRoute == route) return;
    pendingRoute = route;
    _recentRoute = route;
    _recentRouteTimer?.cancel();
    _recentRouteTimer = Timer(const Duration(milliseconds: 350), () {
      _recentRoute = null;
    });
    notifyListeners();
  }

  void consumePendingRoute() {
    pendingRoute = null;
  }

  void closeSheets() {
    queueOpen = false;
    sourceOpen = false;
    organizationOpen = false;
    pickerOpen = false;
    notifyListeners();
  }

  void loadAppearance(LocalStore local) {
    appearance = local.appearance;
    themeAccent = local.themeAccent;
    backgroundImageUrls = local.prefs.backgroundImageUrls;
    shuffleBackground(notify: false);
  }

  void setAppearance(AppearanceMode mode, LocalStore local) {
    appearance = mode;
    local.setAppearance(mode);
    notifyListeners();
  }

  void setThemeAccent(ThemeAccent accent, LocalStore local) {
    themeAccent = accent;
    local.setThemeAccent(accent);
    notifyListeners();
  }

  bool setBackgroundImageUrls(String raw, LocalStore local) {
    final urls = _parseBackgroundUrls(raw);
    if (raw.trim().isNotEmpty && urls.isEmpty) return false;
    backgroundImageUrls = urls.join('\n');
    local.setBackgroundImageUrls(backgroundImageUrls);
    _backgroundIndex = -1;
    shuffleBackground(notify: false);
    notifyListeners();
    return true;
  }

  void shuffleBackground({bool notify = true}) {
    final urls = _parseBackgroundUrls(backgroundImageUrls);
    if (urls.isEmpty) {
      backgroundImageUrl = null;
      _backgroundIndex = -1;
    } else {
      var next = Random().nextInt(urls.length);
      if (urls.length > 1 && next == _backgroundIndex) {
        next = (next + 1) % urls.length;
      }
      _backgroundIndex = next;
      final uri = Uri.parse(urls[next]);
      backgroundImageUrl = uri
          .replace(fragment: 'mx-${DateTime.now().microsecondsSinceEpoch}')
          .toString();
    }
    if (notify) notifyListeners();
  }

  List<String> _parseBackgroundUrls(String raw) {
    final seen = <String>{};
    final urls = <String>[];
    for (final item in raw.split(RegExp(r'[\r\n]+'))) {
      final value = item.trim();
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
        continue;
      }
      if (seen.add(value)) urls.add(value);
    }
    return urls;
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _recentRouteTimer?.cancel();
    super.dispose();
  }
}
