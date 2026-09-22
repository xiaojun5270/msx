import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'local/local_store.dart';
import 'stores/audio_handler.dart';
import 'stores/player_store.dart';
import 'stores/session_store.dart';
import 'stores/ui_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Persistence must be ready before any store reads it.
  final local = await LocalStore.open();

  // Configure the platform audio session for music playback (focus handling,
  // ducking, interruption). Mirrors the Swift `AVAudioSession` setup.
  final audioSession = await AudioSession.instance;
  await audioSession.configure(const AudioSessionConfiguration.music());

  final session = SessionStore(local: local);
  final ui = UIStore()..loadAppearance(local);
  final player = PlayerStore();

  // Bind the player to its dependencies, then hand it to the OS media session.
  player.bind(session: session, ui: ui);
  await AudioService.init(
    builder: () => MusixAudioHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'app.altman.musix.playback',
      androidNotificationChannelName: '正在播放',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

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
