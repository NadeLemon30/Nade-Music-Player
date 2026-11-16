/// A single line of lyrics, either timed ([timestamp] set) or plain text.
///
/// For synchronized LRC lyrics [timestamp] is the original parsed timestamp as
/// written in the file; LRC `[offset:ms]` and manual user offsets are applied
/// during active-line timing calculations (not baked into this value).
class LyricLine {
  final Duration? timestamp;
  final String text;

  const LyricLine({required this.timestamp, required this.text});

  bool get isTimed => timestamp != null;

  Map<String, dynamic> toMap() => {
    'timestampMs': timestamp?.inMilliseconds,
    'text': text,
  };

  factory LyricLine.fromMap(Map<String, dynamic> map) {
    final ms = map['timestampMs'] as int?;
    return LyricLine(
      timestamp: ms == null ? null : Duration(milliseconds: ms),
      text: map['text'] as String? ?? '',
    );
  }
}

/// Lyrics for a track: either synchronized (timed lines) or plain text.
class Lyrics {
  final String trackId;
  final List<LyricLine> lines;
  final bool synchronized;

  /// Where these lyrics came from (embedded/file/cache), for diagnostics/UI.
  final String? source;

  /// Global timing offset from an LRC `[offset:ms]` tag (milliseconds). Applied
  /// during timing calculations, not stored in each line's [LyricLine.timestamp].
  final Duration lrcOffset;

  const Lyrics({
    required this.trackId,
    required this.lines,
    required this.synchronized,
    this.source,
    this.lrcOffset = Duration.zero,
  });

  bool get isEmpty => lines.isEmpty;

  Map<String, dynamic> toMap() => {
    'trackId': trackId,
    'synchronized': synchronized,
    'source': source,
    'lrcOffsetMs': lrcOffset.inMilliseconds,
    'lines': [for (final l in lines) l.toMap()],
  };

  factory Lyrics.fromMap(Map<String, dynamic> map) {
    final rawList = map['lines'] as List<dynamic>? ?? const [];
    final raw = <Map<String, dynamic>>[];
    for (final e in rawList) {
      if (e is Map<String, dynamic>) {
        raw.add(e);
      } else if (e is Map) {
        raw.add(e.cast<String, dynamic>());
      }
    }
    return Lyrics(
      trackId: map['trackId'] as String? ?? '',
      synchronized: map['synchronized'] as bool? ?? false,
      source: map['source'] as String?,
      lrcOffset: Duration(milliseconds: map['lrcOffsetMs'] as int? ?? 0),
      lines: [for (final l in raw) LyricLine.fromMap(l)],
    );
  }

  /// Effective timestamp for [line] with the LRC `[offset:ms]` applied, clamped
  /// at zero. Used for active-line timing calculations.
  Duration? effectiveTimestamp(LyricLine line) {
    final t = line.timestamp;
    if (t == null) return null;
    var effective = t + lrcOffset;
    if (effective.isNegative) effective = Duration.zero;
    return effective;
  }
}
