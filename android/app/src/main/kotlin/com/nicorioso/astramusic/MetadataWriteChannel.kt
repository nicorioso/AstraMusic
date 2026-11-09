package com.nicorioso.astramusic

import android.Manifest
import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Copia el audio para editarlo en Dart y reemplaza el elemento de MediaStore con permiso del usuario. */
class MetadataWriteChannel(
    private val activity: AudioServiceActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.nicorioso.astramusic/metadata_write")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var prepared: Prepared? = null
    private var pendingResult: MethodChannel.Result? = null

    private data class Prepared(val uri: Uri, val original: File, val working: File)

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                if (pendingResult != null) {
                    result.error("busy", "La escritura todavía está en curso.", null)
                    return
                }
                val uri = call.argument<String>("uri")?.let(Uri::parse)
                if (uri == null || uri.scheme != "content" || uri.authority != MediaStore.AUTHORITY) {
                    result.error("invalid_uri", "Solo se admiten canciones de MediaStore.", null)
                    return
                }
                executor.execute {
                    try {
                        cleanupPrepared()
                        val name = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                            ?.use { if (it.moveToFirst()) it.getString(0) else null }
                            ?: throw IllegalArgumentException("No se conoce el nombre del archivo.")
                        val ext = name.substringAfterLast('.', "").lowercase()
                        if (ext !in setOf("mp3", "flac", "m4a", "mp4", "wav", "ape")) {
                            throw IllegalArgumentException("Este formato no admite edición de tags.")
                        }
                        val original = File.createTempFile("astra-original-", ".$ext", activity.cacheDir)
                        val working = File.createTempFile("astra-edit-", ".$ext", activity.cacheDir)
                        try {
                            activity.contentResolver.openInputStream(uri)?.use { input ->
                                original.outputStream().use { input.copyTo(it) }
                            } ?: throw IllegalStateException("No se pudo leer el audio.")
                            original.copyTo(working, overwrite = true)
                            prepared = Prepared(uri, original, working)
                            main.post { result.success(working.path) }
                        } catch (error: Exception) {
                            original.delete()
                            working.delete()
                            throw error
                        }
                    } catch (error: Exception) {
                        main.post { result.error("prepare_failed", error.message, null) }
                    }
                }
            }
            "commit" -> {
                val uri = call.argument<String>("uri")?.let(Uri::parse)
                val current = prepared
                if (uri == null || current == null || uri != current.uri || pendingResult != null) {
                    result.error("invalid_state", "No hay una edición preparada para esta canción.", null)
                    return
                }
                pendingResult = result
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                    activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                    activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), PERMISSION_REQUEST_CODE)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    try {
                        val request = MediaStore.createWriteRequest(activity.contentResolver, listOf(uri))
                        activity.startIntentSenderForResult(request.intentSender, REQUEST_CODE, null, 0, 0, 0)
                    } catch (error: Exception) {
                        finishWithError(error)
                    }
                } else {
                    writePrepared()
                }
            }
            "cleanup" -> {
                if (pendingResult != null) {
                    result.error("busy", "La escritura todavía está en curso.", null)
                } else {
                    executor.execute {
                        cleanupPrepared()
                        main.post { result.success(null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE || pendingResult == null) return false
        if (resultCode == Activity.RESULT_OK) writePrepared()
        else {
            pendingResult?.error("cancelled", "No se autorizó la edición del archivo.", null)
            pendingResult = null
        }
        return true
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE || pendingResult == null) return false
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) writePrepared()
        else finishWithError(SecurityException("No se autorizó la escritura del archivo."))
        return true
    }

    private fun writePrepared() {
        executor.execute {
            val current = prepared
            if (current == null) {
                main.post { finishWithError(IllegalStateException("La edición temporal ya no existe.")) }
                return@execute
            }
            try {
                replace(current.uri, current.working)
                main.post {
                    pendingResult?.success(null)
                    pendingResult = null
                }
            } catch (error: SecurityException) {
                if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && error is RecoverableSecurityException) {
                    main.post {
                        try {
                            activity.startIntentSenderForResult(error.userAction.actionIntent.intentSender, REQUEST_CODE, null, 0, 0, 0)
                        } catch (launchError: Exception) { finishWithError(launchError) }
                    }
                } else main.post { finishWithError(error) }
            } catch (error: Exception) {
                try { replace(current.uri, current.original) } catch (_: Exception) { }
                main.post { finishWithError(error) }
            }
        }
    }

    private fun replace(uri: Uri, source: File) {
        activity.contentResolver.openOutputStream(uri, "rwt")?.use { output ->
            source.inputStream().use { it.copyTo(output) }
            output.flush()
        } ?: throw IllegalStateException("No se pudo escribir el audio.")
    }

    private fun finishWithError(error: Exception) {
        pendingResult?.error("write_failed", error.message ?: "No se pudo guardar el archivo.", null)
        pendingResult = null
    }

    private fun cleanupPrepared() {
        prepared?.original?.delete()
        prepared?.working?.delete()
        prepared = null
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.execute { cleanupPrepared() }
        executor.shutdown()
    }

    companion object {
        private const val REQUEST_CODE = 43141
        private const val PERMISSION_REQUEST_CODE = 43142
    }
}
