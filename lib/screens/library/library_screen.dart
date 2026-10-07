import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/library_controller.dart';
import '../../player/player_controller.dart';
import '../../data/repositories/music_repository.dart';
import '../../models/track.dart';
import '../../services/favorites/favorites_service.dart';
import '../../services/playback/play_history_service.dart';
import '../../services/playlists/playlist_service.dart';
import '../../widgets/album_art.dart';
import '../search/search_screen.dart';
import 'albums_list_screen.dart';
import 'artists_list_screen.dart';
import 'favorites_screen.dart';
import 'folders_screen.dart';
import 'playlists_screen.dart';
import 'recently_played_screen.dart';
import 'songs_list_screen.dart';

/// Main Library navigation screen consolidating search, category browsing,
/// and recent-activity sections into a single shared-library experience.
///
/// All sections derive their data from shared Riverpod providers backed by the
/// repository (rather than each screen independently loading the library).
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryControllerProvider);
    final recentlyAddedAsync = ref.watch(recentlyAddedTracksProvider);
    final recentlyPlayedAsync = ref.watch(recentlyPlayedProvider);
    final favoriteCount = ref.watch(favoriteIdsProvider).value?.length ?? 0;
    final playlistCount = ref.watch(playlistsProvider).value?.length ?? 0;

    final trackCount = library.tracks.length;
    final artistCount = library.artists.length;
    final albumCount = library.albums.length;

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Library'),
        actions: [
          IconButton(
            icon: library.isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: library.isScanning
                ? null
                : () async {
                    await ref
                        .read(libraryControllerProvider.notifier)
                        .scanAndRefresh();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Library refreshed.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
            tooltip: 'Scan MediaStore',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        children: [
          if (library.isScanning)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Scanning device for audio files...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          _buildSearchTile(context),

          const SizedBox(height: 8),

          _buildCategoryTile(
            context: context,
            icon: Icons.music_note,
            title: 'Songs',
            subtitle: '$trackCount tracks',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SongsListScreen()),
              );
            },
          ),
          _buildCategoryTile(
            context: context,
            icon: Icons.album,
            title: 'Albums',
            subtitle: '$albumCount albums',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AlbumsListScreen()),
              );
            },
          ),
          _buildCategoryTile(
            context: context,
            icon: Icons.person,
            title: 'Artists',
            subtitle: '$artistCount artists',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ArtistsListScreen()),
              );
            },
          ),
          _buildCategoryTile(
            context: context,
            icon: Icons.folder,
            title: 'Folders',
            subtitle: 'Local storage directories',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FoldersScreen()),
              );
            },
          ),
          _buildCategoryTile(
            context: context,
            icon: Icons.favorite,
            title: 'Favorites',
            subtitle: '$favoriteCount favorites',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FavoritesScreen()),
              );
            },
          ),
          _buildCategoryTile(
            context: context,
            icon: Icons.history,
            title: 'Recently Played',
            subtitle:
                '${recentlyPlayedAsync.value?.length ?? 0} recently played',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecentlyPlayedScreen()),
              );
            },
          ),
          _buildCategoryTile(
            context: context,
            icon: Icons.playlist_play,
            title: 'Playlists',
            subtitle: '$playlistCount ${playlistCount == 1 ? "playlist" : "playlists"}',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
              );
            },
          ),

          const SizedBox(height: 16),

          const _SectionHeader(title: 'Recently Added'),
          _RecentTracksRow(tracks: recentlyAddedAsync.value ?? const []),

          if (trackCount == 0 && !library.isScanning)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: () => ref
                      .read(libraryControllerProvider.notifier)
                      .scanAndRefresh(),
                  icon: const Icon(Icons.search),
                  label: const Text('Scan Device For Music'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchTile(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          alignment: Alignment.centerLeft,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          );
        },
        icon: Icon(Icons.search, color: theme.colorScheme.primary),
        label: Text(
          'Search your library',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: theme.colorScheme.primary,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Compact horizontal row of recently added tracks.
class _RecentTracksRow extends ConsumerWidget {
  final List<Track> tracks;

  const _RecentTracksRow({required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) {
      return const _EmptySectionHint(text: 'No recently added tracks');
    }
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final track = tracks[index];
          return _RecentTrackTile(
            title: track.title,
            subtitle: track.artist,
            artUrl: track.albumArtUri,
            onTap: () {
              ref.read(playerNotifierProvider.notifier).setQueue(
                    tracks,
                    startIndex: index,
                    autoPlay: true,
                  );
            },
          );
        },
      ),
    );
  }
}

class _RecentTrackTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? artUrl;
  final VoidCallback onTap;

  const _RecentTrackTile({
    required this.title,
    required this.subtitle,
    this.artUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 140,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AlbumArt(
              width: 140,
              height: 100,
              borderRadius: 12,
              artUrl: artUrl,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle.isEmpty ? 'Unknown Artist' : subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySectionHint extends StatelessWidget {
  final String text;

  const _EmptySectionHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
