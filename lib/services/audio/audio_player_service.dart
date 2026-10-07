import 'package:just_audio/just_audio.dart' as ja;

import '../../models/track.dart';
import '../../player/player_state.dart';
import '../../player/audio_handler.dart';

/// Facade between the app and the single playback engine + OS integration
/// (Phase 3G).
///
/// Wraps the shared [MusicAudioHandler] (which owns the one [ja.AudioPlayer] and
/// bridges it to the notification / lock screen / media session). This class
/// keeps a stable, minimal surface so the player controller and UI never touch
/// `just_audio` or `audio_service` directly.
class AudioPlayerService {
  final MusicAudioHandler _handler;

  AudioPlayerService(this._handler);

  Stream<Duration> get positionStream => _handler.positionStream;

  Stream<Duration?> get durationStream => _handler.durationStream;

  Stream<ja.PlayerState> get playerStateStream => _handler.playerStateStream;

  Stream<PlayerProcessingState> get processingStateStream =>
      _handler.processingStateStream;

  Stream<void> get completedStream => _handler.completedStream;

  bool get playing => _handler.playing;

  /// Registers OS navigation callbacks (notification/lock-screen/headset) that
  /// route into the controller's shuffle/repeat-aware navigation.
  void setOsHandlers({
    Future<void> Function()? onNext,
    Future<void> Function()? onPrevious,
  }) {
    _handler.onNext = onNext;
    _handler.onPrevious = onPrevious;
  }

  /// Broadcasts the app's latest playback state to OS clients after the
  /// controller navigates on its own (not via the OS).
  void refreshOsPlaybackState() => _handler.refreshPlaybackState();

  /// Pushes the current track's metadata to the OS media session.
  void updateOsMediaItem(Track track) => _handler.publishMediaItem(track);

  Future<void> setAsset(String assetPath, {Track? track}) =>
      _handler.setAsset(assetPath, track: track);

  Future<void> setFile(String filePath, {Track? track}) =>
      _handler.setFile(filePath, track: track);

  Future<void> play() => _handler.play();

  Future<void> pause() => _handler.pause();

  Future<void> stop() => _handler.stop();

  Future<void> seek(Duration position) => _handler.seek(position);

  Future<void> dispose() => _handler.dispose();
}
