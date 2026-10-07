import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture guard for spec §21: the app already owns one audio session, and
/// the equalizer/audio-effects layer must never create a second one.
///
/// The rule is about *source code*, not runtime behaviour — a second session
/// would be created by some `AudioSession`/`AudioFocus` handle appearing in a
/// widget, a controller or the effects service — so it is enforced by reading
/// the sources.
void main() {
  group('audio session ownership (spec §21)', () {
    /// Every Dart source under `lib/`, excluding the generated drift file.
    List<File> sourcesInLib() {
      final lib = Directory('lib');
      expect(lib.existsSync(), isTrue, reason: 'run from the project root');
      return lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('.g.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
    }

    String read(File file) => file.readAsStringSync();

    test('exactly one place configures the audio session', () {
      final configuring = <String>[];
      for (final file in sourcesInLib()) {
        if (read(file).contains('AudioSession.instance')) {
          configuring.add(file.path.replaceAll('\\', '/'));
        }
      }

      expect(
        configuring,
        <String>['lib/player/audio_handler.dart'],
        reason: 'the one audio session must be configured in the one handler',
      );
    });

    test('the effects screens and controller create no session of their own', () {
      const effectsLayer = <String>[
        'lib/controllers/audio_effects_controller.dart',
        'lib/screens/player/equalizer_screen.dart',
        'lib/screens/player/audio_effects_screen.dart',
        'lib/services/audio_effects/',
        'lib/services/audio/audio_player_service.dart',
      ];

      for (final file in sourcesInLib()) {
        final path = file.path.replaceAll('\\', '/');
        final inEffectsLayer = effectsLayer.any(
          (prefix) => path == prefix || path.startsWith(prefix),
        );
        if (!inEffectsLayer) continue;

        final source = read(file);
        expect(
          source.contains('AudioSession'),
          isFalse,
          reason: '$path must use the existing player/session, not its own',
        );
        // A second player is the same mistake in a different form.
        expect(
          source.contains('ja.AudioPlayer(') ||
              source.contains('AudioPlayer(audioPipeline'),
          isFalse,
          reason: '$path must not construct an audio player',
        );
      }
    });

    test('the effects service only receives the player session id stream', () {
      final source = read(File('lib/services/audio_effects/audio_effects_service.dart'));

      // The single source of the session id is the player's own stream, and the
      // native effects are attached to exactly that id.
      expect(source.contains('bindSessionIdStream'), isTrue);
      expect(source.contains('AudioSession'), isFalse);
    });

    test('the one player is still the notification player (spec §1/§19)', () {
      final handler = read(File('lib/player/audio_handler.dart'));

      // Exactly one player, created once, with the effects pipeline inside it.
      expect('AudioPlayer('.allMatches(handler).length, 1);
      expect(handler.contains('audioPipeline: audioEffects?.audioPipeline'), isTrue);
      // The effects layer rides the same session, it does not open another.
      expect(handler.contains('bindSessionIdStream'), isTrue);
    });
  });

  /// The preamp is the one effect that was moved off just_audio's
  /// `AudioPipeline`: `AndroidLoudnessEnhancer` is silently inaudible, so it is
  /// driven from `MainActivity` against the player's own session id instead. That
  /// relocation is only correct while it stays attached to that one session, so
  /// it is pinned here the same way the single-session rule is.
  group('the preamp rides the one audio session', () {
    List<File> sourcesInLib() {
      return Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('.g.dart'))
          .toList();
    }

    String read(File file) => file.readAsStringSync();

    test('just_audio no longer carries a loudness enhancer', () {
      final backend = read(File('lib/services/audio_effects/audio_effects_backend.dart'));

      // The pipeline is equalizer-only; the preamp is applied natively. The
      // trailing paren is what makes this a construction rather than the prose
      // that explains *why* the enhancer was dropped, so the assertion survives
      // the documentation being updated.
      expect(backend.contains('AndroidLoudnessEnhancer('), isFalse);
      expect(backend.contains('AndroidEqualizer'), isTrue);
    });

    test('the effects layer never configures a session or opens a player', () {
      const effectsLayer = <String>[
        'lib/controllers/audio_effects_controller.dart',
        'lib/screens/player/equalizer_screen.dart',
        'lib/screens/player/audio_effects_screen.dart',
        'lib/services/audio_effects/',
      ];

      for (final file in sourcesInLib()) {
        final path = file.path.replaceAll('\\', '/');
        if (!effectsLayer.any(
          (prefix) => path == prefix || path.startsWith(prefix),
        )) {
          continue;
        }
        expect(
          read(file).contains('AudioSession'),
          isFalse,
          reason: '$path must not configure a session',
        );
      }
    });

    test('the native side binds all three effects to the reported session id',
        () {
      final activity = read(File(
        'android/app/src/main/kotlin/com/example/test_app/MainActivity.kt',
      ));

      // The preamp rides the same channel and the same session id as the two
      // effects that were already working — no second session, no second player.
      expect(activity.contains('LoudnessEnhancer'), isTrue);
      expect(activity.contains('BassBoost'), isTrue);
      expect(activity.contains('Virtualizer'), isTrue);
      // It must not acquire or configure a session of its own. Matched on the
      // calls rather than the bare type name, because the doc comment legitimately
      // mentions just_audio's `androidAudioSessionIdStream`.
      expect(activity.contains('AudioSession.instance'), isFalse);
      expect(activity.contains('AudioSessionConfiguration'), isFalse);
      // The target gain is written before the effect is engaged: an `AudioEffect`
      // that is created but never enabled is permanently bypassed.
      final gainIndex = activity.indexOf('setTargetGain');
      final enabledIndex = activity.indexOf('setEnabled(enabled)');
      expect(gainIndex, isNonNegative);
      expect(enabledIndex, greaterThan(gainIndex));
    });
  });
}
