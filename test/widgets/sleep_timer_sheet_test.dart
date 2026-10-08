import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nades_music_player/services/sleep_timer_service.dart';
import 'package:nades_music_player/widgets/player/sleep_timer_sheet.dart';

void main() {
  late ProviderContainer container;
  late SleepTimerService sleepTimer;
  late DateTime fakeNow;

  setUp(() {
    // A fake clock so the countdown is deterministic under FakeAsync: the real
    // DateTime.now() never advances inside tester.pump(), so remaining-time
    // assertions would otherwise be flaky. Tests that exercise ticking advance
    // `fakeNow` in lock-step with the pumped duration.
    fakeNow = DateTime.utc(2026, 1, 1, 12);
    sleepTimer = SleepTimerService(
      tickInterval: const Duration(milliseconds: 10),
      now: () => fakeNow,
    );
    container = ProviderContainer(
      overrides: [
        sleepTimerServiceProvider.overrideWithValue(sleepTimer),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    sleepTimer.cancel();
    await sleepTimer.dispose();
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SleepTimerSheet()),
        ),
      ),
    );
  }

  testWidgets('shows the preset menu when inactive', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Off'), findsOneWidget);
    expect(find.text('15 minutes'), findsOneWidget);
    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.text('45 minutes'), findsOneWidget);
    expect(find.text('60 minutes'), findsOneWidget);
    expect(find.text('90 minutes'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.textContaining('remaining'), findsNothing);
    expect(find.text('Cancel Timer'), findsNothing);
  });

  testWidgets('tapping a preset starts the countdown and shows the active view',
      (tester) async {
    await pumpSheet(tester);
    await tester.pump();

    await tester.tap(find.text('15 minutes'));
    await tester.pump();

    expect(sleepTimer.isActive, isTrue);
    expect(sleepTimer.remaining, const Duration(minutes: 15));
    expect(find.textContaining('remaining'), findsOneWidget);
    expect(find.text('Cancel Timer'), findsOneWidget);
    expect(find.text('30 minutes'), findsNothing);

    await tester.tap(find.text('Cancel Timer'));
    await tester.pump();
    expect(sleepTimer.isActive, isFalse);
  });

  testWidgets('the remaining time ticks down while active', (tester) async {
    sleepTimer.start(const Duration(minutes: 2));
    await pumpSheet(tester);
    await tester.pump();
    await tester.pump();

    expect(find.text('02:00 remaining'), findsOneWidget);

    // Advance the fake countdown clock together with FakeAsync time so the
    // ticks firing inside the pump recompute the wall-clock-anchored remaining
    // from the advanced clock (replicating what real time does on-device).
    fakeNow = fakeNow.add(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(sleepTimer.remaining, isNotNull);
    expect(
      sleepTimer.remaining!,
      lessThan(const Duration(minutes: 2)),
    );
    expect(find.text('01:59 remaining'), findsOneWidget);

    await tester.tap(find.text('Cancel Timer'));
    await tester.pump();
    expect(sleepTimer.isActive, isFalse);
  });

  testWidgets('Cancel Timer clears the countdown and restores the menu',
      (tester) async {
    sleepTimer.start(const Duration(minutes: 30));
    await pumpSheet(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('Cancel Timer'), findsOneWidget);

    await tester.tap(find.text('Cancel Timer'));
    await tester.pump();

    expect(sleepTimer.isActive, isFalse);
    expect(sleepTimer.remaining, isNull);
    expect(find.text('30 minutes'), findsOneWidget);
    expect(find.text('Cancel Timer'), findsNothing);
  });

  testWidgets('Custom opens a dialog with hours and minutes and starts the entered duration',
      (tester) async {
    await pumpSheet(tester);
    await tester.pump();

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    expect(find.text('Set Sleep Timer'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).at(0), '1'); // Hours
    await tester.enterText(find.byType(TextField).at(1), '30'); // Minutes
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(sleepTimer.isActive, isTrue);
    expect(sleepTimer.remaining, const Duration(hours: 1, minutes: 30));
    expect(find.textContaining('remaining'), findsOneWidget);

    await tester.tap(find.text('Cancel Timer'));
    await tester.pump();
    expect(sleepTimer.isActive, isFalse);
  });

  testWidgets('Custom rejects 0 hours/0 minutes and durations over 24 hours',
      (tester) async {
    await pumpSheet(tester);
    await tester.pump();

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    final startButton = find.widgetWithText(FilledButton, 'Start');

    // 0 hours, 0 minutes → Start stays disabled, nothing starts.
    await tester.enterText(find.byType(TextField).at(0), '0');
    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.pump();

    expect(tester.widget<FilledButton>(startButton).onPressed, isNull);
    expect(find.text('Set Sleep Timer'), findsOneWidget);
    expect(sleepTimer.isActive, isFalse);

    // Over the 24-hour maximum → Start disabled + a visible hint.
    await tester.enterText(find.byType(TextField).at(0), '25');
    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.pump();

    expect(find.text('Maximum 24 hours'), findsOneWidget);
    expect(tester.widget<FilledButton>(startButton).onPressed, isNull);
    expect(sleepTimer.isActive, isFalse);

    // A valid entry re-enables Start.
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.pump();
    expect(tester.widget<FilledButton>(startButton).onPressed, isNotNull);

    // Cancelling leaves the timer untouched.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(sleepTimer.isActive, isFalse);
    expect(find.text('Set Sleep Timer'), findsNothing);
  });

  testWidgets('starting a preset then reopening shows the active view',
      (tester) async {
    await pumpSheet(tester);
    await tester.pump();

    await tester.tap(find.text('60 minutes'));
    await tester.pump();

    expect(sleepTimer.isActive, isTrue);
    expect(find.textContaining('remaining'), findsOneWidget);
    expect(find.text('Cancel Timer'), findsOneWidget);

    await tester.tap(find.text('Cancel Timer'));
    await tester.pump();
    expect(sleepTimer.isActive, isFalse);
  });
}