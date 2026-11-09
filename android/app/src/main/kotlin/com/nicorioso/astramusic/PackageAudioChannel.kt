package com.nicorioso.astramusic

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Copia audio de MediaStore a la carpeta temporal de exportación. */
class PackageAudioChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.nicorioso.astramusic/package_audio")
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "copyAudio") {
            result.notImplemented()
            return
        }
        val uriValue = call.argument<String>("uri")
        val destination = call.argument<String>("destination")
        val stem = call.argument<String>("stem")
        if (uriValue == null || destination == null || stem == null ||
            !stem.matches(Regex("[0-9]{5}"))) {
            result.error("invalid_arguments", "URI, carpeta y nombre son requeridos.", null)
            return
        }
        executor.execute {
            var output: File? = null
            try {
                val uri = Uri.parse(uriValue)
                require(uri.scheme == "content") { "Solo se admite audio de MediaStore." }
                val displayName = context.contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
                val extensionFromName = displayName?.substringAfterLast('.', "")
                    ?.takeIf { it.matches(Regex("[a-zA-Z0-9]+")) }
                val extension = extensionFromName
                    ?: MimeTypeMap.getSingleton().getExtensionFromMimeType(
                        context.contentResolver.getType(uri),
                    )?.takeIf { it.matches(Regex("[a-zA-Z0-9]+")) }
                    ?: throw IllegalArgumentException("No se conoce el formato del audio.")
                val filename = "$stem.${extension.lowercase()}"
                val target = File(destination, filename)
                output = target
                context.contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { stream -> input.copyTo(stream) }
                } ?: throw IllegalArgumentException("No se pudo abrir el audio.")
                mainHandler.post { result.success(filename) }
            } catch (error: Exception) {
                output?.delete()
                mainHandler.post {
                    result.error("audio_copy_failed", error.message ?: "No se pudo copiar el audio.", null)
                }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }
}
