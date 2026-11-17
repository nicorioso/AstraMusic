package com.nicorioso.astramusic

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.YoutubeDL.UpdateChannel
import com.yausername.ffmpeg.FFmpeg
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class AndroidYtDlpChannel(private val context: Context, messenger: BinaryMessenger) {
    private val methods = MethodChannel(messenger, "astramusic/yt_dlp")
    private val events = EventChannel(messenger, "astramusic/yt_dlp/events")
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var sink: EventChannel.EventSink? = null
    @Volatile private var processId: String? = null
    @Volatile private var canceled = false
    @Volatile private var workDir: File? = null

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        methods.setMethodCallHandler(::handle)
    }

    private fun emit(value: Map<String, Any?>) { main.post { sink?.success(value) } }
    private fun reply(result: MethodChannel.Result, value: Any?) { main.post { result.success(value) } }
    private fun fail(result: MethodChannel.Result, error: Throwable) {
        main.post { result.error("download_error", diagnostic(error.message ?: "Error de descarga"), null) }
    }
    private fun initialize() {
        synchronized(initializationLock) {
            if (!initialized) {
                YoutubeDL.getInstance().init(context.applicationContext)
                FFmpeg.getInstance().init(context.applicationContext)
                initialized = true
            }
        }
    }
    companion object {
        private val initializationLock = Any()
        @Volatile private var initialized = false
    }
    private fun request(url: String, vararg options: Pair<String, String>): YoutubeDLRequest {
        val request = YoutubeDLRequest(url)
        request.addOption("--ignore-config")
        request.addOption("--no-warnings")
        for ((key, value) in options) request.addOption(key, value)
        return request
    }
    private fun diagnostic(detail: String): String {
        val lines = detail.lines().map { it.trim().replace(Regex("^(Bad state:|StateError:)\\s*", RegexOption.IGNORE_CASE), "") }.filter { it.isNotEmpty() }
        val errors = lines.filter { it.startsWith("ERROR:", ignoreCase = true) }
        val relevant = errors.ifEmpty {
            lines.filterNot { it.startsWith("WARNING:", ignoreCase = true) ||
                it.startsWith("Bad state:", ignoreCase = true) }
        }
        return relevant.takeLast(3).joinToString(" ").ifBlank { "yt-dlp falló sin un diagnóstico." }
    }
    private fun updateEngine(): String {
        initialize()
        return try {
            YoutubeDL.getInstance().updateYoutubeDL(context, UpdateChannel.NIGHTLY).toString()
        } catch (nightly: Exception) {
            Log.w("AstraYtDlp", "Nightly update failed; trying stable", nightly)
            YoutubeDL.getInstance().updateYoutubeDL(context, UpdateChannel.STABLE).toString()
        }
    }
    private fun execute(url: String, vararg options: Pair<String, String>): String {
        val id = UUID.randomUUID().toString()
        processId = id
        try {
            val response = YoutubeDL.getInstance().execute(request(url, *options), id) { progress, _, _ ->
                emit(mapOf("status" to "downloading", "percent" to progress.toDouble()))
            }
            Log.d("AstraYtDlp", "yt-dlp stderr: ${response.err}")
            if (response.exitCode != 0) error(diagnostic(response.err.ifBlank { response.out }))
            return response.out
        } finally { processId = null }
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") {
            canceled = true
            processId?.let { YoutubeDL.getInstance().destroyProcessById(it) }
            reply(result, null)
            return
        }
        executor.execute {
            try {
                when (call.method) {
                    "updateEngine" -> reply(result, mapOf("status" to updateEngine(),
                        "version" to YoutubeDL.getInstance().version(context)))
                    "checkAvailability" -> {
                        initialize()
                        reply(result, mapOf("available" to true))
                    }
                    "analyzeUrl", "analyzePlaylist" -> {
                        initialize()
                        val url = call.argument<String>("url") ?: error("Falta URL")
                        val playlist = call.method == "analyzePlaylist"
                        val output = if (playlist) execute(url,
                            "--flat-playlist" to "", "--playlist-end" to "151",
                            "--skip-download" to "", "--dump-single-json" to "")
                        else execute(url, "--no-playlist" to "", "--skip-download" to "", "--dump-single-json" to "")
                        if (canceled) error("Cancelado")
                        reply(result, mapOf("json" to output))
                    }
                    "downloadAudio" -> download(call, result)
                    else -> main.post { result.notImplemented() }
                }
            } catch (error: Throwable) {
                Log.e("AstraYtDlp", "Native download failed", error)
                if (call.method == "downloadAudio") {
                    emit(mapOf("status" to if (canceled) "canceled" else "failed", "error" to diagnostic(error.message ?: "Error de descarga")))
                    workDir?.deleteRecursively()
                    workDir = null
                } else fail(result, error)
            }
        }
    }
    private fun download(call: MethodCall, result: MethodChannel.Result) {
        canceled = false
        reply(result, null)
        initialize()
        val url = call.argument<String>("url") ?: error("Falta URL")
        val id = call.argument<String>("id") ?: error("Falta ID")
        require(Regex("[A-Za-z0-9_-]{1,128}").matches(id)) { "ID inválido" }
        val supplied = call.argument<String>("temporaryDirectory") ?: error("Falta directorio temporal")
        val directory = File(supplied).canonicalFile
        require(directory.path.startsWith(context.cacheDir.canonicalPath + File.separator)) {
            "El directorio temporal no pertenece a la caché privada"
        }
        require(directory.isDirectory || directory.mkdirs()) { "No se pudo crear el directorio temporal" }
        workDir = directory
        emit(mapOf("status" to "analyzing"))
        val outputPattern = File(directory, "$id.%(ext)s").absolutePath
        execute(url,
            "--no-playlist" to "", "-f" to "bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio",
            "--concurrent-fragments" to "4", "--buffer-size" to "16K",
            "--write-thumbnail" to "", "--print" to "after_move:filepath",
            "-o" to outputPattern)
        if (canceled) error("Cancelado")
        val audioExtensions = setOf("mp3", "m4a", "aac", "opus", "ogg", "webm", "wav", "flac")
        val files = directory.listFiles()?.filter { it.isFile } ?: emptyList()
        Log.d("AstraYtDlp", "Final files: ${files.joinToString { "${it.name} (${it.length()} bytes)" }}")
        val audio = files.filter { it.name.startsWith("$id.") &&
            it.extension.lowercase() in audioExtensions && it.length() > 0L }
            .maxByOrNull { it.length() }
            ?: error("yt-dlp no produjo un archivo de audio válido")
        val thumbnail = files.firstOrNull { it.name.startsWith("$id.") &&
            it.extension.lowercase() in setOf("jpg", "jpeg", "webp", "png") && it.length() > 0L }
        workDir = null
        emit(mapOf("status" to "completed", "path" to audio.absolutePath,
            "thumbnailPath" to thumbnail?.absolutePath))
    }
    fun dispose() {
        canceled = true
        processId?.let { YoutubeDL.getInstance().destroyProcessById(it) }
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        executor.shutdownNow()
    }
}
