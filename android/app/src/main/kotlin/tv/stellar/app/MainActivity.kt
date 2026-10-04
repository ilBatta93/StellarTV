package tv.stellar.app

import android.app.PictureInPictureParams
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.MediaCodecList
import android.os.Build
import android.provider.Settings
import android.util.Rational
import android.view.Display
import android.view.WindowManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var autoPip = false
    private var pipRatio = Rational(16, 9)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stellartv/player")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> result.success(pipSupported())
                "enterPip" -> {
                    updateRatio(call.argument<Int>("width"), call.argument<Int>("height"))
                    result.success(enterPip())
                }
                "setAutoPip" -> {
                    autoPip = call.argument<Boolean>("enabled") ?: false
                    updateRatio(call.argument<Int>("width"), call.argument<Int>("height"))
                    applyPipParams()
                    result.success(null)
                }
                "setOrientation" -> {
                    // Flutter maps landscape-only to USER_LANDSCAPE, which on many
                    // phones ignores the sensor: use real sensor modes instead.
                    requestedOrientation = when (call.argument<String>("mode")) {
                        "landscape" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                        "portrait" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                        "sensor" -> ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
                        else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    }
                    result.success(null)
                }
                "setKeepScreenOn" -> {
                    if (call.argument<Boolean>("enabled") == true) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "setBrightness" -> {
                    val value = call.argument<Double>("value") ?: -1.0
                    val lp = window.attributes
                    lp.screenBrightness = if (value < 0) {
                        WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    } else {
                        value.toFloat().coerceIn(0.01f, 1f)
                    }
                    window.attributes = lp
                    result.success(null)
                }
                "getBrightness" -> {
                    val current = window.attributes.screenBrightness
                    result.success(
                        if (current >= 0) current.toDouble()
                        else Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255.0
                    )
                }
                "getCapabilities" -> result.success(capabilities())
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun updateRatio(width: Int?, height: Int?) {
        if (width == null || height == null || width <= 0 || height <= 0) return
        // Android rejects PiP ratios outside 1:2.39 .. 2.39:1.
        val ratio = width.toDouble() / height
        pipRatio = when {
            ratio > 2.39 -> Rational(239, 100)
            ratio < 1 / 2.39 -> Rational(100, 239)
            else -> Rational(width, height)
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(pipRatio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoPip)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun applyPipParams() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && pipSupported()) {
            setPictureInPictureParams(buildParams())
        }
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !pipSupported()) return false
        return try {
            enterPictureInPictureMode(buildParams())
        } catch (e: IllegalStateException) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPip && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    private fun capabilities(): Map<String, Any> {
        val hdr = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val display: Display? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                this.display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
            display?.hdrCapabilities?.supportedHdrTypes?.forEach { type ->
                when (type) {
                    Display.HdrCapabilities.HDR_TYPE_HDR10 -> hdr.add("HDR10")
                    Display.HdrCapabilities.HDR_TYPE_HLG -> hdr.add("HLG")
                    Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> hdr.add("Dolby Vision")
                    4 -> hdr.add("HDR10+")
                }
            }
        }
        val mimes = linkedMapOf(
            "HEVC / H.265" to "video/hevc",
            "AV1" to "video/av01",
            "VP9" to "video/x-vnd.on2.vp9",
            "Dolby Vision" to "video/dolby-vision",
            "Dolby Digital (AC-3)" to "audio/ac3",
            "Dolby Digital Plus (E-AC-3)" to "audio/eac3",
            "Dolby Atmos (E-AC-3 JOC)" to "audio/eac3-joc",
            "Dolby AC-4" to "audio/ac4",
            "DTS" to "audio/vnd.dts",
            "DTS-HD" to "audio/vnd.dts.hd",
        )
        val decoders = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.filter { !it.isEncoder }
        val codecs = mimes.mapValues { (_, mime) ->
            decoders.any { info -> info.supportedTypes.any { it.equals(mime, ignoreCase = true) } }
        }
        return mapOf("hdr" to hdr, "codecs" to codecs)
    }
}
