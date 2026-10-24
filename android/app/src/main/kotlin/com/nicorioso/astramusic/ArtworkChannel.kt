package com.nicorioso.astramusic

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Size
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** Carga miniaturas de MediaStore fuera del hilo de interfaz. */
class ArtworkChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "loadThumbnail") {
            result.notImplemented()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(null)
            return
        }
        val uri = call.argument<String>("uri")
        val size = call.argument<Int>("size")
        if (uri == null || size == null || size <= 0) {
            result.error("invalid_arguments", "URI y tamaño son requeridos.", null)
            return
        }
        executor.execute {
            val bytes = try {
                val bitmap = context.contentResolver.loadThumbnail(
                    Uri.parse(uri),
                    Size(size, size),
                    null,
                )
                ByteArrayOutputStream().use { output ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, output)
                    output.toByteArray()
                }
            } catch (_: Exception) {
                null
            }
            mainHandler.post { result.success(bytes) }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private companion object {
        const val CHANNEL_NAME = "com.nicorioso.astramusic/artwork"
        const val JPEG_QUALITY = 90
    }
}
