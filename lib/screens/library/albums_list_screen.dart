import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/library_controller.dart';
import '../../models/album.dart';
import '../../models/track.dart';
import '../../widgets/album_art.dart';
import '../../widgets/collection_options_button.dart';
import '../../widgets/mini_player.dart';
import 'album_detail_screen.dart';

/// Screen displaying all music albums in a responsive visual grid.
class AlbumsListScreen extends ConsumerWidget {
  const AlbumsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryControllerProvider);
    final albums = library.albums;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Albums'),
        actions: [
          IconButton(
            icon: library.isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: library.isScanning
                ? null
                : () => ref
                    .read(libraryControllerProvider.notifier)
                    .scanAndRefresh(),
            tooltip: 'Rescan Music',
          ),
        ],
      ),
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: _buildBody(context, library, albums, ref),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LibraryData library,
    List<Album> albums,
    WidgetRef ref,
  ) {
    final theme = Theme.of(context);

    if (library.error != null && albums.isEmpty) {
      return Center(child: Text('Error loading albums: ${library.error}'));
    }

    if (albums.isEmpty) {
      if (library.loading || library.isScanning) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.album_outlined, size: 72, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'No albums found',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Scan your device storage to discover and organize music albums.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: library.isScanning
                    ? null
                    : () => ref
                        .read(libraryControllerProvider.notifier)
                        .scanAndRefresh(),
                icon: const Icon(Icons.refresh),
                label: Text(
                  library.isScanning ? 'Scanning...' : 'Scan Music',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // Header with total album count
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Text(
              '${albums.length} ${albums.length == 1 ? "album" : "albums"}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        // Albums Grid
        SliverPadding(
          padding: const EdgeInsets.all(12.0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12.0,
              crossAxisSpacing: 12.0,
              childAspectRatio: 0.72,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final album = albums[index];
                return _buildAlbumGridTile(context, library, album);
              },
              childCount: albums.length,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  /// Tracks belonging to this album, resolved from the in-memory library
  /// snapshot (album title + album artist) so the grid never queries Drift.
  List<Track> _tracksForAlbum(List<Track> allTracks, Album album) {
    return allTracks.where((t) {
      if (t.album != album.title) return false;
      if (album.albumArtist.isEmpty) return true;
      return t.artist == album.albumArtist;
    }).toList();
  }

  Widget _buildAlbumGridTile(
    BuildContext context,
    LibraryData library,
    Album album,
  ) {
    final theme = Theme.of(context);
    final albumTracks = _tracksForAlbum(library.tracks, album);

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AlbumDetailScreen(album: album),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surfaceContainerLow,
        ),
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album Artwork AspectRatio
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: AlbumArt(
                        width: double.infinity,
                        height: double.infinity,
                        album: album,
                        artUrl: album.artworkKey,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      child: CollectionOptionsButton(
                        tracks: albumTracks,
                        icon: Icons.more_vert,
                        iconColor: Colors.white,
                        tooltip: 'Album options',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Title
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),

            // Artist
            if (album.albumArtist.isNotEmpty)
              Text(
                album.albumArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

            // Track count and Year
            Text(
              [
                if (album.year != null && album.year! > 0) album.year.toString(),
                '${album.trackCount} tracks',
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}