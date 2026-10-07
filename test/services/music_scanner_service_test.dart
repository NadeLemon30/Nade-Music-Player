import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/track.dart';
import 'package:test_app/services/scanner/music_scanner_service.dart';

void main() {
  group('MockMusicScannerService', () {
    const testTrack1 = Track(
      id: '101',
      title: 'Midnight City',
      artist: 'M83',
      album: 'Hurry Up, We\'re Dreaming',
      albumArtist: 'M83',
      genre: 'Synthwave',
      year: 2011,
      trackNumber: 5,
      discNumber: 1,
      duration: Duration(minutes: 4, seconds: 4),
      filePath: '/storage/emulated/0/Music/midnight_city.mp3',
      fileName: 'midnight_city.mp3',
      fileSize: 5800000,
      mimeType: 'audio/mpeg',
    );

    const testTrack2 = Track(
      id: '102',
      title: 'Starboy',
      artist: 'The Weeknd',
      album: 'Starboy',
      albumArtist: 'The Weeknd',
      genre: 'Pop',
      year: 2016,
      trackNumber: 1,
      discNumber: 1,
      duration: Duration(minutes: 3, seconds: 50),
      filePath: '/storage/emulated/0/Music/starboy.mp3',
      fileName: 'starboy.mp3',
      fileSize: 4900000,
      mimeType: 'audio/mpeg',
    );

    test('returns tracks on scan when permission is granted', () async {
      final scanner = MockMusicScannerService(
        tracks: [testTrack1, testTrack2],
        permissionGranted: true,
      );
      addTearDown(scanner.dispose);

      final result = await scanner.scan();
      expect(result.length, 2);
      expect(result[0].title, 'Midnight City');
      expect(result[1].artist, 'The Weeknd');
    });

    test('returns empty list when permission is denied', () async {
      final scanner = MockMusicScannerService(
        tracks: [testTrack1, testTrack2],
        permissionGranted: false,
      );
      addTearDown(scanner.dispose);

      final result = await scanner.scan();
      expect(result, isEmpty);
    });

    test('emits updates via scanChanges stream', () async {
      final scanner = MockMusicScannerService(tracks: [testTrack1]);
      addTearDown(scanner.dispose);

      final expectation = expectLater(
        scanner.scanChanges(),
        emitsInOrder([
          [testTrack1],
          [testTrack1, testTrack2],
        ]),
      );

      scanner.emitChanges([testTrack1]);
      scanner.emitChanges([testTrack1, testTrack2]);

      await expectation;
    });

    test('Riverpod provider override injects scanner cleanly', () async {
      final mockScanner = MockMusicScannerService(tracks: [testTrack1]);
      addTearDown(mockScanner.dispose);

      final container = ProviderContainer(
        overrides: [
          musicScannerServiceProvider.overrideWithValue(mockScanner),
        ],
      );
      addTearDown(container.dispose);

      final scanner = container.read(musicScannerServiceProvider);
      final tracks = await scanner.scan();

      expect(tracks.length, 1);
      expect(tracks.first.id, '101');
    });
  });
}
