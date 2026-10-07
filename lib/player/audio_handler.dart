import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../models/track.dart';
import '../services/audio_effects/audio_effects_service.dart';
import 'player_state.dart';

/// The single app-wide [MusicAudioHandler], assigned during
/// [AudioService.init] in `main()`. Held in a plain global (per audio_service's
/// own guidance) so the app's service facade can reach the same handler instance
/// the OS talks to. Null before main initializes it.
MusicAudioHandler? globalAudioHandler;

/// The single app-wide audio engine + OS integration layer (Phase 3G).
///
/// Owns the one [ja.AudioPlayer] for the whole application (single-player
/// rule) and bridges it to the operating system via `audio_service`: the
/// media notification, lock-screen controls, headset buttons, and the OS
/// media session all call back into this handler.
///
/// The Flutter UI never talks to `just_audio` directly; it drives and reads
/// [MusicAudioHandler] (normally through [AudioPlayerService]). Navigation
/// from the notification/lock-screen/headset ([skipToNext]/[skipToPrevious])
/// is forwarded to the controller via [onNext]/[onPrevious] callbacks.
///
/// Phase 4B: the optional [audioEffects] argument is the app's one
/// [AudioEffectsService] — its pipeline is baked into this player so the
/// equalizer and preamp process the existing output instead of creating a
/// second player.
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  /// The single playback engine.
  ///
  /// Phase 4B: the equalizer/preamp pipeline (spec §1 — effects ride the
  /// existing pipeline, there is never a second player) is handed in by
  /// `main()`; when absent (tests, or a build without the effects service) the
  /// player is built with no effects.
  MusicAudioHandler({AudioEffectsService? audioEffects}) {
    _player = ja.AudioPlayer(audioPipeline: audioEffects?.audioPipeline);
    // The native bass boost / virtualizer are bound to this player's audio
    // session, and must be re-bound whenever just_audio reports a new one.
    audioEffects?.bindSessionIdStream(_player.androidAudioSessionIdStream);
    _playbackSub = _player.playbackEventStream.listen(_broadcastState);
    _completedSub = _player.processingStateStream.listen((state) {
      if (state == ja.ProcessingState.completed) {
        // Broadcast the terminal completed state so the notification's
        // progress track reflects the end.
        _broadcastState(_player.playbackEvent);
      }
    });
    // Configure the OS audio session for music playback. Guarded so that
    // headless/test environments (no platform channels) never crash the
    // handler — OS integration simply stays inert until a real platform.
    _configureSession();
  }

  /// Invoked when the OS requests "next" (notification/lock-screen/headset).
  /// Wired to the player controller so OS navigation shares the app's
  /// shuffle/repeat-aware navigation rules.
  Future<void> Function()? onNext;

  /// Invoked when the OS requests "previous".
  Future<void> Function()? onPrevious;

  /// The single app-wide audio player (created with the Phase 4B effects
  /// pipeline when one is supplied).
  late final ja.AudioPlayer _player;

  late final StreamSubscription<ja.PlaybackEvent> _playbackSub;
  late final StreamSubscription<ja.ProcessingState> _completedSub;

  Future<void> _configureSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // 3G.20: Pause on audio interruptions (phone calls, navigation prompts).
      session.interruptionEventStream.listen((event) async {
        if (event.begin) {
          await _player.pause();
        }
      });

      // 3G.21: Pause when headphones disconnect to avoid blasting audio
      // through the phone speaker.
      session.becomingNoisyEventStream.listen((_) async {
        await _player.pause();
      });
    } catch (_) {
      // No platform audio session available (e.g. unit/widget tests).
    }
  }

  // ---------------------------------------------------------------------------
  // Stream passthroughs the controller's service layer consumes.
  // ---------------------------------------------------------------------------

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<ja.PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<void> get completedStream => _player.processingStateStream
      .where((state) => state == ja.ProcessingState.completed)
      .map((_) {});

  /// Maps the engine's low-level state to the app's playback state machine.
  Stream<PlayerProcessingState> get processingStateStream =>
      _player.processingStateStream.map(_mapProcessingState);

  PlayerProcessingState _mapProcessingState(ja.ProcessingState state) {
    return switch (state) {
      ja.ProcessingState.idle => PlayerProcessingState.idle,
      ja.ProcessingState.loading => PlayerProcessingState.loading,
      ja.ProcessingState.buffering => PlayerProcessingState.buffering,
      ja.ProcessingState.ready => PlayerProcessingState.ready,
      ja.ProcessingState.completed => PlayerProcessingState.completed,
    };
  }

  bool get playing => _player.playing;

  // ---------------------------------------------------------------------------
  // Source loading — also promotes the track to the OS media item.
  // ---------------------------------------------------------------------------

  /// Loads an asset-backed source. Also promotes [track] to the OS media item
  /// (metadata for the notification / lock screen).
  Future<void> setAsset(String assetPath, {Track? track}) async {
    await _player.setAsset(assetPath);
    _publishMediaItem(track);
  }

  /// Loads a file-backed source. Also promotes [track] to the OS media item.
  Future<void> setFile(String filePath, {Track? track}) async {
    await _player.setFilePath(filePath);
    _publishMediaItem(track);
  }

  void _publishMediaItem(Track? track) {
    if (track == null) return;
    mediaItem.add(_trackToMediaItem(track));
  }

  /// Pushes [track]'s metadata to the OS media session without reloading.
  void publishMediaItem(Track track) => _publishMediaItem(track);

  MediaItem _trackToMediaItem(Track track) {
    return MediaItem(
      id: track.filePath,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
      artUri: track.albumArtUri != null
          ? Uri.tryParse(track.albumArtUri!)
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // AudioHandler overrides — the OS calls these.
  // ---------------------------------------------------------------------------

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (onNext != null) {
      await onNext!();
    } else {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPrevious != null) {
      await onPrevious!();
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await playbackState.firstWhere(
      (state) => state.processingState == AudioProcessingState.idle,
    );
  }

  // ---------------------------------------------------------------------------
  // State broadcasting to the OS (notification, lock screen, media session).
  // ---------------------------------------------------------------------------

  /// Broadcasts the current engine state to all audio_service clients.
  void _broadcastState(ja.PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ja.ProcessingState.idle: AudioProcessingState.idle,
        ja.ProcessingState.loading: AudioProcessingState.loading,
        ja.ProcessingState.buffering: AudioProcessingState.buffering,
        ja.ProcessingState.ready: AudioProcessingState.ready,
        ja.ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }

  /// Broadcasts the latest controls/state without an engine event (used after
  /// the controller navigates, so OS clients reflect the new track/state).
  void refreshPlaybackState() => _broadcastState(_player.playbackEvent);

  // ---------------------------------------------------------------------------
  // Cleanup.
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await _playbackSub.cancel();
    await _completedSub.cancel();
    await _player.dispose();
  }
}
