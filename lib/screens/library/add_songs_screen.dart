import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/library_controller.dart';
import '../../models/track.dart';
import '../../services/playlists/playlist_service.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/track_tile.dart';

/// Multi-select song picker for adding songs to a playlist (Phase 3J, spec
/// 3J.16). Reuses the existing library tracks and [TrackTile] rather than
/// building another music browser.
///
/// Songs already in [playlistId] are shown as pre-selected and disabled so the
/// user cannot create duplicates (3J.17). On confirmation the selected tracks
/// are appended to the playlist in their selection order.
class AddSongsScreen extends ConsumerStatefulWidget {
  final String playlistId;

  const AddSongsScreen({super.key, required this.playlistId});

  @override
  ConsumerState<AddSongsScreen> createState() => _AddSongsScreenState();
}

class _AddSongsScreenState extends ConsumerState<AddSongsScreen> {
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryControllerProvider);
    final service = ref.read(playlistServiceProvider);
    final tracks = library.tracks;

    // Tracks already in the playlist — pre-checked and locked.
    final existingIds = service.tracksForPlaylist(widget.playlistId)
        .map((t) => t.id)
        .toSet();

    final selectableCount =
        _selectedIds.difference(existingIds).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Songs'),
        actions: [
          if (tracks.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  final allSelectable = tracks
                      .where((t) => !existingIds.contains(t.id))
                      .map((t) => t.id);
                  if (_selectedIds.containsAll(allSelectable)) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds.addAll(allSelectable);
                  }
                });
              },
              child: Text(
                _selectedIds.containsAll(
                        tracks.where((t) => !existingIds.contains(t.id)).map((t) => t.id))
                    ? 'Deselect All'
                    : 'Select All',
              ),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectableCount > 0)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _confirm(context),
                    child: Text(
                      'Add $selectableCount ${selectableCount == 1 ? "Song" : "Songs"}',
                    ),
                  ),
                ),
              ),
            ),
          const ConnectedMiniPlayer(),
        ],
      ),
      body: _buildBody(context, library, tracks, existingIds),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LibraryData library,
    List<Track> tracks,
    Set<String> existingIds,
  ) {
    final theme = Theme.of(context);

    if (tracks.isEmpty) {
      if (library.loading || library.isScanning) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No songs found', style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final alreadyInPlaylist = existingIds.contains(track.id);
        final selected = _selectedIds.contains(track.id) || alreadyInPlaylist;

        return TrackTile(
          track: track,
          showAlbum: true,
          trailing: alreadyInPlaylist
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                )
              : Checkbox(
                  value: selected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedIds.add(track.id);
                      } else {
                        _selectedIds.remove(track.id);
                      }
                    });
                  },
                ),
          onTap: alreadyInPlaylist
              ? null
              : () {
                  setState(() {
                    if (_selectedIds.contains(track.id)) {
                      _selectedIds.remove(track.id);
                    } else {
                      _selectedIds.add(track.id);
                    }
                  });
                },
          showDuration: true,
        );
      },
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 0.5,
        indent: 16,
        endIndent: 16,
      ),
    );
  }

  void _confirm(BuildContext context) {
    final service = ref.read(playlistServiceProvider);
    final allTracks = ref.read(libraryControllerProvider).tracks;
    final selected = [
      for (final track in allTracks)
        if (_selectedIds.contains(track.id)) track,
    ];

    // One transactional bulk add (spec 24) in selection order.
    // ignore: unawaited_futures
    service.addTracksToPlaylist(widget.playlistId, selected);

    if (context.mounted) {
      Navigator.pop(context);
      if (selected.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added ${selected.length} ${selected.length == 1 ? "song" : "songs"}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
