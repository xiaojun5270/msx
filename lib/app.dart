import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'stores/player_store.dart';
import 'stores/session_store.dart';
import 'stores/ui_store.dart';
import 'theme/glass.dart';
import 'theme/theme.dart';
import 'views/deep_link.dart';
import 'views/login_view.dart';
import 'views/shell.dart';

/// Root widget. Resolves the active [Brightness] into [MXBrightness] (which the
/// `MX` color tokens read) and hosts the app shell. Mirrors Swift `RootView`.
class MusixApp extends StatefulWidget {
  const MusixApp({super.key});

  @override
  State<MusixApp> createState() => _MusixAppState();
}

class _MusixAppState extends State<MusixApp> with WidgetsBindingObserver {
  late Brightness _platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  @override
  void didChangePlatformBrightness() {
    final next = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (next != _platformBrightness) setState(() => _platformBrightness = next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.watch<UIStore>();
    MXBrightness.value = switch (ui.appearance) {
      AppearanceMode.light => Brightness.light,
      AppearanceMode.dark => Brightness.dark,
      AppearanceMode.system => _platformBrightness,
    };
    return MaterialApp(
      title: 'Musix',
      debugShowCheckedModeBanner: false,
      themeMode: ui.appearance.themeMode,
      themeAnimationDuration: Duration.zero,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      builder: (context, child) {
        return AppBackdrop(
          imageUrl: ui.backgroundImageUrl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _RootGate(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: ThemeAccent.current.color,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

/// Routes between the loading, login, and shell states based on session
/// readiness/auth. Mirrors the `Group` in Swift `RootView.body`. Also runs the
/// initial `/api/me` bootstrap and subscribes to `musicx://` deep links.
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionStore>().bootstrap();
    });
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _handleLink(initial);
    _linkSub = _appLinks.uriLinkStream.listen(_handleLink);
  }

  void _handleLink(Uri uri) {
    if (!mounted) return;
    DeepLink.open(
      uri,
      player: context.read<PlayerStore>(),
      ui: context.read<UIStore>(),
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    MXBrightness.value = Theme.of(context).brightness;
    final session = context.watch<SessionStore>();
    if (!session.ready) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(strokeWidth: 2.4, color: MX.ember),
        ),
      );
    }
    if (!session.authed) {
      return LoginView();
    }
    return MobileShell();
  }
}
