package tv.stellar.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.StringReader
import java.util.concurrent.Executors

/// Personal VPN on the `stellartv/vpn` channel: one WireGuard tunnel run by the
/// wireguard-android library inside the app process. The configuration (with
/// its private key) only passes through memory and is never logged.
class VpnController(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private var pending: Pending? = null

    private class Pending(val config: String, val appOnly: Boolean, val result: MethodChannel.Result)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> {
                val config = call.argument<String>("config")
                if (config == null) {
                    result.error("config", null, null)
                    return
                }
                val appOnly = call.argument<Boolean>("appOnly") ?: true
                val interactive = call.argument<Boolean>("interactive") ?: true
                val consent = try {
                    VpnService.prepare(activity)
                } catch (_: Exception) {
                    null
                }
                if (consent == null) {
                    start(config, appOnly, result)
                } else if (!interactive) {
                    result.error("permission", null, null)
                } else {
                    pending?.result?.error("denied", null, null)
                    pending = Pending(config, appOnly, result)
                    try {
                        activity.startActivityForResult(consent, REQUEST)
                    } catch (_: Exception) {
                        pending = null
                        result.error("permission", null, null)
                    }
                }
            }
            "disconnect" -> worker.execute {
                try {
                    backend(activity).setState(tunnel, Tunnel.State.DOWN, null)
                } catch (_: Exception) {
                }
                main.post { result.success(null) }
            }
            "stats" -> worker.execute {
                val out = try {
                    val b = backend(activity)
                    if (b.getState(tunnel) != Tunnel.State.UP) null else {
                        val s = b.getStatistics(tunnel)
                        var handshake = 0L
                        for (key in s.peers()) {
                            val peer = s.peer(key) ?: continue
                            handshake = maxOf(handshake, peer.latestHandshakeEpochMillis())
                        }
                        mapOf("handshake" to handshake, "rx" to s.totalRx(), "tx" to s.totalTx())
                    }
                } catch (_: Exception) {
                    null
                }
                main.post { result.success(out) }
            }
            else -> result.notImplemented()
        }
    }

    /// Called by MainActivity; true when the request was the VPN consent.
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST) return false
        val p = pending ?: return true
        pending = null
        if (resultCode == Activity.RESULT_OK) start(p.config, p.appOnly, p.result)
        else p.result.error("denied", null, null)
        return true
    }

    private fun start(text: String, appOnly: Boolean, result: MethodChannel.Result) {
        worker.execute {
            val error: String? = try {
                val config = parse(text, appOnly)
                val b = backend(activity)
                // Replacing a running tunnel: bring it down first so the new
                // server and keys are applied cleanly.
                if (b.getState(tunnel) == Tunnel.State.UP) {
                    b.setState(tunnel, Tunnel.State.DOWN, null)
                }
                b.setState(tunnel, Tunnel.State.UP, config)
                null
            } catch (e: com.wireguard.config.BadConfigException) {
                "config"
            } catch (e: com.wireguard.android.backend.BackendException) {
                if (e.reason == com.wireguard.android.backend.BackendException.Reason.VPN_NOT_AUTHORIZED)
                    "permission"
                else if (e.reason == com.wireguard.android.backend.BackendException.Reason.UNABLE_TO_START_VPN)
                    "always_on"
                else "backend"
            } catch (e: Exception) {
                "backend"
            }
            main.post {
                if (error == null) result.success(null) else result.error(error, null, null)
            }
        }
    }

    /// "Only StellarTV": the tunnel carries this app's traffic only, so the
    /// rest of the TV keeps its normal connection.
    private fun parse(text: String, appOnly: Boolean): Config {
        val lines = text.lines()
            .filterNot { it.trim().lowercase().startsWith("includedapplications") }
            .toMutableList()
        if (appOnly) {
            val at = lines.indexOfFirst { it.trim().equals("[Interface]", ignoreCase = true) }
            if (at >= 0) lines.add(at + 1, "IncludedApplications = ${activity.packageName}")
        }
        return Config.parse(BufferedReader(StringReader(lines.joinToString("\n"))))
    }

    companion object {
        private const val REQUEST = 7343
        private val worker = Executors.newSingleThreadExecutor()
        private var shared: GoBackend? = null

        // One backend for the whole process: it outlives activity restarts.
        @Synchronized
        private fun backend(context: Context): GoBackend =
            shared ?: GoBackend(context.applicationContext).also { shared = it }

        private val tunnel = object : Tunnel {
            override fun getName() = "stellartv"
            override fun onStateChange(newState: Tunnel.State) {}
        }
    }
}
