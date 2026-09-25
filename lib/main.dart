import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'local/app_log.dart';
import 'local/local_store.dart';
import 'stores/audio_handler.dart';
import 'stores/player_store.dart';
import 'stores/session_store.dart';
import 'stores/ui_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(() {
    debugPaintBaselinesEnabled = false;
    WidgetsBinding.instance.addPersistentFrameCallback((_) {
      if (!debugPaintBaselinesEnabled) return;
      debugPaintBaselinesEnabled = false;
      late RenderObjectVisitor repaint;
      repaint = (renderObject) {
        renderObject.markNeedsPaint();
        renderObject.visitChildren(repaint);
      };
      for (final renderView in RendererBinding.instance.renderViews) {
        renderView.visitChildren(repaint);
      }
      WidgetsBinding.instance.scheduleFrame();
    });
    return true;
  }());
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Persistence must be ready before any store reads it.
  final local = await LocalStore.open();
  final logs = LocalLogStore.shared;
  await logs.init();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logs.error(
      AppLogCategory.app,
      'flutter.error',
      fields: {
        'error': details.exceptionAsString(),
        if (details.library != null) 'library': details.library!,
      },
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logs.error(
      AppLogCategory.app,
      'platform.error',
      fields: {'error': error.toString()},
    );
    return false;
  };
  logs.info(AppLogCategory.app, 'app.started');

  // Configure the platform audio session for music playback (focus handling,
  // ducking, interruption). Mirrors the Swift `AVAudioSession` setup.
  final audioSession = await AudioSession.instance;
  await audioSession.configure(const AudioSessionConfiguration.music());

  final session = SessionStore(local: local);
  final ui = UIStore()..loadAppearance(local);
  final player = PlayerStore();

  // Bind the player to its dependencies, then hand it to the OS media session.
  player.bind(session: session, ui: ui);
  session.onSigningOut = player.clearForSignOut;
  try {
    await AudioService.init(
      builder: () => MusixAudioHandler(player),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.altman.musix.playback',
        androidNotificationChannelName: '正在播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (error, stackTrace) {
    logs.error(
      AppLogCategory.player,
      'audio_service.init_failed',
      fields: {'error': error.toString()},
    );
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'audio_service',
      context: ErrorDescription('while initializing Android media controls'),
    ));
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<LocalStore>.value(value: local),
        ChangeNotifierProvider<SessionStore>.value(value: session),
        ChangeNotifierProvider<UIStore>.value(value: ui),
        ChangeNotifierProvider<PlayerStore>.value(value: player),
      ],
      child: const MusixApp(),
    ),
  );
}
