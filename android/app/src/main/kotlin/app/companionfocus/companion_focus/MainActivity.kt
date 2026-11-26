package app.companionfocus.companion_focus

import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val sound = PackSoundPlayer()
    private var soundChannel: MethodChannel? = null

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
    }

    override fun onStop() {
        sound.stop()
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        soundChannel?.setMethodCallHandler(null)
        soundChannel = null
        sound.stop()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
