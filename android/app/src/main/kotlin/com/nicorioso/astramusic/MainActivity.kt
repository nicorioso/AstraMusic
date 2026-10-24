package com.nicorioso.astramusic

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var mediaStoreScanner: MediaStoreLibraryScanner? = null
    private var artworkChannel: ArtworkChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaStoreScanner = MediaStoreLibraryScanner(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        artworkChannel = ArtworkChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaStoreScanner?.dispose()
        mediaStoreScanner = null
        artworkChannel?.dispose()
        artworkChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
