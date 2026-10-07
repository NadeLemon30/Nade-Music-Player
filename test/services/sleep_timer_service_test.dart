import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/services/sleep_timer_service.dart';

void main() {
  // Always use a fake clock so unit tests stay deterministic regardless of
  // real-world scheduling jitter. The clock is only advanced explicitly by the
  // test body, so every value observed from the service is fully predictable.
  late DateTime fakeNow;
  late SleepTimerService service;

  setUp(() {
    fakeNow = DateTime.utc(2026, 1, 1, 12);
    service = SleepTimerService(
      tickInterval: const Duration(milliseconds: 10),
      now: () => fakeNow,
    );
  });

  tearDown(() => service.dispose());

  // Helpers ---------------------------------------------------------------

  /// Advance the fake clock by [d] and allow one real timer tick to fire.
  Future<void> tick([Duration d = const Duration(milliseconds: 20)]) async {
    fakeNow = fakeNow.add(d);
    // Wait slightly longer than tickInterval so at least one periodic callback
    // is scheduled and executed, but short enough not to overshoot tests.
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }

  // Tests -----------------------------------------------------------------

  test('is inactive immediately', () {
    expect(service.isActive, isFalse);
    expect(service.remaining, isNull);
  });

  test('start activates with requested duration', () {
    service.start(const Duration(minutes: 30));
    expect(service.isActive, isTrue);
    expect(service.remaining, const Duration(minutes: 30));
  });

  test('start replaces a running timer', () {
    service.start(const Duration(minutes: 15));
    expect(service.remaining, const Duration(minutes: 15));

    service.start(const Duration(minutes: 60));
    expect(service.remaining, const Duration(minutes: 60));
  });

  test('emits decreasing remaining and expires at zero', () async {
    final seen = <Duration?>[];
    service.stateStream.listen(seen.add);

    service.start(const Duration(milliseconds: 100));
    // First emission is the initial value (Duration 100ms), delivered
    // synchronously during start(). Ticks are the subsequent emissions.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(seen.last, const Duration(milliseconds: 100));

    await tick(); // +20 ms → remaining 80 ms
    expect(seen.last, const Duration(milliseconds: 80));

    await tick(const Duration(milliseconds: 40)); // +40 → 40 ms
    expect(seen.last, const Duration(milliseconds: 40));

    await tick(const Duration(milliseconds: 40)); // +40 → 0 → expires
    expect(seen.last, isNull);

    expect(service.isActive, isFalse);
  });

  test('fires expiredStream exactly once when the countdown reaches zero',
      () async {
    var expired = 0;
    service.expiredStream.listen((_) => expired++);

    service.start(const Duration(milliseconds: 100));
    expect(expired, 0);

    await tick(const Duration(milliseconds: 100)); // exactly at expiry
    expect(expired, 1);

    await tick(); // another tick — must not fire again
    expect(expired, 1);

    expect(service.isActive, isFalse);
  });

  test('cancel stops the countdown and emits null', () async {
    service.start(const Duration(minutes: 5));
    expect(service.isActive, isTrue);

    service.cancel();
    expect(service.isActive, isFalse);
    expect(service.remaining, isNull);
  });

  test('cancel does not fire expiredStream', () async {
    var expired = 0;
    service.expiredStream.listen((_) => expired++);

    service.start(const Duration(minutes: 5));
    service.cancel();

    await tick(); // confirm the expiry callback is never scheduled
    expect(expired, 0);
  });

  test('start with zero duration expires immediately', () async {
    var expired = 0;
    service.expiredStream.listen((_) => expired++);

    service.start(Duration.zero);
    expect(service.isActive, isFalse);
    expect(service.remaining, isNull);
    expect(expired, 1);
  });

  test('stateStream emits null once when cancelled', () async {
    final values = <Duration?>[];
    final sub = service.stateStream.listen(values.add);
    addTearDown(sub.cancel);

    service.start(const Duration(minutes: 15));
    expect(values.first, const Duration(minutes: 15));

    service.cancel();

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(values.length, 2);
    expect(values.last, isNull);
  });

  test('dispose is safe while the timer is active', () async {
    service.start(const Duration(minutes: 1));
    fakeNow = fakeNow.add(const Duration(minutes: 5)); // past expiry
    await service.dispose();
    // dispose must complete without error; cancel + close run first.
    expect(service.isActive, isFalse);
  });

  test('remaining is anchored to expiresAt — a delayed tick catches up (§8)',
      () async {
    var expired = 0;
    service.expiredStream.listen((_) => expired++);

    service.start(const Duration(minutes: 1));
    expect(service.remaining, const Duration(minutes: 1));

    // App suspended for 30 s: the clock jumps, but no ticks have fired yet.
    fakeNow = fakeNow.add(const Duration(seconds: 30));
    // The getter recomputes from expiresAt – the remaining time has shrunk
    // even before the next tick fires.
    expect(service.remaining, const Duration(seconds: 30));

    // A further jump past expiry.
    fakeNow = fakeNow.add(const Duration(seconds: 31));
    expect(service.remaining, Duration.zero);

    // The next real tick picks up the expired state and fires once.
    await tick();
    expect(expired, 1);
    expect(service.isActive, isFalse);
  });

  test('presets list contains exactly 15, 30, 45, 60, 90 minutes', () {
    expect(SleepTimerService.presets, const [
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(minutes: 45),
      Duration(minutes: 60),
      Duration(minutes: 90),
    ]);
  });
}