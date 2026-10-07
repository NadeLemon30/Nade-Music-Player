import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../player/player_controller.dart';
import 'playlist_picker_sheet.dart';

/// Reusable "context menu" for a music collection (album / artist / folder).
///
/// All collection-level actions route through [PlayerNotifier]'s batch
/// primitives and the shared [showAddTracksToPlaylistSheet], so every surface
/// that renders an album/artist/folder row reuses the exact same menu instead
/// of duplicating Play/Shuffle/Play Next/Add to Queue/Add to Playlist logic.
class CollectionOptionsButton extends ConsumerWidget {
  final List<Track> tracks;
  final bool includePlayNext;
  final IconData icon;
  final Color? iconColor;
  final String tooltip;

  const CollectionOptionsButton({
    super.key,
    required this.tracks,
    this.includePlayNext = true,
    this.icon = Icons.more_vert,
    this.iconColor,
    this.tooltip = 'Options',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canPlay = tracks.isNotEmpty;

    return PopupMenuButton<String>(
      icon: Icon(icon, color: iconColor),
      tooltip: tooltip,
      onSelected: (value) => _handle(context, ref, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'play',
          enabled: canPlay,
          child: const Text('Play'),
        ),
        PopupMenuItem(
          value: 'shuffle',
          enabled: canPlay,
          child: const Text('Shuffle'),
        ),
        if (includePlayNext)
          PopupMenuItem(
            value: 'play_next',
            enabled: canPlay,
            child: const Text('Play Next'),
          ),
        PopupMenuItem(
          value: 'queue',
          enabled: canPlay,
          child: const Text('Add to Queue'),
        ),
        PopupMenuItem(
          value: 'playlist',
          enabled: canPlay,
          child: const Text('Add to Playlist'),
        ),
      ],
    );
  }

  void _handle(BuildContext context, WidgetRef ref, String value) {
    if (tracks.isEmpty) return;

    final notifier = ref.read(playerNotifierProvider.notifier);
    switch (value) {
      case 'play':
        notifier.setQueue(tracks, startIndex: 0, autoPlay: true);
      case 'shuffle':
        notifier.shuffleAll(tracks);
      case 'play_next':
        notifier.playNextAll(tracks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playing ${tracks.length} songs next'),
            duration: const Duration(seconds: 1),
          ),
        );
      case 'queue':
        notifier.addToQueueAll(tracks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${tracks.length} songs to queue'),
            duration: const Duration(seconds: 1),
          ),
        );
      case 'playlist':
        showAddTracksToPlaylistSheet(context, ref, tracks);
    }
  }
}