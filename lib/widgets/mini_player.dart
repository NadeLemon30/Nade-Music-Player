import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/duration_utils.dart';
import '../player/player_controller.dart';
import '../models/track.dart';
import '../screens/player/player_screen.dart';
import '../services/favorites/favorites_service.dart';
import '../services/sleep_timer_service.dart';
import 'album_art.dart';

/// Modular presentational mini player widget.
class MiniPlayer extends StatelessWidget {
  final Track track;
  final bool isPlaying;
  final bool isBuffering;
  final bool isFavorite;
  final Duration? sleepTimerRemaining;
  final VoidCallback onPlayPause;
  final VoidCallback? onFavorite;
  final VoidCallback? onTap;

  const MiniPlayer({
    super.key,
    required this.track,
    required this.isPlaying,
    this.isBuffering = false,
    this.isFavorite = false,
    this.sleepTimerRemaining,
    required this.onPlayPause,
    this.onFavorite,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.15),
                width: 1.0,
              ),
            ),
          ),
          child: Row(
            children: [
              AlbumArt(
                size: 44,
                artUrl: track.albumArtUri,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (sleepTimerRemaining != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.bedtime,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  DurationUtils.formatDuration(sleepTimerRemaining!),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              if (onFavorite != null)
                IconButton(
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                  ),
                  color: isFavorite
                      ? Colors.redAccent
                      : theme.colorScheme.onSurfaceVariant,
                  tooltip: isFavorite
                      ? 'Remove from Favorites'
                      : 'Add to Favorites',
                  onPressed: onFavorite,
                ),
              SizedBox(
                width: 48,
                height: 48,
                child: isBuffering
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : IconButton(
                        iconSize: 32,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                        ),
                        color: theme.colorScheme.primary,
                        onPressed: onPlayPause,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Connected MiniPlayer reactively bound to [playerNotifierProvider].
///
/// When used as a [Scaffold.bottomNavigationBar] directly, [MiniPlayer] must
/// reserve the system bottom inset (home/gesture bar) itself, since [Scaffold]
/// positions the bar flush against the physical bottom edge. When another bar
/// below already reserves the inset (e.g. MainShellScreen's `NavigationBar`),
/// pass [handleBottomInset] as `false` to avoid double padding.
class ConnectedMiniPlayer extends ConsumerWidget {
  final bool handleBottomInset;

  const ConnectedMiniPlayer({super.key, this.handleBottomInset = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final playerState = ref.watch(playerNotifierProvider);
    final track = playerState.currentTrack;

    if (track == null) {
      return const SizedBox.shrink();
    }

    final favoriteIds =
        ref.watch(favoriteIdsProvider).value ?? const <String>{};
    final isFavorite = favoriteIds.contains(track.id);
    final sleepTimerRemaining = ref.watch(sleepTimerStateProvider).value;

    final MiniPlayer miniPlayer = MiniPlayer(
      track: track,
      isPlaying: playerState.isPlaying,
      isBuffering: playerState.isBuffering,
      isFavorite: isFavorite,
      sleepTimerRemaining: sleepTimerRemaining,
      onPlayPause: () => ref.read(playerNotifierProvider.notifier).togglePlayPause(),
      onFavorite: () => ref
          .read(favoritesServiceProvider)
          .toggleFavorite(track),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PlayerScreen(),
          ),
        );
      },
    );

    if (!handleBottomInset) {
      return miniPlayer;
    }

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: miniPlayer,
      ),
    );
  }
}
