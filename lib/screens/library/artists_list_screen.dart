import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/library_controller.dart';
import '../../models/artist.dart';
import '../../widgets/collection_options_button.dart';
import '../../widgets/mini_player.dart';
import 'artist_detail_screen.dart';

/// Screen displaying all artists in the library grouped alphabetically.
class ArtistsListScreen extends ConsumerWidget {
  const ArtistsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryControllerProvider);
    final artists = library.artists;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Artists'),
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
      body: _buildBody(context, library, artists, ref),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LibraryData library,
    List<Artist> artists,
    WidgetRef ref,
  ) {
    final theme = Theme.of(context);

    if (library.error != null && artists.isEmpty) {
      return Center(child: Text('Error loading artists: ${library.error}'));
    }

    if (artists.isEmpty) {
      if (library.loading || library.isScanning) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_off, size: 72, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'No artists found',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Scan your storage to discover artists and organize your music library.',
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

    final groupedArtists = _groupArtistsAlphabetically(artists);
    final sectionKeys = groupedArtists.keys.toList();

    return CustomScrollView(
      slivers: [
        // Header with total artists count
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Text(
              '${artists.length} ${artists.length == 1 ? "artist" : "artists"}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        // Alphabetically grouped sections
        for (final letter in sectionKeys) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(context, letter),
          ),
          SliverList.separated(
            itemCount: groupedArtists[letter]!.length,
            itemBuilder: (context, index) {
              final artist = groupedArtists[letter]![index];
              return _buildArtistTile(context, library, artist);
            },
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              thickness: 0.5,
              indent: 72,
              endIndent: 16,
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Map<String, List<Artist>> _groupArtistsAlphabetically(List<Artist> artists) {
    final Map<String, List<Artist>> grouped = {};

    for (final artist in artists) {
      final trimmed = artist.name.trim();
      final firstChar = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '#';
      final letter = RegExp(r'^[A-Z]$').hasMatch(firstChar) ? firstChar : '#';

      grouped.putIfAbsent(letter, () => []).add(artist);
    }

    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });

    final Map<String, List<Artist>> sortedGrouped = {};
    for (final key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    return sortedGrouped;
  }

  Widget _buildSectionHeader(BuildContext context, String letter) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Text(
        letter,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildArtistTile(
    BuildContext context,
    LibraryData library,
    Artist artist,
  ) {
    final theme = Theme.of(context);
    final artistTracks = library.tracks
        .where((t) => t.artist == artist.name)
        .toList();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          artist.name.isNotEmpty ? artist.name[0].toUpperCase() : '?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(
        artist.name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${artist.trackCount} ${artist.trackCount == 1 ? "song" : "songs"}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CollectionOptionsButton(
            tracks: artistTracks,
            tooltip: 'Artist options',
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArtistDetailScreen(
              artist: artist,
              artistId: int.tryParse(artist.id),
            ),
          ),
        );
      },
    );
  }
}
