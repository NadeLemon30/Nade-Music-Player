import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database/app_database.dart';
import 'data/repositories/audio_effects_preferences.dart';
import 'data/repositories/music_repository.dart';
import 'controllers/audio_effects_controller.dart';
import 'screens/main_shell_screen.dart';
import 'player/audio_handler.dart';
import 'services/audio_effects/audio_effects_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One database connection for the whole app. Spec §16: the audio-effects
  // settings live in their own single-row table, with no relation to tracks,
  // albums, artists, playlists, history or favorites.
  final database = AppDatabase();

  // Phase 4B: the one audio-effects service is *constructed* before the audio
  // service so its equalizer/preamp pipeline can be baked into the single
  // player, and stored in a global so the Riverpod layer reaches the very same
  // instance the engine uses. There is still exactly one player / handler /
  // audio session (spec §1).
  final audioEffects = AudioEffectsService(
    preferences: AudioEffectsPreferences(database),
  );
  globalAudioEffects = audioEffects;

  // Phase 3G: initialize the background audio service (notification,
  // lock-screen controls, media session) before the UI starts. The returned
  // handler becomes the app-wide [MusicAudioHandler] shared with the OS.
  globalAudioHandler = await AudioService.init(
    builder: () => MusicAudioHandler(audioEffects: audioEffects),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.nade.musicplayer.channel.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationChannelDescription:
          'Shows playback controls on Android.',
      androidNotificationOngoing: true,
    ),
  );

  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(database)],
  );

  // Spec §17 startup order: the audio handler is up, now the audio-effects
  // controller initializes, the saved settings are loaded, the supported effects
  // are detected and the effects are applied. `initialize()` is deliberately
  // **not awaited** — the player must never wait for optional effects, and a
  // failing effect disables itself instead of holding up playback.
  container.read(audioEffectsControllerProvider);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MusicPlayerApp(),
    ),
  );
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Nade's Music Player",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),
      home: const MainShellScreen(),
    );
  }
}
