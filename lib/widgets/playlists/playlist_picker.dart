import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../services/playlists/playlist_service.dart';

/// Shared "choose (or create) a playlist" bottom sheet (specs 18-19).
///
/// Any feature that needs the user to pick a playlist — Song / Album / Artist /
/// Folder / multi-select "Add to Playlist", or just selecting a playlist to act
/// on — goes through this single entry point instead of rolling its own dialog
/// (spec 18).
///
/// The sheet lists every playlist (live via [playlistServiceProvider]) plus a
/// "+ New Playlist" entry that opens a name dialog; once created, the new
/// playlist automatically becomes the selection (spec 19), making
/// "Song → Add to Playlist → New Playlist" a one-flow operation.
///
/// When [tracks] is non-empty the picker runs the "Add to Playlist" flow:
/// playlists that already hold every track are marked (tapping one is a
/// no-op), the missing tracks are appended to the chosen playlist in order,
/// and a confirmation snackbar is shown. When [tracks] is null the picker only
/// *selects*: it returns the chosen (or newly created) playlist for the caller
/// to act on.
///
/// Returns the chosen playlist, or null when dismissed.
Future<Playlist?> showPlaylistPicker({
  required BuildContext context,
  required WidgetRef ref,
  List<Track>? tracks,
  String? headerTitle,
}) async {
  final service = ref.read(playlistServiceProvider);
  final theme = Theme.of(context);
  final selection = tracks;

  final picked = await showModalBottomSheet<Playlist>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: [
                Icon(Icons.playlist_add, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    headerTitle ??
                        (selection != null && selection.length == 1
                            ? 'Add to playlist'
                            : 'Choose Playlist'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (selection != null && selection.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  selection.length == 1
                      ? selection.first.title
                      : '${selection.length} songs selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const Divider(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: _PlaylistPickerList(service: service, tracks: selection),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (picked == null) return null;

  if (selection != null && selection.isNotEmpty) {
    final missing = selection
        .where((t) => !service.contains(picked.id, t.id))
        .toList();
    // Everything already added — the tap was a pure no-op selection.
    if (missing.isNotEmpty) {
      // One transactional bulk add (spec 24) instead of N single-track adds.
      await service.addTracksToPlaylist(picked.id, missing);
      if (context.mounted) {
        final missingLabel = missing.length == 1
            ? '${missing.length} song'
            : '${missing.length} songs';
        final message = missing.length == 1
            ? 'Added "${missing.first.title}" to "${picked.name}"'
            : 'Added $missingLabel to "${picked.name}"';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
  return picked;
}

class _PlaylistPickerList extends ConsumerWidget {
  final PlaylistService service;
  final List<Track>? tracks;

  const _PlaylistPickerList({required this.service, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final theme = Theme.of(context);
    final selection = tracks;

    final first = selection == null || selection.isEmpty ? null : selection.first;
    final seed = first == null
        ? null
        : (() {
            final title = first.title.trim();
            return title.length > 100 ? title.substring(0, 100) : title;
          })();

    final countLabel = selection == null || selection.length == 1
        ? '${selection?.length ?? 0} song'
        : '${selection.length} songs';

    return ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          leading: Icon(
            Icons.add,
            color: theme.colorScheme.primary,
          ),
          title: const Text('New playlist'),
          subtitle: Text(
            selection == null || selection.isEmpty
                ? 'Create a new playlist'
                : selection.length == 1
                    ? 'Create a playlist and add "${first!.title}"'
                    : 'Create a playlist and add $countLabel',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () async {
            final created =
                await _promptForNewPlaylist(context, service, seed ?? '');
            if (created != null && context.mounted) {
              Navigator.pop(context, created);
            }
          },
        ),
        if (playlists.isNotEmpty) const Divider(height: 1),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'No playlists yet. Create one above.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...playlists.map((playlist) {
            // Tracks of the selection not already in this playlist — the ones
            // adding actually inserts. Duplicates are never created.
            final missing = selection
                ?.where((t) => !service.contains(playlist.id, t.id))
                .toList();
            final allAdded = missing?.isEmpty ?? false;

            return ListTile(
              leading: Icon(
                allAdded ? Icons.playlist_add_check : Icons.playlist_play,
                color: allAdded
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${service.trackCount(playlist.id)} '
                '${service.trackCount(playlist.id) == 1 ? "song" : "songs"}'
                '${allAdded ? " • Already added" : ""}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () => Navigator.pop(context, playlist),
            );
          }),
      ],
    );
  }

  /// Opens the spec 19 name dialog, prefilled with [seed]. Returns the newly
  /// created playlist, or null when cancelled / the name is left empty.
  Future<Playlist?> _promptForNewPlaylist(
    BuildContext context,
    PlaylistService service,
    String seed,
  ) {
    return showDialog<Playlist>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(text: seed);
        return AlertDialog(
          title: const Text('New Playlist'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Playlist name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                try {
                  final playlist = await service.createPlaylist(name);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, playlist);
                  }
                } on ArgumentError {
                  // Invalid name: keep the dialog open for correction.
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}