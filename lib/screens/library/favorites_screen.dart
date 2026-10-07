import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/library_controller.dart';
import '../../player/player_controller.dart';
import '../../services/favorites/favorites_service.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/track_tile.dart';
import 'songs_list_screen.dart';

/// "Favorites" — the user's favorited tracks (Phase 3I).
///
/// Lists favorited songs in the configured [FavoriteSort] order, with each
/// tile offering quick favorite toggling (unfavorite). Reuses the existing
/// [TrackTile] component, which already wires the favorite heart into the
/// track-context options sheet.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final service = ref.watch(favoritesServiceProvider);

    // Lazy stale-favorite cleanup (3I): drop favorites whose music file has
    // been deleted, only when this screen is shown (not via a background
    // scan), matching the history-prune pattern.
    final library = ref.read(libraryControllerProvider);
    final availableIds = library.tracks
        .where((t) => t.isAvailable)
        .map((t) => t.id)
        .toSet();
    ref.read(favoritesServiceProvider).pruneMissingTracks(availableIds);

    final favoritesAsync = ref.watch(favoriteIdsProvider);
    final count = service.favoriteIds.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: [
          if (service.count > 0)
            IconButton(
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              onPressed: () => _showSortMenu(context, ref),
            ),
        ],
      ),
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: count == 0
          ? _buildEmpty(context, theme)
          : _buildList(context, ref, favoritesAsync.value ?? const {}),
    );
  }

  void _showSortMenu(BuildContext context, WidgetRef ref) {
    final service = ref.read(favoritesServiceProvider);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Sort favorites',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ...FavoriteSort.values.map((option) {
              return ListTile(
                leading: Icon(
                  option == service.sort
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: option == service.sort
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                title: Text(_sortLabel(option)),
                onTap: () {
                  service.sort = option;
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _sortLabel(FavoriteSort option) {
    return switch (option) {
      FavoriteSort.newest => 'Recently added',
      FavoriteSort.artist => 'Artist',
      FavoriteSort.title => 'Title',
    };
  }

  Widget _buildEmpty(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_border,
            size: 72,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('No favorites yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Tap the heart on any song to add it here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SongsListScreen()),
              );
            },
            icon: const Icon(Icons.library_music_outlined),
            label: const Text('Browse Songs'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    Set<String> favoriteIds,
  ) {
    final playerState = ref.watch(playerNotifierProvider);
    final notifier = ref.read(playerNotifierProvider.notifier);
    final service = ref.read(favoritesServiceProvider);
    final tracks = service.favoriteTracks;

    return ListView.separated(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isCurrent = playerState.currentTrack?.id == track.id;
        return TrackTile(
          track: track,
          isCurrent: isCurrent,
          isPlaying: isCurrent && playerState.isPlaying,
          showAlbum: true,
          onTap: () => notifier.playTrack(track),
          onFavorite: () =>
              ref.read(favoritesServiceProvider).toggleFavorite(track),
          onMoreOptions: () =>
              ref.read(favoritesServiceProvider).removeFavoriteId(track.id),
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
