package app.companionfocus.companion_focus

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground timer feedback and notification-settings navigation.
 *
 * The host is attached to `app.companionfocus/timer_feedback` by the runner.
 * It plays the same app-owned chime the audible notification channels use when
 * the named channel does not exist yet, so a blocked notification permission
 * cannot suppress an in-app completion. When the channel does exist, its
 * current sound is used, which keeps a foreground alert consistent with the
 * notification and lets the user's channel sound and vibration choices win.
 *
 * Sound and vibration are separate requests. Vibration never reads touch
 * haptics settings, and this host never requests notification policy access or
 * bypasses Do Not Disturb: sound and vibration are suppressed unless the
 * interruption filter is fully off, the ringer mode is normal, and the
 * notification stream is audible.
 */
internal class TimerFeedbackHost(private val context: Context) {
    private var channel: MethodChannel? = null
    private var ringtone: Ringtone? = null

    private val appContext: Context
        get() = context.applicationContext ?: context

    private val notificationManager: NotificationManager
        get() = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private val audioManager: AudioManager
        get() = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    /**
     * The app-owned chime in `res/raw/timer_completion_chime.wav`.
     *
     * The numeric resource ID is used so a missing file fails at build time
     * instead of falling back to the system tone at runtime.
     */
    private val chimeUri: Uri
        get() = Uri.parse("android.resource://${appContext.packageName}/${R.raw.timer_completion_chime}")

    /**
     * Registers the method channel. Safe to call again after a detach.
     */
    fun attach(messenger: BinaryMessenger) {
        detach()
        val next = MethodChannel(messenger, CHANNEL)
        next.setMethodCallHandler { call, result ->
            when (call.method) {
                "playCompletion" -> {
                    try {
                        val sound = call.argument<Boolean>("sound") ?: false
                        val vibration = call.argument<Boolean>("vibration") ?: false
                        val channelId = call.argument<String>("channelId")
                        playCompletion(sound, vibration, channelId)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }

                "openNotificationSettings" -> result.success(openNotificationSettings())

                "stop" -> {
                    stop()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
        channel = next
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        stop()
    }

    fun stop() {
        val current = ringtone
        ringtone = null
        current?.stop()
        vibrator()?.cancel()
    }

    private fun playCompletion(sound: Boolean, vibration: Boolean, channelId: String?) {
        // A second completion must not talk over the first.
        val current = ringtone
        ringtone = null
        current?.stop()

        if (sound) playSound(channelId)
        if (vibration) vibrate(channelId)
    }

    private fun playSound(channelId: String?) {
        val channel = notificationChannel(channelId)
        val uri: Uri? = when {
            // The app-owned channel has not been created yet, or the user
            // blocked the app's notifications. Play the app's own chime; it is
            // not a notification and needs no POST_NOTIFICATIONS grant.
            channel == null -> chimeUri
            channel.importance < NotificationManager.IMPORTANCE_DEFAULT -> null
            // A null sound means the user silenced this channel. Respect it.
            else -> channel.sound
        } ?: return
        if (!allowsSound()) return
        try {
            val next = RingtoneManager.getRingtone(appContext, uri) ?: return
            next.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            ringtone = next
            next.play()
        } catch (_: Exception) {
            // No notification tone, or audio is temporarily unavailable.
        }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(channelId: String?) {
        val channel = notificationChannel(channelId)
        if (channel != null) {
            if (channel.importance < NotificationManager.IMPORTANCE_DEFAULT) return
            if (!channel.enableVibration) return
        }
        if (!allowsVibration()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val vibrateOn = try {
                Settings.System.getInt(
                    appContext.contentResolver,
                    Settings.System.VIBRATE_ON,
                    1
                )
            } catch (_: Exception) {
                1
            }
            if (vibrateOn == 0) return
        }
        val device = vibrator() ?: return
        if (!device.hasVibrator()) return
        val pattern = longArrayOf(0, 180, 120, 220)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                device.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                device.vibrate(pattern, -1)
            }
        } catch (_: Exception) {
            // Vibration may be disabled by the device policy.
        }
    }

    private fun notificationChannel(channelId: String?): NotificationChannel? {
        if (channelId == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        return notificationManager.getNotificationChannel(channelId)
    }

    private fun allowsSound(): Boolean {
        // The ringer mode and the notification stream are the user's device
        // mute choices. A raw Ringtone is not filtered by the notification
        // policy the way a posted notification is, so check both here.
        if (audioManager.ringerMode != AudioManager.RINGER_MODE_NORMAL) return false
        if (audioManager.getStreamVolume(AudioManager.STREAM_NOTIFICATION) <= 0) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (audioManager.isStreamMute(AudioManager.STREAM_NOTIFICATION)) return false
            if (notificationManager.currentInterruptionFilter !=
                NotificationManager.INTERRUPTION_FILTER_ALL
            ) {
                return false
            }
        }
        return true
    }

    private fun allowsVibration(): Boolean {
        // Direct vibration is not filtered by the notification policy, so only
        // run it while the user's device would normally vibrate at all.
        if (audioManager.ringerMode == AudioManager.RINGER_MODE_SILENT) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (notificationManager.currentInterruptionFilter !=
                NotificationManager.INTERRUPTION_FILTER_ALL
            ) {
                return false
            }
        }
        return true
    }

    @Suppress("DEPRECATION")
    private fun vibrator(): Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        appContext.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        appContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    fun openNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, appContext.packageName)
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${appContext.packageName}")
            )
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            appContext.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    companion object {
        const val CHANNEL = "app.companionfocus/timer_feedback"
    }
}
