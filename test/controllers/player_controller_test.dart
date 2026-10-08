import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:nades_music_player/models/track.dart';
import 'package:nades_music_player/player/player_controller.dart';
import 'package:nades_music_player/player/queue/queue_item.dart';
import 'package:nades_music_player/services/playback/play_history_service.dart';
import 'package:nades_music_player/services/sleep_timer_service.dart';

import '../helpers/fake_audio_player_service.dart';

void main() {
  late ProviderContainer container;
  late FakeAudioPlayerService fakeAudio;
  late PlayerNotifier notifier;
  late SleepTimerService sleepTimer;

  PlayerState state() => container.read(playerNotifierProvider);

  setUp(() {
    fakeAudio = FakeAudioPlayerService();
    sleepTimer = SleepTimerService(
      tickInterval: const Duration(milliseconds: 10),
    );
    container = ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(fakeAudio),
        playHistoryServiceProvider.overrideWith(
          (ref) => NoopPlayHistoryService(),
        ),
        sleepTimerServiceProvider.overrideWithValue(sleepTimer),
      ],
    );
    notifier = container.read(playerNotifierProvider.notifier);
  });

  tearDown(() async {
    await notifier.clearQueue();
    container.dispose();
    await sleepTimer.dispose();
    await fakeAudio.dispose();
  });

  group('setQueue / playTrack', () {
    test('loads and plays the first track when autoPlay is enabled', () async {
      await notifier.setQueue([testTrack('a'), testTrack('b'), testTrack('c')]);

      expect(state().queue.length, 3);
      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 'a');
      expect(state().isPlaying, isTrue);
      expect(fakeAudio.loadedPath, '/music/a.mp3');
      expect(fakeAudio.playCount, 1);
    });

    test('does not auto-play when autoPlay is false', () async {
      await notifier.setQueue([testTrack('a')], autoPlay: false);

      expect(state().isPlaying, isFalse);
      expect(fakeAudio.playCount, 0);
      expect(state().currentTrack?.id, 'a');
    });

    test('clears the queue when given an empty list', () async {
      await notifier.setQueue([testTrack('a')]);
      await notifier.setQueue(const []);

      expect(state().queue, isEmpty);
      expect(state().currentTrack, isNull);
      expect(state().currentIndex, -1);
      expect(state().isPlaying, isFalse);
    });

    test('clamps the start index into range', () async {
      await notifier.setQueue([testTrack('a'), testTrack('b')], startIndex: 99);

      expect(state().currentTrack?.id, 'b');
    });

    test('playTrack adopts the provided queue at the track position', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.playTrack(tracks[1], queue: tracks);

      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'b');
      expect(state().isPlaying, isTrue);
    });

    test('loads asset tracks through setAsset', () async {
      final asset = Track(
        id: 'asset',
        title: 'Bundle',
        artist: 'A',
        album: '',
        albumArtist: '',
        genre: '',
        year: null,
        trackNumber: null,
        discNumber: null,
        duration: const Duration(seconds: 30),
        filePath: 'assets/audio/song_1.mp3',
        fileName: 'song_1.mp3',
        fileSize: null,
        mimeType: null,
        isAsset: true,
      );
      await notifier.setQueue([asset], autoPlay: false);

      expect(fakeAudio.loadedAsAsset, isTrue);
      expect(fakeAudio.loadedPath, 'assets/audio/song_1.mp3');
    });
  });

  group('play / pause / seek', () {
    test('togglePlayPause pauses and resumes', () async {
      await notifier.setQueue([testTrack('a')]);
      expect(state().isPlaying, isTrue);

      await notifier.togglePlayPause();
      expect(state().isPlaying, isFalse);
      expect(fakeAudio.pauseCount, 1);

      await notifier.togglePlayPause();
      expect(state().isPlaying, isTrue);
    });

    test('seek updates state and forwards to the service', () async {
      await notifier.setQueue([testTrack('a')], autoPlay: false);
      fakeAudio.emitDuration(const Duration(minutes: 3));
      await notifier.seek(const Duration(seconds: 42));

      expect(state().position, const Duration(seconds: 42));
      expect(fakeAudio.lastSeek, const Duration(seconds: 42));
    });

    test('seek clamps to the track bounds', () async {
      await notifier.setQueue([testTrack('a')], autoPlay: false);
      fakeAudio.emitDuration(const Duration(minutes: 3));

      await notifier.seek(const Duration(seconds: -5));
      expect(fakeAudio.lastSeek, Duration.zero);
      expect(state().position, Duration.zero);

      await notifier.seek(const Duration(minutes: 5));
      expect(fakeAudio.lastSeek, const Duration(minutes: 3));
      expect(state().position, const Duration(minutes: 3));
    });

    test('seek does nothing without a track or a known duration', () async {
      await notifier.seek(const Duration(seconds: 30));
      expect(fakeAudio.lastSeek, isNull);

      await notifier.setQueue([testTrack('a')], autoPlay: false);
      await notifier.seek(const Duration(seconds: 30));
      expect(fakeAudio.lastSeek, isNull);
      expect(state().position, Duration.zero);
    });

    test('seekForward jumps ahead by the given amount', () async {
      await notifier.setQueue([testTrack('a')], autoPlay: false);
      fakeAudio.emitDuration(const Duration(minutes: 3));
      fakeAudio.emitPosition(const Duration(minutes: 1, seconds: 20));

      await notifier.seekForward();
      expect(fakeAudio.lastSeek, const Duration(minutes: 1, seconds: 30));
      expect(state().position, const Duration(minutes: 1, seconds: 30));

      await notifier.seekForward(amount: const Duration(seconds: 20));
      expect(fakeAudio.lastSeek, const Duration(minutes: 1, seconds: 50));
    });

    test('seekBackward clamps at the start of the track', () async {
      await notifier.setQueue([testTrack('a')], autoPlay: false);
      fakeAudio.emitDuration(const Duration(minutes: 3));
      fakeAudio.emitPosition(const Duration(seconds: 5));

      await notifier.seekBackward();
      expect(fakeAudio.lastSeek, Duration.zero);
      expect(state().position, Duration.zero);

      fakeAudio.emitPosition(const Duration(seconds: 30));
      await notifier.seekBackward(amount: const Duration(seconds: 10));
      expect(fakeAudio.lastSeek, const Duration(seconds: 20));
    });

    test('stop stops playback and resets the position', () async {
      await notifier.setQueue([testTrack('a')]);
      await notifier.seek(const Duration(seconds: 30));

      await notifier.stop();

      expect(fakeAudio.stopCount, 1);
      expect(state().isPlaying, isFalse);
      expect(state().position, Duration.zero);
      expect(state().processingState, PlayerProcessingState.idle);
    });

    test('play is a no-op without a current track', () async {
      await notifier.play();

      expect(state().currentTrack, isNull);
      expect(fakeAudio.playCount, 0);
    });

    test('play failures surface as a clearable error', () async {
      await notifier.setQueue([testTrack('a')], autoPlay: false);
      fakeAudio.failNextPlay = true;

      await notifier.play();

      expect(state().hasError, isTrue);
      expect(state().isPlaying, isFalse);
      expect(state().processingState, PlayerProcessingState.error);

      notifier.clearError();
      expect(state().hasError, isFalse);
      expect(state().processingState, PlayerProcessingState.error);
    });

    test('maps engine buffering into the playback state', () async {
      await notifier.setQueue([testTrack('a')]);

      fakeAudio.setProcessingState(ProcessingState.buffering);

      expect(state().isBuffering, isTrue);
      expect(state().processingState, PlayerProcessingState.buffering);
    });

    test('position stream events update state', () async {
      await notifier.setQueue([testTrack('a')]);
      fakeAudio.emitPosition(const Duration(seconds: 10));

      expect(state().position, const Duration(seconds: 10));
    });

    test('duration stream events update state', () async {
      await notifier.setQueue([testTrack('a')]);
      fakeAudio.emitDuration(const Duration(minutes: 5));

      expect(state().duration, const Duration(minutes: 5));
    });
  });

  group('next / previous', () {
    test('next advances through the queue', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks);

      await notifier.next();
      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'b');
      expect(fakeAudio.loadedPath, '/music/b.mp3');

      await notifier.next();
      expect(state().currentIndex, 2);
      expect(state().currentTrack?.id, 'c');
    });

    test('next at the end is a no-op (queues do not wrap)', () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks, autoPlay: false);

      await notifier.next();
      await notifier.next();

      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'b');
      expect(state().isPlaying, isTrue);
    });

    test('loading over a playing engine keeps the play button in sync',
        () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks);
      expect(state().isPlaying, isTrue);
      expect(fakeAudio.playing, isTrue);

      // just_audio keeps playing through a source swap; the subsequent play()
      // is a silent no-op, so the controller must reconcile isPlaying with the
      // engine instead of waiting for a stream event that never arrives.
      await notifier.next();

      expect(state().currentTrack?.id, 'b');
      expect(fakeAudio.playing, isTrue);
      expect(state().isPlaying, isTrue);

      // Pressing the button must now pause (the engine state matches the UI).
      await notifier.togglePlayPause();
      expect(fakeAudio.pauseCount, 1);
      expect(state().isPlaying, isFalse);
    });

    test('next wraps to the start with repeat all', () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks);
      notifier.cycleRepeatMode();

      await notifier.next();
      fakeAudio.emitCompleted();
      await pumpEventQueue();

      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 'a');
      expect(state().isPlaying, isTrue);
    });

    test('previous goes back when the track has barely started', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks);

      await notifier.next();
      await notifier.next();
      fakeAudio.emitPosition(const Duration(seconds: 1));
      await notifier.previous();

      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'b');
      expect(state().isPlaying, isTrue);
    });

    test('previous restarts the current track after 3 seconds', () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks);
      fakeAudio.emitDuration(const Duration(minutes: 3));

      await notifier.next();
      fakeAudio.emitDuration(const Duration(minutes: 3));
      fakeAudio.emitPosition(const Duration(seconds: 20));
      await notifier.previous();

      expect(state().currentIndex, 1);
      expect(fakeAudio.lastSeek, Duration.zero);
    });

    test('previous at exactly 3 seconds goes back (restart is strictly > 3s)',
        () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks);
      fakeAudio.emitDuration(const Duration(minutes: 3));

      await notifier.next();
      fakeAudio.emitPosition(const Duration(seconds: 3));
      await notifier.previous();

      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 'a');
      expect(fakeAudio.loadedPath, '/music/a.mp3');
    });

    test('previous at the queue start restarts the current track', () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks, autoPlay: false);
      fakeAudio.emitDuration(const Duration(minutes: 3));

      fakeAudio.emitPosition(Duration.zero);
      await notifier.previous();

      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 'a');
      expect(fakeAudio.lastSeek, Duration.zero);
    });

    test('previous at the queue start wraps to the last item with repeat all',
        () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks, autoPlay: false);
      fakeAudio.emitDuration(const Duration(minutes: 3));
      notifier.cycleRepeatMode();

      fakeAudio.emitPosition(Duration.zero);
      await notifier.previous();

      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'b');
      expect(fakeAudio.loadedPath, '/music/b.mp3');
    });
  });

  group('queue management', () {
    test('queue boundary flags reflect the current position', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);

      expect(state().hasTrack, isTrue);
      expect(state().hasPrevious, isFalse);
      expect(state().hasNext, isTrue);

      await notifier.next();
      expect(state().hasPrevious, isTrue);
      expect(state().hasNext, isTrue);

      await notifier.next();
      expect(state().hasPrevious, isTrue);
      expect(state().hasNext, isFalse);
    });

    test('playQueue plays the track at the initial index with queue context',
        () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.playQueue(tracks, initialIndex: 1);

      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'b');
      expect(state().queue.map((t) => t.id), ['a', 'b', 'c']);
      expect(state().isPlaying, isTrue);
    });

    test('playQueue is a no-op for an empty list', () async {
      await notifier.playQueue(const []);
      expect(state().hasTrack, isFalse);
    });

    test('queue getter exposes the backing spec queue (3E.10)', () async {
      expect(notifier.queue.items, isEmpty);

      await notifier.setQueue([testTrack('a'), testTrack('b')],
          autoPlay: false);

      expect(notifier.queue.items.length, 2);
      expect(notifier.queue.currentIndex, 0);
      expect(notifier.queue.currentTrack?.id, 'a');
    });

    test('playQueueItem resolves a queue item and plays it (3E.11)', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);

      final item = notifier.queue.items[2];
      await notifier.playQueueItem(item);

      expect(notifier.queue.currentIndex, 2);
      expect(state().currentIndex, 2);
      expect(state().currentTrack?.id, 'c');
      expect(state().queue.map((t) => t.id), ['a', 'b', 'c']);
      expect(state().isPlaying, isTrue);
      expect(fakeAudio.loadedPath, '/music/c.mp3');
    });

    test('playQueueItem ignores items not present in the queue', () async {
      await notifier.setQueue([testTrack('a')], autoPlay: false);

      await notifier.playQueueItem(
        QueueItem(id: 'foreign', track: testTrack('x')),
      );

      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 'a');
      expect(state().isPlaying, isFalse);
      expect(fakeAudio.loadedPath, '/music/a.mp3');
    });

    test('transition clears a previous load error', () async {
      fakeAudio.failNextLoad = true;
      await notifier.setQueue([testTrack('x')], autoPlay: false);
      expect(state().error, isNotNull);

      await notifier.setQueue([testTrack('a')], autoPlay: false);
      expect(state().error, isNull);
      expect(state().currentTrack?.id, 'a');
    });

    test('playNext inserts directly after the current track', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);

      notifier.playNext(testTrack('x'));

      expect(state().queue.map((t) => t.id), ['a', 'x', 'b', 'c']);
      expect(state().currentIndex, 0);
    });

    test('addToQueue appends to the end', () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks, autoPlay: false);

      notifier.addToQueue(testTrack('z'));

      expect(state().queue.map((t) => t.id), ['a', 'b', 'z']);
    });

    test('playNextAll inserts all tracks after the current one, in order (3K.4)',
        () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);

      notifier.playNextAll([testTrack('x'), testTrack('y')]);

      expect(state().queue.map((t) => t.id), ['a', 'x', 'y', 'b', 'c']);
      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 'a');
    });

    test('playNextAll after a mid-queue position keeps position order', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);
      await notifier.next();
      expect(state().currentTrack?.id, 'b');

      notifier.playNextAll([testTrack('x'), testTrack('y'), testTrack('z')]);

      expect(state().queue.map((t) => t.id), ['a', 'b', 'x', 'y', 'z', 'c']);
      expect(state().currentTrack?.id, 'b');
    });

    test('addToQueueAll appends all tracks to the end, in order (3K.5)',
        () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks, autoPlay: false);

      notifier.addToQueueAll([testTrack('x'), testTrack('y')]);

      expect(state().queue.map((t) => t.id), ['a', 'b', 'x', 'y']);
    });

    test('playNextAll and addToQueueAll are no-ops on an empty list', () async {
      await notifier.setQueue([testTrack('a')], autoPlay: false);

      notifier.playNextAll(const []);
      notifier.addToQueueAll(const []);

      expect(state().queue.map((t) => t.id), ['a']);
    });

    test('removeFromQueue removes a queued track and fixes the index', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);

      await notifier.next();
      expect(state().currentIndex, 1);

      notifier.removeFromQueue(2);
      expect(state().queue.map((t) => t.id), ['a', 'b']);
      expect(state().currentIndex, 1);

      notifier.removeFromQueue(0);
      expect(state().queue.map((t) => t.id), ['b']);
      expect(state().currentIndex, 0);
    });

    test('removeFromQueue ignores out of range and current indices', () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks, autoPlay: false);

      notifier.removeFromQueue(5);
      notifier.removeFromQueue(state().currentIndex);

      expect(state().queue.length, 2);
    });

    test('jumpToIndex plays the requested track', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);

      await notifier.jumpToIndex(2);

      expect(state().currentIndex, 2);
      expect(state().currentTrack?.id, 'c');
      expect(state().isPlaying, isTrue);
      expect(fakeAudio.loadedPath, '/music/c.mp3');
    });

    test('clearQueue stops playback and empties the state', () async {
      await notifier.setQueue([testTrack('a'), testTrack('b')]);

      await notifier.clearQueue();

      expect(state().queue, isEmpty);
      expect(state().currentTrack, isNull);
      expect(state().currentIndex, -1);
      expect(state().isPlaying, isFalse);
      expect(fakeAudio.stopCount, 1);
    });
  });

  group('queue reordering', () {
    test('moveInQueue reorders and keeps the current track playing', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);

      notifier.moveInQueue(2, 0);

      expect(state().queue.map((t) => t.id), ['c', 'a', 'b']);
      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'a');
    });

    test('moveInQueue relocates the playing track within the queue', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);

      notifier.moveInQueue(0, 2);

      expect(state().queue.map((t) => t.id), ['b', 'c', 'a']);
      expect(state().currentIndex, 2);
      expect(state().currentTrack?.id, 'a');
    });

    test('moveInQueue adjusts hasNext when the current track is moved', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);

      notifier.moveInQueue(0, 2);

      expect(state().hasPrevious, isTrue);
      expect(state().hasNext, isFalse);
    });

    test('moveInQueue is a no-op for an empty queue and bad indices', () async {
      notifier.moveInQueue(0, 1);
      expect(state().queue, isEmpty);

      await notifier.setQueue([testTrack('a'), testTrack('b')],
          autoPlay: false);

      notifier.moveInQueue(0, 9);
      notifier.moveInQueue(-1, 1);

      expect(state().queue.map((t) => t.id), ['a', 'b']);
      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 'a');
    });
  });

  group('completion auto-advance', () {
    test('moves to the next track when a song completes', () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks);

      fakeAudio.emitCompleted();
      await pumpEventQueue();

      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'b');
      expect(state().isPlaying, isTrue);
    });

    test('replays the current track with repeat one', () async {
      final tracks = [testTrack('a'), testTrack('b')];
      await notifier.setQueue(tracks);
      fakeAudio.emitDuration(const Duration(minutes: 3));
      notifier.cycleRepeatMode();
      notifier.cycleRepeatMode();
      expect(state().repeatMode, RepeatMode.one);

      final playsBefore = fakeAudio.playCount;
      fakeAudio.emitCompleted();
      await pumpEventQueue();

      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 'a');
      expect(fakeAudio.lastSeek, Duration.zero);
      expect(fakeAudio.playCount, playsBefore + 1);
    });

    test('advances only once for a single completion event', () async {
      final tracks =
          [testTrack('a'), testTrack('b'), testTrack('c'), testTrack('d')];
      await notifier.setQueue(tracks);

      fakeAudio.emitCompleted();
      await pumpEventQueue();

      expect(state().currentIndex, 1);
    });

    test('marks the state completed when the last track finishes', () async {
      await notifier.setQueue([testTrack('a')]);

      fakeAudio.emitCompleted();
      await pumpEventQueue();

      expect(state().processingState, PlayerProcessingState.completed);
      expect(state().isCompleted, isTrue);
      expect(state().isPlaying, isFalse);
    });

    test('pins position at the natural end when the last track completes',
        () async {
      await notifier.setQueue([testTrack('a')], autoPlay: false);
      fakeAudio.emitDuration(const Duration(minutes: 3));

      fakeAudio.emitCompleted();
      await pumpEventQueue();

      expect(state().isCompleted, isTrue);
      expect(state().isPlaying, isFalse);
      expect(state().position, const Duration(minutes: 3));
    });

    test('play restarts a parked completed track from the beginning', () async {
      await notifier.setQueue([testTrack('a')]);
      fakeAudio.emitDuration(const Duration(minutes: 3));

      fakeAudio.emitCompleted();
      await pumpEventQueue();

      expect(state().isCompleted, isTrue);

      await notifier.play();

      // Just play() on a completed engine is a silent no-op — the controller
      // must seek back to the start (mirroring Repeat ONE) and restart.
      expect(fakeAudio.lastSeek, Duration.zero);
      expect(state().position, Duration.zero);
      expect(state().isCompleted, isFalse);
      expect(state().isPlaying, isTrue);
    });
  });

  group('shuffle', () {
    test('pins the current track and randomizes the rest', () async {
      final tracks = List.generate(8, (i) => testTrack('t$i'));
      await notifier.setQueue(tracks, autoPlay: false);

      notifier.toggleShuffle();

      expect(state().shuffleEnabled, isTrue);
      expect(state().queue.length, 8);
      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 't0');
      expect(state().queue.first.id, 't0');
      expect(
        state().queue.map((t) => t.id).toSet(),
        tracks.map((t) => t.id).toSet(),
      );
    });

    test('restores the original order when toggled off', () async {
      final tracks = List.generate(8, (i) => testTrack('t$i'));
      await notifier.setQueue(tracks, autoPlay: false);

      notifier.toggleShuffle();
      notifier.toggleShuffle();

      expect(state().shuffleEnabled, isFalse);
      expect(state().queue.map((t) => t.id), tracks.map((t) => t.id));
      expect(state().currentIndex, 0);
      expect(state().currentTrack?.id, 't0');
    });

    test('setQueue reshuffles when shuffle mode is already active', () async {
      final tracks = List.generate(8, (i) => testTrack('t$i'));
      notifier.toggleShuffle();
      await notifier.setQueue(tracks, startIndex: 3, autoPlay: false);

      expect(state().shuffleEnabled, isTrue);
      expect(state().currentTrack?.id, 't3');
      expect(state().queue.first.id, 't3');
      expect(state().queue.length, 8);
    });

    test('_refreshShuffleState prunes ids removed from the queue (3F.18)',
        () async {
      final tracks = List.generate(8, (i) => testTrack('t$i'));
      await notifier.setQueue(tracks, autoPlay: false);
      notifier.toggleShuffle();

      notifier.removeFromQueue(3);

      expect(state().queue.length, 7);
      // The pinned current item still plays after a non-current removal.
      expect(state().currentTrack?.id, 't0');
    });

    test('next follows the shuffle order, leaving the visible queue untouched',
        () async {
      final tracks = List.generate(8, (i) => testTrack('t$i'));
      await notifier.setQueue(tracks, autoPlay: false);
      notifier.toggleShuffle();

      await notifier.next();
      final after = state();

      // Enabling shuffle must never reorder the user's visible queue (3F.1).
      expect(after.queue.map((t) => t.id), tracks.map((t) => t.id));
      // The next item is a different track, played at its queue position.
      expect(after.currentTrack?.id, isNot('t0'));
      expect(after.queue[after.currentIndex].id, after.currentTrack?.id);
    });
  });

  group('load failures', () {
    test('an unplayable next track surfaces a clearable error (no auto-skip)',
        () async {
      final tracks = [testTrack('a'), testTrack('b'), testTrack('c')];
      await notifier.setQueue(tracks, autoPlay: false);

      fakeAudio.failNextLoad = true;
      await notifier.next();

      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'b');
      expect(state().isPlaying, isFalse);
      expect(state().hasError, isTrue);
    });

    test('sets an error message when the first track cannot load', () async {
      fakeAudio.failNextLoad = true;
      await notifier.setQueue([testTrack('a')]);

      expect(state().currentTrack?.id, 'a');
      expect(state().isPlaying, isFalse);
      expect(state().hasError, isTrue);
      expect(state().error, isNotNull);
      expect(state().processingState, PlayerProcessingState.error);
    });
  });

  group('Phase 3H resume', () {
    Future<PlayHistoryService> seededService(Track track,
        {Duration resume = const Duration(seconds: 45)}) async {
      final service = PlayHistoryService(null, 50);
      await service.record(track);
      await service.saveResumePosition(track.id, resume);
      return service;
    }

    PlayerState readState(ProviderContainer c) =>
        c.read(playerNotifierProvider);

    test('seeks to a saved resume position and exposes resumedFrom', () async {
      final track = testTrack('a');
      final service = await seededService(track);
      final local = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakeAudio),
          playHistoryServiceProvider.overrideWithValue(service),
        ],
      );
      final n = local.read(playerNotifierProvider.notifier);
      await n.playTrack(track);

      final st = readState(local);
      expect(st.position, const Duration(seconds: 45));
      expect(st.resumedFrom, const Duration(seconds: 45));
      expect(fakeAudio.seekCount, greaterThanOrEqualTo(1));

      local.dispose();
      await fakeAudio.dispose();
    });

    test('does not resume for a position at the very start', () async {
      final track = testTrack('a');
      final service = await seededService(track, resume: const Duration(seconds: 2));
      final local = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakeAudio),
          playHistoryServiceProvider.overrideWithValue(service),
        ],
      );
      final n = local.read(playerNotifierProvider.notifier);
      await n.playTrack(track);

      final st = readState(local);
      expect(st.resumedFrom, isNull);
      expect(st.position, Duration.zero);

      local.dispose();
      await fakeAudio.dispose();
    });

    test('dismissResume clears the resumedFrom indication', () async {
      final track = testTrack('a');
      final service = await seededService(track);
      final local = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakeAudio),
          playHistoryServiceProvider.overrideWithValue(service),
        ],
      );
      final n = local.read(playerNotifierProvider.notifier);
      await n.playTrack(track);
      expect(readState(local).resumedFrom, isNotNull);

      n.dismissResume();
      expect(readState(local).resumedFrom, isNull);

      local.dispose();
      await fakeAudio.dispose();
    });
  });

  group('Phase 3H play count', () {
    Future<(ProviderContainer, PlayerNotifier, PlayHistoryService)> startPlaying(
        String id) async {
      final service = PlayHistoryService(null, 50);
      final local = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakeAudio),
          playHistoryServiceProvider.overrideWithValue(service),
        ],
      );
      final n = local.read(playerNotifierProvider.notifier);
      await n.playTrack(testTrack(id));
      return (local, n, service);
    }

    test('does not record a play before the 10s threshold', () async {
      final (local, n, service) = await startPlaying('a');
      fakeAudio.emitPosition(const Duration(seconds: 5));

      expect(service.entries, isEmpty);

      local.dispose();
      await fakeAudio.dispose();
    });

    test('records a play once the position reaches 10s', () async {
      final (local, n, service) = await startPlaying('a');
      fakeAudio.emitPosition(const Duration(seconds: 9));
      fakeAudio.emitPosition(const Duration(seconds: 10));
      await pumpEventQueue();

      expect(service.entries.length, 1);
      expect(service.entries.single.track.id, 'a');

      local.dispose();
      await fakeAudio.dispose();
    });

    test('records each track at most once per session', () async {
      final (local, n, service) = await startPlaying('a');
      fakeAudio.emitPosition(const Duration(seconds: 12));
      fakeAudio.emitPosition(const Duration(seconds: 30));
      fakeAudio.emitPosition(const Duration(seconds: 45));
      await pumpEventQueue();

      expect(service.entries.single.playCount, 1);

      local.dispose();
      await fakeAudio.dispose();
    });
  });

  group('Phase 3H resume save throttle', () {
    test('an active seek past the threshold saves the resume position',
        () async {
      final service = PlayHistoryService(null, 50);
      final local = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakeAudio),
          playHistoryServiceProvider.overrideWithValue(service),
        ],
      );
      final n = local.read(playerNotifierProvider.notifier);
      await n.playTrack(testTrack('a'));
      fakeAudio.emitDuration(const Duration(minutes: 4, seconds: 32));
      fakeAudio.emitPosition(const Duration(seconds: 12));
      await pumpEventQueue();

      await n.seek(const Duration(minutes: 2, seconds: 17));
      await pumpEventQueue();

      expect(service.entries.single.resumePosition,
          const Duration(minutes: 2, seconds: 17));

      local.dispose();
      await fakeAudio.dispose();
    });

    test('a second seek within the throttle window is skipped (3H.15)',
        () async {
      final service = PlayHistoryService(null, 50);
      final local = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakeAudio),
          playHistoryServiceProvider.overrideWithValue(service),
        ],
      );
      final n = local.read(playerNotifierProvider.notifier);
      await n.playTrack(testTrack('a'));
      fakeAudio.emitDuration(const Duration(minutes: 4, seconds: 32));
      fakeAudio.emitPosition(const Duration(seconds: 12));
      await pumpEventQueue();

      await n.seek(const Duration(minutes: 1));
      await n.seek(const Duration(minutes: 3));
      await pumpEventQueue();

      expect(service.entries.single.resumePosition, const Duration(minutes: 1));

      local.dispose();
      await fakeAudio.dispose();
    });
  });

  group('Phase 3H threshold edge cases (3H.35)', () {
    Track longTrack() => Track(
          id: 'long',
          title: 'Long',
          artist: 'A',
          album: '',
          albumArtist: '',
          genre: '',
          year: null,
          trackNumber: null,
          discNumber: null,
          duration: const Duration(minutes: 4, seconds: 34),
          filePath: '/music/long.mp3',
          fileName: 'long.mp3',
          fileSize: null,
          mimeType: null,
        );

    Future<PlayHistoryService> seeded(Track track, Duration resume) async {
      final service = PlayHistoryService(null, 50);
      await service.record(track);
      await service.saveResumePosition(track.id, resume);
      return service;
    }

    test('beginning threshold: stopping early clears a stale resume (3H.35 #6)',
        () async {
      final track = testTrack('a');
      // Prior session left a resume point, but this session stopped at 0:02.
      final service = await seeded(track, const Duration(minutes: 2, seconds: 15));
      final local = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakeAudio),
          playHistoryServiceProvider.overrideWithValue(service),
        ],
      );
      final n = local.read(playerNotifierProvider.notifier);

      // Reopen (resumes from 2:15), then stop near the very start.
      await n.playTrack(track);
      fakeAudio.emitPosition(const Duration(seconds: 2));
      await n.pause();
      await pumpEventQueue();

      // Replay must start from the beginning, not the stale 2:15.
      await n.playTrack(track);
      expect(local.read(playerNotifierProvider).position, Duration.zero);
      expect(local.read(playerNotifierProvider).resumedFrom, isNull);

      local.dispose();
      await fakeAudio.dispose();
    });

    test('near-end threshold: stopping close to the end clears resume (3H.35 #7)',
        () async {
      final track = longTrack();
      final service = PlayHistoryService(null, 50);
      await service.record(track);
      final local = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakeAudio),
          playHistoryServiceProvider.overrideWithValue(service),
        ],
      );
      final n = local.read(playerNotifierProvider.notifier);

      await n.playTrack(track);
      fakeAudio.emitDuration(track.duration);
      fakeAudio.emitPosition(const Duration(minutes: 4, seconds: 29));
      await n.pause();
      await pumpEventQueue();

      await n.playTrack(track);
      expect(local.read(playerNotifierProvider).position, Duration.zero);
      expect(local.read(playerNotifierProvider).resumedFrom, isNull);

      local.dispose();
      await fakeAudio.dispose();
    });

    test('completion clears the resume position (3H.35 #8)', () async {
      final track = longTrack();
      final service = PlayHistoryService(null, 50);
      await service.record(track);
      await service.saveResumePosition(track.id, const Duration(minutes: 3));
      final local = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(fakeAudio),
          playHistoryServiceProvider.overrideWithValue(service),
        ],
      );
      final n = local.read(playerNotifierProvider.notifier);

      await n.playTrack(track);
      fakeAudio.emitDuration(track.duration);
      fakeAudio.emitCompleted();
      await pumpEventQueue();

      expect(service.entries.single.resumePosition, Duration.zero);

      await n.playTrack(track);
      expect(local.read(playerNotifierProvider).position, Duration.zero);

      local.dispose();
      await fakeAudio.dispose();
    });
  });

  group('sleep timer (Phase 4A)', () {
    test('an expired sleep timer stops playback and returns the engine to idle',
        () async {
      await notifier.setQueue([testTrack('a')], autoPlay: true);
      expect(state().isPlaying, isTrue);

      final deactivated = Completer<void>();
      final sub = sleepTimer.stateStream.listen((remaining) {
        if (remaining == null && !deactivated.isCompleted) {
          deactivated.complete();
        }
      });

      sleepTimer.start(const Duration(milliseconds: 50));
      await deactivated.future.timeout(const Duration(seconds: 2));
      await sub.cancel();

      // Give the unawaited stop() a chance to settle.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(sleepTimer.isActive, isFalse);
      expect(state().isPlaying, isFalse);
      expect(state().processingState, PlayerProcessingState.idle);
      expect(fakeAudio.stopCount, greaterThanOrEqualTo(1));
    });

    test('cancelling the sleep timer does not stop playback', () async {
      await notifier.setQueue([testTrack('a')], autoPlay: true);
      expect(state().isPlaying, isTrue);

      sleepTimer.start(const Duration(minutes: 30));
      sleepTimer.cancel();

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(sleepTimer.isActive, isFalse);
      expect(state().isPlaying, isTrue);
      expect(state().processingState, PlayerProcessingState.ready);
      expect(fakeAudio.stopCount, 0);
    });

    test('a running sleep timer alone does not stop playback', () async {
      await notifier.setQueue([testTrack('a')], autoPlay: true);

      sleepTimer.start(const Duration(minutes: 30));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(sleepTimer.isActive, isTrue);
      expect(state().isPlaying, isTrue);
      expect(fakeAudio.stopCount, 0);

      sleepTimer.cancel();
    });

    test('a sleep timer stays active when a track completes and the next starts',
        () async {
      await notifier.setQueue([testTrack('a'), testTrack('b')],
          autoPlay: true);
      expect(state().isPlaying, isTrue);

      sleepTimer.start(const Duration(minutes: 30));
      expect(sleepTimer.isActive, isTrue);

      // Natural completion → the next track plays normally; the timer is based
      // on real elapsed time (spec §15), never individual songs.
      fakeAudio.emitCompleted();
      await pumpEventQueue();

      expect(state().currentIndex, 1);
      expect(state().currentTrack?.id, 'b');
      expect(state().isPlaying, isTrue);
      expect(sleepTimer.isActive, isTrue);
      expect(sleepTimer.remaining, isNotNull);
      expect(sleepTimer.remaining!, greaterThan(Duration.zero));

      sleepTimer.cancel();
    });
  });
}
