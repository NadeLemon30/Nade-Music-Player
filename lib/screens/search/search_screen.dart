import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_controller.dart';
import '../../controllers/search_controller.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/folder_node.dart';
import '../../models/genre.dart';
import '../../models/playlist.dart';
import '../../models/search_results.dart';
import '../../models/track.dart';
import '../../widgets/album_art.dart';
import '../../widgets/track_tile.dart';
import '../library/album_detail_screen.dart';
import '../library/artist_detail_screen.dart';
import '../library/folder_browser_screen.dart';
import '../library/genre_detail_screen.dart';
import '../library/playlist_detail_screen.dart';

/// Screen providing instant, indexed SQLite search across songs, artists,
/// albums, genres, and folders, plus client-side playlist matching.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(searchControllerProvider).query;
    _textController = TextEditingController(text: initialQuery);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchControllerProvider);
    final searchNotifier = ref.read(searchControllerProvider.notifier);
    final theme = Theme.of(context);

    // Keep text controller in sync if query was updated externally
    if (_textController.text != searchState.query) {
      _textController.value = TextEditingValue(
        text: searchState.query,
        selection: TextSelection.collapsed(offset: searchState.query.length),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: TextField(
          controller: _textController,
          focusNode: _focusNode,
          onChanged: searchNotifier.onQueryChanged,
          onSubmitted: searchNotifier.submitQuery,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search songs, artists, albums, genres, folders, playlists...',
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            border: InputBorder.none,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: searchState.query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _textController.clear();
                      searchNotifier.clearQuery();
                    },
                  )
                : null,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Column(
            children: [
              if (searchState.isLoading)
                const LinearProgressIndicator(minHeight: 2)
              else
                const SizedBox(height: 2),
              _buildFilterChips(searchState, searchNotifier, theme),
            ],
          ),
        ),
      ),
      body: _buildBody(searchState, searchNotifier, theme),
    );
  }

  Widget _buildFilterChips(
    SearchState searchState,
    SearchControllerNotifier searchNotifier,
    ThemeData theme,
  ) {
    final results = searchState.results;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: SearchFilter.values.map((filter) {
          final isSelected = searchState.activeFilter == filter;
          String label = filter.label;

          // Add count badges when query is active
          if (searchState.query.isNotEmpty) {
            switch (filter) {
              case SearchFilter.all:
                if (results.totalCount > 0) {
                  label = 'All (${results.totalCount})';
                }
                break;
              case SearchFilter.songs:
                if (results.tracks.isNotEmpty) {
                  label = 'Songs (${results.tracks.length})';
                }
                break;
              case SearchFilter.artists:
                if (results.artists.isNotEmpty) {
                  label = 'Artists (${results.artists.length})';
                }
                break;
              case SearchFilter.albums:
                if (results.albums.isNotEmpty) {
                  label = 'Albums (${results.albums.length})';
                }
                break;
              case SearchFilter.genres:
                if (results.genres.isNotEmpty) {
                  label = 'Genres (${results.genres.length})';
                }
                break;
              case SearchFilter.folders:
                if (results.folders.isNotEmpty) {
                  label = 'Folders (${results.folders.length})';
                }
                break;
              case SearchFilter.playlists:
                if (results.playlists.isNotEmpty) {
                  label = 'Playlists (${results.playlists.length})';
                }
                break;
            }
          }

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => searchNotifier.setFilter(filter),
              showCheckmark: false,
              labelStyle: theme.textTheme.labelMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody(
    SearchState searchState,
    SearchControllerNotifier searchNotifier,
    ThemeData theme,
  ) {
    if (searchState.query.trim().isEmpty) {
      return _buildEmptyQueryView(searchState, searchNotifier, theme);
    }

    if (searchState.results.isEmpty && !searchState.isLoading) {
      return _buildNoResultsView(searchState.query, theme);
    }

    switch (searchState.activeFilter) {
      case SearchFilter.all:
        return _buildCategorizedResultsView(searchState.results, theme);
      case SearchFilter.songs:
        return _buildSongsListView(searchState.results.tracks, theme);
      case SearchFilter.artists:
        return _buildArtistsListView(searchState.results.artists, theme);
      case SearchFilter.albums:
        return _buildAlbumsListView(searchState.results.albums, theme);
      case SearchFilter.genres:
        return _buildGenresListView(searchState.results.genres, theme);
      case SearchFilter.folders:
        return _buildFoldersListView(searchState.results.folders, theme);
      case SearchFilter.playlists:
        return _buildPlaylistsListView(searchState.results.playlists, theme);
    }
  }

  Widget _buildEmptyQueryView(
    SearchState searchState,
    SearchControllerNotifier searchNotifier,
    ThemeData theme,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        if (searchState.recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: searchNotifier.clearRecentSearches,
                child: const Text('Clear all'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: searchState.recentSearches.map((query) {
              return ActionChip(
                label: Text(query),
                avatar: const Icon(Icons.history, size: 16),
                onPressed: () {
                  _textController.text = query;
                  searchNotifier.submitQuery(query);
                },
              );
            }).toList(),
          ),
          const Divider(height: 36),
        ],
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32.0),
            child: Column(
              children: [
                Icon(
                  Icons.search_outlined,
                  size: 64,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'Search your media library',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quickly find tracks, artists, albums, genres, local folders, '
                  'and playlists.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoResultsView(String query, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No matches found',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No songs, artists, albums, genres, folders, or playlists '
              'matching "$query".',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorizedResultsView(SearchResults results, ThemeData theme) {
    final playerState = ref.watch(playerNotifierProvider);

    return CustomScrollView(
      slivers: [
        // 1. Albums Section
        if (results.albums.isNotEmpty) ...[
          _buildSectionHeaderSliver('Albums', results.albums.length, theme),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: results.albums.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final album = results.albums[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AlbumDetailScreen(album: album),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AlbumArt(
                            album: album,
                            size: 100,
                            borderRadius: 8,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            album.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            album.albumArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],

        // 2. Artists Section
        if (results.artists.isNotEmpty) ...[
          _buildSectionHeaderSliver('Artists', results.artists.length, theme),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: results.artists.length,
                separatorBuilder: (context, index) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final artist = results.artists[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArtistDetailScreen(artist: artist),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 72,
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor:
                                theme.colorScheme.primaryContainer,
                            child: Icon(
                              Icons.person,
                              size: 32,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],

        // 3. Songs Section
        if (results.tracks.isNotEmpty) ...[
          _buildSectionHeaderSliver('Songs', results.tracks.length, theme),
          SliverList.separated(
            itemCount: results.tracks.length,
            itemBuilder: (context, index) {
              final track = results.tracks[index];
              final isCurrent = playerState.currentTrack?.id == track.id;

              return TrackTile(
                track: track,
                isCurrent: isCurrent,
                isPlaying: isCurrent && playerState.isPlaying,
                onTap: () {
                  ref.read(playerNotifierProvider.notifier).setQueue(
                        results.tracks,
                        startIndex: index,
                        autoPlay: true,
                      );
                },
              );
            },
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],

        // 4. Folders Section
        if (results.folders.isNotEmpty) ...[
          _buildSectionHeaderSliver('Folders', results.folders.length, theme),
          SliverList.separated(
            itemCount: results.folders.length,
            itemBuilder: (context, index) {
              final folder = results.folders[index];
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.folder,
                    color: theme.colorScheme.secondary,
                    size: 24,
                  ),
                ),
                title: Text(
                  folder.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  folder.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          FolderBrowserScreen(folderPath: folder.path),
                    ),
                  );
                },
              );
            },
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              indent: 64,
              endIndent: 16,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],

        // 5. Playlists Section
        if (results.playlists.isNotEmpty) ...[
          _buildSectionHeaderSliver('Playlists', results.playlists.length, theme),
          SliverList.separated(
            itemCount: results.playlists.length,
            itemBuilder: (context, index) {
              final playlist = results.playlists[index];
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.queue_music,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
                title: Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Playlist',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PlaylistDetailScreen(playlistId: playlist.id),
                    ),
                  );
                },
              );
            },
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              indent: 64,
              endIndent: 16,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],

        // 6. Genres Section
        if (results.genres.isNotEmpty) ...[
          _buildSectionHeaderSliver('Genres', results.genres.length, theme),
          SliverList.separated(
            itemCount: results.genres.length,
            itemBuilder: (context, index) {
              final genre = results.genres[index];
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.graphic_eq,
                    color: theme.colorScheme.tertiary,
                    size: 24,
                  ),
                ),
                title: Text(
                  genre.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${genre.trackCount} tracks',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GenreDetailScreen(genre: genre),
                    ),
                  );
                },
              );
            },
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              indent: 64,
              endIndent: 16,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ],
    );
  }

  Widget _buildSongsListView(List<Track> tracks, ThemeData theme) {
    final playerState = ref.watch(playerNotifierProvider);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isCurrent = playerState.currentTrack?.id == track.id;

        return TrackTile(
          track: track,
          isCurrent: isCurrent,
          isPlaying: isCurrent && playerState.isPlaying,
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
        indent: 16,
        endIndent: 16,
      ),
    );
  }

  Widget _buildArtistsListView(List<Artist> artists, ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.person,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          title: Text(
            artist.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${artist.trackCount} tracks',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ArtistDetailScreen(artist: artist),
              ),
            );
          },
        );
      },
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        indent: 64,
        endIndent: 16,
      ),
    );
  }

  Widget _buildAlbumsListView(List<Album> albums, ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return ListTile(
          leading: AlbumArt(
            album: album,
            size: 48,
            borderRadius: 6,
          ),
          title: Text(
            album.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${album.albumArtist} • ${album.trackCount} tracks',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AlbumDetailScreen(album: album),
              ),
            );
          },
        );
      },
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        indent: 64,
        endIndent: 16,
      ),
    );
  }

  Widget _buildGenresListView(List<Genre> genres, ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: genres.length,
      itemBuilder: (context, index) {
        final genre = genres[index];
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.graphic_eq,
              color: theme.colorScheme.tertiary,
              size: 24,
            ),
          ),
          title: Text(
            genre.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${genre.trackCount} tracks',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GenreDetailScreen(genre: genre),
              ),
            );
          },
        );
      },
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        indent: 64,
        endIndent: 16,
      ),
    );
  }

  Widget _buildFoldersListView(List<FolderNode> folders, ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final folder = folders[index];
        return ListTile(
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
            folder.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            folder.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FolderBrowserScreen(folderPath: folder.path),
              ),
            );
          },
        );
      },
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        indent: 64,
        endIndent: 16,
      ),
    );
  }

  Widget _buildPlaylistsListView(List<Playlist> playlists, ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.queue_music,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            'Playlist',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
              ),
            );
          },
        );
      },
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        indent: 64,
        endIndent: 16,
      ),
    );
  }

  Widget _buildSectionHeaderSliver(String title, int count, ThemeData theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 12.0,
          bottom: 8.0,
        ),
        child: Row(
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
