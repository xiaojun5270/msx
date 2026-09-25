import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_bottom_bar/liquid_glass_bottom_bar.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/glass.dart';
import '../theme/theme.dart';
import 'account_view.dart';
import 'home_view.dart';
import 'library_view.dart';
import 'mini_player.dart';
import 'now_playing_view.dart';
import 'route_page.dart';
import 'search_view.dart';
import 'sheets.dart';
import 'source_organization_view.dart';

PageRoute<T> _instantPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    opaque: true,
    fullscreenDialog: fullscreenDialog,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
  );
}

/// The five-tab mobile shell. Mirrors Swift `MobileShell`: one tab each for
/// 首页 / 资料库 / 最近播放 / 我的 / 搜索, each hosting its own navigation stack,
/// with the mini player + tab bar as persistent bottom chrome and the toast
/// floating on top.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  static const _order = [
    AppTab.home,
    AppTab.library,
    AppTab.recents,
    AppTab.profile,
    AppTab.search
  ];

  final Map<AppTab, GlobalKey<NavigatorState>> _navKeys = {
    for (final t in _order) t: GlobalKey<NavigatorState>(),
  };

  late AppTab _tab;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionStore>();
    _tab = AppTab.fromRaw(session.local.prefs.lastTab);
  }

  void _selectTab(AppTab tab) {
    if (tab == _tab) {
      // Re-tapping the active tab pops to its root — matches iOS behavior.
      _navKeys[tab]?.currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _tab = tab);
    context.read<SessionStore>().local.setTab(tab);
  }

  void _consumePendingRoute(UIStore ui) {
    final route = ui.pendingRoute;
    if (route == null) return;
    ui.consumePendingRoute();
    final nav = _navKeys[_tab]?.currentState;
    nav?.push(_instantPageRoute(
      builder: (_) => RoutePage(route: route),
      settings: RouteSettings(name: route.heroId),
    ));
  }

  Widget _rootFor(AppTab tab) {
    switch (tab) {
      case AppTab.home:
        return HomeView();
      case AppTab.library:
        return LibraryView();
      case AppTab.recents:
        return RecentsView();
      case AppTab.profile:
        return AccountView();
      case AppTab.search:
        return SearchView();
    }
  }

  Widget _tabNavigator(AppTab tab) {
    return Navigator(
      key: _navKeys[tab],
      onGenerateRoute: (settings) => _instantPageRoute(
        builder: (context) {
          MXBrightness.value = Theme.of(context).brightness;
          return _rootFor(tab);
        },
        settings: settings,
      ),
    );
  }

  Future<void> _handleSystemBack() async {
    final nav = _navKeys[_tab]?.currentState;
    if (nav != null && await nav.maybePop()) return;

    if (_tab != AppTab.home) {
      _selectTab(AppTab.home);
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UIStore>();
    final player = context.watch<PlayerStore>();
    final media = MediaQuery.of(context);
    final safeBottom = media.padding.bottom > 8 ? media.padding.bottom : 8.0;
    final navExtent = 74.0 + safeBottom;
    final playerExtent =
        player.track == null ? 0.0 : (ui.playerExpanded ? 169.0 : 88.0);
    final contentBottomInset = navExtent + playerExtent + 16;
    final bodyMedia = media.copyWith(
      padding: media.padding.copyWith(bottom: safeBottom),
    );

    // Route intents raised anywhere (deep links, in-view navigation) are
    // pushed onto the active tab's stack after the frame commits.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _consumePendingRoute(ui));

    // Present / dismiss the full Now Playing surface as a fullscreen route.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _syncNowPlaying(player));

    // Present the source-organization sheet when requested via UIStore.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOrganization(ui));

    // Present the aux bottom sheets (队列 / 换源 / 加入歌单) when requested.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSheets(ui));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            body: Padding(
              padding: EdgeInsets.only(bottom: contentBottomInset),
              child: MediaQuery(
                data: bodyMedia,
                child: IndexedStack(
                  index: _order.indexOf(_tab),
                  children: [for (final t in _order) _tabNavigator(t)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (player.track != null) const MiniPlayer(),
                _LiquidDock(
                    current: _tab, order: _order, onSelect: _selectTab),
              ],
            ),
          ),
          if (ui.toast.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: Center(child: _Toast(text: ui.toast)),
            ),
        ],
      ),
    );
  }

  bool _organizationShown = false;
  void _syncOrganization(UIStore ui) {
    if (ui.organizationOpen && !_organizationShown) {
      _organizationShown = true;
      final tracks = List<Track>.from(ui.organizationTracks);
      Navigator.of(context, rootNavigator: true)
          .push(_instantPageRoute(
        builder: (_) => SourceOrganizationView(tracks: tracks),
        fullscreenDialog: true,
      ))
          .then((_) {
        _organizationShown = false;
        ui.closeSheets();
      });
    }
  }

  bool _queueShown = false;
  bool _sourceShown = false;
  bool _pickerShown = false;
  void _syncSheets(UIStore ui) {
    if (ui.queueOpen && !_queueShown) {
      _queueShown = true;
      showAuxSheet(context, const QueueSheet()).then((_) {
        _queueShown = false;
        ui.closeSheets();
      });
    }
    if (ui.sourceOpen && !_sourceShown) {
      _sourceShown = true;
      showAuxSheet(context, const SourceSheet()).then((_) {
        _sourceShown = false;
        ui.closeSheets();
      });
    }
    if (ui.pickerOpen && !_pickerShown) {
      _pickerShown = true;
      showAuxSheet(context, const PlaylistPickerSheet()).then((_) {
        _pickerShown = false;
        ui.closeSheets();
      });
    }
  }

  bool _nowPlayingShown = false;
  void _syncNowPlaying(PlayerStore player) {
    if (player.nowPlayingOpen && !_nowPlayingShown) {
      _nowPlayingShown = true;
      Navigator.of(context, rootNavigator: true)
          .push(PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => const NowPlayingView(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ))
          .then((_) {
        _nowPlayingShown = false;
        player.setNowPlayingOpen(false);
      });
    } else if (!player.nowPlayingOpen && _nowPlayingShown) {
      _nowPlayingShown = false;
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }
}

class _LiquidDock extends StatelessWidget {
  final AppTab current;
  final List<AppTab> order;
  final ValueChanged<AppTab> onSelect;
  const _LiquidDock(
      {required this.current, required this.order, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 8),
      child: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: LiquidGlassBottomBar(
          items: [
            for (final tab in order)
              LiquidGlassBottomBarItem(
                icon: _tabIcon(tab, false),
                activeIcon: _tabIcon(tab, true),
                label: tab.title,
              ),
          ],
          currentIndex: order.indexOf(current),
          onTap: (index) => onSelect(order[index]),
          height: 74,
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          activeColor: ThemeAccent.current.color,
          barBlurSigma: 20,
          activeBlurSigma: 28,
        ),
      ),
    );
  }

  IconData _tabIcon(AppTab tab, bool active) {
    switch (tab) {
      case AppTab.home:
        return active ? Icons.home_rounded : Icons.home_outlined;
      case AppTab.library:
        return active ? Icons.library_music : Icons.library_music_outlined;
      case AppTab.recents:
        return active ? Icons.access_time_filled : Icons.access_time;
      case AppTab.profile:
        return active ? Icons.account_circle : Icons.account_circle_outlined;
      case AppTab.search:
        return Icons.search;
    }
  }
}

/// Glass capsule toast. Mirrors Swift `ToastChrome`.
class _Toast extends StatelessWidget {
  final String text;
  const _Toast({required this.text});

  @override
  Widget build(BuildContext context) {
    return GlassCapsule(
      child: Text(
        text,
        style:
            TextStyle(color: MX.fg, fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }
}
