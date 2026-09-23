import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../stores/player_store.dart';
import '../stores/session_store.dart';
import '../stores/ui_store.dart';
import '../theme/glass.dart';
import '../theme/route.dart';
import '../theme/theme.dart';
import 'account_view.dart';
import 'home_view.dart';
import 'library_view.dart';
import 'mini_player.dart';
import 'now_playing_view.dart';
import 'placeholders.dart';
import 'route_page.dart';
import 'search_view.dart';
import 'sheets.dart';
import 'source_organization_view.dart';

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
    nav?.push(MaterialPageRoute(
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
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (context) {
          MXBrightness.value = Theme.of(context).brightness;
          return _rootFor(tab);
        },
        settings: settings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UIStore>();
    final player = context.watch<PlayerStore>();

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

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: false,
          body: IndexedStack(
            index: _order.indexOf(_tab),
            children: [for (final t in _order) _tabNavigator(t)],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (player.track != null) const MiniPlayer(),
              _TabBar(current: _tab, order: _order, onSelect: _selectTab),
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
    );
  }

  bool _organizationShown = false;
  void _syncOrganization(UIStore ui) {
    if (ui.organizationOpen && !_organizationShown) {
      _organizationShown = true;
      final tracks = List<Track>.from(ui.organizationTracks);
      Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute(
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

/// Custom glass tab bar — the "自定义高保真玻璃质感" requirement means we do not
/// use Material's `NavigationBar` chrome.
class _TabBar extends StatelessWidget {
  final AppTab current;
  final List<AppTab> order;
  final ValueChanged<AppTab> onSelect;
  const _TabBar(
      {required this.current, required this.order, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding:
          EdgeInsets.fromLTRB(14, 0, 14, bottomInset > 0 ? bottomInset : 8),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(32),
        blur: 42,
        tint: dark
            ? const Color.fromRGBO(255, 255, 255, 0.06)
            : const Color.fromRGBO(255, 255, 255, 0.28),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        showBorder: false,
        showHighlight: false,
        showShadow: false,
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final tab in order) _item(tab, dark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(AppTab tab, bool dark) {
    final active = tab == current;
    final color = active ? MX.fg : MX.mute.withOpacity(0.76);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: active
                ? MX.fg.withOpacity(dark ? 0.10 : 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(27),
            border: Border.all(
              color: active ? MX.fg.withOpacity(0.12) : Colors.transparent,
              width: 0.6,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_tabIcon(tab, active), size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                tab.title,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: active ? 18 : 0,
                height: 1.5,
                decoration: BoxDecoration(
                  color: MX.ember,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
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
