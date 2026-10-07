import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/audio_metadata.dart';
import 'package:test_app/services/metadata/metadata_extractor_service.dart';

void main() {
  group('DefaultMetadataExtractorService', () {
    final service = DefaultMetadataExtractorService();

    test('extracts FileInformation with MIME type correctly', () {
      final fileInfo = service.extractFileInfo(
        '/storage/emulated/0/Music/01 - Numb.mp3',
        fileSize: 7458921,
      );

      expect(fileInfo.filePath, '/storage/emulated/0/Music/01 - Numb.mp3');
      expect(fileInfo.fileName, '01 - Numb.mp3');
      expect(fileInfo.fileSize, 7458921);
      expect(fileInfo.mimeType, 'audio/mpeg');
    });

    test('combines clean FileInformation and MusicMetadata into Track', () {
      const fileInfo = FileInformation(
        filePath: '/storage/emulated/0/Music/Linkin Park/Meteora/01 - Numb.mp3',
        fileName: '01 - Numb.mp3',
        fileSize: 7458921,
        mimeType: 'audio/mpeg',
      );

      const metadata = MusicMetadata(
        title: 'Numb',
        artist: 'Linkin Park',
        album: 'Meteora',
        albumArtist: 'Linkin Park',
        genre: 'Alternative Rock',
        year: 2003,
        trackNumber: 1,
        duration: Duration(minutes: 3, seconds: 7),
      );

      final track = service.combine(
        id: '4001',
        fileInfo: fileInfo,
        metadata: metadata,
      );

      expect(track.id, '4001');
      expect(track.title, 'Numb');
      expect(track.artist, 'Linkin Park');
      expect(track.album, 'Meteora');
      expect(track.albumArtist, 'Linkin Park');
      expect(track.genre, 'Alternative Rock');
      expect(track.year, 2003);
      expect(track.trackNumber, 1);
      expect(track.duration, const Duration(minutes: 3, seconds: 7));
      expect(track.filePath, '/storage/emulated/0/Music/Linkin Park/Meteora/01 - Numb.mp3');
      expect(track.fileName, '01 - Numb.mp3');
      expect(track.fileSize, 7458921);
      expect(track.mimeType, 'audio/mpeg');
    });

    test('parses track number and title from filename when tags are missing', () {
      const emptyMetadata = MusicMetadata(
        title: '<unknown>',
        artist: '<unknown>',
      );

      final enriched = service.sanitizeAndEnrich(
        emptyMetadata,
        fileName: '01 - Numb.mp3',
      );

      expect(enriched.title, 'Numb');
      expect(enriched.trackNumber, 1);
      expect(enriched.artist, 'Unknown Artist');
    });

    test('parses artist and title from filename pattern Artist - Title.mp3', () {
      const emptyMetadata = MusicMetadata(
        title: '',
        artist: '',
      );

      final enriched = service.sanitizeAndEnrich(
        emptyMetadata,
        fileName: 'Linkin Park - Numb.flac',
      );

      expect(enriched.title, 'Numb');
      expect(enriched.artist, 'Linkin Park');
    });
  });
}
