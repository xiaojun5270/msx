package com.musix.app

import android.content.Intent
import android.media.MediaRouter2
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val audioRouteChannel = "com.musix.app/audio_route"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioRouteChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "showOutputSwitcher") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                result.success(showOutputSwitcher())
            }
    }

    private fun showOutputSwitcher(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                if (MediaRouter2.getInstance(this).showSystemOutputSwitcher()) return true
            } catch (_: Exception) {
                // Fall through to the settings panels used by older/OEM devices.
            }
        }

        val actions = listOf(Settings.ACTION_CAST_SETTINGS, Settings.ACTION_BLUETOOTH_SETTINGS)
        for (action in actions) {
            try {
                startActivity(Intent(action))
                return true
            } catch (_: Exception) {
                // Try the next system-provided output settings surface.
            }
        }
        return false
    }
}
