import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/core/lyrics/lyrics_file_picker.dart';
import 'package:nades_music_player/data/repositories/lyrics_repository.dart';
import 'package:nades_music_player/models/lyrics.dart';
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/player/player_controller.dart';
import 'package:nades_music_player/screens/player/lyrics_screen.dart';
import 'package:nades_music_player/services/favorites/favorites_service.dart';
import 'package:nades_music_player/services/playback/play_history_service.dart';

import '../helpers/fake_audio_player_service.dart';

/// In-memory lyrics store so the widget tests never touch the filesystem.
class FakeLyricsRepository extends LyricsRepository {
  Lyrics? stored;

  @override
  Future<Lyrics?> getLyrics(Track track) async => stored;

  @override
  Future<Lyrics?> getCachedLyrics(String trackId) async => stored;

  @override
  Future<void> saveLyrics(Lyrics lyrics) async => stored = lyrics;

  @override
  Future<void> removeLyrics(String trackId) async => stored = null;

  @override
  Future<void> removeImportedLyrics(String trackId) async {
    if (stored?.source == LyricsRepository.importedSource) stored = null;
  }

  @override
  Future<int> getLyricOffsetMs(String trackId) async => 0;

  @override
  Future<void> setLyricOffsetMs(String trackId, int offsetMs) async {}
}

void main() {
  Future<void> flush(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<ProviderContainer> pumpLyrics(
    WidgetTester tester, {
    required FakeLyricsRepository repository,
    LyricsFilePicker? picker,
  }) async {
    final container = ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(FakeAudioPlayerService()),
        playHistoryServiceProvider.overrideWith(
          (ref) => NoopPlayHistoryService(),
        ),
        favoritesServiceProvider.overrideWithValue(FavoritesService(null)),
        lyricsRepositoryProvider.overrideWithValue(repository),
        if (picker != null) lyricsFilePickerProvider.overrideWithValue(picker),
      ],
    );
    addTearDown(container.dispose);

    await container.read(playerNotifierProvider.notifier).setQueue([
      testTrack('a'),
    ], autoPlay: false);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LyricsScreen()),
      ),
    );
    await flush(tester);
    return container;
  }

  testWidgets('offers to add a lyrics file when none are found', (
    tester,
  ) async {
    await pumpLyrics(tester, repository: FakeLyricsRepository());

    expect(find.text('No lyrics available'), findsOneWidget);
    expect(find.text('Add Lyrics File'), findsOneWidget);
  });

  testWidgets('importing a picked .lrc file displays its lyrics', (
    tester,
  ) async {
    final repository = FakeLyricsRepository();
    await pumpLyrics(
      tester,
      repository: repository,
      picker: () async => PickedLyricsFile(
        name: 'a.lrc',
        bytes: Uint8List.fromList(
          utf8.encode('[00:00.00]Imported line one\n[00:05.00]Line two'),
        ),
      ),
    );

    await tester.tap(find.text('Add Lyrics File'));
    await flush(tester);

    expect(find.text('Imported line one'), findsOneWidget);
    expect(find.text('Line two'), findsOneWidget);
    expect(find.byTooltip('Remove imported lyrics'), findsOneWidget);
    expect(repository.stored?.source, LyricsRepository.importedSource);
  });

  testWidgets('removing imported lyrics restores the unavailable state', (
    tester,
  ) async {
    final repository = FakeLyricsRepository();
    await pumpLyrics(
      tester,
      repository: repository,
      picker: () async => PickedLyricsFile(
        name: 'a.lrc',
        bytes: Uint8List.fromList(utf8.encode('[00:00.00]Temporary lyric')),
      ),
    );

    await tester.tap(find.text('Add Lyrics File'));
    await flush(tester);
    expect(find.text('Temporary lyric'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove imported lyrics'));
    await flush(tester);

    expect(find.text('No lyrics available'), findsOneWidget);
    expect(repository.stored, isNull);
  });
}
