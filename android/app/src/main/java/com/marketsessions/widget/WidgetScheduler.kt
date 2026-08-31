package com.marketsessions.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import java.time.Instant

/**
 * The hands move once a minute, so the widget redraws once a minute.
 *
 * ACTION_TIME_TICK cannot be received by a manifest declared receiver, and inexact alarm windows
 * are clamped to ten minutes on Android 12+, so a self rescheduling alarm is the only way to keep
 * a minute hand honest. RTC rather than RTC_WAKEUP: a home screen widget nobody is looking at is
 * not worth waking the device for, and the redraw simply happens at the next wake.
 *
 * Without the exact alarm permission on Android 12+ the tick can drift by a few minutes; the
 * digital TextClock in the layout ticks by itself regardless, so the widget never shows a
 * plainly wrong time.
 */
object WidgetScheduler {

    const val ACTION_TICK = "com.marketsessions.widget.TICK"

    fun scheduleNext(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val now = Instant.now()
        val nextMinute = now.plusSeconds(60 - (now.epochSecond % 60)).toEpochMilli()
        val pending = tickIntent(context)

        if (canScheduleExact(alarms)) {
            alarms.setExact(AlarmManager.RTC, nextMinute, pending)
        } else {
            alarms.set(AlarmManager.RTC, nextMinute, pending)
        }
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(tickIntent(context))
    }

    fun canScheduleExact(alarms: AlarmManager): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()

    private fun tickIntent(context: Context): PendingIntent {
        val intent = Intent(ACTION_TICK).apply {
            component = ComponentName(context, MarketWidgetProvider::class.java)
        }
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
