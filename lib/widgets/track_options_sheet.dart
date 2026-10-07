import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/player_controller.dart';
import '../core/utils/duration_utils.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../screens/library/album_detail_screen.dart';
import '../screens/library/artist_detail_screen.dart';
import '../services/favorites/favorites_service.dart';
import 'album_art.dart';
import 'playlist_picker_sheet.dart';

/// Displays a modal bottom sheet with actions for a selected track.
void showTrackOptionsSheet(
  BuildContext context,
  Track track, {
  VoidCallback? onPlayNow,
  VoidCallback? onPlayNext,
  VoidCallback? onAddToQueue,
  VoidCallback? onAddToPlaylist,
  VoidCallback? onFavorite,
  VoidCallback? onViewArtist,
  VoidCallback? onViewAlbum,
  VoidCallback? onShowDetails,
}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Consumer(
      builder: (context, ref, _) {
        final theme = Theme.of(context);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Track Info Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                  child: Row(
                    children: [
                      AlbumArt(
                        size: 52,
                        artUrl: track.albumArtUri,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (track.album != null && track.album!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                track.album!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                            if (track.duration != null &&
                                track.duration! > Duration.zero) ...[
                              const SizedBox(height: 2),
                              Text(
                                DurationUtils.format(track.duration!),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // Actions List
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('Play Now'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (onPlayNow != null) {
                      onPlayNow();
                    } else {
                      ref.read(playerNotifierProvider.notifier).playTrack(track);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: const Text('Play Next'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (onPlayNext != null) {
                      onPlayNext();
                    } else {
                      ref.read(playerNotifierProvider.notifier).playNext(track);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Playing "${track.title}" next'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: const Text('Add to Queue'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (onAddToQueue != null) {
                      onAddToQueue();
                    } else {
                      ref.read(playerNotifierProvider.notifier).addToQueue(track);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Added "${track.title}" to queue'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: const Text('Add to Playlist'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (onAddToPlaylist != null) {
                      onAddToPlaylist();
                    } else {
                      showAddToPlaylistSheet(context, ref, track);
                    }
                  },
                ),
                ListTile(
                  leading: Icon(
                    ref.watch(favoriteIdsProvider).value?.contains(track.id) ==
                            true
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: ref
                                .watch(favoriteIdsProvider)
                                .value
                                ?.contains(track.id) ==
                            true
                        ? Colors.redAccent
                        : null,
                  ),
                  title: Text(
                    ref.watch(favoriteIdsProvider).value?.contains(track.id) ==
                            true
                        ? 'Remove from Favorites'
                        : 'Add to Favorites',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (onFavorite != null) {
                      onFavorite();
                    } else {
                      ref
                          .read(favoritesServiceProvider)
                          .toggleFavorite(track);
                    }
                  },
                ),
                if (track.album != null && track.album!.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.album),
                    title: Text('View Album (${track.album})'),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (onViewAlbum != null) {
                        onViewAlbum();
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AlbumDetailScreen(
                              album: Album(
                                id: track.albumId ?? 0,
                                title: track.album,
                                albumArtist: track.albumArtist,
                                artistId: track.artistId,
                                year: track.year,
                                trackCount: 1,
                                artworkKey: track.albumId?.toString(),
                              ),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text('View Artist (${track.artist})'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (onViewArtist != null) {
                      onViewArtist();
                    } else {
                      final artistId = track.artist
                          .trim()
                          .toLowerCase()
                          .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArtistDetailScreen(
                            artist: Artist(id: artistId, name: track.artist),
                          ),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Track Details'),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (onShowDetails != null) {
                      onShowDetails();
                    } else {
                      _showTrackDetailsDialog(context, track);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void _showTrackDetailsDialog(BuildContext context, Track track) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Track Details'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _detailRow('Title', track.title),
            _detailRow('Artist', track.artist),
            if (track.album != null) _detailRow('Album', track.album!),
            if (track.albumArtist != null) _detailRow('Album Artist', track.albumArtist!),
            if (track.genre != null) _detailRow('Genre', track.genre!),
            if (track.year != null) _detailRow('Year', track.year.toString()),
            if (track.trackNumber != null) _detailRow('Track #', track.trackNumber.toString()),
            if (track.duration != null && track.duration! > Duration.zero)
              _detailRow('Duration', DurationUtils.format(track.duration!)),
            if (track.fileSize != null)
              _detailRow('File Size', _formatFileSize(track.fileSize!)),
            if (track.mimeType != null) _detailRow('MIME Type', track.mimeType!),
            _detailRow('Path', track.filePath),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _detailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}
