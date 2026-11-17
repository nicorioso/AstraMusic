package com.nicorioso.astramusic

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.ffmpeg.FFmpeg
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
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
        main.post { result.error("download_error", error.message ?: "Error de descarga", null) }
    }
    private fun initialize() {
        YoutubeDL.getInstance().init(context)
        FFmpeg.getInstance().init(context)
    }
    private fun request(url: String, vararg options: Pair<String, String>): YoutubeDLRequest {
        val request = YoutubeDLRequest(url)
        request.addOption("--ignore-config")
        for ((key, value) in options) request.addOption(key, value)
        return request
    }
    private fun execute(url: String, vararg options: Pair<String, String>): String {
        val id = UUID.randomUUID().toString()
        processId = id
        try {
            return YoutubeDL.getInstance().execute(request(url, *options), id) { progress, _, _ ->
                emit(mapOf("status" to "downloading", "percent" to progress.toDouble()))
            }.out
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
                if (call.method == "downloadAudio") {
                    emit(mapOf("status" to if (canceled) "canceled" else "failed", "error" to error.message))
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
        val directory = File(context.cacheDir, "astra-download-${UUID.randomUUID()}")
        directory.mkdirs()
        workDir = directory
        emit(mapOf("status" to "analyzing"))
        val output = execute(url,
            "--no-playlist" to "", "--no-overwrites" to "", "--no-continue" to "",
            "--extract-audio" to "", "--audio-format" to "mp3",
            "--write-thumbnail" to "", "--convert-thumbnails" to "jpg",
            "--embed-thumbnail" to "", "-o" to File(directory, "$id.%(ext)s").absolutePath)
        if (canceled) error("Cancelado")
        val audio = File(directory, "$id.mp3")
        if (!audio.isFile || audio.length() == 0L) error("yt-dlp no produjo un MP3 válido: ${output.takeLast(500)}")
        val thumbnail = File(directory, "$id.jpg")
        workDir = null
        emit(mapOf("status" to "completed", "path" to audio.absolutePath,
            "thumbnailPath" to thumbnail.takeIf { it.isFile && it.length() > 0 }?.absolutePath))
    }
    fun dispose() {
        canceled = true
        processId?.let { YoutubeDL.getInstance().destroyProcessById(it) }
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        executor.shutdownNow()
    }
}
