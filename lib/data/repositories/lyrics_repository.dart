import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/lyrics/lrc_parser.dart';
import '../../models/lyrics.dart';
import '../../models/track.dart';

/// Thrown when a lyrics file is found but cannot be read or parsed.
class LyricsReadException implements Exception {
  final String path;
  final Object? cause;

  LyricsReadException(this.path, [this.cause]);

  @override
  String toString() => 'LyricsReadException($path, $cause)';
}

/// Resolves lyrics for a track from embedded metadata, local files, or cache.
///
/// Priority (spec 4C): embedded → local .lrc → local plain text → cache →
/// unavailable (null).
class LyricsRepository {
  LyricsRepository({this.customCacheDir});

  final String? customCacheDir;
  String? _resolvedCacheDir;

  // In-memory cache to avoid repeated disk reads within a session.
  final Map<String, Lyrics?> _memory = {};

  Future<String> _cacheDir() async {
    if (customCacheDir != null) {
      final dir = Directory(customCacheDir!);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return customCacheDir!;
    }
    if (_resolvedCacheDir != null) return _resolvedCacheDir!;
    try {
      Directory base;
      try {
        base = await getApplicationSupportDirectory();
      } catch (_) {
        base = await getTemporaryDirectory();
      }
      final dir = Directory(p.join(base.path, 'nade_lyrics_cache'));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      _resolvedCacheDir = dir.path;
      return _resolvedCacheDir!;
    } catch (e) {
      debugPrint('LyricsRepository: cache dir error: $e');
      _resolvedCacheDir = Directory.systemTemp.path;
      return _resolvedCacheDir!;
    }
  }

  String _sanitizeKey(String trackId) =>
      trackId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

  Future<File> _cacheFile(String trackId) async {
    final dir = await _cacheDir();
    return File(p.join(dir, '${_sanitizeKey(trackId)}.json'));
  }

  /// Returns lyrics for [track] following the priority order. The result is
  /// cached (memory + disk) on a hit so future lookups are fast/offline.
  ///
  /// Throws [LyricsReadException] if a matching local lyrics file is found but
  /// cannot be read or parsed.
  Future<Lyrics?> getLyrics(Track track) async {
    if (_memory.containsKey(track.id)) {
      return _memory[track.id];
    }

    Lyrics? result;

    try {
      result = await getEmbeddedLyrics(track);
    } catch (e) {
      debugPrint('LyricsRepository: embedded lookup failed: $e');
    }

    result ??= await getLocalLyrics(track);

    if (result == null) {
      result = await getCachedLyrics(track.id);
      if (result != null) {
        result = Lyrics(
          trackId: result.trackId,
          lines: result.lines,
          synchronized: result.synchronized,
          source: result.source ?? 'cache',
          lrcOffset: result.lrcOffset,
        );
      }
    }
    // Local/embedded sources are already available on disk; do not cache raw
    // local files unnecessarily. Cached (including future online) lyrics are
    // returned as-is when no preferred local source exists.

    _memory[track.id] = result;
    return result;
  }

  /// Extracts embedded lyrics from the audio file's tags when possible.
  ///
  /// Best-effort: supports common ID3v2 USLT (unsynchronised lyrics/text)
  /// frames for files accessible on disk. Returns null when unavailable or on
  /// parse failure (never throws into playback).
  Future<Lyrics?> getEmbeddedLyrics(Track track) async {
    if (track.isAsset) return null;
    final path = track.filePath;
    if (path.isEmpty) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    try {
      final bytes = await file.openRead(0, 256 * 1024).fold<List<int>>(
        <int>[],
        (prev, chunk) {
          if (prev.length >= 256 * 1024) return prev;
          prev.addAll(chunk);
          return prev;
        },
      );
      if (bytes.length < 10) return null;

      final text = _tryExtractId3Uslt(bytes);
      if (text == null || text.trim().isEmpty) return null;

      final parsed = LrcParser.parse(track.id, text, source: 'embedded');
      return parsed.isEmpty ? null : parsed;
    } catch (e) {
      debugPrint('LyricsRepository: embedded read error for ${track.id}: $e');
      return null;
    }
  }

  /// Searches for local `.lrc` or plain-text lyric files next to the audio.
  ///
  /// Matching is case-insensitive to handle `.lrc/.LRC/.Lrc` and name variants.
  /// Priority within local files: `.lrc` before `.txt` in the same directory,
  /// audio directory before a `Lyrics/` subdirectory.
  ///
  /// Throws [LyricsReadException] if a matching lyrics file is found but cannot
  /// be read or parsed.
  Future<Lyrics?> getLocalLyrics(Track track) async {
    if (track.isAsset) return null;
    final audioPath = track.filePath;
    if (audioPath.isEmpty) return null;

    final audioFile = File(audioPath);
    final dir = audioFile.parent;
    final base = p.basenameWithoutExtension(audioPath);

    final searchDirs = <Directory>[
      dir,
      Directory(p.join(dir.path, 'Lyrics')),
      Directory(p.join(dir.path, 'lyrics')),
    ];

    LyricsReadException? readError;

    for (final searchDir in searchDirs) {
      if (!await searchDir.exists()) continue;
      final lrc = await _findCaseInsensitive(searchDir, base, const ['.lrc']);
      if (lrc != null) {
        try {
          final lyrics = await _readLyricsFile(track.id, lrc);
          if (lyrics != null && !lyrics.isEmpty) return lyrics;
        } on LyricsReadException catch (e) {
          readError ??= e;
        }
      }
    }
    for (final searchDir in searchDirs) {
      if (!await searchDir.exists()) continue;
      final txt = await _findCaseInsensitive(searchDir, base, const ['.txt']);
      if (txt != null) {
        try {
          final lyrics = await _readLyricsFile(track.id, txt);
          if (lyrics != null && !lyrics.isEmpty) return lyrics;
        } on LyricsReadException catch (e) {
          readError ??= e;
        }
      }
    }

    if (readError != null) throw readError;
    return null;
  }

  Future<File?> _findCaseInsensitive(
    Directory dir,
    String baseName,
    List<String> extensions,
  ) async {
    final wantBase = baseName.toLowerCase();
    final wantExts = extensions.map((e) => e.toLowerCase()).toSet();
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final ext = p.extension(name).toLowerCase();
        if (!wantExts.contains(ext)) continue;
        final stem = p.basenameWithoutExtension(name).toLowerCase();
        if (stem == wantBase) return entity;
      }
    } catch (e) {
      debugPrint('LyricsRepository: scan failed for ${dir.path}: $e');
    }
    return null;
  }

  Future<Lyrics?> _readLyricsFile(String trackId, File file) async {
    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      debugPrint('LyricsRepository: failed to read ${file.path}: $e');
      throw LyricsReadException(file.path, e);
    }

    if (content.trim().isEmpty) return null;
    final ext = p.extension(file.path).toLowerCase();
    try {
      final lyrics = ext == '.lrc'
          ? LrcParser.parseLrc(trackId, content, source: 'file')
          : LrcParser.parsePlain(trackId, content, source: 'file');
      return lyrics.isEmpty ? null : lyrics;
    } catch (e) {
      debugPrint('LyricsRepository: failed to parse ${file.path}: $e');
      throw LyricsReadException(file.path, e);
    }
  }

  /// Reads cached lyrics for [trackId] from disk.
  Future<Lyrics?> getCachedLyrics(String trackId) async {
    try {
      final file = await _cacheFile(trackId);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final lyrics = Lyrics.fromMap(map);
      return lyrics.isEmpty ? null : lyrics;
    } catch (e) {
      debugPrint('LyricsRepository: cache read failed for $trackId: $e');
      return null;
    }
  }

  Future<void> saveLyrics(Lyrics lyrics) async {
    _memory[lyrics.trackId] = lyrics;
    try {
      final file = await _cacheFile(lyrics.trackId);
      await file.writeAsString(jsonEncode(lyrics.toMap()), flush: true);
    } catch (e) {
      debugPrint('LyricsRepository: cache write failed: $e');
    }
  }

  Future<void> removeLyrics(String trackId) async {
    _memory.remove(trackId);
    try {
      final file = await _cacheFile(trackId);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('LyricsRepository: cache remove failed: $e');
    }
  }

  /// Removes cached lyrics for tracks no longer present in [availableTrackIds].
  ///
  /// Used when music files are deleted: only the lyrics cache for removed tracks
  /// is cleared (external `.lrc`/`.txt` files are never deleted).
  Future<void> pruneMissingTracks(Set<String> availableTrackIds) async {
    final toRemove = _memory.keys
        .where((id) => !availableTrackIds.contains(id))
        .toList(growable: false);
    for (final id in toRemove) {
      await removeLyrics(id);
    }
  }

  Future<void> clearCache() async {
    _memory.clear();
    try {
      final dirPath = await _cacheDir();
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('LyricsRepository: clear cache failed: $e');
    }
  }

  // -------------------- Manual lyric offset persistence (per track) ---------

  Future<File> _offsetsFile() async {
    final dir = await _cacheDir();
    return File(p.join(dir, 'lyric_offsets.json'));
  }

  Future<Map<String, int>> _readOffsets() async {
    try {
      final file = await _offsetsFile();
      if (!await file.exists()) return <String, int>{};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <String, int>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final out = <String, int>{};
      decoded.forEach((k, v) {
        if (k is String && v is num) out[k] = v.round();
      });
      return out;
    } catch (e) {
      debugPrint('LyricsRepository: offset read failed: $e');
      return <String, int>{};
    }
  }

  /// Returns the saved manual lyric offset for [trackId] in milliseconds
  /// (0 when none). Offsets are stored per track, not globally.
  Future<int> getLyricOffsetMs(String trackId) async {
    final map = await _readOffsets();
    return map[trackId] ?? 0;
  }

  /// Persists the manual lyric offset for [trackId] in milliseconds.
  /// Pass 0 to clear the stored offset.
  Future<void> setLyricOffsetMs(String trackId, int offsetMs) async {
    try {
      final map = await _readOffsets();
      if (offsetMs == 0) {
        map.remove(trackId);
      } else {
        map[trackId] = offsetMs;
      }
      final file = await _offsetsFile();
      await file.writeAsString(jsonEncode(map), flush: true);
    } catch (e) {
      debugPrint('LyricsRepository: offset write failed: $e');
    }
  }

  // -------------------- Parsing helpers (delegated to [LrcParser]) --------------------

  /// Parses text that may be LRC-timed or plain; prefers synced result when
  /// timed lines are present.
  static Lyrics parseLyricsText(
    String trackId,
    String content, {
    String? source,
  }) => LrcParser.parse(trackId, content, source: source);

  /// Parses LRC content. Supports `[mm:ss.xx]` / `[mm:ss.xxx]` tags, multiple
  /// timestamps per line, and applies `[offset:ms]`; metadata tags are ignored.
  static Lyrics parseLrc(String trackId, String content, {String? source}) =>
      LrcParser.parseLrc(trackId, content, source: source);

  /// Parses plain, untimed lyrics text (metadata-like tags removed).
  static Lyrics parsePlain(String trackId, String content, {String? source}) =>
      LrcParser.parsePlain(trackId, content, source: source);

  // -------------------- Embedded (ID3v2 USLT) best-effort --------------------

  static String? _tryExtractId3Uslt(List<int> bytes) {
    // ID3v2 header: 'ID3' + ver(2) + flags(1) + size(4 syncsafe)
    if (bytes.length < 10) return null;
    if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) return null;
    final ver = bytes[3];
    final tagSize = _syncSafe32(bytes, 6);
    final limit = (10 + tagSize).clamp(0, bytes.length);
    var offset = 10;
    final frameHeaderSize = ver >= 3 ? 10 : 6;

    while (offset + frameHeaderSize <= limit) {
      if (ver >= 3) {
        final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        if (id == '\x00\x00\x00\x00') break;
        final size = ver == 4
            ? _syncSafe32(bytes, offset + 4)
            : _u32(bytes, offset + 4);
        final frameEnd = offset + 10 + size;
        if (size <= 0 || frameEnd > limit) break;
        if (id == 'USLT' || id == 'ULT') {
          final payload = bytes.sublist(offset + 10, frameEnd);
          final text = _decodeUsltPayload(payload, ver);
          if (text != null && text.trim().isNotEmpty) return text;
        }
        offset = frameEnd;
      } else {
        // ID3v2.2: 3-char id, 3-byte size
        final id = String.fromCharCodes(bytes.sublist(offset, offset + 3));
        if (id == '\x00\x00\x00') break;
        final size = _u24(bytes, offset + 3);
        final frameEnd = offset + 6 + size;
        if (size <= 0 || frameEnd > limit) break;
        if (id == 'ULT') {
          final payload = bytes.sublist(offset + 6, frameEnd);
          final text = _decodeUsltPayload(payload, ver);
          if (text != null && text.trim().isNotEmpty) return text;
        }
        offset = frameEnd;
      }
    }
    return null;
  }

  static String? _decodeUsltPayload(List<int> data, int ver) {
    if (data.isEmpty) return null;
    final encoding = data[0];
    var i = 1;
    // language (3 bytes)
    if (i + 3 > data.length) return null;
    i += 3;
    // content descriptor (terminated string) — skip it
    i = _skipTerminatedString(data, i, encoding);
    if (i >= data.length) return null;
    final textBytes = data.sublist(i);
    return _decodeText(textBytes, encoding);
  }

  static int _skipTerminatedString(List<int> data, int start, int encoding) {
    var i = start;
    if (encoding == 1 || encoding == 2) {
      // UTF-16: double-null terminator (aligned)
      while (i + 1 < data.length) {
        if (data[i] == 0 && data[i + 1] == 0) {
          return i + 2;
        }
        i += 2;
      }
      return data.length;
    } else {
      while (i < data.length) {
        if (data[i] == 0) return i + 1;
        i += 1;
      }
      return data.length;
    }
  }

  static String? _decodeText(List<int> bytes, int encoding) {
    if (bytes.isEmpty) return null;
    try {
      switch (encoding) {
        case 0: // ISO-8859-1
          return latin1.decode(bytes, allowInvalid: true);
        case 1: // UTF-16 with BOM
          if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
            return _decodeUtf16Le(bytes.sublist(2));
          } else if (bytes.length >= 2 &&
              bytes[0] == 0xFE &&
              bytes[1] == 0xFF) {
            return _decodeUtf16Be(bytes.sublist(2));
          }
          return _decodeUtf16Le(bytes);
        case 2: // UTF-16BE without BOM
          return _decodeUtf16Be(bytes);
        case 3: // UTF-8
          return utf8.decode(bytes, allowMalformed: true);
        default:
          return utf8.decode(bytes, allowMalformed: true);
      }
    } catch (_) {
      return null;
    }
  }

  static String _decodeUtf16Le(List<int> bytes) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }

  static String _decodeUtf16Be(List<int> bytes) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  static int _syncSafe32(List<int> b, int o) =>
      ((b[o] & 0x7F) << 21) |
      ((b[o + 1] & 0x7F) << 14) |
      ((b[o + 2] & 0x7F) << 7) |
      (b[o + 3] & 0x7F);

  static int _u32(List<int> b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _u24(List<int> b, int o) =>
      (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
}

/// Provider for the singleton [LyricsRepository].
final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  return LyricsRepository();
});
