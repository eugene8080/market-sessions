package com.marketsessions.widget

import java.time.Duration
import java.time.Instant
import java.time.format.DateTimeFormatter

/** Whether an alert fires ahead of the bell or after it. */
enum class Lead { BEFORE, AFTER }

/**
 * What to be told about. Deliberately opt in per market: fourteen markets alerting on both bells
 * would be over fifty notifications a day.
 */
data class AlertSettings(
    val enabled: Boolean = false,
    val beforeMinutes: Int = 15,
    val afterMinutes: Int = 0,
    val onOpen: Boolean = true,
    val onClose: Boolean = true,
    val markets: Set<String> = emptySet(),
) {
    /** True when the settings, whatever their shape, can never produce an alert. */
    val silent: Boolean
        get() = !enabled ||
            markets.isEmpty() ||
            (!onOpen && !onClose) ||
            (beforeMinutes <= 0 && afterMinutes <= 0)
}

data class Alert(
    val at: Instant,
    val market: Market,
    val kind: Transition,
    val lead: Lead,
    val minutes: Int,
    val session: Session,
) {
    fun title(): String = when (lead) {
        Lead.BEFORE -> "${market.name} ${if (kind == Transition.OPEN) "opens" else "closes"} in $minutes min"
        Lead.AFTER -> "${market.name} ${if (kind == Transition.OPEN) "opened" else "closed"} $minutes min ago"
    }

    fun body(): String = "Trading ${clock(session.start)} to ${clock(session.end)}"

    /** Stable per market and event, so a repeat replaces its predecessor rather than stacking. */
    fun id(): Int = "${market.name}|${kind.name}|${lead.name}".hashCode()

    private fun clock(instant: Instant) = HHMM.format(instant.atZone(Config.displayZone()))

    private companion object {
        val HHMM: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")
    }
}

object Alerts {

    /**
     * How stale an alert may be and still be worth posting. A phone that was off overnight should
     * not wake to a queue of bells it already missed.
     */
    private val GRACE: Duration = Duration.ofMinutes(30)

    fun upcoming(settings: AlertSettings, now: Instant): List<Alert> {
        if (settings.silent) return emptyList()

        val alerts = ArrayList<Alert>()
        MARKETS.filter { it.name in settings.markets }.forEach { market ->
            Sessions.transitions(market, now).forEach { transition ->
                val wanted =
                    if (transition.kind == Transition.OPEN) settings.onOpen else settings.onClose
                if (!wanted) return@forEach

                if (settings.beforeMinutes > 0) {
                    alerts += Alert(
                        transition.at.minus(Duration.ofMinutes(settings.beforeMinutes.toLong())),
                        market, transition.kind, Lead.BEFORE, settings.beforeMinutes, transition.session,
                    )
                }
                if (settings.afterMinutes > 0) {
                    alerts += Alert(
                        transition.at.plus(Duration.ofMinutes(settings.afterMinutes.toLong())),
                        market, transition.kind, Lead.AFTER, settings.afterMinutes, transition.session,
                    )
                }
            }
        }
        return alerts.sortedBy { it.at }
    }

    /** Alerts whose moment arrived since we last looked, ignoring any older than the grace window. */
    fun due(settings: AlertSettings, since: Instant, now: Instant): List<Alert> {
        val floor = maxOf(since, now.minus(GRACE))
        return upcoming(settings, now).filter { it.at.isAfter(floor) && !it.at.isAfter(now) }
    }

    /** When the next alarm should wake us, or null when these settings never will. */
    fun nextAt(settings: AlertSettings, now: Instant): Instant? =
        upcoming(settings, now).firstOrNull { it.at.isAfter(now) }?.at
}
