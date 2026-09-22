package com.musix.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Android home-screen "正在播放" widget. Mirrors the SwiftUI NowPlayingWidget:
 * cover + title + artist + play/pause state + progress, tap opens musicx://now-playing.
 *
 * Data is written from Dart via [WidgetBridge.savePlayback] using the home_widget
 * plugin, then delivered here as [widgetData] (a SharedPreferences view).
 */
class NowPlayingWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.now_playing_widget)

            val title = widgetData.getString("np_title", null).orEmpty()
            val artist = widgetData.getString("np_artist", null).orEmpty()
            val coverFile = widgetData.getString("np_cover_file", null).orEmpty()
            val playing = widgetData.getBoolean("np_playing", false)
            val elapsed = widgetData.getInt("np_elapsed", 0)
            val duration = widgetData.getInt("np_duration", 0)
            val hasTrack = title.isNotEmpty()

            if (hasTrack) {
                views.setTextViewText(R.id.widget_label, "正在播放")
                views.setTextViewText(R.id.widget_title, title)
                views.setTextViewText(
                    R.id.widget_artist,
                    if (artist.isNotEmpty()) artist else "MusicX"
                )
                views.setViewVisibility(R.id.widget_state, View.VISIBLE)
                views.setImageViewResource(
                    R.id.widget_state,
                    if (playing) android.R.drawable.ic_media_pause
                    else android.R.drawable.ic_media_play
                )
                views.setViewVisibility(R.id.widget_progress, View.VISIBLE)
                val progress = if (duration > 0) {
                    (elapsed.toLong() * 1000L / duration).toInt().coerceIn(0, 1000)
                } else 0
                views.setProgressBar(R.id.widget_progress, 1000, progress, false)
            } else {
                views.setTextViewText(R.id.widget_label, "正在播放")
                views.setTextViewText(R.id.widget_title, "未在播放")
                views.setTextViewText(R.id.widget_artist, "打开 MusicX 开始听歌")
                views.setViewVisibility(R.id.widget_state, View.GONE)
                views.setViewVisibility(R.id.widget_progress, View.INVISIBLE)
            }

            // Cover: home_widget can render a cover file into the shared dir; fall
            // back to the placeholder drawable when no bitmap is available.
            var coverSet = false
            if (coverFile.isNotEmpty()) {
                try {
                    val f = File(coverFile)
                    if (f.exists()) {
                        val bmp = BitmapFactory.decodeFile(f.absolutePath)
                        if (bmp != null) {
                            views.setImageViewBitmap(R.id.widget_cover, bmp)
                            coverSet = true
                        }
                    }
                } catch (_: Exception) {
                }
            }
            if (!coverSet) {
                views.setImageViewResource(R.id.widget_cover, R.drawable.widget_cover_placeholder)
            }

            // Tap anywhere opens the Now Playing surface via the musicx:// deep link.
            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("musicx://now-playing")
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
