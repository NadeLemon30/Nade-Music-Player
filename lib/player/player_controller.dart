import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../services/audio/audio_player_service.dart';
import 'audio_handler.dart';
import '../services/playback/play_history_service.dart';
import '../services/sleep_timer_service.dart';
import 'player_state.dart';
import 'queue/playback_queue.dart';
import 'queue/queue_item.dart';

export 'player_state.dart';

/// Provider for the singleton [AudioPlayerService].
///
/// There is exactly one audio engine for the entire application: every UI
/// surface references this provider instead of constructing its own player.
/// The engine lives inside the app-wide [MusicAudioHandler] (Phase 3G) which is
/// created by `AudioService.init` in `main()`. When that global is set (i.e.
/// normal app startup) the service wraps it; tests usually override this whole
/// provider with a fake instead.
final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService(globalAudioHandler ?? MusicAudioHandler());
  ref.onDispose(service.dispose);
  return service;
});

/// Riverpod Notifier managing reactive audio playback state and queue
/// transitions.
///
/// Owns the playback queue (Phase 3E spec model), play state, position,
/// duration, previous/next navigation, repeat handling, and automatic
/// advancement when a track completes.
///
/// Queue mutations ([playNext], [addToQueue], [removeFromQueue]) only modify
/// the queue — playback always starts through [playTrack]/[playQueueItem]
/// (3E.9: "modify queue" and "start playback" are separate operations).
class PlayerNotifier extends Notifier<PlayerState> {
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<dynamic>? _playingSub;
  StreamSubscription<PlayerProcessingState>? _processingSub;
  StreamSubscription<void>? _completedSub;
  StreamSubscription<void>? _sleepTimerExpiredSub;

  /// Backing store for the queue (Phase 3E spec [PlaybackQueue]).
  final PlaybackQueue _queue = PlaybackQueue();

  /// Random source used when building shuffled orders.
  final Random _random = Random();

  /// The playback mode: shuffle + repeat navigation settings (Phase 3F).
  /// Source of truth for playback-mode state, mirrored into [PlayerState] so
  /// the reactive UI reads a single snapshot.
  PlaybackMode _playbackMode = const PlaybackMode();

  /// Shuffle playback order as queue-item ids (Phase 3F). Kept separate from
  /// the visible queue order: enabling shuffle never rearranges the
  /// [PlaybackQueue] itself, only this id-based navigation order.
  List<String> _shuffleOrder = [];

  int _shufflePosition = -1;

  /// Whether the current track has already been counted as a play (Phase 3H).
  /// Reset whenever a new track starts loading; prevents re-counting on pause
  /// + resume or repeated rebuilds (3H.9).
  bool _playRecordedForCurrentTrack = false;

  AudioPlayerService get _audioService => ref.read(audioPlayerServiceProvider);

  /// Timestamp of the last resume-position write, used to throttle database
  /// writes (3H.15 — the position stream can fire many times per second; we
  /// persist at most one write every few seconds per session).
  DateTime? _lastResumeSave;

  /// The saved-position threshold below which a position is treated as "start".
  static const Duration _resumeThreshold = Duration(seconds: 5);

  /// Guard token so a stale async [load] never overwrites newer state.
  int _loadEpoch = 0;

  @override
  PlayerState build() {
    _initSubscriptions();
    ref.onDispose(_disposeSubscriptions);
    return const PlayerState();
  }

  /// The backing playback queue (3E.10).
  PlaybackQueue get queue => _queue;

  /// The current playback mode (3F.7).
  PlaybackMode get playbackMode => _playbackMode;

  void _initSubscriptions() {
    _positionSub = _audioService.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
      _handlePosition(pos);
    });

    _durationSub = _audioService.durationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(duration: dur);
      }
    });

    _playingSub = _audioService.playerStateStream.listen((playerState) {
      state = state.copyWith(isPlaying: playerState.playing);
    });

    _processingSub = _audioService.processingStateStream.listen((processing) {
      state = state.copyWith(processingState: processing);
    });

    _completedSub = _audioService.completedStream.listen((_) {
      unawaited(_handleTrackCompleted());
    });

    // Phase 4A: an expired sleep timer stops playback. The timer service never
    // touches the engine itself — it only signals expiry, and this controller
    // owns the single stop path (stop() also persists the current resume point,
    // matching a manual stop).
    _sleepTimerExpiredSub = ref
        .read(sleepTimerServiceProvider)
        .expiredStream
        .listen((_) {
      unawaited(stop());
    });

    // Phase 3G: route OS navigation (notification / lock-screen / headset) into
    // the app's own shuffle/repeat-aware navigation so both sources agree.
    _audioService.setOsHandlers(
      onNext: () async {
        await next();
        _audioService.refreshOsPlaybackState();
      },
      onPrevious: () async {
        await previous();
        _audioService.refreshOsPlaybackState();
      },
    );
  }

  void _disposeSubscriptions() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _processingSub?.cancel();
    _sleepTimerExpiredSub?.cancel();
  }

  /// Sets a new playback queue and optionally begins playing at [startIndex].
  ///
  /// When shuffle is enabled the target track is pinned first and the rest of
  /// the queue is randomized.
  Future<void> setQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) {
      _queue.clear();
      ++_loadEpoch;
      state = state.copyWith(
        queue: [],
        currentIndex: -1,
        clearCurrentTrack: true,
        isPlaying: false,
        processingState: PlayerProcessingState.idle,
        position: Duration.zero,
        duration: Duration.zero,
      );
      await _audioService.stop();
      return;
    }

    final index = startIndex.clamp(0, tracks.length - 1);
    final target = tracks[index];
    final order = state.shuffleEnabled
        ? _shuffledOrder(tracks, first: target)
        : List.of(tracks);
    _queue.setQueue(order, initialIndex: state.shuffleEnabled ? 0 : index);

    final loadEpoch = ++_loadEpoch;
    final currentTrack = _queue.currentTrack!;
    state = state.copyWith(
      queue: _queue.items.map((e) => e.track).toList(),
      currentIndex: _queue.currentIndex,
      currentTrack: currentTrack,
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: false,
      processingState: PlayerProcessingState.loading,
      clearError: true,
    );

    final loaded = await _loadTrack(currentTrack, epoch: loadEpoch);
    if (loaded && loadEpoch == _loadEpoch && autoPlay) {
      await play();
    }
  }

  /// Plays [tracks] as a queue starting at [initialIndex].
  ///
  /// Unlike [playTrack], the player learns the tracks before and after the
  /// selection so previous/next navigation works immediately.
  Future<void> playQueue(
    List<Track> tracks, {
    int initialIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    await setQueue(tracks, startIndex: initialIndex, autoPlay: true);
  }

  /// Plays [track] — either adopting [queue] (when provided) or playing the
  /// track within the existing queue context (when it is the current item,
  /// used by [playQueueItem]/[next]/[previous]).
  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    if (queue != null) {
      final index = queue.indexWhere((t) => t.id == track.id);
      await setQueue(
        queue,
        startIndex: index >= 0 ? index : 0,
        autoPlay: true,
      );
      return;
    }

    final currentIndex = _queue.currentIndex;
    final isCurrent = currentIndex >= 0 &&
        currentIndex < _queue.items.length &&
        _queue.items[currentIndex].track.id == track.id;
    if (!isCurrent) {
      await setQueue([track], autoPlay: true);
      return;
    }

    final loadEpoch = ++_loadEpoch;
    state = state.copyWith(
      currentTrack: track,
      currentIndex: _queue.currentIndex,
      queue: _queue.items.map((e) => e.track).toList(),
      position: Duration.zero,
      duration: Duration.zero,
      isPlaying: false,
      processingState: PlayerProcessingState.loading,
      clearError: true,
    );

    final loaded = await _loadTrack(track, epoch: loadEpoch);
    if (loaded && loadEpoch == _loadEpoch) {
      await play();
    }
  }

  /// Plays the given queue item (3E.11): resolves it to a queue index, moves
  /// the current position there, then plays the track — never creating an
  /// unrelated queue state.
  Future<void> playQueueItem(
    QueueItem item,
  ) async {
    final index = _queue.items.indexWhere(
      (queueItem) => queueItem.id == item.id,
    );

    if (index == -1) {
      return;
    }

    _queue.setCurrentIndex(index);

    await playTrack(item.track);
  }

  /// Starts playback of [tracks] at [startIndex] with shuffle enabled.
  Future<void> shuffleAll(List<Track> tracks, {int startIndex = 0}) async {
    _playbackMode = _playbackMode.copyWith(shuffleEnabled: true);
    _applyPlaybackMode();
    await setQueue(tracks, startIndex: startIndex, autoPlay: true);
  }

  Future<bool> _loadTrack(Track track, {required int epoch}) async {
    // A new track starts a fresh listening session: it must be listened past
    // the play-count threshold before it counts as a new play (3H.9).
    _playRecordedForCurrentTrack = false;
    state = state.copyWith(processingState: PlayerProcessingState.loading);
    try {
      if (track.isAsset) {
        await _audioService.setAsset(track.filePath, track: track);
      } else {
        await _audioService.setFile(track.filePath, track: track);
      }
      if (epoch != _loadEpoch) return false;

      final resumed = await _maybeResume(track, epoch: epoch);
      if (epoch != _loadEpoch) return false;

      state = state.copyWith(
        error: null,
        clearError: true,
        // just_audio keeps playing through a source swap, so the ready snapshot
        // reflects the engine's actual state instead of blindly resetting to
        // false (an ongoing play must not flip the button to "play").
        isPlaying: _audioService.playing,
        processingState: PlayerProcessingState.ready,
        position: resumed ?? Duration.zero,
        resumedFrom: resumed,
        clearResumedFrom: resumed == null,
      );
      _audioService.refreshOsPlaybackState();
      return true;
    } catch (_) {
      if (epoch != _loadEpoch) return false;
      _setError('Unable to play this file.\n'
          'It may have been moved or deleted.');
      return false;
    }
  }

  /// Decides the resume value to persist for [track] at [position].
  ///
  /// Only a meaningful mid-track position is kept: near the start
  /// (`<= _resumeThreshold`) or near the end (`>= duration - _resumeEdge`,
  /// per 3H.18) clear any stale resume to `Duration.zero` so reopening the
  /// track starts from the beginning. Returns null when there is no track to
  /// persist for.
  Duration? _resumeValueFor(Track? track, Duration position) {
    if (track == null) return null;

    if (position <= _resumeThreshold) {
      return Duration.zero;
    }

    final duration = track.duration;
    if (duration != null && position >= duration - _resumeEdge) {
      return Duration.zero;
    }

    return position;
  }

  /// Persists the current track's playback position so it can be resumed on
  /// reopen. Positions outside the meaningful range (near start / near end)
  /// clear any stale resume instead of keeping it.
  Future<void> _persistResumeForCurrent() async {
    final value = _resumeValueFor(state.currentTrack, state.position);
    if (value == null) return;
    await _saveResumePosition(state.currentTrack!, value);
  }

  /// Writes [track]'s resume [position], throttled to avoid hammering SQLite
  /// with the high-frequency position stream (3H.15). Clearing writes of
  /// `Duration.zero` are never throttled so a stale resume is reliably dropped.
  Future<void> _saveResumePosition(
    Track track,
    Duration position,
  ) async {
    final clearing = position == Duration.zero;
    final now = DateTime.now();
    final last = _lastResumeSave;
    if (!clearing &&
        last != null &&
        now.difference(last) < _resumeSaveThrottle) {
      return;
    }
    _lastResumeSave = now;

    await ref
        .read(playHistoryServiceProvider)
        .saveResumePosition(track.id, position);
  }

  /// Minimum gap between resume-position database writes (3H.15).
  static const Duration _resumeSaveThrottle = Duration(seconds: 5);

  /// Returns a saved position to resume [track] from, or null when there is
  /// none worth resuming (too early, or too close to the end for its duration).
  Future<Duration?> _maybeResume(Track track, {required int epoch}) async {
    PlayHistoryEntry? entry;
    for (final e in ref.read(playHistoryServiceProvider).entries) {
      if (e.track.id == track.id) {
        entry = e;
        break;
      }
    }

    if (entry == null) return null;

    final saved = entry.resumePosition;
    if (saved <= _resumeThreshold) return null;

    final duration = track.duration;
    if (duration != null && saved >= duration - _resumeEdge) return null;

    try {
      await _audioService.seek(saved);
      return saved;
    } catch (_) {
      return null;
    }
  }

  /// Records a play once the user has listened to the current track long enough
  /// to make the session meaningful (Phase 3H.6-3H.9).
  ///
  /// Fired from the position stream; each track is counted at most once per
  /// session so pause/resume and repeated UI rebuilds never inflate the count.
  void _handlePosition(Duration position) {
    if (_playRecordedForCurrentTrack) return;
    if (position < _playCountThreshold) return;

    _playRecordedForCurrentTrack = true;

    final track = state.currentTrack;
    if (track == null) return;

    unawaited(_recordTrackPlay(track));
  }

  /// Tells the history service that [track] was meaningfully played.
  Future<void> _recordTrackPlay(Track track) async {
    await ref.read(playHistoryServiceProvider).record(track);
  }

  /// The listening duration (after the last play/pause) counted as a play (3H.9).
  static const Duration _playCountThreshold = Duration(seconds: 10);

  /// The distance from a track's end at which resume is treated as pointless.
  static const Duration _resumeEdge = Duration(seconds: 5);

  Future<void> play() async {
    final track = state.currentTrack;
    if (track == null) return;
    // A player parked at the natural end (end-of-queue, repeat off) won't
    // restart from just [play()] — replay from the start like Repeat ONE does.
    if (state.isCompleted) {
      await seek(Duration.zero);
    }
    try {
      await _audioService.play();
      // just_audio's play() early-returns (and emits nothing) when the engine
      // is already playing — e.g. a source swap over a playing engine. Reconcile
      // with the engine's actual state so the button can never stick showing
      // "play" while audio is running (the stream may never fire).
      state = state.copyWith(isPlaying: _audioService.playing);
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> pause() async {
    unawaited(_persistResumeForCurrent());
    try {
      await _audioService.pause();
      // Same reconciliation as [play]: pause() is also a silent no-op when the
      // engine is already paused, and the flag must mirror the engine exactly.
      state = state.copyWith(isPlaying: _audioService.playing);
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Records a playback error and drops the player out of the loading/buffering
  /// states so the UI can display the message instead of hanging.
  void _setError(Object error) {
    state = state.copyWith(
      isPlaying: false,
      processingState: PlayerProcessingState.error,
      error: error.toString(),
    );
  }

  /// Clears the sticky playback error so the UI can dismiss it.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Dismisses the "Resumed from mm:ss" indication after the user has seen it.
  void dismissResume() {
    state = state.copyWith(clearResumedFrom: true);
  }

  /// Stops playback and resets to the start of the current track.
  Future<void> stop() async {
    // Persist the current position first so stopping (3H.16) is a valid
    // resume point too.
    unawaited(_persistResumeForCurrent());
    await _audioService.stop();
    state = state.copyWith(
      isPlaying: false,
      position: Duration.zero,
      processingState: PlayerProcessingState.idle,
    );
  }

  Future<void> seek(Duration position) async {
    if (!state.hasTrack) return;

    final duration = state.duration;
    if (duration <= Duration.zero) return;

    final clampedPosition = Duration(
      milliseconds: position.inMilliseconds.clamp(
        0,
        duration.inMilliseconds,
      ),
    );

    state = state.copyWith(position: clampedPosition);

    try {
      await _audioService.seek(clampedPosition);
      // An active seek re-anchors the resume point (3H.14/3H.15) so stopping
      // mid-track after scrubbing resumes from the new spot. Seeks that land
      // mid-track only; near-start/near-end clears happen on pause/stop.
      final track = state.currentTrack;
      if (track != null && clampedPosition > _resumeThreshold) {
        unawaited(_saveResumePosition(track, clampedPosition));
      }
    } catch (e) {
      _setError(e);
    }
  }

  /// Jumps [amount] ahead in the current track (clamped to its end).
  Future<void> seekForward({
    Duration amount = const Duration(seconds: 10),
  }) async {
    await seek(state.position + amount);
  }

  /// Jumps [amount] back in the current track (clamped to its start).
  Future<void> seekBackward({
    Duration amount = const Duration(seconds: 10),
  }) async {
    await seek(state.position - amount);
  }

  /// Advances to the next playback item (3F.15). Uses the same navigation
  /// rules as automatic completion ([_handleTrackCompleted]) so the Next
  /// button and a finished song behave identically.
  Future<void> next() async {
    final item = _getNextPlaybackItem();

    if (item == null) {
      return;
    }

    await playQueueItem(item);
  }

  /// Goes to the previous item in the queue (3E.13/3F.16). Within the first 3
  /// seconds previous goes to the previous item (shuffle-aware); past that it
  /// restarts the current one. At the queue start previous restarts the
  /// current track.
  Future<void> previous() async {
    if (!state.hasTrack) {
      return;
    }

    const restartThreshold =
        Duration(seconds: 3);

    if (state.position > restartThreshold) {
      await seek(Duration.zero);
      return;
    }

    final item = _getPreviousPlaybackItem();

    if (item == null) {
      await seek(Duration.zero);
      return;
    }

    await playQueueItem(item);
  }

  /// Jumps to [index] in the playback queue and starts playing it.
  Future<void> jumpToIndex(int index) async {
    if (index < 0 || index >= _queue.items.length) return;
    if (index == _queue.currentIndex) return;

    _queue.setCurrentIndex(index);
    await playTrack(_queue.currentTrack!);
  }

    /// Inserts a track directly after the currently playing song in the queue
  /// without starting playback (3E.9).
  void playNext(Track track) {
    if (_queue.isEmpty) {
      setQueue([track]);
      return;
    }

    _queue.addNext(track);
    _refreshShuffleState();
    _syncQueueState();
  }

  /// Appends a track to the end of the current playback queue without starting
  /// playback (3E.9).
  void addToQueue(Track track) {
    if (_queue.isEmpty) {
      setQueue([track], autoPlay: false);
      return;
    }

    _queue.add(track);
    _refreshShuffleState();
    _syncQueueState();
  }

  /// Inserts every track in [tracks] directly after the currently playing song,
  /// preserving [tracks] order, without starting playback (spec 3K.4 — Playlist
  /// "Play Next"). An empty queue falls back to queueing the tracks.
  void playNextAll(List<Track> tracks) {
    if (tracks.isEmpty) return;
    if (_queue.isEmpty) {
      setQueue(tracks);
      return;
    }

    // addNext pins the insertion to _currentIndex + 1, so inserting in reverse
    // preserves the requested order: [Cur, t1, t2, t3, ...].
    for (final track in tracks.reversed) {
      _queue.addNext(track);
    }
    _refreshShuffleState();
    _syncQueueState();
  }

  /// Appends every track in [tracks] to the end of the queue, preserving
  /// [tracks] order, without starting playback (spec 3K.5 — Playlist "Add to
  /// Queue").
  void addToQueueAll(List<Track> tracks) {
    if (tracks.isEmpty) return;
    if (_queue.isEmpty) {
      setQueue(tracks, autoPlay: false);
      return;
    }

    for (final track in tracks) {
      _queue.add(track);
    }
    _refreshShuffleState();
    _syncQueueState();
  }

  /// Removes the track at [index] from the queue. The currently playing track
  /// cannot be removed (it would orphan the audio session).
  void removeFromQueue(int index) {
    if (_queue.isEmpty) return;
    if (index < 0 || index >= _queue.items.length) return;
    if (index == _queue.currentIndex) return;

    _queue.removeAt(index);
    _refreshShuffleState();
    _syncQueueState();
  }

  /// Reorders the playback queue, moving the item at [fromIndex] to [toIndex].
  ///
  /// Out-of-range indexes are clamped. The currently playing item is relocated
  /// by entry id (via [PlaybackQueue.move]), so it keeps playing wherever it
  /// lands.
  void moveInQueue(int fromIndex, int toIndex) {
    if (_queue.isEmpty) return;
    final from = fromIndex.clamp(0, _queue.items.length - 1);
    final to = toIndex.clamp(0, _queue.items.length - 1);
    _queue.move(from, to);
    _refreshShuffleState();
    _syncQueueState();
  }

  /// Empties the queue and stops playback.
  Future<void> clearQueue() async {
    _queue.clear();
    _refreshShuffleState();
    ++_loadEpoch;
    state = state.copyWith(
      queue: [],
      currentIndex: -1,
      clearCurrentTrack: true,
      isPlaying: false,
      processingState: PlayerProcessingState.idle,
      position: Duration.zero,
      duration: Duration.zero,
    );
    await _audioService.stop();
  }

  /// Enables/disables shuffle (3F.7/3F.6). Enabling never reorders the visible
  /// queue — it builds the separate id-based [_shuffleOrder] navigation order
  /// with the current track pinned first; disabling clears it.
  void toggleShuffle() {
    final enabled =
        !_playbackMode.shuffleEnabled;

    _playbackMode =
        _playbackMode.copyWith(
      shuffleEnabled: enabled,
    );

    if (enabled) {
      _createShuffleOrder();
    } else {
      _shuffleOrder.clear();
      _shufflePosition = -1;
    }

    _applyPlaybackMode();
  }

  /// Cycles repeat: OFF → ALL → ONE → OFF (3F.8).
  void cycleRepeatMode() {
    final RepeatMode nextMode;

    switch (_playbackMode.repeatMode) {
      case RepeatMode.off:
        nextMode = RepeatMode.all;
        break;

      case RepeatMode.all:
        nextMode = RepeatMode.one;
        break;

      case RepeatMode.one:
        nextMode = RepeatMode.off;
        break;
    }

    _playbackMode =
        _playbackMode.copyWith(
      repeatMode: nextMode,
    );

    _applyPlaybackMode();
  }

    /// Mirrors [_playbackMode] into [PlayerState] so the reactive UI (and tests)
  /// still read shuffle/repeat from a single immutable snapshot.
  void _applyPlaybackMode() {
    state = state.copyWith(
      shuffleEnabled: _playbackMode.shuffleEnabled,
      repeatMode: _playbackMode.repeatMode,
    );
  }

  /// Prunes ids from [_shuffleOrder] that no longer exist in the queue (3F.18).
  /// After queue mutations the visible queue may contain different items while
  /// the shuffle order still references stale ids; this brings the two back
  /// into sync. Reordering is harmless — ids are position-independent so the
  /// order never needs rebuilding for a simple move.
  void _refreshShuffleState() {
    if (!_playbackMode.shuffleEnabled) {
      return;
    }

    final validIds = _queue.items
        .map((item) => item.id)
        .toSet();

    _shuffleOrder = _shuffleOrder
        .where(validIds.contains)
        .toList();
  }

  /// Handles the audio engine reporting a completed track (3F.9/3F.10).
  ///
  /// Repeat ONE restarts the current track immediately. Otherwise the next
  /// playback item is resolved and played; when there is nothing next, playback
  /// parks in the `completed` state with the position pinned at the track's
  /// natural end.
  Future<void> _handleTrackCompleted() async {
    final repeatMode =
        _playbackMode.repeatMode;

    if (repeatMode == RepeatMode.one) {
      await seek(Duration.zero);
      await play();
      return;
    }

    final nextItem =
        _getNextPlaybackItem();

    if (nextItem == null) {
      // Played to the natural end: clear the saved resume so reopening the
      // track starts from the beginning (Phase 3H).
      final completedTrack = state.currentTrack;
      if (completedTrack != null) {
        unawaited(
          ref
              .read(playHistoryServiceProvider)
              .saveResumePosition(completedTrack.id, Duration.zero),
        );
      }
      state = state.copyWith(
        isPlaying: false,
        position: state.duration,
        processingState:
            PlayerProcessingState.completed,
        clearResumedFrom: true,
      );

      return;
    }

    await playQueueItem(nextItem);
  }

  /// Resolves the item to play when the current track finishes or the Next
  /// button is pressed (3F.11). Shuffle-aware: delegates to
  /// [_getNextShuffleItem] when shuffle is on.
  QueueItem? _getNextPlaybackItem() {
    if (_queue.isEmpty) {
      return null;
    }

    if (_playbackMode.shuffleEnabled) {
      return _getNextShuffleItem();
    }

    if (_queue.hasNext) {
      return _queue.items[
        _queue.currentIndex + 1
      ];
    }

    if (_playbackMode.repeatMode ==
        RepeatMode.all) {
      _queue.setCurrentIndex(0);
      return _queue.currentItem;
    }

    return null;
  }

  /// Returns the next item from the id-based shuffle order (3F.12). Advances
  /// [_shufflePosition] by one; when Repeat ALL is active and the end of the
  /// order is reached a fresh order is generated (3F.13) and playback resumes
  /// from position 1 (skipping the current item pinned at 0 — avoiding
  /// immediate repeats per 3F.14).
  QueueItem? _getNextShuffleItem() {
    if (_shuffleOrder.isEmpty) {
      _createShuffleOrder();
    }

    if (_shufflePosition <
        _shuffleOrder.length - 1) {
      _shufflePosition++;

      return _findQueueItem(
        _shuffleOrder[_shufflePosition],
      );
    }

    if (_playbackMode.repeatMode ==
        RepeatMode.all) {
      _createShuffleOrder();

      if (_shuffleOrder.length <= 1) {
        return _findQueueItem(
          _shuffleOrder.first,
        );
      }

      _shufflePosition = 1;

      return _findQueueItem(
        _shuffleOrder[_shufflePosition],
      );
    }

    return null;
  }

  /// Resolves the previous item during manual back-navigation (3F.16).
  QueueItem? _getPreviousPlaybackItem() {
    if (_playbackMode.shuffleEnabled) {
      return _getPreviousShuffleItem();
    }

    if (_queue.hasPrevious) {
      return _queue.items[
        _queue.currentIndex - 1
      ];
    }

    if (_playbackMode.repeatMode ==
        RepeatMode.all) {
      _queue.setCurrentIndex(
        _queue.items.length - 1,
      );

      return _queue.currentItem;
    }

    return null;
  }

  /// Walks backwards through the shuffle order. At the start of the
  /// current order with Repeat ALL active, wraps to the last item so the
  /// cycle can be traced in reverse. Provisional — will be replaced if the
  /// spec's own previous-shuffle section diverges.
  QueueItem? _getPreviousShuffleItem() {
    if (_shuffleOrder.isEmpty) {
      _createShuffleOrder();
    }

    if (_shufflePosition > 0) {
      _shufflePosition--;
      return _findQueueItem(
        _shuffleOrder[_shufflePosition],
      );
    }

    if (_playbackMode.repeatMode ==
        RepeatMode.all) {
      _shufflePosition =
          _shuffleOrder.length - 1;
      return _findQueueItem(
        _shuffleOrder[_shufflePosition],
      );
    }

    return null;
  }

  /// Locates the queue item with the given [id] in the current playback
  /// queue.
  QueueItem? _findQueueItem(String id) {
    for (final item in _queue.items) {
      if (item.id == id) {
        return item;
      }
    }

    return null;
  }

  /// Mirrors the queue's current position into [PlayerState].
  void _syncQueueState() {
    state = state.copyWith(
      queue: _queue.items.map((e) => e.track).toList(),
      currentIndex: _queue.currentIndex,
      currentTrack: _queue.currentTrack,
    );
  }

  /// Builds a shuffled order that pins [first] to the front and randomizes the
  /// remaining tracks.
  List<Track> _shuffledOrder(
    List<Track> tracks, {
    required Track first,
  }) {
    final rest = tracks.where((t) => t.id != first.id).toList()
      ..shuffle(_random);
    return [first, ...rest];
  }

  /// Creates the shuffle order (Phase 3F.5): a separate playback order of
  /// [QueueItem.id]s derived from the current queue, with the current item
  /// pinned to the front. The visible queue order is left untouched.
  void _createShuffleOrder() {
    final items = _queue.items;

    if (items.isEmpty) {
      _shuffleOrder = [];
      _shufflePosition = -1;
      return;
    }

    final current = _queue.currentItem;

    final ids = items.map((item) => item.id).toList();

    ids.shuffle();

    if (current != null) {
      ids.remove(current.id);
      ids.insert(0, current.id);
    }

    _shuffleOrder = ids;

    _shufflePosition = current == null
        ? 0
        : 0;
  }
}

/// Provider exposing [PlayerNotifier] and reactive [PlayerState].
final playerNotifierProvider =
    NotifierProvider<PlayerNotifier, PlayerState>(PlayerNotifier.new);