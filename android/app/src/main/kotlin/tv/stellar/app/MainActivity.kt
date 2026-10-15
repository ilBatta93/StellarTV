package tv.stellar.app

import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.MediaCodecList
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.util.Rational
import android.view.Display
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var autoPip = false
    private var pipRatio = Rational(16, 9)

    // TV text input: true while a Flutter text field is being edited.
    private var textEditing = false
    private var imeHealBudget = 0
    private var lastImeHeal = 0L
    private var editorProxy: View? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (isTelevision()) installTextEditorProxy()
    }

    // Many Google TV / Android TV devices (low-RAM overlay, e.g. Chromecast
    // with Google TV, TCL/Philips TVs) enable config_preventImeStartupUnlessTextEditor:
    // the system refuses to bind the keyboard to a view that does not report
    // onCheckIsTextEditor(). FlutterView never reports it, so the keyboard is
    // drawn but not connected to the app: D-Pad keys reach Flutter instead of
    // the keyboard, focus moves and the keyboard closes (flutter/flutter#177360).
    // This 1x1 view lives inside FlutterView, holds Android focus in its place,
    // reports itself as a text editor while a field is edited and hands the
    // system Flutter's own InputConnection. Keys still go through FlutterView.
    private inner class TextEditorProxyView(context: Context, private val flutterView: View) : View(context) {
        init {
            isFocusable = true
            isFocusableInTouchMode = true
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        override fun onCheckIsTextEditor(): Boolean = textEditing

        override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? =
            flutterView.onCreateInputConnection(outAttrs)

        override fun checkInputConnectionProxy(view: View): Boolean = view === flutterView
    }

    private fun flutterView(): View? = findViewById(FlutterActivity.FLUTTER_VIEW_ID)

    private fun installTextEditorProxy() {
        val fv = flutterView() as? ViewGroup ?: return
        fv.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
        val proxy = TextEditorProxyView(this, fv)
        fv.addView(proxy, FrameLayout.LayoutParams(1, 1))
        editorProxy = proxy
        if (fv.isFocused) proxy.requestFocus()
    }

    private fun isImeVisible(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        return window.decorView.rootWindowInsets?.isVisible(WindowInsets.Type.ime()) == true
    }

    private fun setTextEditing(value: Boolean) {
        val old = textEditing
        textEditing = value
        if (value && !old) {
            imeHealBudget = 2
            val proxy = editorProxy
            if (proxy != null && !proxy.isFocused) proxy.requestFocus()
        }
    }

    // A healthy keyboard consumes D-Pad keys before the app. One arriving here
    // while the keyboard is visible means it is not connected: reconnect it
    // and swallow the key so the focus cannot move behind the keyboard.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (textEditing && imeHealBudget > 0 && isImeVisible()) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_DPAD_UP,
                KeyEvent.KEYCODE_DPAD_DOWN,
                KeyEvent.KEYCODE_DPAD_LEFT,
                KeyEvent.KEYCODE_DPAD_RIGHT,
                KeyEvent.KEYCODE_DPAD_CENTER -> {
                    if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                        val now = SystemClock.uptimeMillis()
                        if (now - lastImeHeal >= 1000L) {
                            lastImeHeal = now
                            imeHealBudget--
                            flutterView()?.let {
                                val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                                imm.restartInput(it)
                            }
                        }
                    }
                    return true
                }
            }
        }
        // A native video surface (ExoPlayer on TV) must never keep the
        // remote keys away from the app: give the focus back to Flutter.
        if (!textEditing && event.action == KeyEvent.ACTION_DOWN) {
            val fv = flutterView()
            val focused = currentFocus
            if (fv != null && focused != null && !isInside(focused, fv)) {
                fv.requestFocus()
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun isInside(view: View, ancestor: View): Boolean {
        var current: View? = view
        while (current != null) {
            if (current === ancestor) return true
            current = current.parent as? View
        }
        return false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stellartv/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTv" -> result.success(isTelevision())
                    "isFireTv" -> result.success(isTelevision() &&
                        (Build.MANUFACTURER.equals("Amazon", ignoreCase = true) ||
                         packageManager.hasSystemFeature("amazon.hardware.fire_tv")))
                    "moveToBack" -> result.success(moveTaskToBack(true))
                    "showKeyboard" -> result.success(showSoftKeyboard())
                    "setTextEditing" -> {
                        setTextEditing(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
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

    private fun isTelevision(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        val televisionMode = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        val leanback = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        val television = packageManager.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
        return televisionMode || leanback || television
    }

    /** TV fallback when the Flutter IME request is ignored by the system. */
    private fun showSoftKeyboard(): Boolean {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        val view = currentFocus ?: window.decorView
        if (!view.hasFocus()) view.requestFocus()
        if (imm.showSoftInput(view, 0)) return true
        @Suppress("DEPRECATION")
        return imm.showSoftInput(view, InputMethodManager.SHOW_FORCED)
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
