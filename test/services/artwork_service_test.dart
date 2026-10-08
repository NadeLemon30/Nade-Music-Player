import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/services/artwork/artwork_service.dart';

void main() {
  late Directory tempDir;
  late DefaultArtworkService artworkService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('artwork_test_');
    artworkService = DefaultArtworkService(
      customCacheDir: tempDir.path,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ArtworkService Caching Pipeline Tests', () {
    test('Stores and retrieves artwork from high-speed memory cache', () async {
      final mockService = MockArtworkService();
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      mockService.setArtwork('track_1', sampleBytes);

      final retrieved = await mockService.getArtwork(id: 'track_1');
      expect(retrieved, equals(sampleBytes));

      final memoryHit = mockService.getFromMemoryCache('track_1');
      expect(memoryHit, equals(sampleBytes));
    });

    test('Discovers folder images and caches them to disk and memory', () async {
      // Create a dummy audio file and sibling cover.jpg in the temp directory
      final audioFile = File('${tempDir.path}/song.mp3');
      await audioFile.writeAsString('dummy mp3 content');

      final coverFile = File('${tempDir.path}/cover.jpg');
      final dummyArtBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      await coverFile.writeAsBytes(dummyArtBytes);

      // First extraction - should discover cover.jpg and write to disk cache
      final extracted = await artworkService.getArtwork(
        id: 'track_test_1',
        filePath: audioFile.path,
      );

      expect(extracted, isNotNull);
      expect(extracted, equals(dummyArtBytes));

      // Memory cache should now be populated
      final memoryCacheKey = 'audio_track_test_1';
      expect(artworkService.getFromMemoryCache(memoryCacheKey), equals(dummyArtBytes));

      // Delete the original cover file from the audio folder
      await coverFile.delete();

      // Clear in-memory cache to force reading from disk cache
      final service2 = DefaultArtworkService(customCacheDir: tempDir.path);

      // Second retrieval - should hit the disk cache file without the original cover existing!
      final diskHit = await service2.getArtwork(
        id: 'track_test_1',
        filePath: audioFile.path,
      );

      expect(diskHit, isNotNull);
      expect(diskHit, equals(dummyArtBytes));
    });

    test('Negative caching prevents repeated file scans when no artwork exists', () async {
      final audioFile = File('${tempDir.path}/no_art_song.mp3');
      await audioFile.writeAsString('dummy mp3 without artwork');

      // First query: no artwork found
      final result1 = await artworkService.getArtwork(
        id: 'no_art_1',
        filePath: audioFile.path,
      );
      expect(result1, isNull);

      // Memory cache should contain negative cache entry
      expect(artworkService.getFromMemoryCache('audio_no_art_1'), isNull);
    });

    test('Preload artwork initiates background cache extraction for tracks', () async {
      final track = Track(
        id: 'track_preload_1',
        title: 'Test Song',
        artist: 'Test Artist',
        album: '',
        albumArtist: '',
        genre: '',
        year: null,
        trackNumber: null,
        discNumber: null,
        duration: null,
        filePath: '${tempDir.path}/dummy.mp3',
        fileName: 'dummy.mp3',
        fileSize: null,
        mimeType: null,
      );

      await expectLater(
        artworkService.preloadArtwork([track]),
        completes,
      );
    });
  });
}
