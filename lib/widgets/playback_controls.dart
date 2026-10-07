import 'package:flutter/material.dart';

class PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final bool isLoading;
  final VoidCallback onPlayPause;
  final VoidCallback? onSeekBackward;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSeekForward;
  final double iconSize;

  const PlaybackControls({
    super.key,
    required this.isPlaying,
    this.isBuffering = false,
    this.isLoading = false,
    required this.onPlayPause,
    this.onSeekBackward,
    this.onPrevious,
    this.onNext,
    this.onSeekForward,
    this.iconSize = 32.0,
  });

  @override
  Widget build(BuildContext context) {
    final showSpinner = isLoading || isBuffering;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: iconSize,
          icon: const Icon(Icons.replay_10),
          onPressed: isLoading ? null : onSeekBackward,
        ),
        IconButton(
          iconSize: iconSize,
          icon: const Icon(Icons.skip_previous),
          onPressed: isLoading ? null : onPrevious,
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          iconSize: iconSize * 1.25,
          icon: showSpinner
              ? SizedBox(
                  width: iconSize * 1.25,
                  height: iconSize * 1.25,
                  child: const CircularProgressIndicator(strokeWidth: 3),
                )
              : Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: isLoading ? null : onPlayPause,
        ),
        const SizedBox(width: 12),
        IconButton(
          iconSize: iconSize,
          icon: const Icon(Icons.skip_next),
          onPressed: isLoading ? null : onNext,
        ),
        IconButton(
          iconSize: iconSize,
          icon: const Icon(Icons.forward_10),
          onPressed: isLoading ? null : onSeekForward,
        ),
      ],
    );
  }
}
