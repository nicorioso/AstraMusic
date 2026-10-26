package com.nicorioso.astramusic

import android.content.ContentUris
import android.content.Context
import android.provider.MediaStore
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Consulta MediaStore fuera del hilo principal y reporta progreso a Flutter. */
class MediaStoreLibraryScanner(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var scanning = false
    @Volatile private var cancelled = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startScan" -> startScan(result)
            "cancelScan" -> {
                cancelled = true
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        cancelled = true
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private fun startScan(result: MethodChannel.Result) {
        if (scanning) {
            result.error("scan_in_progress", "Ya hay un escaneo en curso.", null)
            return
        }

        scanning = true
        cancelled = false
        result.success(null)
        executor.execute(::queryMediaStore)
    }

    private fun queryMediaStore() {
        val batch = ArrayList<Map<String, Any?>>(BATCH_SIZE)
        var found = 0
        var errors = 0

        try {
            val mediaUri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM,
                MediaStore.Audio.Media.DURATION,
                MediaStore.Audio.Media.TRACK,
                MediaStore.Audio.Media.YEAR,
                MediaStore.Audio.Media.SIZE,
                MediaStore.Audio.Media.DATE_ADDED,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.DISPLAY_NAME,
            )
            val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND " +
                "${MediaStore.Audio.Media.IS_RINGTONE} = 0 AND " +
                "${MediaStore.Audio.Media.IS_NOTIFICATION} = 0 AND " +
                "${MediaStore.Audio.Media.IS_ALARM} = 0"

            context.contentResolver.query(
                mediaUri,
                projection,
                selection,
                null,
                "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val titleColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artistColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val albumColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val trackColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
                val yearColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
                val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                val dateAddedColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                val dateModifiedColumn = cursor.getColumnIndexOrThrow(
                    MediaStore.Audio.Media.DATE_MODIFIED,
                )
                val displayNameColumn = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)

                while (!cancelled && cursor.moveToNext()) {
                    try {
                        val id = cursor.getLong(idColumn)
                        val displayName = cursor.stringOrNull(displayNameColumn)
                        val title = cursor.stringOrNull(titleColumn)
                            ?.takeUnless { it == MediaStore.UNKNOWN_STRING }
                            ?: displayName?.substringBeforeLast('.')
                            ?: "Audio $id"
                        batch.add(
                            mapOf(
                                "uri" to ContentUris.withAppendedId(mediaUri, id).toString(),
                                "title" to title,
                                "artist" to cursor.stringOrNull(artistColumn)
                                    ?.takeUnless { it == MediaStore.UNKNOWN_STRING },
                                "album" to cursor.stringOrNull(albumColumn)
                                    ?.takeUnless { it == MediaStore.UNKNOWN_STRING },
                                "durationMs" to cursor.positiveLongOrNull(durationColumn),
                                "trackNumber" to cursor.positiveIntOrNull(trackColumn),
                                "year" to cursor.positiveIntOrNull(yearColumn),
                                "fileSize" to cursor.longOrNull(sizeColumn),
                                "dateAddedMs" to cursor.positiveLongOrNull(dateAddedColumn)
                                    ?.times(1000L),
                                "dateModifiedMs" to cursor.positiveLongOrNull(dateModifiedColumn)
                                    ?.times(1000L),
                            ),
                        )
                        found++
                        if (batch.size >= BATCH_SIZE) {
                            sendBatch(batch)
                        }
                        if (found % PROGRESS_INTERVAL == 0) {
                            sendProgress(found, errors)
                        }
                    } catch (_: RuntimeException) {
                        errors++
                    }
                }
            }

            if (cancelled) {
                invokeFlutter("scanCancelled", emptyMap<String, Any?>())
            } else {
                sendBatch(batch)
                invokeFlutter(
                    "scanCompleted",
                    mapOf("foundCount" to found, "errorCount" to errors),
                )
            }
        } catch (error: Exception) {
            invokeFlutter(
                "scanFailed",
                mapOf("message" to (error.message ?: "No fue posible consultar MediaStore.")),
            )
        } finally {
            scanning = false
        }
    }

    private fun sendProgress(foundCount: Int, errorCount: Int) {
        invokeFlutter(
            "scanProgress",
            mapOf("foundCount" to foundCount, "errorCount" to errorCount),
        )
    }

    private fun sendBatch(batch: ArrayList<Map<String, Any?>>) {
        if (batch.isEmpty()) return
        val payload = ArrayList(batch)
        batch.clear()
        invokeFlutter("scanBatch", mapOf("tracks" to payload))
    }

    private fun invokeFlutter(method: String, arguments: Map<String, Any?>) {
        mainHandler.post { channel.invokeMethod(method, arguments) }
    }

    private fun android.database.Cursor.stringOrNull(column: Int): String? =
        if (isNull(column)) null else getString(column)

    private fun android.database.Cursor.longOrNull(column: Int): Long? =
        if (isNull(column)) null else getLong(column)

    private fun android.database.Cursor.positiveLongOrNull(column: Int): Long? =
        longOrNull(column)?.takeIf { it > 0L }

    private fun android.database.Cursor.positiveIntOrNull(column: Int): Int? =
        if (isNull(column)) null else getInt(column).takeIf { it > 0 }

    private companion object {
        const val CHANNEL_NAME = "com.nicorioso.astramusic/library_scanner"
        const val BATCH_SIZE = 100
        const val PROGRESS_INTERVAL = 100
    }
}
