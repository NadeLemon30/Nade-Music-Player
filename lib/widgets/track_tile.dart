import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/duration_utils.dart';
import '../models/track.dart';
import '../services/favorites/favorites_service.dart';
import 'album_art.dart';
import 'track_options_sheet.dart';

/// Reusable tile component representing a single track in list views.
///
/// Features:
/// - 3-line metadata layout: Title, Artist, Album
/// - Tap to play
/// - Long press or 3-dots to open track options
/// - Future-proof hooks for Queue, Playlist, Favorite, View Album, View Artist
class TrackTile extends ConsumerWidget {
  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final bool showAlbum;
  final bool showDuration;
  final bool showDivider;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMoreOptions;
  final VoidCallback? onPlay;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onFavorite;
  final VoidCallback? onViewAlbum;
  final VoidCallback? onViewArtist;
  final VoidCallback? onShowDetails;

  const TrackTile({
    super.key,
    required this.track,
    this.isCurrent = false,
    this.isPlaying = false,
    this.showAlbum = true,
    this.showDuration = true,
    this.showDivider = false,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onMoreOptions,
    this.onPlay,
    this.onPlayNext,
    this.onAddToQueue,
    this.onAddToPlaylist,
    this.onFavorite,
    this.onViewAlbum,
    this.onViewArtist,
    this.onShowDetails,
  });

  void _openOptions(BuildContext context) {
    showTrackOptionsSheet(
      context,
      track,
      onPlayNow: onPlay,
      onPlayNext: onPlayNext,
      onAddToQueue: onAddToQueue,
      onAddToPlaylist: onAddToPlaylist,
      onFavorite: onFavorite,
      onViewAlbum: onViewAlbum,
      onViewArtist: onViewArtist,
      onShowDetails: onShowDetails,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final titleColor = isCurrent ? theme.colorScheme.primary : null;
    final hasAlbum = showAlbum && track.album != null && track.album!.trim().isNotEmpty;

    final favoriteIdsAsync = ref.watch(favoriteIdsProvider);
    final isFavorite = favoriteIdsAsync.value?.contains(track.id) ?? false;

    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      isThreeLine: hasAlbum,
      onTap: onTap ?? onPlay,
      onLongPress: onLongPress ?? () => _openOptions(context),
      leading: leading ??
          Stack(
            alignment: Alignment.center,
            children: [
              AlbumArt(
                size: 50,
                artUrl: track.albumArtUri,
              ),
              if (isCurrent)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isPlaying ? Icons.equalizer : Icons.pause,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
            ],
          ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
          color: titleColor,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isCurrent
                  ? theme.colorScheme.primary.withValues(alpha: 0.9)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (hasAlbum) ...[
            const SizedBox(height: 2),
            Text(
              track.album!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isCurrent
                    ? theme.colorScheme.primary.withValues(alpha: 0.7)
                    : theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
      trailing: trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDuration &&
                  track.duration != null &&
                  track.duration! > Duration.zero)
                Padding(
                  padding: const EdgeInsets.only(right: 4.0),
                  child: Text(
                    DurationUtils.format(track.duration!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  size: 20,
                ),
                color: isFavorite
                    ? Colors.redAccent
                    : theme.colorScheme.onSurfaceVariant,
                tooltip: isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                onPressed: onFavorite ??
                    () => ref
                        .read(favoritesServiceProvider)
                        .toggleFavorite(track),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                color: theme.colorScheme.onSurfaceVariant,
                tooltip: 'Options',
                onPressed: onMoreOptions ?? () => _openOptions(context),
              ),
            ],
          ),
    );

    if (showDivider) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tile,
          const Divider(height: 1, thickness: 0.5),
        ],
      );
    }

    return tile;
  }
}
