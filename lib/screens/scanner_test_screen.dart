import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/artwork/artwork_service.dart';
import '../services/scanner/music_library_sync_service.dart';
import '../widgets/album_art.dart';

class ScannerTestScreen extends StatefulWidget {
  const ScannerTestScreen({super.key});

  @override
  State<ScannerTestScreen> createState() => _ScannerTestScreenState();
}

class _ScannerTestScreenState extends State<ScannerTestScreen> {
  final MusicLibrarySyncService _library = MusicLibrarySyncService();
  final ArtworkService _artworkService = DefaultArtworkService();
  final Map<int, Uint8List?> _artworkCache = {};

  List<Track> _songs = [];
  int _libraryCount = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLibraryCount();
  }

  Future<void> _loadLibraryCount() async {
    final count = await _library.getLibrary().then((tracks) => tracks.length);
    if (mounted) {
      setState(() {
        _libraryCount = count;
      });
    }
  }

  Future<Uint8List?> _getArtwork(Track track) async {
    final albumId = track.albumId;

    if (albumId == null) {
      return null;
    }

    if (_artworkCache.containsKey(albumId)) {
      return _artworkCache[albumId];
    }

    final artwork = await _artworkService.getAlbumArtwork(albumId);

    _artworkCache[albumId] = artwork;

    return artwork;
  }

  Future<void> _scanMusic() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final permission = await _library.requestPermission();

      if (!permission) {
        setState(() {
          _error = 'Music permission was not granted.';
          _loading = false;
        });
        return;
      }

      await _library.synchronize();

      final tracks = await _library.getLibrary();

      setState(() {
        _songs = tracks;
        _libraryCount = tracks.length;
        _loading = false;
      });
    } catch (e) {
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
        title: const Text('Music Scanner Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _scanMusic,
                child: Text(
                  _loading ? 'Scanning...' : 'Scan Music',
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.red,
                ),
              ),

            Text(
              'Music Library',
              style: Theme.of(context).textTheme.titleLarge,
            ),

            Text(
              '$_libraryCount songs',
              style: Theme.of(context).textTheme.titleMedium,
            ),

            const SizedBox(height: 16),

            Expanded(
              child: ListView.builder(
                itemCount: _songs.length,
                itemBuilder: (context, index) {
                  final song = _songs[index];

                  return FutureBuilder<Uint8List?>(
                    future: _getArtwork(song),
                    builder: (context, snapshot) {
                      return ListTile(
                        leading: AlbumArt(
                          artwork: snapshot.data,
                          size: 56,
                        ),
                        title: Text(song.title),
                        subtitle: Text(
                          '${song.artist} • ${song.album}',
                        ),
                        trailing: Text(
                          song.duration != null
                              ? _formatDuration(song.duration!)
                              : '--:--',
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
