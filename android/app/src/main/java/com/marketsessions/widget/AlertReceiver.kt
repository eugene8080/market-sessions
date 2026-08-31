package com.marketsessions.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlertReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            AlertScheduler.ACTION_ALERT -> AlertScheduler.fire(context)

            // An alarm does not survive a reboot, and a clock or zone change moves every bell.
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> AlertScheduler.reschedule(context)
        }
    }
}
