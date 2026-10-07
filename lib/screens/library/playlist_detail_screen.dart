import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/duration_utils.dart';
import '../../controllers/library_controller.dart';
import '../../data/repositories/playlist_history_repository.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../player/player_controller.dart';
import '../../services/playlists/playlist_service.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/track_tile.dart';
import 'add_songs_screen.dart';

/// Detail view of a single user-created playlist (Phase 3J, 3K; spec 20).
///
/// Shows the playlist's ordered songs with the spec 20 header actions — Play,
/// Shuffle, Play Next, Add to Queue — all visible up front, per-row removal,
/// and drag-to-reorder. Commands go through [PlayerNotifier] like every other
/// playback surface (spec 17: the playlist never owns a player); the playlist
/// itself is mutated through [PlaylistService]. Explicit playlist-level Play /
/// Shuffle record playlist history (spec 3K.3); queuing actions do not.
class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final service = ref.watch(playlistServiceProvider);
    // Watching the playlists stream also rebuilds this screen after mutations
    // (rename, remove track, reorder). Resolve the live header from it.
    final playlistsAsync = ref.watch(playlistsProvider);
    Playlist? playlist;
    for (final p in playlistsAsync.value ?? const <Playlist>[]) {
      if (p.id == playlistId) {
        playlist = p;
        break;
      }
    }
    playlist ??= service.getPlaylist(playlistId);

    // Lazy stale-entry cleanup (3J): drop playlist entries whose music file has
    // been deleted, only when this screen is shown (matching the favorites /
    // history prune pattern).
    final library = ref.read(libraryControllerProvider);
    final availableIds = library.tracks
        .where((t) => t.isAvailable)
        .map((t) => t.id)
        .toSet();
    ref.read(playlistServiceProvider).pruneMissingTracks(availableIds);

    final tracks = playlist == null ? const <Track>[] : service.tracksForPlaylist(playlistId);

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? 'Playlist'),
        actions: [
          if (playlist != null) ...[
            IconButton(
              tooltip: 'Add songs',
              icon: const Icon(Icons.playlist_add),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AddSongsScreen(playlistId: playlistId),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  _showRenameDialog(context, ref, playlist?.name ?? 'Playlist'),
            ),
          ],
        ],
      ),
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: playlist == null
          ? Center(
              child: Text(
                'Playlist not found.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          : tracks.isEmpty
              ? _buildEmpty(context, theme, playlist.name)
              : _buildList(context, ref, tracks),
    );
  }

  Widget _buildEmpty(
    BuildContext context,
    ThemeData theme,
    String name,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Icon(
            Icons.music_note,
            size: 72,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No songs yet',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Add songs from your library to start building this playlist.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddSongsScreen(playlistId: playlistId),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Songs'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
  ) {
    final playerState = ref.watch(playerNotifierProvider);
    final player = ref.read(playerNotifierProvider.notifier);
    final service = ref.read(playlistServiceProvider);
    final theme = Theme.of(context);

    final totalDuration = tracks.fold<Duration>(
      Duration.zero,
      (prev, t) => prev + (t.duration ?? Duration.zero),
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                Text(
                  '${tracks.length} ${tracks.length == 1 ? "song" : "songs"}'
                  '${totalDuration > Duration.zero ? " • ${DurationUtils.format(totalDuration)}" : ""}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _playPlaylist(ref, tracks),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _shufflePlaylist(ref, tracks),
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => player.playNextAll(tracks),
                      icon: const Icon(Icons.playlist_play),
                      label: const Text('Play Next'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => player.addToQueueAll(tracks),
                      icon: const Icon(Icons.queue_music),
                      label: const Text('Add to Queue'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Drag a song by its handle to reorder',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Divider(height: 1, thickness: 0.6),
        ),
        SliverReorderableList(
          itemCount: tracks.length,
          onReorderItem: (oldIndex, newIndex) {
            // ReorderableListView reports its own adjusted new index.
            service.moveTrack(playlistId, oldIndex, newIndex);
          },
          itemBuilder: (context, index) {
            final track = tracks[index];
            final isCurrent = playerState.currentTrack?.id == track.id;
            return Padding(
              key: ValueKey('playlist-track-${track.id}-$index'),
              padding: const EdgeInsets.only(left: 8, right: 4),
              child: Row(
                children: [
                  ReorderableDelayedDragStartListener(
                    index: index,
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
                      isCurrent: isCurrent,
                      isPlaying: isCurrent && playerState.isPlaying,
                      showAlbum: true,
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Playlist item options',
                        onSelected: (value) {
                          if (value == 'remove') {
                            service.removeTrackFromPlaylist(
                              playlistId,
                              track.id,
                            );
                          } else if (value == 'playNext') {
                            player.playNext(track);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'playNext',
                            child: Text('Play next'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove from playlist'),
                          ),
                        ],
                      ),
                      onTap: () {
                        player.setQueue(
                          tracks,
                          startIndex: index,
                          autoPlay: true,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// Explicit playlist-level play: queues [tracks] and records the playlist in
  /// playlist history (spec 3K.3 — individual song plays never count).
  void _playPlaylist(WidgetRef ref, List<Track> tracks) {
    if (tracks.isEmpty) return;
    unawaited(
      ref.read(playlistHistoryRepositoryProvider).recordPlay(playlistId),
    );
    ref
        .read(playerNotifierProvider.notifier)
        .setQueue(tracks, startIndex: 0, autoPlay: true);
  }

  /// Explicit playlist-level shuffle play, recorded in playlist history (3K.3).
  void _shufflePlaylist(WidgetRef ref, List<Track> tracks) {
    if (tracks.isEmpty) return;
    unawaited(
      ref.read(playlistHistoryRepositoryProvider).recordPlay(playlistId),
    );
    ref.read(playerNotifierProvider.notifier).shuffleAll(tracks);
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, String currentName) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: currentName);
        return AlertDialog(
          title: const Text('Rename Playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Playlist name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                await ref
                    .read(playlistServiceProvider)
                    .renamePlaylist(playlistId, name);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }
}