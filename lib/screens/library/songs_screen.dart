import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/player_controller.dart';
import '../../models/track.dart';
import '../../services/artwork/artwork_service.dart';
import '../../services/scanner/music_library_sync_service.dart';
import '../../widgets/album_art.dart';

class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  final MusicLibrarySyncService _library = MusicLibrarySyncService();
  final ArtworkService _artworkService = DefaultArtworkService();

  List<Track> _songs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final songs = await _library.getLibrary();

      if (!mounted) return;

      setState(() {
        _songs = songs;
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

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scanning music...')),
    );

    try {
      final permission = await _library.requestPermission();

      if (!permission) {
        setState(() {
          _error = 'Music permission was not granted.';
          _loading = false;
        });

        return;
      }

      final result = await _library.synchronize();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Scan complete: +${result.added} added, '
            '${result.updated} updated, '
            '-${result.removed} removed. '
            '${result.total} songs total',
          ),
        ),
      );

      await _loadLibrary();
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
    ref.listen(playerNotifierProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Songs'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _scan,
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan music',
          ),
        ],
      ),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!),
        ),
      );
    }

    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_outlined,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text('No music found'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.sync),
              label: const Text('Scan Music'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            8,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_songs.length} songs',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),

        Expanded(
          child: ListView.builder(
            itemCount: _songs.length,
            itemBuilder: (context, index) {
              final song = _songs[index];

              return ListTile(
                leading: _buildSongArtwork(song),
                title: Text(song.title),
                subtitle: Text(
                  '${song.artist} • ${song.album}',
                ),
                trailing: song.duration == null
                    ? null
                    : Text(
                        _formatDuration(song.duration!),
                      ),
                onTap: () {
                  ref
                      .read(playerNotifierProvider.notifier)
                      .playQueue(_songs, initialIndex: _songs.indexOf(song));
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSongArtwork(Track song) {
    if (song.albumId == null) {
      return const AlbumArt(
        artwork: null,
        size: 52,
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _artworkService.getAlbumArtwork(
        song.albumId!,
      ),
      builder: (context, snapshot) {
        return AlbumArt(
          artwork: snapshot.data,
          size: 52,
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}