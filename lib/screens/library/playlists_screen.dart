import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/playlist_history_repository.dart';
import '../../models/playlist.dart';
import '../../player/player_controller.dart';
import '../../services/playlists/playlist_service.dart';
import '../../widgets/mini_player.dart';
import 'add_songs_screen.dart';
import 'playlist_detail_screen.dart';

/// UI-only ordering applied to the playlist list (Phase 3K, spec 3K.2).
/// Sorting never changes the stored playlist order — it only affects the order
/// the screen renders them in. Newest is the default.
enum PlaylistSort { newest, oldest, nameAZ, nameZA }

/// Orders [playlists] per the UI-only [PlaylistSort]. Pure and deterministic
/// so the ordering rules are unit-testable; the screen never mutates the stored
/// playlist order.
List<Playlist> sortedPlaylists(
  List<Playlist> playlists,
  PlaylistSort sort,
) {
  final result = [...playlists];
  return switch (sort) {
    PlaylistSort.newest => result
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    PlaylistSort.oldest => result
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    PlaylistSort.nameAZ => result
      ..sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    PlaylistSort.nameZA => result
      ..sort((a, b) =>
          b.name.toLowerCase().compareTo(a.name.toLowerCase())),
  };
}

/// "Playlists" — the user's created playlist collections (Phase 3J, 3K).
///
/// Lists every playlist (name, song count, creation date) with create / rename
/// / delete actions, live client-side search (3K.1), UI-only sorting (3K.2),
/// and an empty state. Tapping a playlist opens the [PlaylistDetailScreen].
class PlaylistsScreen extends ConsumerStatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  ConsumerState<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends ConsumerState<PlaylistsScreen> {
  final _searchController = TextEditingController();
  PlaylistSort _sort = PlaylistSort.newest;

  /// Playlist ids with playlist-level play history, most recently played
  /// first (spec 22). Empty until the async repository read completes.
  List<String> _recentPlaylistIds = const [];
  bool _recentLoaded = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playlistsAsync = ref.watch(playlistsProvider);
    final playlists = playlistsAsync.value ?? const [];

    // Lazily load playlist-level history (spec 22) once per state lifetime.
    _ensureRecentlyPlayedLoaded();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          if (playlists.isNotEmpty)
            IconButton(
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              onPressed: () => _showSortMenu(context),
            ),
          IconButton(
            tooltip: 'New playlist',
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateDialog(context, ref),
          ),
        ],
      ),
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: playlists.isEmpty
          ? _buildEmpty(context, theme, ref)
          : _buildSearchableList(ref, playlists),
    );
  }

  void _ensureRecentlyPlayedLoaded() {
    if (_recentLoaded) return;
    _recentLoaded = true;
    _loadRecentlyPlayed();
  }

  Future<void> _loadRecentlyPlayed() async {
    final entries = await ref
        .read(playlistHistoryRepositoryProvider)
        .getRecentlyPlayed();
    if (!mounted) return;
    setState(() {
      _recentPlaylistIds = [for (final e in entries) e.playlistId];
    });
  }

  /// Playlists in [_recentPlaylistIds] that still exist and match the current
  /// search query, in history order (spec 22).
  List<Playlist> _recentVisible(List<Playlist> playlists) {
    final query = _searchController.text.trim().toLowerCase();
    final result = <Playlist>[];
    for (final id in _recentPlaylistIds) {
      for (final p in playlists) {
        if (p.id != id) continue;
        if (query.isEmpty || p.name.toLowerCase().contains(query)) {
          result.add(p);
        }
        break;
      }
    }
    return result;
  }

  /// Filters by the current search query, then orders by [_sort]. Pure UI:
  /// the underlying [PlaylistService] keeps its own (creation) order.
  List<Playlist> _applyView(List<Playlist> playlists) {
    final query = _searchController.text.trim().toLowerCase();
    final result = query.isEmpty
        ? [...playlists]
        : playlists
            .where((p) => p.name.toLowerCase().contains(query))
            .toList();

    return sortedPlaylists(result, _sort);
  }

  Widget _buildSearchableList(WidgetRef ref, List<Playlist> playlists) {
    final visible = _applyView(playlists);
    final recentVisible = _recentVisible(playlists);
    final query = _searchController.text.trim();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search playlists',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty && recentVisible.isEmpty
              ? _buildNoMatches(context, query)
              : _buildList(context, ref, visible, recentVisible),
        ),
      ],
    );
  }

  Widget _buildNoMatches(BuildContext context, String query) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No playlists match "$query"',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {});
            },
            child: const Text('Clear search'),
          ),
        ],
      ),
    );
  }

  void _showSortMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Sort playlists',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ...PlaylistSort.values.map((option) {
              return ListTile(
                leading: Icon(
                  option == _sort
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: option == _sort
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                title: Text(_sortLabel(option)),
                onTap: () {
                  setState(() => _sort = option);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _sortLabel(PlaylistSort option) {
    return switch (option) {
      PlaylistSort.newest => 'Newest',
      PlaylistSort.oldest => 'Oldest',
      PlaylistSort.nameAZ => 'Name (A-Z)',
      PlaylistSort.nameZA => 'Name (Z-A)',
    };
  }

  Widget _buildEmpty(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.playlist_add,
            size: 72,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('No playlists yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Create a playlist, then add songs to it from any track\'s '
            'options menu.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showCreateDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Create Playlist'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return _PlaylistSectionHeader(title: title);
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<Playlist> playlists,
    List<Playlist> recent,
  ) {
    final items = <Widget>[];
    if (recent.isNotEmpty) {
      // Spec 22: sections only surface when playlist-level history exists.
      items.add(_sectionHeader('Recently Played'));
      items.addAll([for (final p in recent) _playlistTile(context, ref, p)]);
      items.add(_sectionHeader('All Playlists'));
    }
    items.addAll([for (final p in playlists) _playlistTile(context, ref, p)]);

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final child = items[index];
        if (child is _PlaylistSectionHeader) return child;
        final isLast = index == items.length - 1;
        if (isLast) return child;
        return Column(
          children: [
            child,
            const Divider(height: 1, thickness: 0.5, indent: 16, endIndent: 16),
          ],
        );
      },
    );
  }

  Widget _playlistTile(BuildContext context, WidgetRef ref, Playlist playlist) {
    final service = ref.read(playlistServiceProvider);
    final count = service.trackCount(playlist.id);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.playlist_play,
          color: Theme.of(context).colorScheme.primary,
          size: 24,
        ),
      ),
      title: Text(
        playlist.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      subtitle: Text(
        '${count == 1 ? "1 song" : "$count songs"} • '
        'Created ${_formatDate(playlist.createdAt)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) => switch (action) {
          'play' => _playPlaylist(ref, playlist),
          'shuffle' => _shufflePlaylist(ref, playlist),
          'playNext' => _playNextPlaylist(ref, playlist),
          'addToQueue' => _addToQueuePlaylist(ref, playlist),
          'addSongs' => _openAddSongs(context, playlist),
          'rename' => _showRenameDialog(context, ref, playlist),
          'delete' => _showDeleteDialog(context, ref, playlist),
          _ => null,
        },
        itemBuilder: (ctx) => [
          if (count > 0) ...[
            const PopupMenuItem(
              value: 'play',
              child: ListTile(
                leading: Icon(Icons.play_arrow),
                title: Text('Play'),
              ),
            ),
            const PopupMenuItem(
              value: 'shuffle',
              child: ListTile(
                leading: Icon(Icons.shuffle),
                title: Text('Shuffle'),
              ),
            ),
            const PopupMenuItem(
              value: 'playNext',
              child: ListTile(
                leading: Icon(Icons.playlist_play),
                title: Text('Play Next'),
              ),
            ),
            const PopupMenuItem(
              value: 'addToQueue',
              child: ListTile(
                leading: Icon(Icons.queue_music),
                title: Text('Add to Queue'),
              ),
            ),
          ],
          const PopupMenuItem(
            value: 'addSongs',
            child: ListTile(
              leading: Icon(Icons.playlist_add),
              title: Text('Add Songs'),
            ),
          ),
          const PopupMenuItem(
            value: 'rename',
            child: ListTile(
              leading: Icon(Icons.edit),
              title: Text('Rename'),
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Delete'),
            ),
          ),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
          ),
        );
      },
    );
  }

  void _playPlaylist(WidgetRef ref, Playlist playlist) {
    final tracks = ref
        .read(playlistServiceProvider)
        .tracksForPlaylist(playlist.id);
    if (tracks.isEmpty) return;
    unawaited(
      ref.read(playlistHistoryRepositoryProvider).recordPlay(playlist.id),
    );
    ref.read(playerNotifierProvider.notifier).setQueue(
          tracks,
          startIndex: 0,
          autoPlay: true,
        );
  }

  void _shufflePlaylist(WidgetRef ref, Playlist playlist) {
    final tracks = ref
        .read(playlistServiceProvider)
        .tracksForPlaylist(playlist.id);
    if (tracks.isEmpty) return;
    unawaited(
      ref.read(playlistHistoryRepositoryProvider).recordPlay(playlist.id),
    );
    ref
        .read(playerNotifierProvider.notifier)
        .shuffleAll(tracks);
  }

  void _playNextPlaylist(WidgetRef ref, Playlist playlist) {
    final tracks = ref
        .read(playlistServiceProvider)
        .tracksForPlaylist(playlist.id);
    if (tracks.isEmpty) return;
    ref.read(playerNotifierProvider.notifier).playNextAll(tracks);
  }

  void _addToQueuePlaylist(WidgetRef ref, Playlist playlist) {
    final tracks = ref
        .read(playlistServiceProvider)
        .tracksForPlaylist(playlist.id);
    if (tracks.isEmpty) return;
    ref.read(playerNotifierProvider.notifier).addToQueueAll(tracks);
  }

  void _openAddSongs(BuildContext context, Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddSongsScreen(playlistId: playlist.id),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _PlaylistNameDialog(
        title: 'New Playlist',
        confirmLabel: 'Create',
        onSubmit: (name) async {
          await ref
              .read(playlistServiceProvider)
              .createPlaylist(name);
          if (ctx.mounted) {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Created "$name"'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _PlaylistNameDialog(
        title: 'Rename Playlist',
        confirmLabel: 'Rename',
        initialName: playlist.name,
        onSubmit: (name) async {
          await ref
              .read(playlistServiceProvider)
              .renamePlaylist(playlist.id, name);
          if (ctx.mounted) {
            Navigator.pop(ctx);
          }
        },
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text('"${playlist.name}" will be removed. '
            'The songs themselves are untouched.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(playlistServiceProvider)
                  .deletePlaylist(playlist.id);
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// Section header for the Playlists screen (spec 22). Marked with its own type
/// so the list builder can skip separators beneath headers.
class _PlaylistSectionHeader extends StatelessWidget {
  final String title;

  const _PlaylistSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Modal dialog for creating or renaming a playlist.
class _PlaylistNameDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String? initialName;
  final Future<void> Function(String name) onSubmit;

  const _PlaylistNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialName,
    required this.onSubmit,
  });

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialName ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid =>
      _controller.text.trim().isNotEmpty && !_submitting;

  Future<void> _submit() async {
    if (!_valid) return;
    setState(() => _submitting = true);
    await widget.onSubmit(_controller.text.trim());
    if (mounted) {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(
          labelText: 'Playlist name',
          hintText: 'e.g. Road Trip',
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}