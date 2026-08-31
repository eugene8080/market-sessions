package com.marketsessions.widget

import android.content.Context
import java.time.Instant

/** Where the alert settings live, plus the watermark that stops an alert firing twice. */
object AlertStore {

    private const val PREFS = "market-sessions"
    private const val ENABLED = "alerts.enabled"
    private const val BEFORE = "alerts.before"
    private const val AFTER = "alerts.after"
    private const val ON_OPEN = "alerts.onOpen"
    private const val ON_CLOSE = "alerts.onClose"
    private const val MARKETS = "alerts.markets"
    private const val LAST_FIRED = "alerts.lastFired"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(context: Context): AlertSettings {
        val p = prefs(context)
        val defaults = AlertSettings()
        return AlertSettings(
            enabled = p.getBoolean(ENABLED, defaults.enabled),
            beforeMinutes = p.getInt(BEFORE, defaults.beforeMinutes),
            afterMinutes = p.getInt(AFTER, defaults.afterMinutes),
            onOpen = p.getBoolean(ON_OPEN, defaults.onOpen),
            onClose = p.getBoolean(ON_CLOSE, defaults.onClose),
            markets = p.getStringSet(MARKETS, defaults.markets) ?: defaults.markets,
        )
    }

    fun save(context: Context, settings: AlertSettings) {
        prefs(context).edit()
            .putBoolean(ENABLED, settings.enabled)
            .putInt(BEFORE, settings.beforeMinutes)
            .putInt(AFTER, settings.afterMinutes)
            .putBoolean(ON_OPEN, settings.onOpen)
            .putBoolean(ON_CLOSE, settings.onClose)
            .putStringSet(MARKETS, settings.markets)
            .apply()
    }

    /**
     * The moment alerts were last checked; everything after it is still owed. It starts at the
     * epoch rather than at now, so the very first alert is not swallowed by its own watermark —
     * the grace window in [Alerts.due] is what keeps that from dredging up history.
     */
    fun lastFired(context: Context): Instant =
        Instant.ofEpochMilli(prefs(context).getLong(LAST_FIRED, 0L))

    fun setLastFired(context: Context, at: Instant) {
        prefs(context).edit().putLong(LAST_FIRED, at.toEpochMilli()).apply()
    }
}
