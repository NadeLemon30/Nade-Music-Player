import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/models/track.dart';

void main() {
  group('Track model', () {
    const track = Track(
      id: '1',
      title: 'Get Lucky',
      artist: 'Daft Punk',
      album: 'Random Access Memories',
      albumArtist: 'Daft Punk',
      genre: 'Disco / Funk',
      year: 2013,
      trackNumber: 8,
      discNumber: 1,
      duration: Duration(minutes: 6, seconds: 9),
      filePath: '/storage/emulated/0/Music/get_lucky.mp3',
      fileName: 'get_lucky.mp3',
      fileSize: 14782012,
      mimeType: 'audio/mpeg',
      isAsset: false,
      albumArtUri: 'content://media/external/audio/albumart/12',
    );

    test('supports value equality and copyWith', () {
      final copy = track.copyWith(title: 'Get Lucky (Radio Edit)');
      expect(copy.id, track.id);
      expect(copy.title, 'Get Lucky (Radio Edit)');
      expect(copy.artist, track.artist);
      expect(copy.albumArtist, 'Daft Punk');
      expect(copy.discNumber, 1);
      expect(copy.fileSize, 14782012);
      expect(copy == track, false);

      final identicalCopy = track.copyWith();
      expect(identicalCopy, track);
      expect(identicalCopy.hashCode, track.hashCode);
    });

    test('serializes toMap and deserializes fromMap accurately', () {
      final map = track.toMap();
      expect(map['id'], '1');
      expect(map['title'], 'Get Lucky');
      expect(map['artist'], 'Daft Punk');
      expect(map['album'], 'Random Access Memories');
      expect(map['albumArtist'], 'Daft Punk');
      expect(map['genre'], 'Disco / Funk');
      expect(map['year'], 2013);
      expect(map['trackNumber'], 8);
      expect(map['discNumber'], 1);
      expect(map['durationMs'], const Duration(minutes: 6, seconds: 9).inMilliseconds);
      expect(map['filePath'], '/storage/emulated/0/Music/get_lucky.mp3');
      expect(map['fileName'], 'get_lucky.mp3');
      expect(map['fileSize'], 14782012);
      expect(map['mimeType'], 'audio/mpeg');

      final reconstructed = Track.fromMap(map);
      expect(reconstructed.id, track.id);
      expect(reconstructed.title, track.title);
      expect(reconstructed.albumArtist, track.albumArtist);
      expect(reconstructed.discNumber, track.discNumber);
      expect(reconstructed.duration, track.duration);
      expect(reconstructed.fileSize, track.fileSize);
      expect(reconstructed.mimeType, track.mimeType);
      expect(reconstructed, track);
    });

    test('backward-compatible getters work as expected', () {
      expect(track.assetPath, track.filePath);
      expect(track.size, track.fileSize);
    });
  });
}
