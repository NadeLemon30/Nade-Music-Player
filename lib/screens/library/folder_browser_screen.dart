import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/library_controller.dart';
import '../../player/player_controller.dart';
import '../../data/repositories/music_repository.dart';
import '../../models/folder_node.dart';
import '../../models/track.dart';
import '../../services/folders/folder_service.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/playlist_picker_sheet.dart';
import '../../widgets/track_tile.dart';

/// Screen enabling hierarchical browsing of device audio files strictly by
/// physical [filePath], driven by the actual scanned files (scoped-storage
/// safe) rather than arbitrary filesystem access.
///
/// When [folderPath] is null the root view shows the normalized top-level
/// folders (`Music`, `Download`, `Other`). Otherwise it shows the folders and
/// files directly inside [folderPath].
class FolderBrowserScreen extends ConsumerWidget {
  final String? folderPath;

  const FolderBrowserScreen({
    super.key,
    this.folderPath,
  });

  static Widget _folderTile({
    required BuildContext context,
    required FolderNode node,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 2.0,
      ),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.folder,
          color: theme.colorScheme.secondary,
          size: 24,
        ),
      ),
      title: Text(
        node.name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(libraryTracksProvider);
    final playerState = ref.watch(playerNotifierProvider);
    final libraryState = ref.watch(libraryControllerProvider);
    final theme = Theme.of(context);
    final folderService = FolderService();

    final title = folderPath != null
        ? folderService.getName(folderPath!)
        : 'Folders';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (folderPath != null)
            IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Add Folder to Playlist',
              onPressed: () {
                final allTracks = tracksAsync.value ?? const <Track>[];
                final folderTracks = folderService
                    .getTracksInFolderRecursive(folderPath!, allTracks);
                if (folderTracks.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No audio files in this folder'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                showAddTracksToPlaylistSheet(context, ref, folderTracks);
              },
            ),
          IconButton(
            icon: libraryState.isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: libraryState.isScanning
                ? null
                : () => ref
                    .read(libraryControllerProvider.notifier)
                    .scanAndRefresh(),
            tooltip: 'Rescan Storage',
          ),
        ],
      ),
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: tracksAsync.when(
        data: (allTracks) {
          if (allTracks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.folder_off_outlined,
                        size: 72, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      folderPath != null
                          ? 'Folder is empty'
                          : 'No music folders found',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scan local storage to discover audio folders on your device.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: libraryState.isScanning
                          ? null
                          : () => ref
                              .read(libraryControllerProvider.notifier)
                              .scanAndRefresh(),
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        libraryState.isScanning
                            ? 'Scanning...'
                            : 'Scan Storage',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final List<FolderNode> folders;
          List<FolderNode> files;
          List<Track> directTracks;
          String? pathLabel;

          if (folderPath == null) {
            // Root view â€” normalized top-level folders only.
            folders = folderService.getTopLevelFolders(allTracks);
            files = const [];
            directTracks = const [];
          } else {
            final nodes = folderService.getChildren(folderPath!, allTracks);
            folders = nodes.where((n) => n.isFolder).toList();
            files = nodes.where((n) => !n.isFolder).toList();
            directTracks = _tracksFromNodes(files, allTracks);
            pathLabel = folderPath;
          }

          return CustomScrollView(
            slivers: [
              if (pathLabel != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      pathLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),

              if (folders.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 12.0,
                      bottom: 4.0,
                    ),
                    child: Text(
                      'Folders (${folders.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                SliverList.separated(
                  itemCount: folders.length,
                  itemBuilder: (context, index) {
                    final node = folders[index];
                    return _folderTile(
                      context: context,
                      node: node,
                      theme: theme,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FolderBrowserScreen(
                              folderPath: node.path,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  separatorBuilder: (context, index) => const Divider(
                    height: 1,
                    thickness: 0.4,
                    indent: 64,
                    endIndent: 16,
                  ),
                ),
              ],

              if (files.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 16.0,
                      bottom: 4.0,
                    ),
                    child: Text(
                      'Files (${files.length})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                SliverList.separated(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final track = directTracks[index];
                    final isCurrent =
                        playerState.currentTrack?.id == track.id;

                    return TrackTile(
                      track: track,
                      isCurrent: isCurrent,
                      isPlaying: isCurrent && playerState.isPlaying,
                      onTap: () {
                        ref.read(playerNotifierProvider.notifier).setQueue(
                              directTracks,
                              startIndex: index,
                              autoPlay: true,
                            );
                      },
                    );
                  },
                  separatorBuilder: (context, index) => const Divider(
                    height: 1,
                    thickness: 0.4,
                    indent: 16,
                    endIndent: 16,
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Error loading folders: $err'),
        ),
      ),
    );
  }

  /// Resolves the `Track` for each file [FolderNode] in the same order.
  List<Track> _tracksFromNodes(
    List<FolderNode> fileNodes,
    List<Track> allTracks,
  ) {
    final byPath = <String, Track>{
      for (final t in allTracks) t.filePath: t,
    };
    final result = <Track>[];
    for (final node in fileNodes) {
      final track = byPath[node.path];
      if (track != null) result.add(track);
    }
    return result;
  }
}
