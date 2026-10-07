import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/album.dart';
import 'package:test_app/models/track.dart';
import 'package:test_app/services/artwork/artwork_service.dart';
import 'package:test_app/widgets/album_art.dart';

void main() {
  // 1x1 transparent PNG bytes for widget test rendering
  final transparentPng = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  testWidgets('AlbumArt renders placeholder icon when artUrl is null',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlbumArt(
            size: 80,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });

  testWidgets('AlbumArt renders album placeholder icon when album is provided',
      (WidgetTester tester) async {
    const album = Album(
      id: 1,
      title: 'Meteora',
      albumArtist: 'Linkin Park',
      artistId: 1,
      year: null,
      trackCount: 13,
      artworkKey: '1',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AlbumArt(
            album: album,
            size: 80,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.album), findsOneWidget);
  });

  testWidgets('AlbumArt renders cached memory image when available',
      (WidgetTester tester) async {
    final mockService = MockArtworkService();
    mockService.setArtwork('track_art_1', transparentPng);

    const track = Track(
      id: 'track_art_1',
      title: 'Numb',
      artist: 'Linkin Park',
      album: '',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: null,
      filePath: '/dummy/numb.mp3',
      fileName: 'numb.mp3',
      fileSize: null,
      mimeType: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artworkServiceProvider.overrideWithValue(mockService),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AlbumArt(
              track: track,
              size: 80,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
      'AlbumArt resolves a numeric track art key as album artwork (album id)',
      (WidgetTester tester) async {
    final mockService = MockArtworkService();
    // A numeric art key on a track is the MediaStore *album* id
    // (scanner sets albumArtUri = song.albumId), so it must be queried as
    // album artwork — mirroring the albums list which resolves via
    // ArtworkSourceType.album.
    mockService.setArtwork(
      '42',
      transparentPng,
      sourceType: ArtworkSourceType.album,
    );

    const track = Track(
      id: 'song_1',
      title: 'Numb',
      artist: 'Linkin Park',
      album: 'Meteora',
      albumArtist: 'Linkin Park',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: null,
      filePath: '/dummy/numb.mp3',
      fileName: 'numb.mp3',
      fileSize: null,
      mimeType: null,
      albumId: 42,
      albumArtUri: '42',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artworkServiceProvider.overrideWithValue(mockService),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AlbumArt(
              track: track,
              artUrl: track.albumArtUri,
              size: 80,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
      'AlbumArt resolves a numeric track id (no album art key) as audio artwork, not album',
      (WidgetTester tester) async {
    final mockService = MockArtworkService();
    // When a track has no album-art key (albumArtUri == null) the id falls
    // back to track.id, a MediaStore *song* id. It must NOT be routed as album
    // artwork, or queryArtwork could return a different album's art / collide
    // cache keys across songs. It must resolve as per-audio artwork.
    mockService.setArtwork(
      '123',
      transparentPng,
      sourceType: ArtworkSourceType.audio,
    );

    const track = Track(
      id: '123',
      title: 'Numb',
      artist: 'Linkin Park',
      album: '',
      albumArtist: '',
      genre: '',
      year: null,
      trackNumber: null,
      discNumber: null,
      duration: null,
      filePath: '/dummy/numb.mp3',
      fileName: 'numb.mp3',
      fileSize: null,
      mimeType: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artworkServiceProvider.overrideWithValue(mockService),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AlbumArt(
              track: track,
              size: 80,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(Image), findsOneWidget);
  });
}
