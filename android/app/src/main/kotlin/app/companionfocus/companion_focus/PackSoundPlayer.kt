package app.companionfocus.companion_focus

import android.media.AudioAttributes
import android.media.MediaDataSource
import android.media.MediaPlayer

internal class PackSoundPlayer {
    private var player: MediaPlayer? = null

    fun play(bytes: ByteArray, volume: Float) {
        stop()
        val next = MediaPlayer()
        player = next
        try {
            next.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            next.setDataSource(PackSoundSource(bytes))
            next.setVolume(volume, volume)
            next.setOnPreparedListener { ready ->
                if (player === ready) {
                    try {
                        ready.start()
                    } catch (_: IllegalStateException) {
                        stop()
                    }
                }
            }
            next.setOnCompletionListener { finished ->
                if (player === finished) stop()
            }
            next.setOnErrorListener { failed, _, _ ->
                if (player === failed) stop()
                true
            }
            next.prepareAsync()
        } catch (error: Exception) {
            stop()
            throw error
        }
    }

    fun stop() {
        val current = player
        player = null
        current?.release()
    }
}

private class PackSoundSource(private val bytes: ByteArray) : MediaDataSource() {
    override fun getSize(): Long = bytes.size.toLong()

    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        if (position < 0 || position >= bytes.size.toLong()) return -1
        val start = position.toInt()
        val count = minOf(size, bytes.size - start)
        bytes.copyInto(buffer, offset, start, start + count)
        return count
    }

    override fun close() = Unit
}
