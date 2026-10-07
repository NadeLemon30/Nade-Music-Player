/// Playback repeat behaviour for end-of-track and end-of-queue navigation.
enum RepeatMode {
  off,
  all,
  one,
}

/// Playback mode: how the player navigates through the queue (Phase 3F).
///
/// Kept separate from [PlaybackQueue] — the queue owns *what* is queued
/// (order, current item, add/remove/reorder), while this layer owns *how* we
/// navigate it (shuffle + repeat). Enabling shuffle never reorders the
/// visible queue.
class PlaybackMode {
  final bool shuffleEnabled;

  final RepeatMode repeatMode;

  const PlaybackMode({
    this.shuffleEnabled = false,
    this.repeatMode = RepeatMode.off,
  });

  PlaybackMode copyWith({
    bool? shuffleEnabled,
    RepeatMode? repeatMode,
  }) {
    return PlaybackMode(
      shuffleEnabled:
          shuffleEnabled ?? this.shuffleEnabled,
      repeatMode:
          repeatMode ?? this.repeatMode,
    );
  }
}