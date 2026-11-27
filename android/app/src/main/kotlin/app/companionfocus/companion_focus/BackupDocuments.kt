package app.companionfocus.companion_focus

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Document-backed file transport for approved portable backups.
 *
 * The host is attached to `app.companionfocus/backup_documents` by the runner.
 * It uses the Storage Access Framework, so the app requests no broad storage
 * permission and Dart never receives a picked path: a chosen document is read
 * into memory under a fixed cap and a save writes only to the URI the user just
 * chose. A cancelled picker is reported as `success(null)` or
 * `success(false)`, never as an error, so the caller can keep copy/paste quiet.
 *
 * Threading: [attach], [detach], [onActivityResult] and the channel handler run
 * on the main thread and only launch or receive the picker. Provider metadata,
 * the bounded read and the write run on one serial daemon worker, and every
 * [MethodChannel.Result] reply is posted back to the main thread. A single
 * [Request] stays pending from launch until its I/O has finished, so a second
 * request is rejected with `busy` for the whole logical lifetime.
 *
 * Lifecycle: [detach] abandons the pending request, answers it with `cancelled`
 * on the old engine and lets any already-started worker finish without replying
 * again. A late completion can never clear a request from a later attach.
 *
 * Irreversible save: the provider truncates the chosen document when it is
 * opened for writing. A save that fails, or an engine that is detached after
 * the user chose the destination, cannot restore the previous contents; the
 * write may also complete after the reply was reported as cancelled.
 *
 * The runner must forward activity results to [onActivityResult] after
 * Flutter's own forwarding. [MAX_BYTES] matches `maxBackupFileBytes` in the
 * Dart transport.
 */
internal class BackupDocuments(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var pending: Request? = null
    private var worker: ExecutorService? = null

    fun attach(messenger: BinaryMessenger) {
        detach()
        val next = MethodChannel(messenger, CHANNEL)
        next.setMethodCallHandler { call, result ->
            when (call.method) {
                "save" -> save(call, result)
                "pick" -> pick(result)
                else -> result.notImplemented()
            }
        }
        channel = next
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        val request = pending
        pending = null
        if (request != null && request.replied.compareAndSet(false, true)) {
            try {
                request.result.error("cancelled", "The file request ended.", null)
            } catch (_: Exception) {
                // The old engine is already gone.
            }
        }
        // Let an in-flight read or write close its stream. Its reply is dropped
        // by the replied flag above, and the next request gets a fresh worker.
        worker?.shutdown()
        worker = null
    }

    /**
     * Returns true when the result belongs to this host and was consumed.
     *
     * Must be called on the main thread, after the runner has forwarded the
     * result to the Flutter delegate. Unknown request codes and results with no
     * pending request are ignored.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val request = pending ?: return false
        val expected = when (requestCode) {
            REQUEST_OPEN -> Kind.OPEN
            REQUEST_CREATE -> Kind.CREATE
            else -> return false
        }
        if (request.kind != expected) return false
        if (resultCode != Activity.RESULT_OK) {
            finish(request) {
                if (request.kind == Kind.OPEN) it.success(null) else it.success(false)
            }
            return true
        }
        val uri = data?.data
        if (uri == null) {
            val code = if (request.kind == Kind.OPEN) "read_failed" else "write_failed"
            finish(request) {
                it.error(code, "The document provider returned no document.", null)
            }
            return true
        }
        // Keep the request pending through I/O: this is still one logical
        // request and a second one stays busy until the worker replies.
        val bytes = request.bytes
        try {
            worker().execute {
                when (request.kind) {
                    Kind.OPEN -> read(request, uri)
                    Kind.CREATE -> write(request, uri, bytes ?: ByteArray(0))
                }
            }
        } catch (_: Exception) {
            val code = if (request.kind == Kind.OPEN) "read_failed" else "write_failed"
            finish(request) {
                it.error(code, "The file request could not start.", null)
            }
        }
        return true
    }

    private fun save(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null || bytes.isEmpty()) {
            result.error("write_failed", "The backup is empty.", null)
            return
        }
        if (bytes.size > MAX_BYTES) {
            result.error("too_large", "The backup is too large.", null)
            return
        }
        if (pending != null) {
            result.error("busy", "Another file request is open.", null)
            return
        }
        val request = Request(Kind.CREATE, result, bytes)
        pending = request
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, safeName(call.argument<String>("fileName")))
        }
        launch(intent, REQUEST_CREATE, request, "write_failed")
    }

    private fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "Another file request is open.", null)
            return
        }
        val request = Request(Kind.OPEN, result, null)
        pending = request
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, MIME_EXTRA)
        }
        launch(intent, REQUEST_OPEN, request, "read_failed")
    }

    private fun launch(
        intent: Intent,
        requestCode: Int,
        request: Request,
        failureCode: String,
    ) {
        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (_: ActivityNotFoundException) {
            finish(request) {
                it.error(failureCode, "No document provider is available.", null)
            }
        } catch (_: SecurityException) {
            finish(request) {
                it.error(failureCode, "The document provider rejected the request.", null)
            }
        }
    }

    private fun read(request: Request, uri: Uri) {
        val resolver = activity.contentResolver
        try {
            if (!isBackup(resolver, uri)) {
                replyUnsupported(request)
                return
            }
            val descriptor = resolver.openAssetFileDescriptor(uri, "r")
                ?: throw IOException("The provider returned no document.")
            descriptor.use { file ->
                val declared = file.length
                if (declared > MAX_BYTES) {
                    replyTooLarge(request)
                    return
                }
                val output = ByteArrayOutputStream()
                val input = file.createInputStream()
                input.use { stream ->
                    val buffer = ByteArray(BUFFER_BYTES)
                    var total = 0
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > MAX_BYTES) {
                            replyTooLarge(request)
                            return
                        }
                        output.write(buffer, 0, count)
                    }
                }
                val bytes = output.toByteArray()
                reply(request) { it.success(bytes) }
            }
        } catch (_: SecurityException) {
            replyReadFailure(request)
        } catch (_: IOException) {
            replyReadFailure(request)
        } catch (_: Exception) {
            replyReadFailure(request)
        }
    }

    private fun write(request: Request, uri: Uri, bytes: ByteArray) {
        try {
            val output = activity.contentResolver.openOutputStream(uri, "wt")
                ?: throw IOException("The provider returned no stream.")
            output.use {
                it.write(bytes)
                it.flush()
            }
            reply(request) { it.success(true) }
        } catch (_: SecurityException) {
            replyWriteFailure(request)
        } catch (_: IOException) {
            replyWriteFailure(request)
        } catch (_: Exception) {
            replyWriteFailure(request)
        }
    }

    private fun isBackup(resolver: ContentResolver, uri: Uri): Boolean {
        val mime = try {
            resolver.getType(uri)
                ?.substringBefore(';')
                ?.trim()
                ?.lowercase(Locale.ROOT)
        } catch (_: Exception) {
            null
        }
        if (mime != null && mime in MIME_TYPES) return true
        return displayName(resolver, uri)?.endsWith(".json", ignoreCase = true) == true
    }

    private fun displayName(resolver: ContentResolver, uri: Uri): String? = try {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
    } catch (_: Exception) {
        null
    }

    private fun reply(request: Request, block: (MethodChannel.Result) -> Unit) {
        main.post { finish(request, block) }
    }

    /**
     * Delivers the only reply for [request] on the main thread.
     *
     * The replied flag makes detach and a late worker completion mutually
     * exclusive, and the identity check keeps a late completion from clearing a
     * request opened after a later attach.
     */
    private fun finish(request: Request, block: (MethodChannel.Result) -> Unit) {
        if (!request.replied.compareAndSet(false, true)) return
        if (pending === request) pending = null
        try {
            block(request.result)
        } catch (_: Exception) {
            // The engine is already gone and cannot receive the reply.
        }
    }

    private fun replyTooLarge(request: Request) {
        reply(request) { it.error("too_large", "The selected document is too large.", null) }
    }

    private fun replyUnsupported(request: Request) {
        reply(request) { it.error("unsupported_type", "The selected document is not a backup.", null) }
    }

    private fun replyReadFailure(request: Request) {
        reply(request) { it.error("read_failed", "The selected document could not be read.", null) }
    }

    private fun replyWriteFailure(request: Request) {
        reply(request) { it.error("write_failed", "The selected document could not be written.", null) }
    }

    private fun safeName(raw: String?): String {
        val cleaned = raw.orEmpty()
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .filterNot { it.isISOControl() || it in FORBIDDEN_NAME_CHARS }
            .trim()
        val name = cleaned.ifEmpty { DEFAULT_NAME }
        return if (name.endsWith(".json", ignoreCase = true)) name else "$name.json"
    }

    private fun worker(): ExecutorService {
        val current = worker
        if (current != null) return current
        val created = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, WORKER_NAME).apply { isDaemon = true }
        }
        worker = created
        return created
    }

    private enum class Kind { OPEN, CREATE }

    private class Request(
        val kind: Kind,
        val result: MethodChannel.Result,
        val bytes: ByteArray?,
    ) {
        val replied = AtomicBoolean(false)
    }

    companion object {
        const val CHANNEL = "app.companionfocus/backup_documents"
        const val REQUEST_OPEN = 0xB0C1
        const val REQUEST_CREATE = 0xB0C2
        const val MAX_BYTES = 16 * 1024 * 1024

        private const val BUFFER_BYTES = 8 * 1024
        private const val DEFAULT_NAME = "minutemeadow-backup.json"
        private const val WORKER_NAME = "minutemeadow-backup-io"

        private val MIME_EXTRA = arrayOf(
            "application/json",
            "text/json",
            "text/plain",
            "application/octet-stream"
        )
        private val MIME_TYPES = MIME_EXTRA.toSet()
        private val FORBIDDEN_NAME_CHARS =
            charArrayOf(':', '*', '?', '"', '<', '>', '|')
    }
}
