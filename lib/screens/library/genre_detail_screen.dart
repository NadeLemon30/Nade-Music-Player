import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_controller.dart';
import '../../data/repositories/music_repository.dart';
import '../../models/genre.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/track_tile.dart';

/// Detail screen displaying all songs belonging to a selected musical genre.
class GenreDetailScreen extends ConsumerWidget {
  final Genre genre;

  const GenreDetailScreen({
    super.key,
    required this.genre,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(genreTracksProvider(genre.id));
    final playerState = ref.watch(playerNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(genre.name),
      ),
      bottomNavigationBar: const ConnectedMiniPlayer(),
      body: tracksAsync.when(
        data: (tracks) {
          final songCountText =
              '${tracks.length} ${tracks.length == 1 ? "song" : "songs"}';

          return CustomScrollView(
            slivers: [
              // Header with Genre Name, song count, and Play/Shuffle actions
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.graphic_eq,
                          size: 28,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              genre.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              songCountText,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: tracks.isEmpty
                            ? null
                            : () {
                                ref.read(playerNotifierProvider.notifier).setQueue(
                                      tracks,
                                      startIndex: 0,
                                      autoPlay: true,
                                    );
                              },
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Play'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: tracks.isEmpty
                            ? null
                            : () {
                                ref
                                    .read(playerNotifierProvider.notifier)
                                    .shuffleAll(tracks);
                              },
                        icon: const Icon(Icons.shuffle, size: 18),
                        label: const Text('Shuffle'),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: Divider(height: 1, thickness: 0.5),
              ),

              // Tracks List
              if (tracks.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Text('No tracks found for this genre.'),
                    ),
                  ),
                )
              else
                SliverList.separated(
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
                    thickness: 0.5,
                    indent: 16,
                    endIndent: 16,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Error loading genre tracks: $err'),
        ),
      ),
    );
  }
}
