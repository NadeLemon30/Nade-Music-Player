import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/duration_utils.dart';
import '../../player/player_controller.dart';
import '../../services/favorites/favorites_service.dart';
import '../../services/sleep_timer_service.dart';
import '../../widgets/album_art.dart';
import '../../widgets/playback_controls.dart';
import '../../widgets/player/player_progress_bar.dart';
import '../../widgets/player/sleep_timer_sheet.dart';
import '../queue/queue_screen.dart';
import 'audio_effects_screen.dart';
import 'equalizer_screen.dart';

/// Full-screen "Now Playing" view bound to [playerNotifierProvider].
///
/// Shows the current track artwork, metadata, elapsed/total time with scrubbing,
/// transport controls, and shuffle/repeat toggles.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerNotifierProvider);
    final player = ref.read(playerNotifierProvider.notifier);
    final theme = Theme.of(context);
    final track = playerState.currentTrack;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        actions: [
          // Phase 4A: sleep timer. Inactive → outlined bedtime action. Active →
          // compact "bedtime mm:ss" pill that doubles as the entry point
          // (spec §12 compact indicator), opening the preset/active sheet.
          Consumer(
            builder: (context, ref, _) {
              final remaining = ref.watch(sleepTimerStateProvider).value;
              final isActive = remaining != null;
              if (!isActive) {
                return IconButton(
                  tooltip: 'Sleep timer',
                  icon: const Icon(Icons.bedtime_outlined),
                  onPressed: () => showSleepTimerSheet(context),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () => showSleepTimerSheet(context),
                  icon: const Icon(Icons.bedtime, size: 18),
                  label: Text(
                    DurationUtils.formatDuration(remaining),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              );
            },
          ),
          if (track != null)
            Consumer(
              builder: (context, ref, _) {
                final isFavorite = ref
                        .watch(favoriteIdsProvider)
                        .value
                        ?.contains(track.id) ??
                    false;
                return IconButton(
                  tooltip:
                      isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                  color: isFavorite ? Colors.redAccent : null,
                  onPressed: () => ref
                      .read(favoritesServiceProvider)
                      .toggleFavorite(track),
                );
              },
            ),
        ],
      ),
      body: track == null ? _buildEmptyState(theme) : _buildPlayer(context, theme, playerState, player),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_off_outlined,
            size: 72,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('Nothing playing', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Pick a song from your library to start listening.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer(
    BuildContext context,
    ThemeData theme,
    PlayerState playerState,
    PlayerNotifier player,
  ) {
    final track = playerState.currentTrack!;
    final showAlbum = track.album.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        child: Column(
          children: [
            // Artwork (responsive: grows with the available space, capped)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxSide = constraints.biggest.shortestSide;
                  final side = maxSide.clamp(140.0, 420.0).toDouble();
                  return Center(
                    child: AlbumArt(
                      track: track,
                      size: side,
                      borderRadius: 20,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Metadata
            Text(
              track.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              track.artist,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (showAlbum) ...[
              const SizedBox(height: 2),
              Text(
                track.album,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],

            if (playerState.resumedFrom != null) ...[
              const SizedBox(height: 14),
              _ResumeBanner(
                position: playerState.resumedFrom!,
                onDismiss: player.dismissResume,
              ),
            ],

            if (playerState.hasError) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  playerState.error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Progress + scrubbing (drag-local, seek-on-release)
            const PlayerProgressBar(),

            const SizedBox(height: 4),

            const SizedBox(height: 4),

            // Shuffle & repeat (above transport, 3F.20)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: player.playbackMode.shuffleEnabled
                      ? 'Shuffle on'
                      : 'Shuffle off',
                  iconSize: 26,
                  onPressed: player.toggleShuffle,
                  icon: Icon(
                    Icons.shuffle,
                    color: player.playbackMode.shuffleEnabled
                        ? theme.colorScheme.primary
                        : null,
                  ),
                ),
                const SizedBox(width: 24),
                IconButton(
                  tooltip: _repeatLabel(player.playbackMode.repeatMode),
                  iconSize: 26,
                  onPressed: player.cycleRepeatMode,
                  icon: IconTheme(
                    data: IconThemeData(
                      color: player.playbackMode.repeatMode != RepeatMode.off
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    child: _repeatIcon(player.playbackMode.repeatMode),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Transport controls
            PlaybackControls(
              isPlaying: playerState.isPlaying,
              isBuffering: playerState.isBuffering,
              isLoading: playerState.isLoading,
              onPlayPause: player.togglePlayPause,
              onSeekBackward: player.seekBackward,
              onPrevious: player.previous,
              onNext: playerState.hasNext ||
                      playerState.repeatMode == RepeatMode.all
                  ? player.next
                  : null,
              onSeekForward: player.seekForward,
              iconSize: 36,
            ),

            const SizedBox(height: 8),

            // Player options (spec §13): Queue + Sleep Timer are live; the
            // remaining entries are placeholders for future phases.
            TextButton.icon(
              onPressed: () => _showPlayerOptions(context),
              icon: const Icon(Icons.more_horiz),
              label: const Text('Options'),
            ),
          ],
        ),
      ),
    );
  }

  /// Player options menu (spec §13): Queue + Sleep Timer are implemented; the
  /// remaining entries are placeholders until their own phases land.
  void _showPlayerOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Player',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.queue_music),
                title: const Text('Queue'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const QueueScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.graphic_eq),
                title: const Text('Audio Effects'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AudioEffectsScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.equalizer),
                title: const Text('Equalizer'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EqualizerScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('Sleep Timer'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showSleepTimerSheet(context);
                },
              ),
              const ListTile(
                leading: Icon(Icons.lyrics_outlined),
                title: Text('Lyrics'),
              ),
              const ListTile(
                leading: Icon(Icons.speed),
                title: Text('Playback Speed'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _repeatIcon(RepeatMode mode) {
    return switch (mode) {
      RepeatMode.off => const Icon(Icons.repeat),
      RepeatMode.all => const Icon(Icons.repeat),
      RepeatMode.one => const Icon(Icons.repeat_one),
    };
  }

  String _repeatLabel(RepeatMode mode) {
    return switch (mode) {
      RepeatMode.off => 'Repeat off',
      RepeatMode.all => 'Repeat all',
      RepeatMode.one => 'Repeat one',
    };
  }
}

/// Compact banner shown when a track auto-resumes from a previously saved
/// position (Phase 3H). Displays where playback started and offers to dismiss.
class _ResumeBanner extends StatelessWidget {
  final Duration position;
  final VoidCallback onDismiss;

  const _ResumeBanner({
    required this.position,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = 'Resumed from ${DurationUtils.formatDuration(position)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history,
            size: 16,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close,
                size: 16,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}