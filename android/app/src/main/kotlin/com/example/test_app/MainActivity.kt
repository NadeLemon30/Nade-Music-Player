package com.example.test_app

import android.media.audiofx.BassBoost
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * Phase 4B native audio effects (preamp, bass boost, spatial virtualizer).
 *
 * These three `android.media.audiofx` effects live here behind a [MethodChannel]
 * and are attached to the SAME audio session the existing just_audio player
 * owns. The Dart side passes that session id in (it comes from just_audio's
 * `androidAudioSessionIdStream`), which is why the app still has exactly one
 * player, one AudioHandler and one audio session.
 *
 * The preamp used to ride just_audio's `AndroidLoudnessEnhancer` inside the
 * `AudioPipeline` instead, and was silently inaudible. That path has three ways
 * to no-op without ever throwing:
 *  1. `AudioEffect.setEnabled`/`setTargetGain` only reach the platform while the
 *     player is `_active`, so every write made before the first source is loaded
 *     is thrown away;
 *  2. just_audio discards parameter writes made before the effect is attached to
 *     a live audio session;
 *  3. the effect is re-created from a snapshot serialized at platform-init time
 *     whenever Android hands over a new session id, so a value the user set
 *     afterwards silently reverts.
 * Driving it from here removes all three: the effect is created for the session
 * that is actually playing, the gain is written immediately before it is
 * engaged, and it is rebuilt on every session change — the same proven path the
 * bass boost and virtualizer already use.
 *
 * An `AudioEffect` is bound to the audio session it was constructed with, so the
 * effects are released and recreated whenever the session id changes (which
 * happens on some source/attribute changes).
 */
class MainActivity : AudioServiceActivity() {

    private companion object {
        const val CHANNEL = "com.example.test_app/audio_effects"

        /**
         * The strength scale Android documents for `BassBoost.setStrength(short)`
         * and `Virtualizer.setStrength(short)`: a per-mille value, i.e. 1000 is
         * 100%. These effects expose no public strength-range query, so this is the
         * platform contract rather than a per-device guess, and it is reported to
         * Dart so the UI can show what the device actually uses.
         */
        const val STRENGTH_MIN = 0
        const val STRENGTH_MAX = 1000

        /**
         * `LoudnessEnhancer.setTargetGain(int)` takes **millibels**, and Android
         * documents `0 mB` as "no amplification": the effect only ever boosts, so
         * there is no negative gain to ask for. The platform caps the target at
         * 2000 mB, i.e. +20 dB, and — like `BassBoost`'s strength — exposes no
         * public range query, so these are the documented platform bounds rather
         * than a per-device reading. They are reported to Dart so the slider is
         * built from what the effect actually accepts.
         */
        const val PREAMP_GAIN_MIN_MB = 0
        const val PREAMP_GAIN_MAX_MB = 2000
    }

    private var preamp: LoudnessEnhancer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var boundSessionId: Int = 0

    /**
     * Whether the device lets us change the strength at all — the one capability
     * these effects really do report (`getStrengthSupported()`). A device that says
     * no keeps the effect switchable but has no usable strength slider.
     */
    private var bassBoostStrengthSupported = false
    private var virtualizerStrengthSupported = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::onMethodCall)
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "applyEffects" -> result.success(applyEffects(call))
            "releaseEffects" -> {
                releaseEffects()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Applies (or re-binds) all three effects and reports which ones the device
     * actually supports. Never throws: a device without the effect simply reports
     * false, and the UI keeps the control disabled with an explanation.
     */
    private fun applyEffects(call: MethodCall): Map<String, Any> {
        val sessionId = (call.argument<Int>("sessionId") ?: 0)
        val preampEnabled = call.argument<Boolean>("preampEnabled") ?: false
        val preampDb = (call.argument<Double>("preampDb") ?: 0.0)
        val bassBoostEnabled = call.argument<Boolean>("bassBoostEnabled") ?: false
        val bassBoostStrength = (call.argument<Double>("bassBoostStrength") ?: 0.0)
        val virtualizerEnabled = call.argument<Boolean>("virtualizerEnabled") ?: false
        val virtualizerStrength = (call.argument<Double>("virtualizerStrength") ?: 0.0)

        if (sessionId <= 0) {
            return supportMap()
        }

        if (sessionId != boundSessionId) {
            releaseEffects()
            boundSessionId = sessionId
        }

        applyPreamp(sessionId, preampEnabled, preampDb)
        applyBassBoost(sessionId, bassBoostEnabled, bassBoostStrength)
        applyVirtualizer(sessionId, virtualizerEnabled, virtualizerStrength)
        return supportMap()
    }

    /**
     * Creates (or reuses) the `LoudnessEnhancer` for [sessionId] and applies the
     * user's preamp setting to it.
     *
     * The target gain is written **before** `setEnabled(true)`: engaging the
     * effect while it still holds the platform's default target leaves it
     * audibly doing nothing, and `setEnabled` is what puts the effect in the
     * chain at all.
     */
    private fun applyPreamp(sessionId: Int, enabled: Boolean, decibels: Double) {
        var effect = preamp
        if (effect == null) {
            try {
                effect = LoudnessEnhancer(sessionId)
                preamp = effect
            } catch (e: Exception) {
                // No usable loudness enhancer on this device.
                preamp = null
                return
            }
        }
        try {
            effect.setTargetGain(scalePreampDb(decibels))
            effect.setEnabled(enabled)
        } catch (e: Exception) {
            releasePreamp()
        }
    }

    /**
     * Converts the preamp's decibel value into the millibels
     * `LoudnessEnhancer.setTargetGain` takes, clamped to the bounds the platform
     * documents. The clamp lives here so the platform is never asked for a gain
     * outside the range it accepts, whatever the slider produced.
     */
    private fun scalePreampDb(decibels: Double): Int {
        val minDb = PREAMP_GAIN_MIN_MB / 100.0
        val maxDb = PREAMP_GAIN_MAX_MB / 100.0
        val millibels = (decibels.coerceIn(minDb, maxDb) * 100.0).roundToInt()
        return millibels.coerceIn(PREAMP_GAIN_MIN_MB, PREAMP_GAIN_MAX_MB)
    }

    private fun applyBassBoost(sessionId: Int, enabled: Boolean, strength: Double) {
        var effect = bassBoost
        if (effect == null) {
            try {
                effect = BassBoost(0, sessionId)
                bassBoost = effect
                bassBoostStrengthSupported = effect.strengthSupported
            } catch (e: Exception) {
                bassBoost = null
                bassBoostStrengthSupported = false
                return
            }
        }
        try {
            effect.setEnabled(enabled)
            if (enabled && bassBoostStrengthSupported) {
                // BassBoost.setStrength is deprecated and takes a short in the
                // per-mille scale, so the value is narrowed explicitly.
                @Suppress("DEPRECATION")
                effect.setStrength(scaleStrength(strength))
            }
        } catch (e: Exception) {
            releaseBassBoost()
        }
    }

    private fun applyVirtualizer(sessionId: Int, enabled: Boolean, strength: Double) {
        var effect = virtualizer
        if (effect == null) {
            try {
                effect = Virtualizer(0, sessionId)
                virtualizer = effect
                virtualizerStrengthSupported = effect.strengthSupported
            } catch (e: Exception) {
                virtualizer = null
                virtualizerStrengthSupported = false
                return
            }
        }
        try {
            effect.setEnabled(enabled)
            if (enabled && virtualizerStrengthSupported) {
                @Suppress("DEPRECATION")
                effect.setStrength(scaleStrength(strength))
            }
        } catch (e: Exception) {
            releaseVirtualizer()
        }
    }

    /**
     * Scales a normalized 0.0..1.0 strength onto the per-mille short the platform
     * documents for these effects. Mapping happens here because only the platform
     * knows the scale its effects accept; the value is clamped twice (normalized
     * first, then to the short range) so no input can overflow the argument.
     */
    @Suppress("DEPRECATION")
    private fun scaleStrength(normalized: Double): Short {
        val fraction = normalized.coerceIn(0.0, 1.0)
        val span = (STRENGTH_MAX - STRENGTH_MIN).toDouble()
        val scaled = STRENGTH_MIN + (fraction * span).roundToInt()
        return scaled.coerceIn(STRENGTH_MIN, STRENGTH_MAX).toShort()
    }

    private fun supportMap(): Map<String, Any> = mapOf(
        "preamp" to (preamp != null),
        "preampGainMin" to PREAMP_GAIN_MIN_MB,
        "preampGainMax" to PREAMP_GAIN_MAX_MB,
        "bassBoost" to (bassBoost != null),
        "virtualizer" to (virtualizer != null),
        "bassBoostStrengthSupported" to bassBoostStrengthSupported,
        "virtualizerStrengthSupported" to virtualizerStrengthSupported,
        "bassBoostStrengthMin" to STRENGTH_MIN,
        "bassBoostStrengthMax" to STRENGTH_MAX,
        "virtualizerStrengthMin" to STRENGTH_MIN,
        "virtualizerStrengthMax" to STRENGTH_MAX
    )

    private fun releaseEffects() {
        releasePreamp()
        releaseBassBoost()
        releaseVirtualizer()
        boundSessionId = 0
    }

    private fun releasePreamp() {
        try {
            preamp?.release()
        } catch (e: Exception) {
            // Already released.
        }
        preamp = null
    }

    private fun releaseBassBoost() {
        try {
            bassBoost?.release()
        } catch (e: Exception) {
            // Already released.
        }
        bassBoost = null
        bassBoostStrengthSupported = false
    }

    private fun releaseVirtualizer() {
        try {
            virtualizer?.release()
        } catch (e: Exception) {
            // Already released.
        }
        virtualizer = null
        virtualizerStrengthSupported = false
    }

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }
}
