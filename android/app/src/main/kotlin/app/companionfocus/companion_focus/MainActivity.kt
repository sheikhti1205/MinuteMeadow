package app.companionfocus.companion_focus

import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
    }
}
