import java.time.*
import java.time.temporal.TemporalAdjusters

/**
 * The rules a Garmin watch would have to carry, since Connect IQ has no IANA database on device.
 * Each returns the UTC offset in minutes for a given instant. Validated below against java.time.
 */
enum class Rule { NONE, EU, US, AU }

data class Zone(val id: String, val stdOffsetMin: Int, val rule: Rule)

val ZONES = listOf(
    Zone("Australia/Sydney",  600, Rule.AU),
    Zone("Asia/Tokyo",        540, Rule.NONE),
    Zone("Asia/Singapore",    480, Rule.NONE),
    Zone("Asia/Hong_Kong",    480, Rule.NONE),
    Zone("Asia/Shanghai",     480, Rule.NONE),
    Zone("Asia/Kolkata",      330, Rule.NONE),
    Zone("Europe/Berlin",      60, Rule.EU),
    Zone("Europe/London",       0, Rule.EU),
    Zone("Europe/Zurich",      60, Rule.EU),
    Zone("Europe/Paris",       60, Rule.EU),
    Zone("Europe/Amsterdam",   60, Rule.EU),
    Zone("America/Toronto",  -300, Rule.US),
    Zone("America/New_York", -300, Rule.US),
)

/** Nth given weekday of a month, at a UTC hour: the shape every one of these rules takes. */
private fun nth(year: Int, month: Int, ordinal: Int, day: DayOfWeek, utcHour: Int): Instant {
    val date = if (ordinal > 0)
        LocalDate.of(year, month, 1).with(TemporalAdjusters.dayOfWeekInMonth(ordinal, day))
    else
        LocalDate.of(year, month, 1).with(TemporalAdjusters.lastInMonth(day))
    return date.atTime(utcHour, 0).toInstant(ZoneOffset.UTC)
}

fun offsetMinutes(zone: Zone, at: Instant): Int {
    val year = at.atZone(ZoneOffset.UTC).year
    val summer = when (zone.rule) {
        Rule.NONE -> false

        // Every EU zone switches on the same UTC instant: 01:00 UTC, last Sunday of March and October.
        Rule.EU -> at >= nth(year, 3, 0, DayOfWeek.SUNDAY, 1) && at < nth(year, 10, 0, DayOfWeek.SUNDAY, 1)

        // 02:00 local standard on the second Sunday of March (07:00 UTC at -5),
        // back at 02:00 local daylight on the first Sunday of November (06:00 UTC at -4).
        Rule.US -> at >= nth(year, 3, 2, DayOfWeek.SUNDAY, 7) && at < nth(year, 11, 1, DayOfWeek.SUNDAY, 6)

        // Southern hemisphere: summer wraps the new year, so it is the gap between April and October.
        Rule.AU -> at < nth(year, 4, 1, DayOfWeek.SUNDAY, 16).minusSeconds(86400) ||
                   at >= nth(year, 10, 1, DayOfWeek.SUNDAY, 16).minusSeconds(86400)
    }
    return zone.stdOffsetMin + if (summer) 60 else 0
}

fun main() {
    var checks = 0
    var mismatches = 0
    val worst = HashMap<String, Int>()

    // Every hour for five years is 43,000 samples per zone: enough to catch a transition
    // that is off by an hour or a day.
    val from = Instant.parse("2026-01-01T00:00:00Z")
    val to = Instant.parse("2031-01-01T00:00:00Z")

    ZONES.forEach { zone ->
        val real = ZoneId.of(zone.id)
        var t = from
        while (t < to) {
            val mine = offsetMinutes(zone, t)
            val theirs = real.rules.getOffset(t).totalSeconds / 60
            checks++
            if (mine != theirs) {
                mismatches++
                worst[zone.id] = (worst[zone.id] ?: 0) + 1
            }
            t = t.plusSeconds(3600)
        }
    }

    println("compared hand-rolled rules against the IANA database")
    println("  zones:      ${ZONES.size}")
    println("  span:       2026-01-01 to 2031-01-01, hourly")
    println("  comparisons: $checks")
    println("  mismatches:  $mismatches")
    if (worst.isEmpty()) {
        println("\nevery zone agrees at every hour for five years")
    } else {
        println("\nzones that disagree, by number of wrong hours:")
        worst.entries.sortedByDescending { it.value }.forEach { println("  ${it.key}: ${it.value}") }
    }
}
