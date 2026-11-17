import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lyrics/lyrics_controller.dart';
import '../../core/lyrics/lyrics_file_picker.dart';
import '../../data/repositories/lyrics_repository.dart';
import '../../player/player_controller.dart';

/// Displays lyrics for the currently playing track.
///
/// Reads playback position from [PlayerController] (via [LyricsController]) and
/// never controls playback. Supports synced highlighting/auto-scroll, plain
/// text, manual timing offset, and unavailable states.
class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = <int, GlobalKey>{};
  int _lastScrolledIndex = -1;
  String? _lastTrackId;
  bool _importing = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(int index) =>
      _lineKeys.putIfAbsent(index, () => GlobalKey());

  void _maybeScrollTo(int index, {required bool animated}) {
    if (index < 0) return;
    if (index == _lastScrolledIndex) return;
    _lastScrolledIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _lineKeys[index]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: animated ? const Duration(milliseconds: 300) : Duration.zero,
        curve: Curves.easeInOut,
        alignment: 0.35,
      );
    });
  }

  Future<void> _pickLyricsFile() async {
    if (_importing) return;
    final track =
        ref.read(lyricsControllerProvider).track ??
        ref.read(playerNotifierProvider).currentTrack;
    if (track == null) return;

    setState(() => _importing = true);
    try {
      final picked = await ref.read(lyricsFilePickerProvider)();
      if (picked == null || !mounted) return;

      await ref
          .read(lyricsControllerProvider.notifier)
          .importLyricsBytes(picked.bytes, fileName: picked.name);
      if (!mounted) return;

      _lastScrolledIndex = -1;
      _lineKeys.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lyrics added from "${picked.name}"')),
      );
    } on LyricsReadException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That file does not contain readable lyrics.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add the lyrics file.')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _removeImportedLyrics() async {
    try {
      await ref.read(lyricsControllerProvider.notifier).removeImportedLyrics();
      if (!mounted) return;
      _lastScrolledIndex = -1;
      _lineKeys.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Imported lyrics removed')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove imported lyrics.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lyricsControllerProvider);
    final player = ref.watch(playerNotifierProvider);
    final track = state.track ?? player.currentTrack;

    // Reset scroll state on track change.
    if (track?.id != _lastTrackId) {
      _lastTrackId = track?.id;
      _lastScrolledIndex = -1;
      _lineKeys.clear();
    }

    final title = track?.title ?? 'Lyrics';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (state.isSynced)
            IconButton(
              tooltip: 'Reset lyric offset',
              icon: const Icon(Icons.restore),
              onPressed: state.offset == Duration.zero
                  ? null
                  : () => ref
                        .read(lyricsControllerProvider.notifier)
                        .resetOffset(),
            ),
          IconButton(
            tooltip: 'Add or replace lyrics file',
            icon: _importing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_open_outlined),
            onPressed: track == null || _importing ? null : _pickLyricsFile,
          ),
          if (state.isImported)
            IconButton(
              tooltip: 'Remove imported lyrics',
              icon: const Icon(Icons.delete_outline),
              onPressed: _removeImportedLyrics,
            ),
          IconButton(
            tooltip: 'Refresh lyrics',
            icon: const Icon(Icons.refresh),
            onPressed: track == null
                ? null
                : () => ref
                      .read(lyricsControllerProvider.notifier)
                      .refreshCurrent(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (track != null)
            _Header(trackTitle: track.title, artist: track.artist),
          if (state.isSynced) _OffsetBar(state: state),
          Expanded(child: _buildBody(context, state, track)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, LyricsState state, dynamic track) {
    if (track == null) {
      return const _MessageView(
        icon: Icons.music_off,
        title: 'No track playing',
        subtitle: 'Play a song to see its lyrics.',
      );
    }

    if (state.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading lyrics...'),
          ],
        ),
      );
    }

    if (state.error) {
      return _MessageView(
        icon: Icons.error_outline,
        title: 'Unable to read lyrics',
        subtitle:
            'The lyrics file could not be read. The song itself will continue '
            'playing normally.',
        actionLabel: _importing ? 'Adding...' : 'Add Lyrics File',
        onAction: _importing ? null : _pickLyricsFile,
        secondaryActionLabel: 'Try Again',
        onSecondaryAction: () =>
            ref.read(lyricsControllerProvider.notifier).refreshCurrent(),
      );
    }

    if (state.unavailable || !state.hasLyrics) {
      return _MessageView(
        icon: Icons.lyrics_outlined,
        title: 'No lyrics available',
        subtitle:
            'Lyrics could not be found for this song. You can add an .lrc or '
            '.txt file from your device.',
        actionLabel: _importing ? 'Adding...' : 'Add Lyrics File',
        onAction: _importing ? null : _pickLyricsFile,
        secondaryActionLabel: 'Try Again',
        onSecondaryAction: () =>
            ref.read(lyricsControllerProvider.notifier).refreshCurrent(),
      );
    }

    final lyrics = state.lyrics!;

    if (lyrics.synchronized) {
      _maybeScrollTo(state.currentLineIndex, animated: true);
      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        itemCount: lyrics.lines.length,
        itemBuilder: (context, index) {
          final line = lyrics.lines[index];
          final isActive = index == state.currentLineIndex;
          final isPast =
              state.currentLineIndex >= 0 && index < state.currentLineIndex;
          final theme = Theme.of(context);
          final base = theme.textTheme.titleMedium;
          final color = isActive
              ? theme.colorScheme.onSurface
              : isPast
              ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
              : theme.colorScheme.onSurface.withValues(alpha: 0.6);
          return Container(
            key: _keyFor(index),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: (base ?? const TextStyle(fontSize: 18)).copyWith(
                color: color,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                fontSize: isActive ? 22 : 18,
                height: 1.4,
              ),
              child: Text(line.text, textAlign: TextAlign.center),
            ),
          );
        },
      );
    }

    // Plain (unsynced) lyrics.
    _lastScrolledIndex = -1;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'Unsynchronized lyrics',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            itemCount: lyrics.lines.length,
            itemBuilder: (context, index) {
              final line = lyrics.lines[index];
              if (line.text.trim().isEmpty) {
                return const SizedBox(height: 16);
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  line.text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(height: 1.5),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.trackTitle, required this.artist});
  final String trackTitle;
  final String artist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        children: [
          Text(
            'Now Playing',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            artist,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          Text(
            trackTitle,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OffsetBar extends ConsumerWidget {
  const _OffsetBar({required this.state});
  final LyricsState state;

  static String _formatSec(double value) {
    final fixed = value.toStringAsFixed(1);
    final sign = value > 0 ? '+' : '';
    return '$sign$fixed sec';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = (state.offset.inMilliseconds / 1000.0).clamp(-5.0, 5.0);
    final notifier = ref.read(lyricsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lyrics Offset',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            children: [
              const Text('-5.0s'),
              Expanded(
                child: Slider(
                  value: seconds.toDouble(),
                  min: -5.0,
                  max: 5.0,
                  divisions: 20,
                  label: _formatSec(seconds.toDouble()),
                  onChanged: (v) {
                    final ms = (v * 1000).round();
                    notifier.setOffset(Duration(milliseconds: ms));
                  },
                ),
              ),
              const Text('+5.0s'),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    notifier.adjustOffset(const Duration(milliseconds: -500)),
                icon: const Icon(Icons.remove),
                label: const Text('-0.5 sec'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _formatSec(seconds.toDouble()),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    notifier.adjustOffset(const Duration(milliseconds: 500)),
                icon: const Icon(Icons.add),
                label: const Text('+0.5 sec'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
            if (secondaryActionLabel != null) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
