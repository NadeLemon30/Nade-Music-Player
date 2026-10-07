import '../../models/track.dart';

abstract class AudioService {
  Future<void> init();
  Future<void> play(Track track);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

class MockAudioService implements AudioService {
  bool _isPlaying = false;
  Track? _currentTrack;

  bool get isPlaying => _isPlaying;
  Track? get currentTrack => _currentTrack;

  @override
  Future<void> init() async {
    // Initialization logic for audio player
  }

  @override
  Future<void> play(Track track) async {
    _currentTrack = track;
    _isPlaying = true;
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
  }

  @override
  Future<void> resume() async {
    if (_currentTrack != null) {
      _isPlaying = true;
    }
  }

  @override
  Future<void> stop() async {
    _isPlaying = false;
    _currentTrack = null;
  }

  @override
  Future<void> seek(Duration position) async {
    // Seek logic
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
