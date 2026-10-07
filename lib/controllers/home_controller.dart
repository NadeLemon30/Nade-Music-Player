import 'package:flutter/foundation.dart';
import '../models/track.dart';
import '../services/audio/audio_player_service.dart';
import '../player/audio_handler.dart';

class HomeController extends ChangeNotifier {
  final AudioPlayerService _audioPlayerService;

  HomeController({AudioPlayerService? audioPlayerService})
      : _audioPlayerService =
            audioPlayerService ??
            AudioPlayerService(globalAudioHandler ?? MusicAudioHandler());

  int _counter = 0;
  int get counter => _counter;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Track? _currentTrack;
  Track? get currentTrack => _currentTrack;

  void incrementCounter() {
    _counter++;
    notifyListeners();
  }

  Future<void> togglePlayPause(Track track) async {
    if (_isPlaying && _currentTrack?.id == track.id) {
      await _audioPlayerService.pause();
      _isPlaying = false;
    } else {
      _currentTrack = track;
      await _audioPlayerService.setFile(track.filePath);
      await _audioPlayerService.play();
      _isPlaying = true;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _audioPlayerService.dispose();
    super.dispose();
  }
}
