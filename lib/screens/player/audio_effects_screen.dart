import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/audio_effects_controller.dart';
import '../../models/audio_effects.dart';
import 'equalizer_screen.dart';

/// The audio-effects hub (Phase 4B spec §14).
///
/// Instead of one enormous screen, the three effects live here as a short list:
/// the equalizer (switch + a jump into the band/preset screen) followed by the
/// two native effects with their own switch and strength slider. This is the
/// only screen the player's Options menu needs to open — [EqualizerScreen] is a
/// child of it.
///
/// Everything degrades quietly: an effect the platform does not support says so
/// and stays disabled, and playback carries on regardless (spec §12/§13).
class AudioEffectsScreen extends ConsumerWidget {
  const AudioEffectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioEffectsControllerProvider);
    final controller = ref.read(audioEffectsControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Effects'),
        actions: [
          IconButton(
            tooltip: 'Reset audio effects',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => controller.reset(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _EqualizerRow(
            state: state,
            onEnabledChanged: controller.setEqualizerEnabled,
          ),
          const Divider(height: 24),
          _NativeEffectSection(
            title: 'Bass Boost',
            icon: Icons.speaker,
            available: state.bassBoostAvailable,
            strengthSupported: state.bassBoostStrengthSupported,
            enabled: state.bassBoostEnabled,
            strength: state.bassBoostStrength,
            range: state.bassBoostRange,
            onEnabledChanged: controller.setBassBoostEnabled,
            onStrengthChanged: controller.setBassBoost,
          ),
          const SizedBox(height: 16),
          _NativeEffectSection(
            title: 'Virtualizer',
            icon: Icons.surround_sound,
            available: state.virtualizerAvailable,
            strengthSupported: state.virtualizerStrengthSupported,
            enabled: state.virtualizerEnabled,
            strength: state.virtualizerStrength,
            range: state.virtualizerRange,
            onEnabledChanged: controller.setVirtualizerEnabled,
            onStrengthChanged: controller.setVirtualizer,
          ),
          const SizedBox(height: 24),
          Text(
            'Audio effects are applied to the current playback session and stay '
            'active in the background.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// The equalizer row: the master switch (spec §11) plus a jump into the band
/// screen. Bypassing the equalizer keeps the preset, the band gains and the
/// preamp stored, so switching it back on restores them untouched.
class _EqualizerRow extends StatelessWidget {
  const _EqualizerRow({required this.state, required this.onEnabledChanged});

  final AudioEffectsState state;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final preset = state.preset?.label ?? 'Custom';
    final summary = state.equalizerEnabled
        ? 'On \u00b7 $preset'
        : 'Off \u00b7 $preset';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.equalizer),
          title: const Text('Equalizer'),
          subtitle: Text(summary),
          value: state.equalizerEnabled,
          onChanged: state.supported ? onEnabledChanged : null,
        ),
        if (!state.supported)
          const _Note(text: 'Equalizer unavailable on this device.'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EqualizerScreen(),
              ),
            ),
            icon: const Icon(Icons.tune, size: 18),
            label: Text(
              state.parametersReady ? 'Edit bands and preset' : 'Equalizer settings',
            ),
          ),
        ),
      ],
    );
  }
}

/// One native effect: switch + 0-100 % strength (spec §12/§13).
///
/// The strength is stored normalized and mapped by the platform onto the scale
/// its effect accepts, so 0 % is the device's minimum and 100 % its maximum — no
/// fixed per-device integer scale is assumed here. An effect the device does not
/// have is described and disabled; an effect whose strength the device refuses to
/// change (`getStrengthSupported()` is false) stays switchable but shows no
/// slider.
class _NativeEffectSection extends StatelessWidget {
  const _NativeEffectSection({
    required this.title,
    required this.icon,
    required this.available,
    required this.strengthSupported,
    required this.enabled,
    required this.strength,
    required this.range,
    required this.onEnabledChanged,
    required this.onStrengthChanged,
  });

  final String title;
  final IconData icon;
  final bool available;
  final bool strengthSupported;
  final bool enabled;
  final double strength;
  final StrengthRange range;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<double> onStrengthChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(icon),
          title: Text(title),
          subtitle: Text(
            available
                ? (enabled ? '${(strength * 100).round()}%' : 'Off')
                : 'Off',
          ),
          value: enabled,
          onChanged: available ? onEnabledChanged : null,
        ),
        if (!available)
          _Note(text: '$title unavailable on this device.')
        else if (!strengthSupported)
          _Note(text: "This device doesn't let the $title strength be adjusted.")
        else ...[
          Slider(
            value: strength.clamp(0.0, 1.0),
            onChanged: enabled ? onStrengthChanged : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0%', style: theme.textTheme.labelSmall),
                Text('100%', style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          if (!range.isDefault)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                'Device strength range: ${range.min}\u2013${range.max}',
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      ],
    );
  }
}

/// Small explanatory line under a control.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
