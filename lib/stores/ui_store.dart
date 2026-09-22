import 'dart:async';
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

  @override
  void dispose() {
    _toastTimer?.cancel();
    _recentRouteTimer?.cancel();
    super.dispose();
  }
}
