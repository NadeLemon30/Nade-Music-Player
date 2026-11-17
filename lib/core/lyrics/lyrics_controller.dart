import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/lyrics_repository.dart';
import '../../models/lyrics.dart';
import '../../models/track.dart';
import '../../player/player_controller.dart';

/// Immutable view of the current lyrics state for the UI.
class LyricsState {
  final Track? track;
  final Lyrics? lyrics;
  final bool loading;
  final bool unavailable;

  /// True when a matching lyrics source was found but could not be read/parsed.
  final bool error;

  /// Manual timing adjustment applied during active-line calculations
  /// (positive = lyrics later, negative = earlier). Stored per track.
  final Duration offset;

  /// Index of the active line for synchronized lyrics, or -1 when none/plain.
  final int currentLineIndex;

  /// Last playback position received from the player (source of truth).
  final Duration position;

  const LyricsState({
    this.track,
    this.lyrics,
    this.loading = false,
    this.unavailable = false,
    this.error = false,
    this.offset = Duration.zero,
    this.currentLineIndex = -1,
    this.position = Duration.zero,
  });

  bool get hasLyrics => lyrics != null && lyrics!.lines.isNotEmpty;
  bool get isSynced => hasLyrics && lyrics!.synchronized;

  /// True when the displayed lyrics were imported by the user from a file.
  bool get isImported => lyrics?.source == LyricsRepository.importedSource;

  LyricsState copyWith({
    Track? track,
    bool clearTrack = false,
    Lyrics? lyrics,
    bool clearLyrics = false,
    bool? loading,
    bool? unavailable,
    bool? error,
    Duration? offset,
    int? currentLineIndex,
    Duration? position,
  }) {
    return LyricsState(
      track: clearTrack ? null : (track ?? this.track),
      lyrics: clearLyrics ? null : (lyrics ?? this.lyrics),
      loading: loading ?? this.loading,
      unavailable: unavailable ?? this.unavailable,
      error: error ?? this.error,
      offset: offset ?? this.offset,
      currentLineIndex: currentLineIndex ?? this.currentLineIndex,
      position: position ?? this.position,
    );
  }
}

/// Loads lyrics for the current track and tracks the active synced line from
/// the player position. Lyrics never control playback and never create a timer;
/// the player is the source of truth.
class LyricsController extends Notifier<LyricsState> {
  static const Duration minOffset = Duration(milliseconds: -5000);
  static const Duration maxOffset = Duration(milliseconds: 5000);

  int _loadToken = 0;

  @override
  LyricsState build() {
    // React to track and position changes from the single player controller.
    ref.listen<PlayerState>(playerNotifierProvider, (prev, next) {
      final prevId = prev?.currentTrack?.id;
      final nextId = next.currentTrack?.id;
      if (prevId != nextId) {
        unawaited(loadForTrack(nextId, track: next.currentTrack));
      } else {
        updatePosition(next.position);
      }
    }, fireImmediately: true);

    return const LyricsState();
  }

  /// Convenience getter for the active lyrics.
  Lyrics? get lyrics => state.lyrics;

  /// Convenience getter for the active line index.
  int? get currentLineIndex =>
      state.currentLineIndex < 0 ? null : state.currentLineIndex;

  LyricsRepository get _repo => ref.read(lyricsRepositoryProvider);

  /// Loads lyrics (and per-track manual offset) for [trackId].
  ///
  /// A [track] snapshot may be provided to avoid re-reading player state during
  /// loads triggered by player changes.
  Future<void> loadForTrack(String? trackId, {Track? track}) async {
    _loadToken++;
    final token = _loadToken;

    if (trackId == null || trackId.isEmpty) {
      clear();
      return;
    }

    final resolvedTrack = track ?? _trackForId(trackId);
    final initialPosition = ref.read(playerNotifierProvider).position;

    // Clear previous lyrics immediately; keep no stale offset/line/state.
    state = LyricsState(
      track: resolvedTrack,
      loading: true,
      position: initialPosition,
    );

    int offsetMs = 0;
    Lyrics? loaded;
    var hadReadError = false;
    try {
      offsetMs = await _repo.getLyricOffsetMs(trackId);
    } catch (_) {
      offsetMs = 0;
    }

    if (resolvedTrack != null) {
      try {
        loaded = await _repo.getLyrics(resolvedTrack);
      } on LyricsReadException {
        hadReadError = true;
        loaded = null;
      } catch (_) {
        loaded = null;
      }
    }

    if (token != _loadToken) return; // stale

    final manualOffset = _clampOffset(Duration(milliseconds: offsetMs));
    final position = ref.read(playerNotifierProvider).position;

    if (loaded == null || loaded.isEmpty) {
      state = state.copyWith(
        track: resolvedTrack,
        clearLyrics: true,
        loading: false,
        unavailable: !hadReadError,
        error: hadReadError,
        offset: manualOffset,
        position: position,
        currentLineIndex: -1,
      );
    } else {
      final idx = _indexFor(position, manualOffset, loaded);
      state = state.copyWith(
        track: resolvedTrack,
        lyrics: loaded,
        loading: false,
        unavailable: false,
        error: false,
        offset: manualOffset,
        position: position,
        currentLineIndex: idx,
      );
    }
  }

  /// Receives the current playback position from the player (source of truth)
  /// and recomputes the active lyric line immediately (including on seeks).
  ///
  /// Only notifies listeners when the active line (or relevant state) changes to
  /// avoid rebuilding the lyrics UI on every position tick.
  void updatePosition(Duration position) {
    final idx = _indexFor(
      position,
      state.offset,
      state.lyrics,
      hint: state.currentLineIndex,
    );
    if (idx == state.currentLineIndex) return;
    state = state.copyWith(position: position, currentLineIndex: idx);
  }

  /// Sets the manual lyric offset for the current track, persists it
  /// (`track_id -> lyric_offset_ms`), and recomputes the active line.
  ///
  /// Offset is clamped to [-5.0s, +5.0s].
  void setOffset(Duration offset) {
    final clamped = _clampOffset(offset);
    final trackId = state.track?.id;
    if (trackId != null && trackId.isNotEmpty) {
      unawaited(_repo.setLyricOffsetMs(trackId, clamped.inMilliseconds));
    }
    final position = ref.read(playerNotifierProvider).position;
    final idx = _indexFor(
      position,
      clamped,
      state.lyrics,
      hint: state.currentLineIndex,
    );
    state = state.copyWith(
      offset: clamped,
      currentLineIndex: idx,
      position: position,
    );
  }

  /// Adjusts the manual lyric offset by [delta].
  void adjustOffset(Duration delta) {
    setOffset(state.offset + delta);
  }

  void resetOffset() {
    setOffset(Duration.zero);
  }

  /// Clears lyrics/state (e.g. when no track is active).
  void clear() {
    state = const LyricsState();
  }

  /// Imports a user-selected lyrics file for the current track, persists it,
  /// and reloads the lyrics display.
  ///
  /// Throws [LyricsReadException] when the file has no readable lyrics.
  Future<void> importLyricsBytes(List<int> bytes, {String? fileName}) async {
    final track = state.track ?? ref.read(playerNotifierProvider).currentTrack;
    if (track == null) return;
    await _repo.importLyricsBytes(track, bytes, fileName: fileName);
    // If playback moved on while the import was in flight, don't reload the
    // old track over the current one; the import is persisted for next time.
    if (ref.read(playerNotifierProvider).currentTrack?.id != track.id) return;
    await loadForTrack(track.id, track: track);
  }

  /// Removes user-imported lyrics for the current track, restoring embedded or
  /// local lyrics (or the unavailable state) on the next lookup.
  Future<void> removeImportedLyrics() async {
    final track = state.track ?? ref.read(playerNotifierProvider).currentTrack;
    if (track == null) return;
    await _repo.removeImportedLyrics(track.id);
    if (ref.read(playerNotifierProvider).currentTrack?.id != track.id) return;
    await loadForTrack(track.id, track: track);
  }

  /// Clears cached lyrics for the current track and reloads.
  ///
  /// Imported lyrics are kept: they are an explicit user choice, not a stale
  /// cache entry. Use [removeImportedLyrics] to drop them.
  Future<void> refreshCurrent() async {
    final track = state.track ?? ref.read(playerNotifierProvider).currentTrack;
    if (track == null) return;
    if (!state.isImported) {
      await _repo.removeLyrics(track.id);
    }
    await loadForTrack(track.id, track: track);
  }

  Track? _trackForId(String id) {
    final player = ref.read(playerNotifierProvider);
    final current = player.currentTrack;
    if (current?.id == id) return current;
    for (final t in player.queue) {
      if (t.id == id) return t;
    }
    return null;
  }

  Duration _clampOffset(Duration offset) {
    if (offset < minOffset) return minOffset;
    if (offset > maxOffset) return maxOffset;
    return offset;
  }

  /// Computes the active line index for [position] adjusted by the manual
  /// [offset] and the lyrics' own LRC `[offset:ms]` (applied during timing
  /// calculations while original parsed timestamps remain intact).
  ///
  /// Active line = latest effective timestamp <= (position + offset).
  /// Efficient lookup: keep/move from [hint] forward or backward; fall back to
  /// binary search for large jumps/seeks.
  int _indexFor(
    Duration position,
    Duration offset,
    Lyrics? lyrics, {
    int hint = -1,
  }) {
    if (lyrics == null || !lyrics.synchronized || lyrics.lines.isEmpty) {
      return -1;
    }
    final effective = position + offset;
    final lines = lyrics.lines;
    final last = lines.length - 1;

    // Use hint when valid: advance forward during playback, or step backward on
    // seeks/rewinds, then settle locally.
    if (hint >= -1 && hint <= last) {
      var i = hint < 0 ? 0 : hint;
      if (i > last) i = last;

      // Move backward if we're past the effective position.
      while (i >= 0) {
        final t = lyrics.effectiveTimestamp(lines[i]);
        if (t != null && t <= effective) break;
        i--;
      }
      if (i < 0) {
        final t0 = lyrics.effectiveTimestamp(lines[0]);
        if (t0 == null || t0 > effective) return -1;
        i = 0;
      }

      // Move forward while the next line is also active.
      while (i < last) {
        final nextT = lyrics.effectiveTimestamp(lines[i + 1]);
        if (nextT == null || nextT <= effective) {
          i++;
        } else {
          break;
        }
      }

      // If this still doesn't satisfy (e.g. hint was far away / odd ordering),
      // fall through to binary search.
      final ti = lyrics.effectiveTimestamp(lines[i]);
      if (ti != null && ti <= effective) {
        if (i == last) return i;
        final tn = lyrics.effectiveTimestamp(lines[i + 1]);
        if (tn == null || tn > effective) return i;
      }
    }

    return _binarySearchActiveIndex(lyrics, effective);
  }

  /// Binary search: index of the latest line with effective timestamp <= [effective].
  int _binarySearchActiveIndex(Lyrics lyrics, Duration effective) {
    final lines = lyrics.lines;
    var lo = 0;
    var hi = lines.length - 1;
    var ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final t = lyrics.effectiveTimestamp(lines[mid]);
      if (t == null || t <= effective) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }
}

/// Provider exposing [LyricsController] and reactive [LyricsState].
final lyricsControllerProvider =
    NotifierProvider<LyricsController, LyricsState>(LyricsController.new);
