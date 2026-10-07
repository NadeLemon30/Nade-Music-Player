import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/library_controller.dart';
import '../../player/player_controller.dart';
import '../../models/track.dart';
import '../../services/favorites/favorites_service.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../../widgets/track_tile.dart';

/// Screen displaying all indexed songs with instant playback and shuffle options.
///
/// Displays data from the shared [LibraryController]; it does not load or scan
/// the library itself.
///
/// Multi-select (spec 6): long-pressing a song enters selection mode, where a
/// checkbox replaces each tile's quick actions. The selection bar offers
/// Add to Playlist / Add to Queue / Play Next / Favorite. Selection order is
/// the library order (the order songs are shown in).
class SongsListScreen extends ConsumerStatefulWidget {
  const SongsListScreen({super.key});

  @override
  ConsumerState<SongsListScreen> createState() => _SongsListScreenState();
}

class _SongsListScreenState extends ConsumerState<SongsListScreen> {
  final Set<String> _selectedIds = {};

  /// True while the multi-select (spec 6) selection mode is active. The mode
  /// is entered by long-pressing a tile and exits when the last selection is
  /// removed or the close button is pressed.
  bool get _selecting => _selectedIds.isNotEmpty;

  void _enterSelection(String trackId) {
    setState(() => _selectedIds.add(trackId));
  }

  void _toggleSelection(String trackId) {
    setState(() {
      if (!_selectedIds.remove(trackId)) {
        _selectedIds.add(trackId);
      }
    });
  }

  void _exitSelection() {
    setState(_selectedIds.clear);
  }

  /// The selected tracks in the order they appear in [tracks].
  List<Track> _selectedTracks(List<Track> tracks) {
    return [for (final t in tracks) if (_selectedIds.contains(t.id)) t];
  }

  void _addSelectedToPlaylist(List<Track> tracks) {
    final selected = _selectedTracks(tracks);
    if (selected.isEmpty) return;
    showAddTracksToPlaylistSheet(context, ref, selected);
    _exitSelection();
  }

  void _addSelectedToQueue(List<Track> tracks) {
    final selected = _selectedTracks(tracks);
    if (selected.isEmpty) return;
    ref.read(playerNotifierProvider.notifier).addToQueueAll(selected);
    _showResult('Added ${selected.length} '
        '${selected.length == 1 ? "song" : "songs"} to queue');
    _exitSelection();
  }

  void _playSelectedNext(List<Track> tracks) {
    final selected = _selectedTracks(tracks);
    if (selected.isEmpty) return;
    ref.read(playerNotifierProvider.notifier).playNextAll(selected);
    _showResult('Playing ${selected.length} '
        '${selected.length == 1 ? "song" : "songs"} next');
    _exitSelection();
  }

  void _favoriteSelected(List<Track> tracks) {
    final selected = _selectedTracks(tracks);
    if (selected.isEmpty) return;
    final favorites = ref.read(favoritesServiceProvider);
    for (final track in selected) {
      favorites.addFavorite(track);
    }
    _showResult('Added ${selected.length} '
        '${selected.length == 1 ? "song" : "songs"} to favorites');
    _exitSelection();
  }

  void _showResult(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryControllerProvider);
    final tracks = library.tracks;

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Exit selection',
                onPressed: _exitSelection,
              )
            : null,
        title: Text(_selecting ? '${_selectedIds.length} selected' : 'Songs'),
        actions: _selecting
            ? []
            : [
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
      bottomNavigationBar: _selecting
          ? _SelectionActionBar(
              onAddToPlaylist: () => _addSelectedToPlaylist(tracks),
              onAddToQueue: () => _addSelectedToQueue(tracks),
              onPlayNext: () => _playSelectedNext(tracks),
              onFavorite: () => _favoriteSelected(tracks),
            )
          : const ConnectedMiniPlayer(),
      body: _buildBody(context, library, tracks),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LibraryData library,
    List<Track> tracks,
  ) {
    final theme = Theme.of(context);

    if (library.error != null && tracks.isEmpty) {
      return Center(child: Text('Error loading songs: ${library.error}'));
    }

    if (tracks.isEmpty) {
      if (library.loading || library.isScanning) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.music_off, size: 72, color: Colors.grey),
              const SizedBox(height: 16),
              Text('No songs found', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Tap scan to discover music on your device.',
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

    final playerState = ref.watch(playerNotifierProvider);

    return CustomScrollView(
      slivers: [
        // Header Controls (Play all, Shuffle all, Track count) — hidden while
        // multi-selecting so the list is unambiguous.
        if (!_selecting)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  Text(
                    '${tracks.length} songs',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      ref.read(playerNotifierProvider.notifier).setQueue(
                            tracks,
                            startIndex: 0,
                            autoPlay: true,
                          );
                    },
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Play'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      ref
                          .read(playerNotifierProvider.notifier)
                          .shuffleAll(tracks);
                    },
                    icon: const Icon(Icons.shuffle, size: 18),
                    label: const Text('Shuffle'),
                  ),
                ],
              ),
            ),
          ),

        // Track Tiles List with clean dividers
        SliverList.separated(
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            final isCurrent = playerState.currentTrack?.id == track.id;
            final selected = _selectedIds.contains(track.id);

            return TrackTile(
              track: track,
              isCurrent: isCurrent,
              isPlaying: isCurrent && playerState.isPlaying,
              trailing: _selecting
                  ? Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleSelection(track.id),
                    )
                  : null,
              onTap: _selecting
                  ? () => _toggleSelection(track.id)
                  : () {
                      ref.read(playerNotifierProvider.notifier).setQueue(
                            tracks,
                            startIndex: index,
                            autoPlay: true,
                          );
                    },
              onLongPress: () {
                if (_selecting) {
                  _toggleSelection(track.id);
                } else {
                  _enterSelection(track.id);
                }
              },
            );
          },
          separatorBuilder: (context, index) => const Divider(
            height: 1,
            thickness: 0.5,
            indent: 16,
            endIndent: 16,
          ),
        ),
      ],
    );
  }
}

/// The bottom action bar shown during multi-selection (spec 6): Add to
/// Playlist, Add to Queue, Play Next, and Favorite.
class _SelectionActionBar extends StatelessWidget {
  final VoidCallback onAddToPlaylist;
  final VoidCallback onAddToQueue;
  final VoidCallback onPlayNext;
  final VoidCallback onFavorite;

  const _SelectionActionBar({
    required this.onAddToPlaylist,
    required this.onAddToQueue,
    required this.onPlayNext,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                _selectionAction(
                  context,
                  icon: Icons.playlist_add,
                  label: 'Playlist',
                  tooltip: 'Add selected to playlist',
                  onPressed: onAddToPlaylist,
                ),
                _selectionAction(
                  context,
                  icon: Icons.queue_music,
                  label: 'Queue',
                  tooltip: 'Add selected to queue',
                  onPressed: onAddToQueue,
                ),
                _selectionAction(
                  context,
                  icon: Icons.playlist_play,
                  label: 'Play Next',
                  tooltip: 'Play selected next',
                  onPressed: onPlayNext,
                ),
                _selectionAction(
                  context,
                  icon: Icons.favorite,
                  label: 'Favorite',
                  tooltip: 'Favorite selected',
                  onPressed: onFavorite,
                ),
              ],
            ),
          ),
        ),
        const ConnectedMiniPlayer(),
      ],
    );
  }

  Widget _selectionAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Tooltip(
          message: tooltip,
          child: TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
        ),
      ),
    );
  }
}