package com.marketsessions.widget

import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId

/**
 * Trading hours are the exchange's own regular local trading day, so daylight saving is
 * handled by the zone rules rather than by hand. Mirrors the MARKETS table in index.html,
 * garmin/source/Markets.mc and tools/verify_zones.py — change one and change all four.
 *
 * The convention is the regular cash session: first to last continuous trade. Pre-open and
 * post-close auctions are excluded, so Sydney starts at 10:00 rather than at its 07:00
 * pre-open. Midday breaks are not modelled — Tokyo, Hong Kong and Shanghai each shut for
 * lunch and are treated here as trading straight through.
 */
data class Market(
    val name: String,
    val zone: String,
    val open: LocalTime,
    val close: LocalTime,
)

private fun at(hour: Int, minute: Int) = LocalTime.of(hour, minute)

val MARKETS: List<Market> = listOf(
    Market("Sydney", "Australia/Sydney", at(10, 0), at(16, 0)),
    Market("Tokyo", "Asia/Tokyo", at(9, 0), at(15, 30)),
    Market("Singapore", "Asia/Singapore", at(9, 0), at(17, 0)),
    Market("Hong Kong", "Asia/Hong_Kong", at(9, 30), at(16, 0)),
    Market("Shanghai", "Asia/Shanghai", at(9, 30), at(15, 0)),
    Market("Mumbai", "Asia/Kolkata", at(9, 15), at(15, 30)),
    Market("Frankfurt", "Europe/Berlin", at(9, 0), at(17, 30)),
    Market("London", "Europe/London", at(8, 0), at(16, 30)),
    Market("Zurich", "Europe/Zurich", at(9, 0), at(17, 30)),
    Market("Paris", "Europe/Paris", at(9, 0), at(17, 30)),
    Market("Amsterdam", "Europe/Amsterdam", at(9, 0), at(17, 30)),
    Market("Toronto", "America/Toronto", at(9, 30), at(16, 0)),
    Market("New York", "America/New_York", at(9, 30), at(16, 0)),
    Market("NASDAQ", "America/New_York", at(9, 30), at(16, 0)),
)

data class Session(val start: Instant, val end: Instant)

enum class Transition { OPEN, CLOSE }

data class MarketTransition(val at: Instant, val kind: Transition, val session: Session)

data class MarketState(
    val market: Market,
    val current: Session?,
    val next: Session?,
) {
    val isOpen: Boolean get() = current != null

    /** The session the dial draws: the live one, else the one coming up. */
    val window: Session? get() = current ?: next

    /** When this market next flips state, used both for the status line and for scheduling. */
    fun transitionAt(): Instant? = current?.end ?: next?.start
}

object Sessions {

    /**
     * Every regular session in a window around now, two days back and nine forward. Weekends are
     * treated as closed; public holidays are not modelled, same as the web app.
     */
    fun sessionsAround(market: Market, now: Instant): List<Session> {
        val zone = ZoneId.of(market.zone)
        val today = now.atZone(zone).toLocalDate()
        val sessions = ArrayList<Session>()

        for (offset in -2L..9L) {
            val date = today.plusDays(offset)
            if (date.dayOfWeek == DayOfWeek.SATURDAY || date.dayOfWeek == DayOfWeek.SUNDAY) continue

            sessions += Session(
                date.atTime(market.open).atZone(zone).toInstant(),
                date.atTime(market.close).atZone(zone).toInstant(),
            )
        }
        return sessions
    }

    fun stateOf(market: Market, now: Instant): MarketState {
        val sessions = sessionsAround(market, now)
        return MarketState(
            market,
            sessions.firstOrNull { !now.isBefore(it.start) && now.isBefore(it.end) },
            sessions.firstOrNull { it.start.isAfter(now) },
        )
    }

    /** The opens and closes in that window, in order: the moments alerts hang off. */
    fun transitions(market: Market, now: Instant): List<MarketTransition> =
        sessionsAround(market, now)
            .flatMap {
                listOf(
                    MarketTransition(it.start, Transition.OPEN, it),
                    MarketTransition(it.end, Transition.CLOSE, it),
                )
            }
            .sortedBy { it.at }

    fun all(now: Instant): List<MarketState> = MARKETS.map { stateOf(it, now) }

    /** The soonest moment any market opens or closes, so the widget can redraw exactly then. */
    fun nextTransition(states: List<MarketState>): Instant? =
        states.mapNotNull { it.transitionAt() }.minOrNull()

    fun statusLine(states: List<MarketState>, now: Instant, short: Boolean = false): String {
        val openCount = states.count { it.isOpen }
        val head = if (openCount > 0) "$openCount open" else "All closed"

        val soonest = states
            .mapNotNull { state -> state.transitionAt()?.let { state to it } }
            .minByOrNull { it.second } ?: return head

        val (state, at) = soonest
        val verb = if (state.isOpen) "closes" else "opens"
        val gap = shortDuration(Duration.between(now, at))
        return if (short) "$head · ${state.market.name} $verb $gap"
        else "$head · ${state.market.name} $verb in $gap"
    }

    fun shortDuration(d: Duration): String {
        val total = maxOf(d.toMinutes(), 1L)
        val hours = total / 60
        val minutes = total % 60
        return if (hours > 0) "${hours}h ${minutes}m" else "${minutes}m"
    }
}
