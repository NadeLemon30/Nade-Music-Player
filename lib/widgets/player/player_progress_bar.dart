import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/duration_utils.dart';
import '../../player/player_controller.dart';

/// Seekable progress bar for the full player.
///
/// Implements the "drag locally, seek on release" pattern (Phase 3C.4):
/// while the thumb is dragged only a local [_PlayerProgressBarState._dragPosition]
/// is updated; the audio engine is seeked exactly once, in [Slider.onChangeEnd].
/// The bar is disabled while no track is loaded or the duration is unknown.
class PlayerProgressBar extends ConsumerStatefulWidget {
  const PlayerProgressBar({super.key});

  @override
  ConsumerState<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends ConsumerState<PlayerProgressBar> {
  double? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerNotifierProvider);

    final duration = state.duration.inMilliseconds.toDouble();
    final actualPosition = state.position.inMilliseconds.toDouble();

    final sliderPosition = _dragPosition ?? actualPosition;

    final safeDuration = duration > 0 ? duration : 1.0;
    final safePosition = sliderPosition.clamp(0.0, safeDuration).toDouble();

    return Column(
      children: [
        Slider(
          value: safePosition,
          min: 0,
          max: safeDuration,
          onChanged: duration <= 0
              ? null
              : (value) {
                  setState(() => _dragPosition = value);
                },
          onChangeEnd: duration <= 0
              ? null
              : (value) async {
                  await ref
                      .read(playerNotifierProvider.notifier)
                      .seek(Duration(milliseconds: value.round()));
                  if (mounted) {
                    setState(() => _dragPosition = null);
                  }
                },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DurationUtils.formatDuration(state.position),
              ),
              Text(
                DurationUtils.formatDuration(state.duration),
              ),
            ],
          ),
        ),
      ],
    );
  }
}