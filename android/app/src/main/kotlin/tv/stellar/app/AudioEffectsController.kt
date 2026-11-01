package tv.stellar.app

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.AudioEffect
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.roundToInt

/**
 * Equalizer, dialogue boost and night mode on one app-owned audio session.
 * mpv (audiotrack-session-id) and ExoPlayer (setAudioSessionId) play on it;
 * Dart computes every gain (models/audio_effects.dart), this class only maps
 * them onto android.media.audiofx. Bitstream passthrough bypasses all of it.
 */
class AudioEffectsController(private val context: Context) : MethodChannel.MethodCallHandler {
    private var sessionId = 0
    private var dynamics: AudioEffect? = null
    private var dynamicsBands = 0
    private var equalizer: Equalizer? = null
    private var loudness: LoudnessEnhancer? = null

    private val hasDynamics by lazy {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && available(TYPE_DYNAMICS)
    }
    private val hasEqualizer by lazy { available(AudioEffect.EFFECT_TYPE_EQUALIZER) }
    private val hasLoudness by lazy { available(TYPE_LOUDNESS) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "prepare" -> result.success(prepare())
                "apply" -> {
                    apply(call)
                    result.success(null)
                }
                "release" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.w(TAG, "audio effects ${call.method} failed", e)
            result.error("audio_effects", e.message, null)
        }
    }

    private fun prepare(): Map<String, Any> {
        if (sessionId == 0) {
            val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            sessionId = manager.generateAudioSessionId()
        }
        return mapOf(
            "sessionId" to sessionId,
            "dynamics" to hasDynamics,
            "equalizer" to hasEqualizer,
            "loudness" to hasLoudness,
        )
    }

    private fun apply(call: MethodCall) {
        if (sessionId <= 0) return
        if (call.argument<Boolean>("active") != true) {
            release()
            return
        }
        val compress = call.argument<Boolean>("compress") == true
        if (hasDynamics && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            applyDynamics(
                call.argument<List<Double>>("preEqCutoffs") ?: emptyList(),
                call.argument<List<Double>>("preEqGains") ?: emptyList(),
                compress,
            )
        } else {
            applyFallback(
                call.argument<List<Double>>("eqCenters") ?: emptyList(),
                call.argument<List<Double>>("eqGains") ?: emptyList(),
                call.argument<Int>("loudnessGainMb") ?: 0,
            )
        }
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.P)
    private fun applyDynamics(cutoffs: List<Double>, gains: List<Double>, compress: Boolean) {
        val bands = minOf(cutoffs.size, gains.size)
        if (bands == 0) return
        var dp = dynamics as? DynamicsProcessing
        if (dp == null || !dp.hasControl() || dynamicsBands != bands) {
            dp?.release()
            // Topology is fixed at creation: every stage is in use and only
            // switched on or off afterwards, so updates never rebuild it.
            val config = DynamicsProcessing.Config.Builder(
                DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
                2,
                true, bands,
                true, MBC_BANDS,
                false, 0,
                true,
            ).setPreferredFrameDuration(10f).build()
            dp = DynamicsProcessing(0, sessionId, config)
            dynamics = dp
            dynamicsBands = bands
        }
        val eq = DynamicsProcessing.Eq(true, true, bands)
        for (i in 0 until bands) {
            eq.setBand(i, DynamicsProcessing.EqBand(true, cutoffs[i].toFloat(), gains[i].toFloat()))
        }
        dp.setPreEqAllChannelsTo(eq)
        dp.setMbcAllChannelsTo(nightCompressor(compress))
        // The limiter catches peaks raised by positive EQ gains, always.
        dp.setLimiterAllChannelsTo(DynamicsProcessing.Limiter(true, true, 0, 1f, 60f, 10f, -1.5f, 0f))
        dp.setEnabled(true)
        releaseFallback()
    }

    /**
     * Night mode: loud lows and highs (effects, score) are squeezed hard,
     * the speech band gently, then make-up gain lifts everything quiet.
     */
    @androidx.annotation.RequiresApi(Build.VERSION_CODES.P)
    private fun nightCompressor(enabled: Boolean): DynamicsProcessing.Mbc {
        val mbc = DynamicsProcessing.Mbc(true, enabled, MBC_BANDS)
        val cutoffs = floatArrayOf(250f, 4000f, 20000f)
        val ratios = floatArrayOf(4f, 2.5f, 3f)
        val makeUp = floatArrayOf(4f, 8f, 5f)
        val releases = floatArrayOf(200f, 120f, 120f)
        for (i in 0 until MBC_BANDS) {
            mbc.setBand(i, DynamicsProcessing.MbcBand(
                enabled,
                cutoffs[i],
                3f, // attack ms
                releases[i],
                ratios[i],
                -28f, // threshold dB
                6f, // knee dB
                -90f, // noise gate threshold dB
                1f, // expander ratio
                0f, // pre-gain dB
                makeUp[i],
            ))
        }
        return mbc
    }

    /** Android 8 and devices without DynamicsProcessing (some Fire TV). */
    private fun applyFallback(centers: List<Double>, gains: List<Double>, loudnessMb: Int) {
        if (hasEqualizer) {
            var eq = equalizer
            if (eq == null || !eq.hasControl()) {
                eq?.release()
                eq = Equalizer(0, sessionId)
                equalizer = eq
            }
            val range = eq.bandLevelRange
            for (band in 0 until eq.numberOfBands) {
                val hz = eq.getCenterFreq(band.toShort()) / 1000.0
                val db = nearestGain(centers, gains, hz)
                val mb = (db * 100).roundToInt().coerceIn(range[0].toInt(), range[1].toInt())
                eq.setBandLevel(band.toShort(), mb.toShort())
            }
            eq.setEnabled(true)
        }
        if (hasLoudness && loudnessMb > 0) {
            var le = loudness
            if (le == null || !le.hasControl()) {
                le?.release()
                le = LoudnessEnhancer(sessionId)
                loudness = le
            }
            le.setTargetGain(loudnessMb)
            le.setEnabled(true)
        } else {
            loudness?.release()
            loudness = null
        }
        dynamics?.release()
        dynamics = null
    }

    private fun nearestGain(centers: List<Double>, gains: List<Double>, hz: Double): Double {
        var best = 0
        var bestDistance = Double.MAX_VALUE
        for (i in 0 until minOf(centers.size, gains.size)) {
            val distance = abs(ln(hz.coerceAtLeast(1.0)) - ln(centers[i]))
            if (distance < bestDistance) {
                best = i
                bestDistance = distance
            }
        }
        return gains.getOrElse(best) { 0.0 }
    }

    private fun releaseFallback() {
        equalizer?.release()
        equalizer = null
        loudness?.release()
        loudness = null
    }

    fun release() {
        dynamics?.release()
        dynamics = null
        releaseFallback()
    }

    private fun available(type: UUID): Boolean = try {
        AudioEffect.queryEffects()?.any { it.type == type } == true
    } catch (e: Exception) {
        false
    }

    private companion object {
        const val TAG = "StellarAudioFx"
        const val MBC_BANDS = 3
        // AudioEffect.EFFECT_TYPE_DYNAMICS_PROCESSING / _LOUDNESS_ENHANCER are
        // API 28 / 19 constants; the UUIDs keep the lookup safe on older APIs.
        val TYPE_DYNAMICS: UUID = UUID.fromString("7261676f-6d75-7369-6364-28e2fd3ac39e")
        val TYPE_LOUDNESS: UUID = UUID.fromString("fe3199be-aed0-413f-87bb-11260eb63cf1")
    }
}
