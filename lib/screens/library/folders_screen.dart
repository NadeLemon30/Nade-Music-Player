import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_controller.dart';
import '../../data/repositories/music_repository.dart';
import '../../models/folder_node.dart';
import '../../models/track.dart';
import '../../services/folders/folder_service.dart';
import '../../widgets/collection_options_button.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/track_tile.dart';

/// Top-level Folders screen.
///
/// The screen is built entirely from the scanned `Track.filePath` values, so it
/// works within Android's scoped storage without arbitrary filesystem access.
class FoldersScreen extends ConsumerStatefulWidget {
  const FoldersScreen({super.key});

  @override
  ConsumerState<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends ConsumerState<FoldersScreen> {
  final FolderService _folderService = FolderService();

  bool _loading = true;
  String? _error;

  List<Track> _tracks = [];

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  MusicRepository get _repository => ref.read(musicRepositoryProvider);

  Future<void> _loadTracks() async {
    try {
      final tracks = await _repository.getAllTracks();

      if (!mounted) return;

      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Folders'),
      ),
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(_error!),
      );
    }

    if (_tracks.isEmpty) {
      return const Center(
        child: Text('No music found'),
      );
    }

    return _FolderContents(
      path: _getInitialPath(),
      tracks: _tracks,
      folderService: _folderService,
    );
  }

  /// Temporary initial-path heuristic.
  ///
  /// This makes the first available track's directory the starting point. The
  /// final version should derive the normalized top-level folders (e.g.
  /// `Music`, `Download`, `Other`) instead of pinning a single directory.
  String _getInitialPath() {
    final availableTracks = _tracks.where((track) => track.isAvailable);

    if (availableTracks.isEmpty) {
      return '';
    }

    return _folderService.directoryOf(availableTracks.first.filePath);
  }
}

/// Renders the contents of a folder as a drillable list of folders and files.
class _FolderContents extends ConsumerStatefulWidget {
  final String path;
  final List<Track> tracks;
  final FolderService folderService;

  const _FolderContents({
    required this.path,
    required this.tracks,
    required this.folderService,
  });

  @override
  ConsumerState<_FolderContents> createState() => _FolderContentsState();
}

class _FolderContentsState extends ConsumerState<_FolderContents> {
  late String _currentPath;
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _currentPath = widget.path;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodes = widget.folderService.getChildren(_currentPath, widget.tracks);
    final folders = nodes.where((n) => n.isFolder).toList();
    final files = nodes.where((n) => !n.isFolder).toList();
    final tracks = _tracksForNodes(files);

    return CustomScrollView(
      slivers: [
        // Header: current folder name + physical path + back control
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_history.isNotEmpty) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Up',
                        onPressed: _goUp,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Icon(
                      Icons.folder,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.folderService.getName(_currentPath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _currentPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: Divider(height: 1, thickness: 0.5)),

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
            itemBuilder: (context, index) => _folderTile(context, folders[index]),
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
              final track = tracks[index];
              return TrackTile(
                track: track,
                isCurrent:
                    ref.watch(playerNotifierProvider).currentTrack?.id == track.id,
                isPlaying: ref.watch(playerNotifierProvider.select(
                  (s) => s.isPlaying && s.currentTrack?.id == track.id,
                )),
                onTap: () {
                  ref.read(playerNotifierProvider.notifier).setQueue(
                        tracks,
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
  }

  Widget _folderTile(BuildContext context, FolderNode node) {
    final theme = Theme.of(context);
    final folderTracks =
        widget.folderService.getTracksInFolderRecursive(node.path, widget.tracks);
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CollectionOptionsButton(
            tracks: folderTracks,
            includePlayNext: false,
            tooltip: 'Folder options',
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () => _enterFolder(node.path),
    );
  }

  List<Track> _tracksForNodes(List<FolderNode> fileNodes) {
    final byPath = <String, Track>{
      for (final t in widget.tracks) t.filePath: t,
    };
    final result = <Track>[];
    for (final node in fileNodes) {
      final track = byPath[node.path];
      if (track != null) {
        result.add(track);
      }
    }
    return result;
  }

  void _enterFolder(String path) {
    setState(() {
      _history.add(_currentPath);
      _currentPath = path;
    });
  }

  void _goUp() {
    if (_history.isEmpty) return;
    setState(() {
      _currentPath = _history.removeLast();
    });
  }
}
