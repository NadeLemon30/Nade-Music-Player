import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/library_controller.dart';
import '../../player/player_controller.dart';
import '../../services/playback/play_history_service.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/track_tile.dart';
import 'history_screen.dart';

/// "Recently Played" — a focused view of what you've listened to recently
/// (Phase 3H.23). Reuses the existing [TrackTile] list component; this is a
/// different, lighter surface than the full metadata-heavy [HistoryScreen].
class RecentlyPlayedScreen extends ConsumerWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(recentlyPlayedProvider);
    final entries = entriesAsync.value ?? const <PlayHistoryEntry>[];
    final theme = Theme.of(context);

    // Lazy stale-history cleanup (3H.29): drop entries whose music file has
    // been deleted, only when this screen is shown (not via a background scan).
    final library = ref.read(libraryControllerProvider);
    final availableIds = library.tracks
        .where((t) => t.isAvailable)
        .map((t) => t.id)
        .toSet();
    ref.read(playHistoryServiceProvider).pruneMissingTracks(availableIds);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recently Played'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Full history',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: entries.isEmpty
          ? _buildEmpty(theme)
          : _buildList(context, ref, entries),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_toggle_off,
            size: 72,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('Nothing played yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Tracks you play will show up here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<PlayHistoryEntry> entries,
  ) {
    final playerState = ref.watch(playerNotifierProvider);
    final notifier = ref.read(playerNotifierProvider.notifier);

    return ListView.separated(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final track = entries[index].track;
        final isCurrent = playerState.currentTrack?.id == track.id;
        return TrackTile(
          track: track,
          isCurrent: isCurrent,
          isPlaying: isCurrent && playerState.isPlaying,
          showAlbum: false,
          showDuration: false,
          onTap: () => notifier.playTrack(track),
          onMoreOptions: () => ref
              .read(playHistoryServiceProvider)
              .removeEntry(track.id),
        );
      },
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 0.5,
        indent: 16,
        endIndent: 16,
      ),
    );
  }
}
