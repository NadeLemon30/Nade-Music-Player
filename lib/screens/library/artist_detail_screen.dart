import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_controller.dart';
import '../../data/repositories/music_repository.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../widgets/album_art.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../../widgets/track_tile.dart';
import 'album_detail_screen.dart';

/// Detail screen displaying all albums and songs for a selected artist.
class ArtistDetailScreen extends ConsumerWidget {
  final Artist artist;

  /// Relational MediaStore artist ID. When provided, tracks/albums are queried
  /// by this ID rather than by matching the artist name string.
  final int? artistId;

  const ArtistDetailScreen({
    super.key,
    required this.artist,
    this.artistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = artistId ?? int.tryParse(artist.id);
    final tracksAsync = id != null
        ? ref.watch(artistTracksByIdProvider(id))
        : ref.watch(artistTracksProvider(artist.id));
    final albumsAsync = id != null
        ? ref.watch(artistAlbumsByIdProvider(id))
        : ref.watch(artistAlbumsProvider(artist.id));
    final playerState = ref.watch(playerNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: CustomScrollView(
        slivers: [
          // Header App Bar with Artist Info
          SliverAppBar(
            expandedHeight: 200.0,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                artist.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              centerTitle: false,
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.surface,
                    ],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40.0),
                    child: CircleAvatar(
                      radius: 46,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(
                        artist.name.isNotEmpty ? artist.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Play & Shuffle Action Bar
          SliverToBoxAdapter(
            child: tracksAsync.when(
              data: (tracks) {
                final albums = albumsAsync.value ?? [];
                final trackCountText = '${tracks.length} ${tracks.length == 1 ? "song" : "songs"}';
                final albumCountText = albums.isNotEmpty
                    ? '${albums.length} ${albums.length == 1 ? "album" : "albums"} • '
                    : '';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '$albumCountText$trackCountText',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: tracks.isEmpty
                                ? null
                                : () {
                                    ref.read(playerNotifierProvider.notifier).setQueue(
                                          tracks,
                                          startIndex: 0,
                                          autoPlay: true,
                                        );
                                  },
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('Play'),
                          ),
                          FilledButton.icon(
                            onPressed: tracks.isEmpty
                                ? null
                                : () {
                                    ref
                                        .read(playerNotifierProvider.notifier)
                                        .shuffleAll(tracks);
                                  },
                            icon: const Icon(Icons.shuffle, size: 18),
                            label: const Text('Shuffle'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: tracks.isEmpty
                                ? null
                                : () {
                                    showAddTracksToPlaylistSheet(
                                      context,
                                      ref,
                                      tracks,
                                    );
                                  },
                            icon: const Icon(Icons.playlist_add, size: 18),
                            label: const Text('Add All to Playlist'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (err, _) => const SizedBox.shrink(),
            ),
          ),

          // Albums Section Header
          albumsAsync.when(
            data: (albums) {
              if (albums.isEmpty) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }

              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 12.0, bottom: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.album, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Albums',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${albums.length})',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (err, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // Albums Horizontal List
          albumsAsync.when(
            data: (albums) {
              if (albums.isEmpty) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }

              return SliverToBoxAdapter(
                child: SizedBox(
                  height: 190,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    itemCount: albums.length,
                    itemBuilder: (context, index) {
                      final album = albums[index];
                      return _buildAlbumCard(context, ref, album);
                    },
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (err, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // Songs Section Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
              child: Row(
                children: [
                  const Icon(Icons.music_note, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Songs',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (tracksAsync.value != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${tracksAsync.value!.length})',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Songs List
          tracksAsync.when(
            data: (tracks) {
              if (tracks.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(
                      child: Text('No tracks found for this artist.'),
                    ),
                  ),
                );
              }

              return SliverList.separated(
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final isCurrent = playerState.currentTrack?.id == track.id;

                  return TrackTile(
                    track: track,
                    isCurrent: isCurrent,
                    isPlaying: isCurrent && playerState.isPlaying,
                    onTap: () {
                      ref.read(playerNotifierProvider.notifier).setQueue(
                            tracks,
                            startIndex: index,
                            autoPlay: true,
                          );
                    },
                  );
                },
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 16,
                  endIndent: 16,
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            error: (err, _) => SliverToBoxAdapter(
              child: Center(child: Text('Error loading tracks: $err')),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildAlbumCard(BuildContext context, WidgetRef ref, Album album) {
    final theme = Theme.of(context);

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
        width: 124,
        margin: const EdgeInsets.symmetric(horizontal: 4.0),
        padding: const EdgeInsets.all(6.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AlbumArt(
                size: 112,
                album: album,
                artUrl: album.artworkKey,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${album.trackCount} tracks',
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
