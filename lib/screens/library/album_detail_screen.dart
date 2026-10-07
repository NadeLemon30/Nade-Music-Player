import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_controller.dart';
import '../../core/utils/duration_utils.dart';
import '../../data/repositories/music_repository.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/track.dart';
import '../../widgets/album_art.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../../widgets/track_options_sheet.dart';
import 'artist_detail_screen.dart';

/// Detail screen displaying album artwork, metadata, and ordered tracks.
///
/// Track order is sorted by `discNumber` + `trackNumber`.
class AlbumDetailScreen extends ConsumerWidget {
  final Album album;

  const AlbumDetailScreen({
    super.key,
    required this.album,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // [album.id] is the MediaStore album_id, so the lookup must match the
    // `album_id` column — matching the album *title* returns nothing. Albums
    // grouped without a MediaStore id collapse to id 0, so those fall back to a
    // title lookup.
    final tracksAsync = album.id == 0
        ? ref.watch(albumTracksProvider(album.title))
        : ref.watch(albumTracksByIdProvider(album.id));

    final playerState = ref.watch(playerNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(album.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle),
            tooltip: 'Shuffle Album',
            onPressed: () {
              final tracks = tracksAsync.value;
              if (tracks != null && tracks.isNotEmpty) {
                ref.read(playerNotifierProvider.notifier).shuffleAll(tracks);
              }
            },
          ),
        ],
      ),
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: tracksAsync.when(
        data: (rawTracks) {
          // Explicitly sort tracks by discNumber + trackNumber
          final tracks = _sortAlbumTracks(rawTracks);

          final totalDuration = tracks.fold<Duration>(
            Duration.zero,
            (prev, t) => prev + (t.duration ?? Duration.zero),
          );

          final artistName = album.albumArtist.isNotEmpty
              ? album.albumArtist
              : (tracks.isNotEmpty ? tracks.first.artist : 'Unknown Artist');

          return CustomScrollView(
            slivers: [
              // Album Header Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    children: [
                      // Prominent Album Artwork
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AlbumArt(
                              size: 190,
                              album: album,
                              artUrl: album.artworkKey ??
                                  (tracks.isNotEmpty ? tracks.first.albumArtUri : null),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Album Title
                      Text(
                        album.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Artist Name (Clickable to view Artist)
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ArtistDetailScreen(
                                artistId: album.artistId,
                                artist: Artist(
                                  id: artistName
                                      .toLowerCase()
                                      .replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
                                  name: artistName,
                                ),
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                          child: Text(
                            artistName,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Year & Metadata Subtitle
                      Text(
                        _buildAlbumSubtitle(album, tracks.length, totalDuration),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Play All, Shuffle & Add to Playlist Buttons
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
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
                            icon: const Icon(Icons.play_arrow),
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
                            icon: const Icon(Icons.shuffle),
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
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('Add to Playlist'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: Divider(height: 1, thickness: 0.6),
              ),

              // Tracks List Ordered by discNumber + trackNumber
              if (tracks.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Text('No tracks found in this album.'),
                    ),
                  ),
                )
              else
                SliverList.separated(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final isCurrent = playerState.currentTrack?.id == track.id;

                    // Formatted 2-digit track number (e.g. 01, 02)
                    final trackNum = track.trackNumber ?? (index + 1);
                    final trackNumStr = trackNum.toString().padLeft(2, '0');

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 2.0,
                      ),
                      leading: SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                          child: isCurrent
                              ? Icon(
                                  playerState.isPlaying
                                      ? Icons.equalizer
                                      : Icons.pause,
                                  color: theme.colorScheme.primary,
                                  size: 22,
                                )
                              : Text(
                                  trackNumStr,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          color: isCurrent ? theme.colorScheme.primary : null,
                        ),
                      ),
                      subtitle: track.artist != artistName
                          ? Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (track.duration != null &&
                            track.duration! > Duration.zero)
                          Text(
                            DurationUtils.format(track.duration!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert),
                            color: theme.colorScheme.onSurfaceVariant,
                            onPressed: () => showTrackOptionsSheet(context, track),
                          ),
                        ],
                      ),
                      onTap: () {
                        ref.read(playerNotifierProvider.notifier).setQueue(
                              tracks,
                              startIndex: index,
                              autoPlay: true,
                            );
                      },
                      onLongPress: () => showTrackOptionsSheet(context, track),
                    );
                  },
                  separatorBuilder: (context, index) => const Divider(
                    height: 1,
                    thickness: 0.4,
                    indent: 52,
                    endIndent: 16,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Error loading album tracks: $err'),
        ),
      ),
    );
  }

  /// Sorts tracks by discNumber first, then trackNumber, then title fallback.
  List<Track> _sortAlbumTracks(List<Track> tracks) {
    final sorted = List<Track>.from(tracks);
    sorted.sort((a, b) {
      final discA = a.discNumber ?? 1;
      final discB = b.discNumber ?? 1;
      final discCompare = discA.compareTo(discB);
      if (discCompare != 0) return discCompare;

      final trackA = a.trackNumber ?? 0;
      final trackB = b.trackNumber ?? 0;
      final trackCompare = trackA.compareTo(trackB);
      if (trackCompare != 0) return trackCompare;

      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return sorted;
  }

  String _buildAlbumSubtitle(Album album, int trackCount, Duration duration) {
    final parts = <String>[];
    if (album.year != null && album.year! > 0) {
      parts.add(album.year.toString());
    }
    parts.add('$trackCount ${trackCount == 1 ? "track" : "tracks"}');
    if (duration > Duration.zero) {
      parts.add(DurationUtils.format(duration));
    }
    return parts.join(' • ');
  }
}
