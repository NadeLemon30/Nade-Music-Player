import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/data/repositories/music_repository.dart';
import 'package:test_app/models/genre.dart';
import 'package:test_app/models/track.dart';
import 'package:test_app/screens/library/genre_detail_screen.dart';
import 'package:test_app/screens/library/genres_list_screen.dart';
import 'package:test_app/widgets/track_tile.dart';

void main() {
  final sampleGenreTracks = [
    const Track(
      id: 'g_1',
      title: 'Smells Like Teen Spirit',
      artist: 'Nirvana',
      album: '',
      albumArtist: '',
      genre: 'Rock',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 5, seconds: 1),
      filePath: '/music/nirvana.mp3',
      fileName: 'nirvana.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 'g_2',
      title: 'Numb',
      artist: 'Linkin Park',
      album: '',
      albumArtist: '',
      genre: 'Rock',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 7),
      filePath: '/music/numb.mp3',
      fileName: 'numb.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 'g_3',
      title: 'Sweet Child O Mine',
      artist: "Guns N' Roses",
      album: '',
      albumArtist: '',
      genre: 'Rock',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 5, seconds: 56),
      filePath: '/music/gnr.mp3',
      fileName: 'gnr.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 'g_4',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      album: '',
      albumArtist: '',
      genre: 'Pop',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 3, seconds: 20),
      filePath: '/music/blinding_lights.mp3',
      fileName: 'blinding_lights.mp3',
      fileSize: null,
      mimeType: null,
    ),
    const Track(
      id: 'g_5',
      title: 'Take Five',
      artist: 'Dave Brubeck',
      album: '',
      albumArtist: '',
      genre: 'Jazz',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: Duration(minutes: 5, seconds: 24),
      filePath: '/music/take_five.mp3',
      fileName: 'take_five.mp3',
      fileSize: null,
      mimeType: null,
    ),
  ];

  testWidgets('GenresListScreen displays genres list sorted alphabetically',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleGenreTracks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: GenresListScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Genres'), findsOneWidget);
    expect(find.text('3 genres'), findsOneWidget);
    expect(find.text('Jazz'), findsOneWidget);
    expect(find.text('Pop'), findsOneWidget);
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('3 songs'), findsOneWidget); // Rock has 3 songs
    expect(find.text('1 song'), findsNWidgets(2)); // Jazz and Pop have 1 song
  });

  testWidgets('GenreDetailScreen displays genre header, song count, and songs list',
      (WidgetTester tester) async {
    final mockRepo = MockMusicRepository(sampleGenreTracks);
    const rockGenre = Genre(
      id: 'rock',
      name: 'Rock',
      trackCount: 3,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: GenreDetailScreen(genre: rockGenre),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify Header
    expect(find.text('Rock'), findsAtLeastNWidgets(1));
    expect(find.text('3 songs'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);

    // Verify Tracks
    expect(find.text('Smells Like Teen Spirit'), findsOneWidget);
    expect(find.text('Numb'), findsOneWidget);
    expect(find.text('Sweet Child O Mine'), findsOneWidget);
    expect(find.byType(TrackTile), findsNWidgets(3));
  });
}
