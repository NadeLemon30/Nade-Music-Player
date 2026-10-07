import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/library_controller.dart';
import '../../data/repositories/music_repository.dart';
import '../../models/genre.dart';
import '../../widgets/mini_player.dart';
import 'genre_detail_screen.dart';

/// Screen displaying all musical genres in the library.
class GenresListScreen extends ConsumerWidget {
  const GenresListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(libraryGenresProvider);
    final library = ref.watch(libraryControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Genres'),
        actions: [
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
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: genresAsync.when(
        data: (genres) {
          if (genres.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.graphic_eq, size: 72, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'No genres found',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scan your storage to discover musical genres and categorize your music.',
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

          // Sort genres alphabetically
          final sortedGenres = List<Genre>.from(genres)
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          return CustomScrollView(
            slivers: [
              // Header with total genre count
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    '${sortedGenres.length} ${sortedGenres.length == 1 ? "genre" : "genres"}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              // Genres List
              SliverList.separated(
                itemCount: sortedGenres.length,
                itemBuilder: (context, index) {
                  final genre = sortedGenres[index];
                  return _buildGenreTile(context, genre);
                },
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 72,
                  endIndent: 16,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Error loading genres: $err'),
        ),
      ),
    );
  }

  Widget _buildGenreTile(BuildContext context, Genre genre) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.graphic_eq,
          color: theme.colorScheme.onSecondaryContainer,
          size: 22,
        ),
      ),
      title: Text(
        genre.name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${genre.trackCount} ${genre.trackCount == 1 ? "song" : "songs"}',
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
  }
}
