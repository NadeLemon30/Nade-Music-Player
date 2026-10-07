import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../models/playlist.dart';
import '../../player/player_controller.dart';
import '../../services/playback/play_history_service.dart';
import '../../services/playlists/playlist_service.dart';
import '../../widgets/album_art.dart';
import '../library/albums_list_screen.dart';
import '../library/artists_list_screen.dart';
import '../library/favorites_screen.dart';
import '../library/folders_screen.dart';
import '../library/playlist_detail_screen.dart';
import '../library/playlists_screen.dart';
import '../library/recently_played_screen.dart';
import '../library/songs_list_screen.dart';

/// Home dashboard: a Recently Played row and Quick Access links into the
/// library (Phase 3H.24).
class HomeScreen extends ConsumerWidget {
  final String title;

  const HomeScreen({
    super.key,
    this.title = AppConstants.appName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entriesAsync = ref.watch(recentlyPlayedProvider);
    final entries = entriesAsync.value ?? const <PlayHistoryEntry>[];
    final player = ref.watch(playerNotifierProvider);
    final playlistsAsync = ref.watch(playlistsProvider);
    final playlists = playlistsAsync.value ?? const <Playlist>[];

    // Newest-created playlists first (3J.38); only a small handful on Home
    // (3J.36) — the rest live behind "View All".
    final recentPlaylists = playlists.reversed.take(4).toList();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _SectionHeader(
            title: 'Recently Played',
            onSeeAll: entries.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecentlyPlayedScreen(),
                      ),
                    ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Tracks you play will appear here.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: entries.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final track = entries[index].track;
                  final isCurrent = player.currentTrack?.id == track.id;
                  return _RecentCard(
                    artUrl: track.albumArtUri,
                    title: track.title,
                    artist: track.artist,
                    isCurrent: isCurrent,
                    onTap: () =>
                        ref.read(playerNotifierProvider.notifier).playTrack(track),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          if (playlists.isNotEmpty) ...[
            _SectionHeader(
              title: 'Your Playlists',
              onSeeAll: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
              ),
            ),
            SizedBox(
              height: 126,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: recentPlaylists.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final playlist = recentPlaylists[index];
                  return _PlaylistCard(
                    playlist: playlist,
                    songCount: ref
                        .read(playlistServiceProvider)
                        .trackCount(playlist.id),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PlaylistDetailScreen(playlistId: playlist.id),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
          const _SectionHeader(title: 'Quick Access'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                _QuickAccessTile(
                  icon: Icons.music_note,
                  label: 'Songs',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SongsListScreen()),
                  ),
                ),
                _QuickAccessTile(
                  icon: Icons.favorite_outline,
                  label: 'Favorites',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                  ),
                ),
                _QuickAccessTile(
                  icon: Icons.person_outline,
                  label: 'Artists',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ArtistsListScreen()),
                  ),
                ),
                _QuickAccessTile(
                  icon: Icons.album_outlined,
                  label: 'Albums',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AlbumsListScreen()),
                  ),
                ),
                _QuickAccessTile(
                  icon: Icons.folder_outlined,
                  label: 'Folders',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FoldersScreen()),
                  ),
                ),
                _QuickAccessTile(
                  icon: Icons.playlist_play,
                  label: 'Playlists',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Text('See all'),
            ),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final Playlist playlist;
  final int songCount;
  final VoidCallback onTap;

  const _PlaylistCard({
    required this.playlist,
    required this.songCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 140,
              height: 84,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.playlist_play,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$songCount ${songCount == 1 ? "song" : "songs"}',
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

class _RecentCard extends StatelessWidget {
  final String? artUrl;
  final String title;
  final String artist;
  final bool isCurrent;
  final VoidCallback onTap;

  const _RecentCard({
    required this.artUrl,
    required this.title,
    required this.artist,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                AlbumArt(size: 120, artUrl: artUrl),
                if (isCurrent)
                  const Icon(Icons.graphic_eq, color: Colors.white, size: 40),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color:
                    isCurrent ? theme.colorScheme.primary : null,
              ),
            ),
            Text(
              artist,
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

class _QuickAccessTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAccessTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(icon, color: theme.colorScheme.primary),
      ),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
