package app.companionfocus.companion_focus

import android.content.Intent
import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val sound = PackSoundPlayer()
    private var soundChannel: MethodChannel? = null
    private var feedback: TimerFeedbackHost? = null
    private var documents: BackupDocuments? = null
    private var ambience: FocusAmbiencePlayer? = null
    private var ambienceChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.companionfocus/boot_clock"
        ).setMethodCallHandler { call, result ->
            if (call.method != "sample") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bootCount = try {
                Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT, -1)
            } catch (_: SecurityException) {
                -1
            }
            result.success(
                mapOf("bootCount" to bootCount, "elapsedMs" to SystemClock.elapsedRealtime())
            )
        }
        soundChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.companionfocus/pack_sound"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "stop") {
                    sound.stop()
                    result.success(null)
                    return@setMethodCallHandler
                }
                if (call.method != "playWav") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                val volume = call.argument<Double>("volume")
                if (bytes == null || bytes.size !in 44..524288 ||
                    volume == null || volume !in 0.0..1.0
                ) {
                    result.error("invalid_sound", "Invalid pack sound", null)
                    return@setMethodCallHandler
                }
                try {
                    sound.play(bytes, volume.toFloat())
                    result.success(null)
                } catch (_: Exception) {
                    result.error("sound_unavailable", "Could not play the pack sound", null)
                }
            }
        }
        // Foreground completion feedback is its own channel, so a blocked
        // notification permission never suppresses an in-app alert.
        feedback = TimerFeedbackHost(this).also { host ->
            host.attach(flutterEngine.dartExecutor.binaryMessenger)
        }
        // Backup files use the Storage Access Framework and forward activity
        // results back to this host after Flutter has seen them.
        documents = BackupDocuments(this).also { host ->
            host.attach(flutterEngine.dartExecutor.binaryMessenger)
        }
        // Quiet Focus ambience is separate from pack sounds and timer feedback
        // and never requests audio focus or touches the alert channel.
        val player = FocusAmbiencePlayer(this) {
            ambienceChannel?.invokeMethod("headphonesDisconnected", null)
        }
        ambience = player
        ambienceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.companionfocus/focus_ambience"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val track = call.argument<String>("track")
                        val volume = call.argument<Double>("volume")
                        val level = volume?.takeIf { isValidVolume(it) }
                        if (track == null || track !in AMBIENCE_TRACKS || level == null) {
                            result.error("invalid_ambience", "Invalid ambience request", null)
                            return@setMethodCallHandler
                        }
                        player.start(track, level.toFloat())
                        result.success(null)
                    }
                    "setVolume" -> {
                        val level = call.argument<Double>("volume")
                            ?.takeIf { isValidVolume(it) }
                        if (level == null) {
                            result.error("invalid_ambience", "Invalid ambience volume", null)
                            return@setMethodCallHandler
                        }
                        player.setVolume(level.toFloat())
                        result.success(null)
                    }
                    "stop" -> {
                        player.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onStop() {
        feedback?.stop()
        ambience?.stop()
        sound.stop()
        super.onStop()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        documents?.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        soundChannel?.setMethodCallHandler(null)
        soundChannel = null
        sound.stop()
        feedback?.detach()
        feedback = null
        documents?.detach()
        documents = null
        ambienceChannel?.setMethodCallHandler(null)
        ambienceChannel = null
        ambience?.release()
        ambience = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun isValidVolume(volume: Double?): Boolean =
        volume != null && volume.isFinite() && volume >= 0.0 && volume <= 1.0

    private companion object {
        val AMBIENCE_TRACKS = setOf("rain", "wind")
    }
}
