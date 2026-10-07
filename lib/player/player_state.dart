import '../models/track.dart';

import 'playback_mode.dart';

export 'playback_mode.dart';

/// High-level playback processing state driven by the audio engine.
enum PlayerProcessingState {
  idle,
  loading,
  buffering,
  ready,
  completed,
  error,
}

/// Immutable snapshot of the player's playback state exposed to the UI.
///
/// [queue] is always the *playback* order: sequential when shuffle is off,
/// shuffled when it is on. [currentIndex] indexes into that playback order.
class PlayerState {
  final Track? currentTrack;

  final bool isPlaying;

  final Duration position;

  final Duration duration;

  final PlayerProcessingState processingState;

  final String? error;

  final List<Track> queue;

  final int currentIndex;

  final bool shuffleEnabled;

  final RepeatMode repeatMode;

  /// The position playback resumed from when a previously-played track is
  /// reopened (Phase 3H). Null when the latest load did not auto-resume.
  final Duration? resumedFrom;

  const PlayerState({
    this.currentTrack,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.processingState = PlayerProcessingState.idle,
    this.error,
    this.queue = const [],
    this.currentIndex = -1,
    this.shuffleEnabled = false,
    this.repeatMode = RepeatMode.off,
    this.resumedFrom,
  });

  bool get hasTrack => currentTrack != null;

  bool get hasError => error != null;

  bool get isLoading => processingState == PlayerProcessingState.loading;

  bool get isBuffering => processingState == PlayerProcessingState.buffering;

  bool get isCompleted => processingState == PlayerProcessingState.completed;

  /// Whether another track follows the current one in the playback queue
  /// (mirrors [PlaybackQueue.hasNext]).
  bool get hasNext => currentIndex + 1 < queue.length;

  /// Whether a previous track exists before the current one in the playback
  /// queue (mirrors [PlaybackQueue.hasPrevious]).
  bool get hasPrevious => currentIndex > 0;

  /// The track at [index] in the playback queue, or null when out of range.
  Track? trackAt(int index) {
    if (index < 0 || index >= queue.length) return null;
    return queue[index];
  }

  PlayerState copyWith({
    Track? currentTrack,
    bool clearCurrentTrack = false,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    PlayerProcessingState? processingState,
    String? error,
    bool clearError = false,
    List<Track>? queue,
    int? currentIndex,
    bool? shuffleEnabled,
    RepeatMode? repeatMode,
    Duration? resumedFrom,
    bool clearResumedFrom = false,
  }) {
    return PlayerState(
      currentTrack:
          clearCurrentTrack ? null : (currentTrack ?? this.currentTrack),
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      processingState: processingState ?? this.processingState,
      error: clearError ? null : (error ?? this.error),
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      resumedFrom:
          clearResumedFrom ? null : (resumedFrom ?? this.resumedFrom),
    );
  }
}