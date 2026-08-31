package com.marketsessions.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews
import java.time.Instant

/**
 * The three sizes offered in the launcher's widget picker. Each is a separate provider because the
 * picker lists providers, not sizes; all three stay resizable afterwards, and all three are redrawn
 * by the single alarm the base provider owns.
 */
enum class WidgetKind(
    val provider: Class<out MarketWidgetProvider>,
    val style: DialStyle,
    val layout: Int,
    val hasStatusLine: Boolean,
) {
    LARGE(MarketWidgetProvider::class.java, DialStyle.FULL, R.layout.widget_dial, true),
    MEDIUM(MarketWidgetProviderMedium::class.java, DialStyle.COMPACT, R.layout.widget_dial_compact, true),
    SMALL(MarketWidgetProviderSmall::class.java, DialStyle.MINI, R.layout.widget_dial_mini, false),
}

open class MarketWidgetProvider : AppWidgetProvider() {

    protected open val kind: WidgetKind get() = WidgetKind.LARGE

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { draw(context, manager, it, kind) }
        WidgetScheduler.scheduleNext(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) {
        draw(context, manager, id, kind)
    }

    override fun onEnabled(context: Context) {
        WidgetScheduler.scheduleNext(context)
    }

    /** Only the last widget of any size should stop the clock. */
    override fun onDisabled(context: Context) {
        if (activeWidgets(context) == 0) WidgetScheduler.cancel(context)
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

        /** The tick alarm lands on the base provider, so it redraws every size in one pass. */
        fun redrawAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            WidgetKind.values().forEach { kind ->
                idsOf(context, manager, kind).forEach { draw(context, manager, it, kind) }
            }
        }

        fun activeWidgets(context: Context): Int {
            val manager = AppWidgetManager.getInstance(context) ?: return 0
            return WidgetKind.values().sumOf { idsOf(context, manager, it).size }
        }

        private fun idsOf(context: Context, manager: AppWidgetManager, kind: WidgetKind): IntArray =
            manager.getAppWidgetIds(ComponentName(context, kind.provider))

        private fun draw(context: Context, manager: AppWidgetManager, id: Int, kind: WidgetKind) {
            val now = Instant.now()
            val states = Sessions.all(now)

            val views = RemoteViews(context.packageName, kind.layout)
            views.setImageViewBitmap(
                R.id.dial,
                DialRenderer(bitmapSide(context, manager, id, kind), kind.style).render(states, now),
            )
            if (kind.hasStatusLine) {
                views.setTextViewText(R.id.status, Sessions.statusLine(states, now, short = kind != WidgetKind.LARGE))
            }
            views.setOnClickPendingIntent(R.id.root, openSessions(context))

            manager.updateAppWidget(id, views)
        }

        /**
         * Size the bitmap to the cell the launcher gave us. The ceiling keeps it comfortably
         * inside the RemoteViews transaction limit; the per style floor keeps whatever detail
         * that style still draws legible.
         */
        private fun bitmapSide(
            context: Context,
            manager: AppWidgetManager,
            id: Int,
            kind: WidgetKind,
        ): Int {
            val options = manager.getAppWidgetOptions(id)
            val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val sideDp = listOf(widthDp, heightDp).filter { it > 0 }.minOrNull() ?: 180

            val density = context.resources.displayMetrics.density
            return (sideDp * density).toInt().coerceIn(kind.style.minBitmap, 512)
        }

        /** Tapping opens the sessions screen inside this app, not a hosted page in some browser. */
        private fun openSessions(context: Context): PendingIntent {
            val intent = Intent(context, SessionsActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}

/** Two cells: the dial keeps its hour ring but drops the grid and the band labels. */
class MarketWidgetProviderMedium : MarketWidgetProvider() {
    override val kind: WidgetKind get() = WidgetKind.MEDIUM
}

/** One cell: bands and hands only, zoomed into the space the hour ring would have taken. */
class MarketWidgetProviderSmall : MarketWidgetProvider() {
    override val kind: WidgetKind get() = WidgetKind.SMALL
}
