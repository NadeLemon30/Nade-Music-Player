import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/data/repositories/lyrics_repository.dart';
import 'package:nades_music_player/models/track.dart';
import 'package:path/path.dart' as p;

Track buildTrack({
  String id = 'track-1',
  String filePath = '/Music/track.mp3',
}) {
  return Track(
    id: id,
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    genre: '',
    year: null,
    trackNumber: null,
    discNumber: null,
    duration: const Duration(minutes: 3),
    filePath: filePath,
    fileName: p.basename(filePath),
    fileSize: null,
    mimeType: null,
  );
}

void main() {
  group('LyricsRepository imported lyrics', () {
    late Directory tempDir;
    late LyricsRepository repository;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('nade_lyrics_test_');
      repository = LyricsRepository(customCacheDir: tempDir.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('imports and persists synchronized LRC content', () async {
      final track = buildTrack();

      final lyrics = await repository.importLyrics(
        track,
        '[offset:250]\n[00:01.00]Hello\n[00:03.50]World',
        fileName: 'track.lrc',
      );

      expect(lyrics.source, LyricsRepository.importedSource);
      expect(lyrics.synchronized, isTrue);
      expect(lyrics.lines.map((line) => line.text), ['Hello', 'World']);
      expect(lyrics.lrcOffset, const Duration(milliseconds: 250));

      final reopened = LyricsRepository(customCacheDir: tempDir.path);
      final cached = await reopened.getCachedLyrics(track.id);
      expect(cached, isNotNull);
      expect(cached!.source, LyricsRepository.importedSource);
      expect(cached.lines.length, 2);
    });

    test('imported lyrics take precedence over a local .lrc file', () async {
      final audioDir = Directory(p.join(tempDir.path, 'audio'))..createSync();
      final audio = File(p.join(audioDir.path, 'song.mp3'))
        ..writeAsStringSync('not audio');
      File(p.join(audioDir.path, 'song.lrc'))
          .writeAsStringSync('[00:00.00]Local lyric');

      final track = buildTrack(filePath: audio.path);
      await repository.importLyrics(
        track,
        '[00:00.00]Imported lyric',
        fileName: 'song.lrc',
      );

      final reopened = LyricsRepository(customCacheDir: tempDir.path);
      final resolved = await reopened.getLyrics(track);

      expect(resolved, isNotNull);
      expect(resolved!.source, LyricsRepository.importedSource);
      expect(resolved.lines.single.text, 'Imported lyric');
    });

    test(
      'removing imported lyrics falls back to the local .lrc file',
      () async {
        final audioDir = Directory(p.join(tempDir.path, 'audio'))..createSync();
        final audio = File(p.join(audioDir.path, 'song.mp3'))
          ..writeAsStringSync('not audio');
        File(p.join(audioDir.path, 'song.lrc'))
            .writeAsStringSync('[00:00.00]Local lyric');

        final track = buildTrack(filePath: audio.path);
        await repository.importLyrics(
          track,
          '[00:00.00]Imported lyric',
          fileName: 'song.lrc',
        );
        await repository.removeImportedLyrics(track.id);

        final reopened = LyricsRepository(customCacheDir: tempDir.path);
        final resolved = await reopened.getLyrics(track);

        expect(resolved, isNotNull);
        expect(resolved!.source, 'file');
        expect(resolved.lines.single.text, 'Local lyric');
      },
    );

    test('decodes UTF-8 byte-order-mark content', () async {
      final track = buildTrack();
      final bytes = <int>[
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('[00:00.00]Bom lyric'),
      ];

      final lyrics = await repository.importLyricsBytes(track, bytes);

      expect(lyrics.synchronized, isTrue);
      expect(lyrics.lines.single.text, 'Bom lyric');
    });

    test('rejects empty or lyric-less content', () async {
      final track = buildTrack();

      expect(
        () => repository.importLyrics(track, '   '),
        throwsA(isA<LyricsReadException>()),
      );
      expect(
        () => repository.importLyrics(track, '[ar:Artist]\n[ti:Song]'),
        throwsA(isA<LyricsReadException>()),
      );
    });
  });
}
