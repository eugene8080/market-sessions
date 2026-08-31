package com.marketsessions.widget

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import java.time.Instant

/**
 * One alarm at a time: the next alert due across every chosen market. When it fires, everything
 * owed since the last check is posted and the following alarm is set.
 *
 * Unlike the widget's minute tick this uses RTC_WAKEUP — being told fifteen minutes before the
 * open is worthless if it waits for the phone to wake on its own.
 */
object AlertScheduler {

    const val ACTION_ALERT = "com.marketsessions.widget.ALERT"
    private const val CHANNEL = "session-alerts"

    /** Alarms are set for the first alert after the watermark, never one already consumed. */
    fun reschedule(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = alertIntent(context)

        val after = maxOf(Instant.now(), AlertStore.lastFired(context))
        val at = Alerts.nextAt(AlertStore.load(context), after)
        if (at == null) {
            alarms.cancel(pending)
            return
        }
        if (WidgetScheduler.canScheduleExact(alarms)) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), pending)
        } else {
            alarms.set(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), pending)
        }
    }

    fun fire(context: Context) {
        val settings = AlertStore.load(context)

        // A hair beyond now, so an alarm delivered a moment early still counts as arrived. The
        // watermark moves to the same horizon, so nothing inside it can be posted twice.
        val horizon = Instant.now().plusSeconds(5)
        val due = Alerts.due(settings, AlertStore.lastFired(context), horizon)

        if (due.isNotEmpty()) {
            ensureChannel(context)
            due.forEach { post(context, it) }
        }
        AlertStore.setLastFired(context, horizon)
        reschedule(context)
    }

    private fun post(context: Context, alert: Alert) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_session)
            .setContentTitle(alert.title())
            .setContentText(alert.body())
            .setWhen(alert.at.toEpochMilli())
            .setShowWhen(true)
            .setAutoCancel(true)
            .setContentIntent(openWebApp(context))
            .build()
        manager.notify(alert.id(), notification)
    }

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                context.getString(R.string.alert_channel),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = context.getString(R.string.alert_channel_description) }
        )
    }

    private fun alertIntent(context: Context): PendingIntent {
        val intent = Intent(ACTION_ALERT).apply {
            component = ComponentName(context, AlertReceiver::class.java)
        }
        return PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun openWebApp(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context, 0,
            Intent(Intent.ACTION_VIEW, Uri.parse(Config.WEB_APP_URL)),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
