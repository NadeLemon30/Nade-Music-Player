import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/music_repository.dart';
import '../models/playlist.dart';
import '../models/search_results.dart';
import '../services/playlists/playlist_service.dart';

/// State of media search query, category filter, and async results.
class SearchState {
  final String query;
  final SearchFilter activeFilter;
  final SearchResults results;
  final bool isLoading;
  final List<String> recentSearches;

  const SearchState({
    this.query = '',
    this.activeFilter = SearchFilter.all,
    this.results = const SearchResults(),
    this.isLoading = false,
    this.recentSearches = const [],
  });

  SearchState copyWith({
    String? query,
    SearchFilter? activeFilter,
    SearchResults? results,
    bool? isLoading,
    List<String>? recentSearches,
  }) {
    return SearchState(
      query: query ?? this.query,
      activeFilter: activeFilter ?? this.activeFilter,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      recentSearches: recentSearches ?? this.recentSearches,
    );
  }
}

/// Riverpod controller managing search execution directly against SQLite.
class SearchControllerNotifier extends Notifier<SearchState> {
  Timer? _debounceTimer;

  MusicRepository get _repository => ref.read(musicRepositoryProvider);

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });
    return const SearchState();
  }

  /// Updates the query and triggers an indexed search with a slight debounce.
  void onQueryChanged(String newQuery) {
    _debounceTimer?.cancel();

    final trimmed = newQuery.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(
        query: '',
        results: const SearchResults(),
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(
      query: newQuery,
      isLoading: true,
    );

    _debounceTimer = Timer(const Duration(milliseconds: 200), () async {
      await _executeSearch(trimmed);
    });
  }

  /// Executes search immediately without debounce.
  Future<void> submitQuery(String query) async {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(
        query: '',
        results: const SearchResults(),
        isLoading: false,
      );
      return;
    }

    _addToRecent(trimmed);
    state = state.copyWith(query: query, isLoading: true);
    await _executeSearch(trimmed);
  }

  Future<void> _executeSearch(String query) async {
    try {
      final results = await _repository.searchAll(query);
      final withPlaylists = results.copyWith(
        playlists: await _matchingPlaylists(query),
      );
      if (state.query.trim() == query) {
        state = state.copyWith(
          results: withPlaylists,
          isLoading: false,
        );
      }
    } catch (_) {
      if (state.query.trim() == query) {
        state = state.copyWith(
          results: const SearchResults(),
          isLoading: false,
        );
      }
    }
  }

  /// Playlists matching [query] (spec 16), filtered client-side from the same
  /// live [PlaylistService] data that every other playlist surface reads —
  /// never a separate index.
  Future<List<Playlist>> _matchingPlaylists(String query) async {
    final service = ref.read(playlistServiceProvider);
    await service.ready;
    final lower = query.toLowerCase();
    return service.playlists
        .where((p) => p.name.toLowerCase().contains(lower))
        .toList();
  }

  /// Sets the active category filter (All, Songs, Artists, Albums, Genres,
  /// Folders, Playlists).
  void setFilter(SearchFilter filter) {
    state = state.copyWith(activeFilter: filter);
  }

  /// Clears the active search query.
  void clearQuery() {
    _debounceTimer?.cancel();
    state = state.copyWith(
      query: '',
      results: const SearchResults(),
      isLoading: false,
    );
  }

  void _addToRecent(String query) {
    final list = List<String>.from(state.recentSearches)
      ..remove(query)
      ..insert(0, query);
    if (list.length > 10) {
      list.removeLast();
    }
    state = state.copyWith(recentSearches: List.unmodifiable(list));
  }

  /// Clears all recent search history.
  void clearRecentSearches() {
    state = state.copyWith(recentSearches: const []);
  }

  /// Removes a single query from recent searches.
  void removeRecentSearch(String query) {
    final list = List<String>.from(state.recentSearches)..remove(query);
    state = state.copyWith(recentSearches: List.unmodifiable(list));
  }
}

/// Provider exposing [SearchControllerNotifier] and [SearchState].
final searchControllerProvider =
    NotifierProvider<SearchControllerNotifier, SearchState>(
        SearchControllerNotifier.new);
