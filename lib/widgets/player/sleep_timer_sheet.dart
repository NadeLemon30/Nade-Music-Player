import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/duration_utils.dart';
import '../../services/sleep_timer_service.dart';

/// Opens the Sleep Timer modal bottom sheet (Phase 4A).
void showSleepTimerSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const SleepTimerSheet(),
  );
}

/// Sleep Timer picker + active-countdown view.
///
/// Inactive: shows the preset menu (Off / 15 / 30 / 45 / 60 / 90 minutes /
/// Custom), matching the spec's example. Active: shows the live remaining time
/// and a "Cancel Timer" action. All mutations go through
/// [sleepTimerServiceProvider] — no timer logic lives in this screen.
class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remaining = ref.watch(sleepTimerStateProvider).value;
    final service = ref.read(sleepTimerServiceProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Sleep Timer',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              if (remaining == null)
                _SleepTimerOptions(
                  onSelected: service.start,
                  onCustom: () => _showCustomDialog(context, ref),
                )
              else
                _ActiveSleepTimer(
                  remaining: remaining,
                  onCancel: service.cancel,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCustomDialog(BuildContext context, WidgetRef ref) async {
    final totalMinutes = await showDialog<int>(
      context: context,
      builder: (dialogContext) => const _CustomSleepTimerDialog(),
    );

    if (totalMinutes != null && totalMinutes > 0) {
      ref
          .read(sleepTimerServiceProvider)
          .start(Duration(minutes: totalMinutes));
    }
  }
}

/// Custom sleep timer entry: Hours + Minutes (spec §11).
///
/// Start is only enabled when the entered duration is within `1..=1440`
/// minutes — a "0 hours, 0 minutes" value and anything above the 24-hour
/// recommended maximum are both rejected (the dialog stays open). Nothing is
/// started until Start is pressed.
class _CustomSleepTimerDialog extends StatefulWidget {
  const _CustomSleepTimerDialog();

  @override
  State<_CustomSleepTimerDialog> createState() => _CustomSleepTimerDialogState();
}

class _CustomSleepTimerDialogState extends State<_CustomSleepTimerDialog> {
  final _hoursController = TextEditingController(text: '0');
  final _minutesController = TextEditingController(text: '30');

  static const _maxTotalMinutes = 24 * 60;

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  /// Total entered minutes, or null when the value is < 1 or > 24 hours.
  int? get _totalMinutes {
    final hours = int.tryParse(_hoursController.text) ?? 0;
    final minutes = int.tryParse(_minutesController.text) ?? 0;
    final total = hours * 60 + minutes;
    if (total <= 0 || total > _maxTotalMinutes) return null;
    return total;
  }

  bool get _exceedsMaximum {
    final hours = int.tryParse(_hoursController.text) ?? 0;
    final minutes = int.tryParse(_minutesController.text) ?? 0;
    return hours * 60 + minutes > _maxTotalMinutes;
  }

  void _submit() {
    final total = _totalMinutes;
    if (total != null) {
      Navigator.of(context).pop(total);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _totalMinutes;

    return AlertDialog(
      title: const Text('Set Sleep Timer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hoursController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Hours'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _minutesController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Minutes'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),
          if (_exceedsMaximum) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Maximum 24 hours',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: total != null ? _submit : null,
          child: const Text('Start'),
        ),
      ],
    );
  }
}

/// The preset list shown while no countdown is running. "Off" is the current
/// (selected) state; picking any other entry starts the timer.
class _SleepTimerOptions extends StatelessWidget {
  const _SleepTimerOptions({
    required this.onSelected,
    required this.onCustom,
  });

  final ValueChanged<Duration> onSelected;
  final VoidCallback onCustom;

  static List<(String, Duration)> get _presets =>
      SleepTimerService.presets.map((d) => ('${d.inMinutes} minutes', d)).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          dense: true,
          leading: Icon(
            Icons.check,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            'Off',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        for (final (label, duration) in _presets)
          ListTile(
            title: Text(label),
            onTap: () => onSelected(duration),
          ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Custom'),
          onTap: onCustom,
        ),
      ],
    );
  }
}

/// Live countdown view: remaining time + cancel. Shown while the timer runs.
class _ActiveSleepTimer extends StatelessWidget {
  const _ActiveSleepTimer({
    required this.remaining,
    required this.onCancel,
  });

  final Duration remaining;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bedtime, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${DurationUtils.formatDuration(remaining)} remaining',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            label: const Text('Cancel Timer'),
          ),
        ],
      ),
    );
  }
}