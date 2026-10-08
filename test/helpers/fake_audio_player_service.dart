import 'dart:async';

import 'package:just_audio/just_audio.dart' as ja;
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/player/player_state.dart';
import 'package:nades_music_player/services/audio/audio_player_service.dart';
import 'package:nades_music_player/services/playback/play_history_service.dart';

/// In-memory fake of [AudioPlayerService] that records calls and lets tests
/// drive streams (position, duration, completion) directly.
class FakeAudioPlayerService implements AudioPlayerService {
  final _positionCtrl = StreamController<Duration>.broadcast(sync: true);
  final _durationCtrl = StreamController<Duration?>.broadcast(sync: true);
  final _stateCtrl = StreamController<ja.PlayerState>.broadcast(sync: true);
  final _completedCtrl = StreamController<void>.broadcast(sync: true);

  String? loadedPath;
  bool loadedAsAsset = false;
  Duration? lastSeek;
  int seekCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int stopCount = 0;

  /// How many sources were loaded — used to prove that unrelated features (e.g.
  /// the audio effects) never reload the current track (spec §19).
  int setFileCount = 0;

  /// How many times the OS media notification metadata was published.
  int mediaItemUpdateCount = 0;
  Track? lastMediaItem;

  /// When true the next [setFile]/[setAsset] call throws (simulates a missing file).
  bool failNextLoad = false;

  /// When true the next [play] call throws (simulates a playback failure).
  bool failNextPlay = false;

  bool _playing = false;
  ja.ProcessingState _processingState = ja.ProcessingState.idle;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration?> get durationStream => _durationCtrl.stream;

  @override
  Stream<ja.PlayerState> get playerStateStream => _stateCtrl.stream;

  @override
  Stream<PlayerProcessingState> get processingStateStream =>
      _stateCtrl.stream.map(
        (state) => _mapProcessingState(state.processingState),
      );

  PlayerProcessingState _mapProcessingState(ja.ProcessingState state) {
    return switch (state) {
      ja.ProcessingState.idle => PlayerProcessingState.idle,
      ja.ProcessingState.loading => PlayerProcessingState.loading,
      ja.ProcessingState.buffering => PlayerProcessingState.buffering,
      ja.ProcessingState.ready => PlayerProcessingState.ready,
      ja.ProcessingState.completed => PlayerProcessingState.completed,
    };
  }

  @override
  Stream<void> get completedStream => _completedCtrl.stream;

  @override
  bool get playing => _playing;

  @override
  Future<void> setAsset(String assetPath, {Track? track}) async {
    if (failNextLoad) {
      failNextLoad = false;
      throw Exception('load failed');
    }
    loadedAsAsset = true;
    loadedPath = assetPath;
    _prepare();
    // Mirrors MusicAudioHandler: loading a source also publishes the OS media
    // item for the notification / lock screen.
    if (track != null) updateOsMediaItem(track);
  }

  @override
  Future<void> setFile(String filePath, {Track? track}) async {
    if (failNextLoad) {
      failNextLoad = false;
      throw Exception('load failed');
    }
    setFileCount++;
    loadedAsAsset = false;
    loadedPath = filePath;
    _prepare();
    if (track != null) updateOsMediaItem(track);
  }

  /// Called by the controller to register OS navigation callbacks.
  Future<void> Function()? osOnNext;
  Future<void> Function()? osOnPrevious;

  @override
  void setOsHandlers({
    Future<void> Function()? onNext,
    Future<void> Function()? onPrevious,
  }) {
    osOnNext = onNext;
    osOnPrevious = onPrevious;
  }

  @override
  void refreshOsPlaybackState() {}

  @override
  void updateOsMediaItem(Track track) {
    mediaItemUpdateCount++;
    lastMediaItem = track;
  }

  void _prepare() {
    // just_audio keeps `playing` unchanged across a source swap: loading a new
    // track over a playing engine continues playing, over an idle one stays
    // idle until play() is called.
    _processingState = ja.ProcessingState.ready;
    _emit();
  }

  @override
  Future<void> play() async {
    if (failNextPlay) {
      failNextPlay = false;
      throw Exception('play failed');
    }
    playCount++;
    // just_audio's play() early-returns — and emits nothing on the state stream —
    // when the engine is already playing; the caller is expected to reconcile
    // with the engine's actual state itself.
    if (_playing) return;
    _playing = true;
    _emit();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    pauseCount++;
    _emit();
  }

  @override
  Future<void> stop() async {
    _playing = false;
    stopCount++;
    _processingState = ja.ProcessingState.idle;
    _emit();
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
    seekCount++;
    // A seek after the track ended re-opens the source (ExoPlayer returns to
    // READY), so the player state stream reflects a playable engine again.
    if (_processingState == ja.ProcessingState.completed) {
      _processingState = ja.ProcessingState.ready;
      _emit();
    }
  }

  @override
  Future<void> dispose() async {
    _playing = false;
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _stateCtrl.close();
    await _completedCtrl.close();
  }

  void emitPosition(Duration position) => _positionCtrl.add(position);

  void emitDuration(Duration? duration) => _durationCtrl.add(duration);

  /// Signals that the current track reached the end of its source.
  void emitCompleted() {
    _playing = false;
    _processingState = ja.ProcessingState.completed;
    _emit();
    _completedCtrl.add(null);
  }

  /// Emits a low-level engine processing state without changing playback.
  void setProcessingState(ja.ProcessingState processing) {
    _processingState = processing;
    _emit();
  }

  void _emit() {
    if (!_stateCtrl.isClosed) {
      _stateCtrl.add(ja.PlayerState(_playing, _processingState));
    }
  }
}

/// Play history stub that never touches the filesystem.
class NoopPlayHistoryService extends PlayHistoryService {
  @override
  Future<void> record(Track track) async {}
}

/// Convenience track factory for player tests.
Track testTrack(String id, {String? filePath}) {
  return Track(
    id: id,
    title: 'Song $id',
    artist: 'Artist $id',
    album: '',
    albumArtist: '',
    genre: '',
    year: null,
    trackNumber: null,
    discNumber: null,
    duration: const Duration(minutes: 3),
    filePath: filePath ?? '/music/$id.mp3',
    fileName: '$id.mp3',
    fileSize: null,
    mimeType: null,
  );
}