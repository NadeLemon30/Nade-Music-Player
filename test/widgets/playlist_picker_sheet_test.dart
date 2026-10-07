import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/models/playlist.dart';
import 'package:test_app/models/track.dart';
import 'package:test_app/services/playlists/playlist_service.dart';
import 'package:test_app/widgets/playlists/playlist_picker.dart';

import '../helpers/fake_audio_player_service.dart';

/// Minimal host that opens the multi-track picker on demand.
class PickerHost extends ConsumerWidget {
  final List<Track>? tracks;
  final void Function(Playlist? picked)? onPicked;

  const PickerHost({super.key, this.tracks, this.onPicked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final picked = await showPlaylistPicker(
              context: context,
              ref: ref,
              tracks: tracks,
            );
            onPicked?.call(picked);
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];

  ProviderContainer buildContainer() {
    return ProviderContainer(
      overrides: [
        playlistServiceProvider.overrideWithValue(PlaylistService(null)),
      ],
    );
  }

  Future<void> pumpPicker(
    WidgetTester tester,
    ProviderContainer container,
    List<Track> tracks,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PickerHost(tracks: tracks)),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('adds multiple tracks without duplicating an existing one',
      (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final service = container.read(playlistServiceProvider);
    final mix = await service.createPlaylist('Mix');
    // 'a' is already in the playlist: adding the selection must not repeat it.
    await service.addTrackToPlaylist(mix.id, tracks[0]);

    await pumpPicker(tester, container, tracks);

    expect(find.text('Choose Playlist'), findsOneWidget);
    expect(find.text('3 songs selected'), findsOneWidget);

    await tester.tap(find.text('Mix'));
    await tester.pumpAndSettle();

    expect(service.tracksForPlaylist(mix.id).map((t) => t.id), ['a', 'b', 'c']);
    expect(find.text('Added 2 songs to "Mix"'), findsOneWidget);
  });

  testWidgets('marks a playlist that already holds every selected track',
      (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final service = container.read(playlistServiceProvider);
    final mix = await service.createPlaylist('Mix');
    await service.addTrackToPlaylist(mix.id, tracks[0]);

    await pumpPicker(tester, container, [tracks[0]]);

    expect(find.text('Choose Playlist'), findsNothing);
    expect(find.text('Add to playlist'), findsOneWidget);
    expect(find.textContaining('Already added'), findsOneWidget);

    await tester.tap(find.text('Mix'));
    await tester.pumpAndSettle();

    // Nothing changed — the composite PK / idempotent add keeps it a no-op.
    expect(service.tracksForPlaylist(mix.id).map((t) => t.id), ['a']);
  });

testWidgets('creates a new playlist through the name dialog (spec 19)',
    (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final service = container.read(playlistServiceProvider);

    await pumpPicker(tester, container, tracks);

    await tester.tap(find.text('New playlist'));
    await tester.pumpAndSettle();

    // Name dialog appears with the seeded name and Cancel / Create actions.
    expect(find.text('New Playlist'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Song a'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);

    // Nothing is created until Create is confirmed.
    expect(service.count, 0);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(service.count, 1);
    final created = service.playlists.single;
    // Name seeded from the first selected track's title.
    expect(created.name, 'Song a');
    expect(service.tracksForPlaylist(created.id).map((t) => t.id),
        ['a', 'b', 'c']);
  });

  testWidgets('select-only picker returns the chosen playlist without adding tracks (spec 18)',
    (tester) async {
    final container = buildContainer();
    addTearDown(container.dispose);

    final service = container.read(playlistServiceProvider);
    await service.createPlaylist('Mix');

    Playlist? picked;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: PickerHost(tracks: null, onPicked: (p) => picked = p),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Pure selection mode: no add title/subtitle, just the list.
    expect(find.text('Choose Playlist'), findsOneWidget);
    expect(find.textContaining('songs selected'), findsNothing);
    expect(find.text('Mix'), findsOneWidget);

    await tester.tap(find.text('Mix'));
    await tester.pumpAndSettle();

    // The chosen playlist is returned and nothing was mutated.
    expect(picked, isNotNull);
    expect(picked!.name, 'Mix');
    expect(service.trackCount(picked!.id), 0);
  });
}