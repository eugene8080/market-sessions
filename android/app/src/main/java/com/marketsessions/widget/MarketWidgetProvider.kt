package com.marketsessions.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import java.time.Instant

class MarketWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { draw(context, manager, it) }
        WidgetScheduler.scheduleNext(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) {
        draw(context, manager, id)
    }

    override fun onEnabled(context: Context) {
        WidgetScheduler.scheduleNext(context)
    }

    override fun onDisabled(context: Context) {
        WidgetScheduler.cancel(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            WidgetScheduler.ACTION_TICK,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED,
            -> {
                redrawAll(context)
                WidgetScheduler.scheduleNext(context)
            }
        }
    }

    companion object {

        fun redrawAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, MarketWidgetProvider::class.java))
            ids.forEach { draw(context, manager, it) }
        }

        private fun draw(context: Context, manager: AppWidgetManager, id: Int) {
            val now = Instant.now()
            val states = Sessions.all(now)

            val views = RemoteViews(context.packageName, R.layout.widget_dial)
            views.setImageViewBitmap(R.id.dial, DialRenderer(bitmapSide(context, manager, id)).render(states, now))
            views.setTextViewText(R.id.status, Sessions.statusLine(states, now))
            views.setOnClickPendingIntent(R.id.root, openWebApp(context))

            manager.updateAppWidget(id, views)
        }

        /**
         * Size the bitmap to the cell the launcher gave us. The ceiling keeps it comfortably
         * inside the RemoteViews transaction limit; the floor keeps the band labels readable.
         */
        private fun bitmapSide(context: Context, manager: AppWidgetManager, id: Int): Int {
            val options = manager.getAppWidgetOptions(id)
            val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val sideDp = listOf(widthDp, heightDp).filter { it > 0 }.minOrNull() ?: 180

            val density = context.resources.displayMetrics.density
            return (sideDp * density).toInt().coerceIn(256, 512)
        }

        private fun openWebApp(context: Context): PendingIntent {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(Config.WEB_APP_URL))
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
