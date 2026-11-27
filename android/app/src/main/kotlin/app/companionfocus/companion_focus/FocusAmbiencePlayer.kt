package app.companionfocus.companion_focus

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import java.util.Random
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import kotlin.math.PI
import kotlin.math.sin

/**
 * Quiet, procedurally generated Focus ambience for the Android runner.
 *
 * The player sits on its own method channel, separate from pack sounds and
 * timer feedback. It never requests audio focus and never reads or changes the
 * completion notification channel, so other music keeps playing and alerts are
 * neither replaced nor muted.
 *
 * Samples are synthesized on the device on one worker thread; no audio assets
 * and no extra dependencies are used. [AudioManager.ACTION_AUDIO_BECOMING_NOISY]
 * is the protected system broadcast the platform sends when the active output
 * moves to a speaker, so the loop stops as soon as the user's headphones are
 * unplugged while it is audible.
 *
 * Every operation is idempotent: a start after [release] does nothing, repeated
 * stops are no-ops, and [release] may be called twice. Nothing here reports
 * playback; only [start] actually starts a track.
 *
 * @param context any [Context]; only the application context is retained.
 * @param onHeadphonesDisconnected invoked on the main thread after the platform
 *   signals that output moved to a speaker, so the bridge can tell Dart to stop
 *   and stay silent for the rest of the visit.
 */
internal class FocusAmbiencePlayer(
    context: Context,
    private val onHeadphonesDisconnected: () -> Unit = {},
) {
    private val appContext: Context = context.applicationContext ?: context

    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "focus-ambience").apply { isDaemon = true }
    }

    private var track: AudioTrack? = null
    private var currentTrack: String? = null

    @Volatile
    private var released = false

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != AudioManager.ACTION_AUDIO_BECOMING_NOISY) return
            stop()
            onHeadphonesDisconnected()
        }
    }

    init {
        registerNoisyReceiver()
    }

    /** Starts or replaces the loop. A zero or unknown request stays silent. */
    fun start(trackId: String, volume: Float) {
        val requested = when (trackId) {
            "rain" -> Track.RAIN
            "wind" -> Track.WIND
            else -> return
        }
        val level = volume.coerceIn(0f, MAX_VOLUME)
        if (level <= 0f) {
            stop()
            return
        }
        execute {
            // A release can land after this task was accepted; never start a
            // track on a player that is already being torn down.
            if (released) return@execute
            if (currentTrack != requested.id || track == null) {
                releaseTrack()
                val samples = generate(requested)
                val next = createTrack(samples, level) ?: return@execute
                track = next
                currentTrack = requested.id
                try {
                    next.play()
                } catch (_: IllegalStateException) {
                    releaseTrack()
                }
            } else {
                try {
                    track?.setVolume(level)
                } catch (_: IllegalStateException) {
                    releaseTrack()
                }
            }
        }
    }

    /** Adjusts the running loop without rebuilding it. */
    fun setVolume(volume: Float) {
        val level = volume.coerceIn(0f, MAX_VOLUME)
        execute {
            if (level <= 0f) {
                releaseTrack()
                return@execute
            }
            try {
                track?.setVolume(level)
            } catch (_: IllegalStateException) {
                releaseTrack()
            }
        }
    }

    /** Stops and releases the loop. Safe to call repeatedly. */
    fun stop() {
        execute { releaseTrack() }
    }

    /** Unregisters routing callbacks and releases the worker. Idempotent. */
    fun release() {
        if (released) return
        try {
            appContext.unregisterReceiver(noisyReceiver)
        } catch (_: Exception) {
            // The receiver was never registered.
        }
        // Queue the final release before the executor is closed; shutdown still
        // runs the tasks that were already accepted.
        stop()
        released = true
        worker.shutdown()
    }

    private fun execute(block: () -> Unit) {
        if (released) return
        try {
            worker.execute { block() }
        } catch (_: RejectedExecutionException) {
            // The runner has already released the player.
        }
    }

    private fun releaseTrack() {
        val current = track
        track = null
        currentTrack = null
        if (current == null) return
        try {
            current.stop()
        } catch (_: IllegalStateException) {
            // The track was already stopped.
        }
        current.release()
    }

    private fun registerNoisyReceiver() {
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // A protected system broadcast is still delivered to a receiver
                // that is not exported to other apps.
                appContext.registerReceiver(
                    noisyReceiver,
                    filter,
                    Context.RECEIVER_NOT_EXPORTED
                )
            } else {
                appContext.registerReceiver(noisyReceiver, filter)
            }
        } catch (_: Exception) {
            // A receiver failure must not block the rest of the runner.
        }
    }

    private fun createTrack(samples: ShortArray, volume: Float): AudioTrack? {
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
            .build()
        val created = try {
            AudioTrack(
                attributes,
                format,
                samples.size * BYTES_PER_SAMPLE,
                AudioTrack.MODE_STATIC,
                AudioManager.AUDIO_SESSION_ID_GENERATE
            )
        } catch (_: Exception) {
            return null
        }
        if (created.state != AudioTrack.STATE_INITIALIZED) {
            created.release()
            return null
        }
        val written = try {
            created.write(samples, 0, samples.size)
        } catch (_: Exception) {
            -1
        }
        if (written < 0) {
            created.release()
            return null
        }
        val ready = try {
            created.setLoopPoints(0, samples.size, -1)
            created.setVolume(volume)
            true
        } catch (_: Exception) {
            false
        }
        if (!ready) {
            created.release()
            return null
        }
        return created
    }

    /**
     * Renders a seamless loop. The extra tail is cross-faded into the head so
     * the repeat point has no click, which also keeps the loop quiet.
     */
    private fun generate(kind: Track): ShortArray {
        val loopSamples = SAMPLE_RATE * LOOP_SECONDS
        val fade = SAMPLE_RATE / 4
        val buffer = FloatArray(loopSamples + fade)
        val random = Random(if (kind == Track.RAIN) 0x5EED01L else 0x5EED02L)
        when (kind) {
            Track.RAIN -> fillRain(buffer, random)
            Track.WIND -> fillWind(buffer, random)
        }
        val output = ShortArray(loopSamples)
        for (index in output.indices) {
            val sample = if (index < fade) {
                val mix = index.toFloat() / fade
                buffer[index] * mix + buffer[loopSamples + index] * (1f - mix)
            } else {
                buffer[index]
            }
            output[index] =
                (sample.coerceIn(-1f, 1f) * Short.MAX_VALUE).toInt().toShort()
        }
        return output
    }

    private fun fillRain(buffer: FloatArray, random: Random) {
        var hiss = 0f
        var wash = 0f
        var drop = 0f
        for (index in buffer.indices) {
            val white = random.nextFloat() * 2f - 1f
            hiss = hiss * 0.62f + white * 0.38f
            wash = wash * 0.996f + white * 0.004f
            if (random.nextFloat() < 0.0006f) drop = 0.5f
            drop *= 0.986f
            val droplet =
                drop * sin(2.0 * PI * 1700.0 * index / SAMPLE_RATE).toFloat()
            buffer[index] =
                (hiss * 0.18f + wash * 1.4f + droplet * 0.35f) * ENVELOPE
        }
    }

    private fun fillWind(buffer: FloatArray, random: Random) {
        var low = 0f
        var body = 0f
        var phase = 0.0
        for (index in buffer.indices) {
            val white = random.nextFloat() * 2f - 1f
            low = low * 0.997f + white * 0.003f
            body = body * 0.94f + white * 0.06f
            phase += 2.0 * PI / SAMPLE_RATE
            val gust = 0.45f + 0.55f * sin(phase * 0.06).toFloat()
            buffer[index] =
                (low * 1.8f + body * 0.05f) * gust * ENVELOPE
        }
    }

    private enum class Track(val id: String) {
        RAIN("rain"),
        WIND("wind"),
    }

    private companion object {
        const val SAMPLE_RATE = 22050
        const val LOOP_SECONDS = 8
        const val BYTES_PER_SAMPLE = 2

        // The synthesized bed is scaled well below full scale, so a full
        // slider setting is still a background level rather than a foreground
        // track that could compete with alerts or music.
        const val ENVELOPE = 0.45f
        const val MAX_VOLUME = 1f
    }
}
