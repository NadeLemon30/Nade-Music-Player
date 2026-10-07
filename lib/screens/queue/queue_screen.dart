import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_controller.dart';
import '../../widgets/track_tile.dart';

/// Screen showing the current playback queue.
///
/// Splits the queue into a pinned "Playing" section (the current track) and a
/// scrollable, reorderable "Up Next" section. Tapping an up-next track jumps to
/// it; dragging its handle reorders it; the trailing button removes it. A
/// persistent bottom button clears the whole queue.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerNotifierProvider);
    final player = ref.read(playerNotifierProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Queue')),
      body: playerState.queue.isEmpty
          ? _buildEmptyState(theme)
          : _buildQueue(context, theme, playerState, player),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.queue_music,
            size: 72,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('Queue is empty', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Songs you play from the library will appear here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQueue(
    BuildContext context,
    ThemeData theme,
    PlayerState playerState,
    PlayerNotifier player,
  ) {
    final queue = playerState.queue;
    final currentIndex = playerState.currentIndex;
    final hasCurrent = currentIndex >= 0 && currentIndex < queue.length;
    final upNextStart = currentIndex + 1;
    final upNextCount = queue.length - upNextStart;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(theme, 'Playing'),
        if (hasCurrent)
          TrackTile(
            track: queue[currentIndex],
            isCurrent: true,
            isPlaying: playerState.isPlaying,
            showAlbum: false,
            onTap: player.togglePlayPause,
          )
        else
          const _Hint(text: 'No track is playing'),

        const Divider(height: 1, thickness: 1),

        _sectionHeader(
          theme,
          'Up Next',
          trailing: '$upNextCount ${upNextCount == 1 ? 'song' : 'songs'}',
        ),

        if (upNextCount == 0)
          const Expanded(child: _Hint(text: 'Nothing up next'))
        else
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: upNextCount,
              onReorderItem: (oldIndex, newIndex) {
                player.moveInQueue(
                  currentIndex + 1 + oldIndex,
                  currentIndex + 1 + newIndex,
                );
              },
              itemBuilder: (context, localIndex) {
                final queueIndex = currentIndex + 1 + localIndex;
                final track = queue[queueIndex];
                final queueItem = player.queue.items[queueIndex];
                return Padding(
                  key: ValueKey('queue-item-${track.id}-$queueIndex'),
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Row(
                    children: [
                      ReorderableDelayedDragStartListener(
                        index: localIndex,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4, right: 8),
                          child: Icon(
                            Icons.drag_handle,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TrackTile(
                          track: track,
                          showAlbum: false,
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Queue item options',
                            onSelected: (value) {
                              if (value == 'remove') {
                                player.removeFromQueue(queueIndex);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove from queue'),
                              ),
                            ],
                          ),
                          onTap: () => player.playQueueItem(queueItem),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.tonalIcon(
              onPressed: queue.isEmpty ? null : player.clearQueue,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear Queue'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(ThemeData theme, String title, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;

  const _Hint({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}