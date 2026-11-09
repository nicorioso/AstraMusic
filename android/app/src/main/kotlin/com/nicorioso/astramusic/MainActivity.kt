package com.nicorioso.astramusic

import android.content.Intent
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var mediaStoreScanner: MediaStoreLibraryScanner? = null
    private var artworkChannel: ArtworkChannel? = null
    private var packageAudioChannel: PackageAudioChannel? = null
    private var metadataWriteChannel: MetadataWriteChannel? = null
    private var systemSettingsChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // TODO: reconectar MediaStore cuando exista un flujo de UI con alcance explícito.
        mediaStoreScanner = MediaStoreLibraryScanner(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        artworkChannel = ArtworkChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        packageAudioChannel = PackageAudioChannel(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        metadataWriteChannel = MetadataWriteChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        systemSettingsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "astramusic/system_settings",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "openBatteryOptimizationSettings" -> {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (metadataWriteChannel?.onActivityResult(requestCode, resultCode) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ) {
        if (metadataWriteChannel?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaStoreScanner?.dispose()
        mediaStoreScanner = null
        artworkChannel?.dispose()
        artworkChannel = null
        metadataWriteChannel?.dispose()
        metadataWriteChannel = null
        packageAudioChannel?.dispose()
        packageAudioChannel = null
        systemSettingsChannel?.setMethodCallHandler(null)
        systemSettingsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
