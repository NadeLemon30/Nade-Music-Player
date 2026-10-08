import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/models/album.dart';
import 'package:nades_music_player/models/artist.dart';
import 'package:nades_music_player/models/folder_node.dart';
import 'package:nades_music_player/models/genre.dart';
import 'package:nades_music_player/models/search_results.dart';
import 'package:nades_music_player/models/track.dart';

void main() {
  group('SearchResults Model & SearchFilter Enum', () {
    test('SearchFilter labels are defined correctly', () {
      expect(SearchFilter.all.label, 'All');
      expect(SearchFilter.songs.label, 'Songs');
      expect(SearchFilter.artists.label, 'Artists');
      expect(SearchFilter.albums.label, 'Albums');
      expect(SearchFilter.genres.label, 'Genres');
      expect(SearchFilter.folders.label, 'Folders');
    });

    test('SearchResults correctly reports emptiness and total counts', () {
      const empty = SearchResults();
      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);
      expect(empty.totalCount, 0);

      const results = SearchResults(
        query: 'mete',
        tracks: [
          Track(
            id: '1',
            title: 'Numb',
            artist: 'Linkin Park',
            album: 'Meteora',
            albumArtist: '',
            genre: '',
            year: null,
            trackNumber: null,
            discNumber: null,
            duration: null,
            filePath: '/music/numb.mp3',
            fileName: 'numb.mp3',
            fileSize: null,
            mimeType: null,
          ),
          Track(
            id: '2',
            title: 'Faint',
            artist: 'Linkin Park',
            album: 'Meteora',
            albumArtist: '',
            genre: '',
            year: null,
            trackNumber: null,
            discNumber: null,
            duration: null,
            filePath: '/music/faint.mp3',
            fileName: 'faint.mp3',
            fileSize: null,
            mimeType: null,
          ),
        ],
        artists: [
          Artist(
            id: 'linkin_park',
            name: 'Linkin Park',
            trackCount: 20,
          ),
        ],
        albums: [
          Album(
            id: 1,
            title: 'Meteora',
            albumArtist: 'Linkin Park',
            artistId: 1,
            year: null,
            trackCount: 13,
            artworkKey: '1',
          ),
        ],
        folders: [
          FolderNode(
            path: '/music/Linkin Park/Meteora',
            name: 'Meteora',
            isFolder: true,
          ),
        ],
      );

      expect(results.isEmpty, isFalse);
      expect(results.isNotEmpty, isTrue);
      expect(results.totalCount, 5);
      expect(results.tracks.length, 2);
      expect(results.artists.length, 1);
      expect(results.albums.length, 1);
      expect(results.folders.length, 1);
      expect(results.genres.length, 0);
    });

    test('SearchResults supports copyWith and equality', () {
      const r1 = SearchResults(
        query: 'rock',
        genres: [Genre(id: 'rock', name: 'Rock', trackCount: 10)],
      );
      final r2 = r1.copyWith();
      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));

      final r3 = r1.copyWith(query: 'pop');
      expect(r1 == r3, isFalse);
      expect(r1.toString(), contains('SearchResults(query: "rock"'));
    });
  });
}
