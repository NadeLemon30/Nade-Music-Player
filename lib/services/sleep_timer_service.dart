import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Countdown sleep timer (Phase 4A).
///
/// Independent of the audio engine: it only tracks a countdown and fires one
/// [expiredStream] event when it reaches zero. The [PlayerNotifier] listens to
/// that stream and decides what "expired" means (it stops playback via the
/// existing single stop path) — this service never touches the player, the
/// queue, playlists, or playback history directly, so there is no second
/// playback system. Pausing music has no effect on the countdown (§6).
///
/// The remaining time is anchored to a stored target [expiresAt](DateTime)
/// rather than to tick arithmetic (§8): every tick (and the [remaining] getter)
/// computes `expiresAt.difference(now)`, so a tick that is delayed while the
/// app is suspended never under-counts — the countdown jumps straight to the
/// correct value (and can expire) the moment the next tick fires. The plain
/// Dart [Timer.periodic] only schedules ticks, so the countdown keeps working
/// while the app is backgrounded as long as the isolate is alive (the audio
/// foreground service keeps it alive during backgrounded playback, §7).
/// Persistence across a complete app-process death is out of scope (§9).
class SleepTimerService {
  SleepTimerService({
    this.tickInterval = const Duration(seconds: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Recommended preset durations (§10). Picking any of these should be a
  /// one-line change.
  static const presets = <Duration>[
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
    Duration(minutes: 90),
  ];

  /// Interval between countdown ticks. Injectable so tests can count down fast.
  final Duration tickInterval;

  /// Time source for the countdown. Injectable so tests can control the clock.
  final DateTime Function() _now;

  Timer? _timer;

  /// Target wall-clock time at which the countdown reaches zero. `null` when
  /// no countdown is running. Every tick recomputes `remaining` from this.
  DateTime? _expiresAt;

  final StreamController<Duration?> _stateController =
      StreamController<Duration?>.broadcast(sync: true);
  final StreamController<void> _expiredController =
      StreamController<void>.broadcast(sync: true);

  /// Whether a countdown is currently running.
  bool get isActive => _timer != null || _expiresAt != null;

  /// The target expiration time, or null when inactive.
  DateTime? get expiresAt => _expiresAt;

  /// The time remaining on the active countdown, or null when inactive.
  ///
  /// Computed from [expiresAt] against the current clock, so it always reflects
  /// time that passed while ticks were delayed (e.g. during suspension) even
  /// before the next tick fires.
  Duration? get remaining {
    final expiresAt = _expiresAt;
    if (expiresAt == null) return null;
    final value = expiresAt.difference(_now());
    return value.isNegative ? Duration.zero : value;
  }

  /// Live countdown state: the remaining [Duration] each tick, and null when
  /// the timer becomes inactive (expired or cancelled).
  Stream<Duration?> get stateStream => _stateController.stream;

  /// Fires exactly once, when the countdown reaches zero.
  Stream<void> get expiredStream => _expiredController.stream;

  /// Starts a new countdown lasting [duration], replacing any active one.
  ///
  /// A zero (or negative, clamped to zero) [duration] expires immediately.
  void start(Duration duration) {
    _cancelTicker();
    final effective = duration <= Duration.zero ? Duration.zero : duration;
    _expiresAt = _now().add(effective);
    _stateController.add(remaining);

    if (effective == Duration.zero) {
      _expire();
      return;
    }

    _timer = Timer.periodic(tickInterval, (_) => _tick());
  }

  void _tick() {
    final expiresAt = _expiresAt;
    if (expiresAt == null) return;

    final remaining = expiresAt.difference(_now());
    if (remaining <= Duration.zero) {
      _expire();
    } else {
      _stateController.add(remaining);
    }
  }

  void _expire() {
    _cancelTicker();
    _expiresAt = null;
    _stateController.add(null);
    if (!_expiredController.isClosed) {
      _expiredController.add(null);
    }
  }

  /// Stops the countdown and clears the remaining time.
  ///
  /// Cancellation must never affect playback: music is NOT stopped, and the
  /// queue, playlists, and playback history are NOT modified.
  void cancel() {
    _cancelTicker();
    _expiresAt = null;
    _stateController.add(null);
  }

  void _cancelTicker() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    _cancelTicker();
    _expiresAt = null;
    await _stateController.close();
    await _expiredController.close();
  }
}

/// Provider exposing the app-wide [SleepTimerService].
final sleepTimerServiceProvider = Provider<SleepTimerService>((ref) {
  final service = SleepTimerService();
  ref.onDispose(service.dispose);
  return service;
});

/// Reactive remaining-time provider: yields the current remaining [Duration]
/// (null when inactive), then every countdown tick. Drives the Sleep Timer UI
/// so the sheet and the player AppBar reflect the live countdown.
final sleepTimerStateProvider = StreamProvider<Duration?>((ref) async* {
  final service = ref.watch(sleepTimerServiceProvider);
  yield service.remaining;
  yield* service.stateStream;
});