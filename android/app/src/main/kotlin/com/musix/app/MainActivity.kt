package com.musix.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.MediaRouter2
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : AudioServiceActivity() {
    private val audioRouteChannel = "com.musix.app/audio_route"
    private val systemVolumeChannel = "com.musix.app/system_volume"
    private val systemVolumeEvents = "com.musix.app/system_volume_events"
    private var volumeEventSink: EventChannel.EventSink? = null
    private var volumeReceiverRegistered = false

    private val volumeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "android.media.VOLUME_CHANGED_ACTION") {
                val stream = intent.getIntExtra("android.media.EXTRA_VOLUME_STREAM_TYPE", -1)
                if (stream == -1 || stream == AudioManager.STREAM_MUSIC) {
                    emitMediaVolume()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        emitMediaVolume()
    }

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemVolumeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getMediaVolume" -> result.success(mediaVolume())
                    "setMediaVolume" -> {
                        val value = call.argument<Number>("value")?.toDouble()
                        if (value == null) {
                            result.error("invalid_volume", "Missing volume value", null)
                        } else {
                            setMediaVolume(value)
                            result.success(mediaVolume())
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, systemVolumeEvents)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    volumeEventSink = events
                    registerVolumeReceiver()
                    emitMediaVolume()
                }

                override fun onCancel(arguments: Any?) {
                    volumeEventSink = null
                    unregisterVolumeReceiver()
                }
            })
    }

    private fun audioManager(): AudioManager =
        getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun mediaVolume(): Double {
        val audio = audioManager()
        val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (maximum <= 0) return 0.0
        return audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / maximum
    }

    private fun setMediaVolume(value: Double) {
        val audio = audioManager()
        val maximum = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val target = (value.coerceIn(0.0, 1.0) * maximum).roundToInt()
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
        emitMediaVolume()
    }

    private fun emitMediaVolume() {
        volumeEventSink?.success(mediaVolume())
    }

    private fun registerVolumeReceiver() {
        if (volumeReceiverRegistered) return
        val filter = IntentFilter("android.media.VOLUME_CHANGED_ACTION")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(volumeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(volumeReceiver, filter)
        }
        volumeReceiverRegistered = true
    }

    private fun unregisterVolumeReceiver() {
        if (!volumeReceiverRegistered) return
        unregisterReceiver(volumeReceiver)
        volumeReceiverRegistered = false
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
