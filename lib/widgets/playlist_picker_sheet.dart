import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import 'playlists/playlist_picker.dart';

/// "Add to Playlist" specialization of the shared [showPlaylistPicker] (specs
/// 18-19): shows the reusable playlist picker and adds [track] to whichever
/// playlist the user picks (or creates). Called from a track's options sheet.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) {
  return showAddTracksToPlaylistSheet(context, ref, [track]);
}

/// "Add to Playlist" specialization of the shared [showPlaylistPicker] (specs
/// 18-19): shows the reusable playlist picker and adds [tracks] (in their given
/// order) to whichever playlist the user picks, creating a new one on demand
/// (spec 7). Playlists that already hold the whole selection are marked and
/// tapping one is a no-op — adding never creates duplicates because the
/// underlying playlist service is idempotent and the
/// `(playlist_id, track_id)` composite PK keeps the database duplicate-free.
///
/// The sheet itself, the "+ New Playlist" name dialog, the already-added
/// markers, and the confirmation snackbars all live in `playlist_picker.dart`;
/// this file only forwards the selection for the add flow.
Future<void> showAddTracksToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks,
) async {
  if (tracks.isEmpty) return;
  await showPlaylistPicker(context: context, ref: ref, tracks: tracks);
}