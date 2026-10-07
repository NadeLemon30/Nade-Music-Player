import 'album.dart';
import 'artist.dart';
import 'folder_node.dart';
import 'genre.dart';
import 'playlist.dart';
import 'track.dart';

/// Available category filters for narrowing down search results.
enum SearchFilter {
  all('All'),
  songs('Songs'),
  artists('Artists'),
  albums('Albums'),
  genres('Genres'),
  folders('Folders'),
  playlists('Playlists');

  final String label;
  const SearchFilter(this.label);
}

/// Container for structured search results across all library categories.
class SearchResults {
  /// The search query term.
  final String query;

  /// Matching audio tracks.
  final List<Track> tracks;

  /// Matching artists.
  final List<Artist> artists;

  /// Matching albums.
  final List<Album> albums;

  /// Matching musical genres.
  final List<Genre> genres;

  /// Matching physical filesystem folders.
  final List<FolderNode> folders;

  /// Matching user playlists (spec 16), filtered from the live playlist data.
  final List<Playlist> playlists;

  const SearchResults({
    this.query = '',
    this.tracks = const [],
    this.artists = const [],
    this.albums = const [],
    this.genres = const [],
    this.folders = const [],
    this.playlists = const [],
  });

  /// Whether all categories in the search results are empty.
  bool get isEmpty =>
      tracks.isEmpty &&
      artists.isEmpty &&
      albums.isEmpty &&
      genres.isEmpty &&
      folders.isEmpty &&
      playlists.isEmpty;

  /// Whether at least one category has matching results.
  bool get isNotEmpty => !isEmpty;

  /// Total count of matching items across all categories.
  int get totalCount =>
      tracks.length +
      artists.length +
      albums.length +
      genres.length +
      folders.length +
      playlists.length;

  SearchResults copyWith({
    String? query,
    List<Track>? tracks,
    List<Artist>? artists,
    List<Album>? albums,
    List<Genre>? genres,
    List<FolderNode>? folders,
    List<Playlist>? playlists,
  }) {
    return SearchResults(
      query: query ?? this.query,
      tracks: tracks ?? this.tracks,
      artists: artists ?? this.artists,
      albums: albums ?? this.albums,
      genres: genres ?? this.genres,
      folders: folders ?? this.folders,
      playlists: playlists ?? this.playlists,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResults &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          tracks.length == other.tracks.length &&
          artists.length == other.artists.length &&
          albums.length == other.albums.length &&
          genres.length == other.genres.length &&
          folders.length == other.folders.length &&
          playlists.length == other.playlists.length;

  @override
  int get hashCode => Object.hash(
        query,
        tracks.length,
        artists.length,
        albums.length,
        genres.length,
        folders.length,
        playlists.length,
      );

  @override
  String toString() =>
      'SearchResults(query: "$query", songs: ${tracks.length}, artists: ${artists.length}, albums: ${albums.length}, genres: ${genres.length}, folders: ${folders.length}, playlists: ${playlists.length})';
}
