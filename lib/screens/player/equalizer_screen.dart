import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/audio_effects_controller.dart';
import '../../models/audio_effects.dart';

/// The equalizer screen (Phase 4B spec §11, reached from [AudioEffectsScreen]).
///
/// Owns only the equalizer: the master switch (spec §11 — bypassing the effect
/// keeps every stored setting, so switching it back on restores the curve), the
/// preset row, the band sliders and the preamp. Bass boost and the virtualizer
/// live on the [AudioEffectsScreen] hub instead (spec §14).
///
/// The band layout is **built from whatever the audio backend reports**
/// (spec §5/§6): the sliders, their count, their range and their frequency labels
/// all come from [AudioEffectsState.bands] / `minDecibels` / `maxDecibels`, so a
/// device exposing 3, 5 or 10 bands renders correctly instead of a hard-coded
/// 60/230/910/3.6k/14k layout, and a device with a narrower range than
/// -12…+12 dB is never shown a -12…+12 dB slider.
class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioEffectsControllerProvider);
    final controller = ref.read(audioEffectsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Equalizer')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _EnableTile(
            title: 'Equalizer',
            subtitle: state.equalizerEnabled ? 'On' : 'Off',
            value: state.equalizerEnabled,
            onChanged: state.supported
                ? (value) => controller.setEqualizerEnabled(value)
                : null,
          ),
          if (!state.resolved)
            const _Message(
              icon: Icons.hourglass_empty,
              text: 'Band information appears once the first track starts playing.',
            )
          else if (!state.supported)
            const _Message(
              icon: Icons.highlight_off,
              text: 'The equalizer is not available on this device.',
            )
          else ...[
            const SizedBox(height: 8),
            _PresetSelector(
              selectedId: state.presetId,
              bandCount: state.bandCount,
              enabled: state.equalizerEnabled,
              onSelected: controller.applyPreset,
            ),
            const SizedBox(height: 16),
            _BandSection(
              state: state,
              onChanged: (index, gain) =>
                  controller.setBandGain(index, gain),
            ),
          ],
          const Divider(height: 32),
          _PreampSection(
            decibels: state.preampDb,
            minDecibels: state.preampMinDecibels,
            maxDecibels: state.preampMaxDecibels,
            enabled: state.preampEnabled,
            available: state.preampAvailable,
            resolved: state.nativeResolved,
            onToggle: controller.setPreampEnabled,
            onChanged: controller.setPreampGain,
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _EnableTile extends StatelessWidget {
  const _EnableTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// The preset picker (spec §7/§9).
///
/// Only presets that can actually be applied to the reported [bandCount] are
/// offered (spec §7) — a curve that doesn't fit the device's bands is never
/// shown. When no preset applies, the row says so instead of pretending. A
/// hand-edited equalizer shows a non-selectable `Custom` chip (spec §9).
class _PresetSelector extends StatelessWidget {
  const _PresetSelector({
    required this.selectedId,
    required this.bandCount,
    required this.enabled,
    required this.onSelected,
  });

  final String? selectedId;
  final int bandCount;
  final bool enabled;
  final ValueChanged<EqPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presets = eqPresetsFor(bandCount);
    final selected = eqPresetById(selectedId);
    final isCustom =
        selected == null || !presets.any((preset) => preset.id == selected.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preset', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (presets.isEmpty)
          Text(
            'No presets fit this device\u2019s $bandCount equalizer bands.',
            style: theme.textTheme.bodySmall,
          )
        else
          // A single horizontally scrollable row keeps the band sliders on
          // screen even with the full preset list.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final preset in presets)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(preset.label),
                      selected: preset.id == selectedId,
                      onSelected: enabled ? (_) => onSelected(preset) : null,
                    ),
                  ),
                if (isCustom)
                  const Chip(
                    label: Text('Custom'),
                    avatar: Icon(Icons.tune, size: 18),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The dynamic band sliders plus a dB scale (spec §4).
class _BandSection extends StatelessWidget {
  const _BandSection({required this.state, required this.onChanged});

  final AudioEffectsState state;
  final void Function(int index, double gain) onChanged;

  static const double _sliderHeight = 180;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final min = state.minDecibels;
    final max = state.maxDecibels;
    final step = (max - min) / 4;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 5; i++)
              SizedBox(
                height: _sliderHeight / 4,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatDb(max - step * i),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final band in state.bands)
                Expanded(
                  child: _BandSlider(
                    band: band,
                    min: min,
                    max: max,
                    height: _sliderHeight,
                    enabled: state.equalizerEnabled,
                    onChanged: (gain) => onChanged(band.index, gain),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.band,
    required this.min,
    required this.max,
    required this.height,
    required this.enabled,
    required this.onChanged,
  });

  final EqBand band;
  final double min;
  final double max;
  final double height;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatDb(band.gain),
          style: theme.textTheme.labelSmall,
        ),
        SizedBox(
          height: height,
          // Rotating the horizontal Slider gives a vertical band slider without
          // a custom gesture recognizer.
          child: RotatedBox(
            quarterTurns: 3,
            child: Slider(
              value: band.gain.clamp(min, max),
              min: min,
              max: max,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
        Text(
          band.frequencyLabel,
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _PreampSection extends StatelessWidget {
  const _PreampSection({
    required this.decibels,
    required this.minDecibels,
    required this.maxDecibels,
    required this.enabled,
    required this.available,
    required this.resolved,
    required this.onToggle,
    required this.onChanged,
  });

  final double decibels;
  final double minDecibels;
  final double maxDecibels;

  /// Whether the preamp effect is engaged (its own switch, not the equalizer's).
  final bool enabled;

  /// Whether the device reported the preamp as usable.
  final bool available;

  /// Whether the device has been asked at all.
  ///
  /// The preamp is an `AudioEffect` bound to the player's audio session, so it
  /// cannot exist before a track is playing. Until the session is known this is
  /// "not answered yet", which must not be shown as "this device has no
  /// preamp" — that message would appear for every user who opened the screen
  /// before playing anything.
  final bool resolved;

  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          // Before the first song there is no audio session to attach an
          // `AudioEffect` to, so the switch stays tappable but inert rather than
          // claiming the device has no preamp.
          value: enabled,
          onChanged: available || !resolved ? onToggle : null,
          title: Text('Preamp', style: theme.textTheme.titleMedium),
          subtitle: Text(
            _formatDb(decibels),
            style: theme.textTheme.labelMedium,
          ),
        ),
        if (!available)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              resolved
                  ? 'The preamp is not available on this device.'
                  : 'The preamp becomes available once music is playing.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          Slider(
            // The preamp's **own** range, reported by the backend (spec §6) —
            // Android's loudness enhancer documents 0 dB as "no amplification"
            // and only ever boosts, so the bands' symmetric ±12 dB range does not
            // apply here.
            value: decibels.clamp(minDecibels, maxDecibels),
            min: minDecibels,
            max: maxDecibels,
            label: _formatDb(decibels),
            onChanged: enabled ? onChanged : null,
          ),
      ],
    );
  }
}

/// Formats a decibel value as `+6 dB` / `0 dB` / `-12 dB`.
String _formatDb(double decibels) {
  final rounded = decibels.round();
  final sign = rounded > 0 ? '+' : '';
  return '$sign$rounded dB';
}
