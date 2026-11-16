import 'dart:convert';

import '../../models/lyrics.dart';

/// Parsed result of an LRC document, including optional metadata/offset.
class LrcParseResult {
  final Lyrics lyrics;

  /// Global timing offset from `[offset:ms]` (milliseconds). Kept on the
  /// [Lyrics] model and applied during timing calculations (original parsed line
  /// timestamps remain intact).
  final Duration offset;

  /// Metadata tags (e.g. ar/ti/al/by) if present.
  final Map<String, String> metadata;

  const LrcParseResult({
    required this.lyrics,
    this.offset = Duration.zero,
    this.metadata = const {},
  });
}

/// Parses LRC and plain-text lyrics content.
///
/// Supports timestamps `[mm:ss.xx]`, `[mm:ss.xxx]` (and `:`/`.` fractional
/// separator), multiple timestamps per line, and metadata tags like
/// `[ar:...]`, `[ti:...]`, `[al:...]`, `[by:...]`, `[offset:...]`.
class LrcParser {
  LrcParser._();

  static final RegExp _timeTag = RegExp(
    r'\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]',
  );
  static final RegExp _metaTag = RegExp(r'^\[([a-zA-Z]+):(.*)\]$');

  /// Parses [content] as LRC and returns a full parse result including offset.
  static LrcParseResult parseLrcResult(
    String trackId,
    String content, {
    String? source,
  }) {
    final lines = <LyricLine>[];
    final metadata = <String, String>{};
    var offset = Duration.zero;

    for (final raw in const LineSplitter().convert(
      content.replaceAll('\r', ''),
    )) {
      final trimmed = raw.trimRight();
      final meta = _metaTag.firstMatch(trimmed.trim());
      final hasTime = _timeTag.hasMatch(trimmed);

      if (meta != null && !hasTime) {
        final key = meta.group(1)!.toLowerCase();
        final value = meta.group(2)?.trim() ?? '';
        if (key == 'offset') {
          final ms = int.tryParse(value) ?? 0;
          offset = Duration(milliseconds: ms);
        } else {
          metadata[key] = value;
        }
        continue;
      }

      final matches = _timeTag.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      final text = trimmed.replaceAll(_timeTag, '').trim();
      // Timed lines with empty text are ignored (do not show metadata/blank
      // entries as lyric lines).
      if (text.isEmpty) continue;

      for (final m in matches) {
        final t = _parseTimestamp(m);
        if (t == null) continue;
        lines.add(LyricLine(timestamp: t, text: text));
      }
    }

    // Keep original parsed timestamps intact. [offset:ms] is stored on the
    // lyrics and applied during timing calculations; lines are ordered by their
    // effective time so active-line lookup remains a forward scan.
    final ordered = List<LyricLine>.of(lines)
      ..sort((a, b) {
        var ta = (a.timestamp ?? Duration.zero) + offset;
        var tb = (b.timestamp ?? Duration.zero) + offset;
        if (ta.isNegative) ta = Duration.zero;
        if (tb.isNegative) tb = Duration.zero;
        final cmp = ta.compareTo(tb);
        if (cmp != 0) return cmp;
        // Stable-ish fallback for equal effective times.
        return (a.timestamp ?? Duration.zero).compareTo(
          b.timestamp ?? Duration.zero,
        );
      });

    final lyrics = Lyrics(
      trackId: trackId,
      lines: ordered,
      synchronized: ordered.isNotEmpty,
      source: source,
      lrcOffset: offset,
    );

    return LrcParseResult(lyrics: lyrics, offset: offset, metadata: metadata);
  }

  /// Parses LRC content into [Lyrics]. Supports `[mm:ss.xx]` / `[mm:ss.xxx]`
  /// and multiple timestamps per line; metadata tags are not emitted as lines.
  static Lyrics parseLrc(String trackId, String content, {String? source}) {
    return parseLrcResult(trackId, content, source: source).lyrics;
  }

  /// Parses plain, untimed lyrics text. Drops obvious LRC metadata headers.
  static Lyrics parsePlain(String trackId, String content, {String? source}) {
    final rawLines = const LineSplitter().convert(content.replaceAll('\r', ''));
    final out = <LyricLine>[];
    for (final l in rawLines) {
      final trimmed = l.trim();
      // Drop metadata-like tags when encountered in plain text files.
      if (_metaTag.hasMatch(trimmed) && !_timeTag.hasMatch(trimmed)) {
        continue;
      }
      out.add(LyricLine(timestamp: null, text: l));
    }
    while (out.isNotEmpty && out.first.text.trim().isEmpty) {
      out.removeAt(0);
    }
    while (out.isNotEmpty && out.last.text.trim().isEmpty) {
      out.removeLast();
    }
    return Lyrics(
      trackId: trackId,
      lines: out,
      synchronized: false,
      source: source,
    );
  }

  /// Parses content that may be timed (LRC) or plain; prefers synced when
  /// timed lyric lines are present.
  static Lyrics parse(String trackId, String content, {String? source}) {
    final lrc = parseLrc(trackId, content, source: source);
    if (lrc.synchronized && lrc.lines.isNotEmpty) return lrc;
    return parsePlain(trackId, content, source: source);
  }

  static Duration? _parseTimestamp(RegExpMatch m) {
    final min = int.tryParse(m.group(1) ?? '0');
    final sec = int.tryParse(m.group(2) ?? '0');
    if (min == null || sec == null) return null;
    final fracRaw = m.group(3);
    var ms = 0;
    if (fracRaw != null && fracRaw.isNotEmpty) {
      final fracStr = fracRaw.padRight(3, '0').substring(0, 3);
      ms = int.tryParse(fracStr) ?? 0;
    }
    return Duration(minutes: min, seconds: sec, milliseconds: ms);
  }
}
