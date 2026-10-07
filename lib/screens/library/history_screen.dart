import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_controller.dart';
import '../../services/playback/play_history_service.dart';
import '../../widgets/album_art.dart';
import '../../widgets/mini_player.dart';

/// Full playback history: every track played, most recent first, with per-entry
/// removal and a clear-all action (Phase 3H).
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(recentlyPlayedProvider);
    final history = historyAsync.value ?? const <PlayHistoryEntry>[];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playback History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear history',
            onPressed: history.isEmpty
                ? null
                : () => _confirmClear(context, ref),
          ),
        ],
      ),
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: history.isEmpty ? _buildEmpty(theme) : _buildList(context, ref, history, theme),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 72, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('No playback history', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Tracks you play will appear here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<PlayHistoryEntry> history,
    ThemeData theme,
  ) {
    final playerState = ref.watch(playerNotifierProvider);

    return ListView.separated(
      itemCount: history.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, thickness: 0.5),
      itemBuilder: (context, index) {
        final entry = history[index];
        final track = entry.track;
        final isCurrent = playerState.currentTrack?.id == track.id;

        return ListTile(
          leading: AlbumArt(size: 50, artUrl: track.albumArtUri),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
              color: isCurrent ? theme.colorScheme.primary : null,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _metaLabel(entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.playCount > 1)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '${entry.playCount} plays',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: theme.colorScheme.onSurfaceVariant,
                tooltip: 'Remove from history',
                onPressed: () {
                  ref.read(playHistoryServiceProvider).removeEntry(track.id);
                },
              ),
            ],
          ),
          onTap: () {
            ref.read(playerNotifierProvider.notifier).playTrack(track);
          },
        );
      },
    );
  }

  String _metaLabel(PlayHistoryEntry entry) {
    final local = entry.playedAt.toLocal();
    final date =
        '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}:${_two(local.minute)}';
    if (entry.resumePosition > Duration.zero) {
      final seconds = entry.resumePosition.inSeconds;
      return 'Played $date · resume at ${_clock(seconds)}';
    }
    return 'Played $date';
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _clock(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final mm = _two(m);
    final ss = _two(s);
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear playback history?'),
        content: const Text('This removes every entry from your history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(playHistoryServiceProvider).clear();
    }
  }
}
