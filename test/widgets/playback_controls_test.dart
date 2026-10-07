import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_app/widgets/playback_controls.dart';

void main() {
  testWidgets('shows pause while playing and play while paused',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackControls(
            isPlaying: true,
            onPlayPause: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackControls(
            isPlaying: false,
            onPlayPause: () {},
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('shows a loading indicator while buffering instead of play/pause',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackControls(
            isPlaying: false,
            isBuffering: true,
            onPlayPause: () {},
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('renders the full control row and forwards seek callbacks',
      (tester) async {
    var seekBackwardCount = 0;
    var seekForwardCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackControls(
            isPlaying: true,
            onPlayPause: () {},
            onSeekBackward: () => seekBackwardCount++,
            onPrevious: () {},
            onNext: () {},
            onSeekForward: () => seekForwardCount++,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.replay_10), findsOneWidget);
    expect(find.byIcon(Icons.skip_previous), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.skip_next), findsOneWidget);
    expect(find.byIcon(Icons.forward_10), findsOneWidget);

    await tester.tap(find.byIcon(Icons.replay_10));
    await tester.tap(find.byIcon(Icons.forward_10));
    expect(seekBackwardCount, 1);
    expect(seekForwardCount, 1);
  });

  testWidgets('disables every control while loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackControls(
            isPlaying: false,
            isLoading: true,
            onPlayPause: () {},
            onSeekBackward: () {},
            onPrevious: () {},
            onNext: () {},
            onSeekForward: () {},
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    for (final icon in [
      Icons.replay_10,
      Icons.skip_previous,
      Icons.skip_next,
      Icons.forward_10,
    ]) {
      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, icon),
      );
      expect(button.onPressed, isNull,
          reason: '$icon should be disabled while loading');
    }
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.pause), findsNothing);
  });
}