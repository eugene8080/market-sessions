import Toybox.Lang;

//! Civil date arithmetic and daylight saving rules.
//!
//! The web app and the Android widget both lean on a full IANA time zone database
//! (`Intl.DateTimeFormat` and `java.time.ZoneId` respectively), so daylight saving falls out of
//! the platform for free. Connect IQ has no such database: `Toybox.Time` can only tell us the
//! device's own UTC offset. Every offset a market needs therefore has to be derived here.
//!
//! The approach is the same one the tz database itself uses — a standard offset plus a rule that
//! says when the clocks move — and it is exact for the four rule families the market table needs.
//! Public holidays are not modelled, matching the other two codebases.
//!
//! All instants in this module are UTC seconds since the Unix epoch, held in a `Number`. That is
//! 32 bit signed, so the arithmetic here is valid until January 2038, the same ceiling every other
//! 32 bit epoch carries.
(:glance)
module Zones {

    // ---------------------------------------------------------------------------------------
    // Daylight saving rule families
    // ---------------------------------------------------------------------------------------

    //! Fixed offset all year: Tokyo, Singapore, Hong Kong, Shanghai, Mumbai.
    const RULE_NONE = 0;

    //! European Union: forward on the last Sunday in March at 01:00 UTC, back on the last Sunday
    //! in October at 01:00 UTC. Uniquely, the EU rule is expressed in UTC rather than local time,
    //! so every European zone turns over at the same instant.
    const RULE_EU = 1;

    //! United States and Canada: forward on the second Sunday in March at 02:00 local standard
    //! time, back on the first Sunday in November at 02:00 local daylight time.
    const RULE_US = 2;

    //! Australia (New South Wales): southern hemisphere, so daylight saving spans the new year.
    //! Forward on the first Sunday in October at 02:00 local standard time, back on the first
    //! Sunday in April at 03:00 local daylight time.
    const RULE_AU = 3;

    //! Every rule in this module shifts the clock by exactly one hour.
    const DST_SHIFT_MINUTES = 60;

    const SECONDS_PER_DAY = 86400;
    const SECONDS_PER_HOUR = 3600;
    const SECONDS_PER_MINUTE = 60;

    //! Sunday, in the 0 = Sunday numbering `weekday()` returns.
    const SUNDAY = 0;
    const SATURDAY = 6;

    // ---------------------------------------------------------------------------------------
    // Civil date <-> day number
    //
    // Howard Hinnant's `days_from_civil` / `civil_from_days`, the same pair the C++20 chrono
    // calendar is built on. They are exact for every proleptic Gregorian date and use nothing but
    // integer arithmetic, which matters because Monkey C has no date library that works in an
    // arbitrary zone — `Time.Gregorian` only ever speaks the device's local time or UTC.
    // ---------------------------------------------------------------------------------------

    //! Days since 1970-01-01 for a civil date. Month is 1-12, day is 1-31.
    function daysFromCivil(year as Number, month as Number, day as Number) as Number {
        // The algorithm shifts the year to start in March, which puts the leap day last and makes
        // the month-length pattern regular enough to compute with one linear expression.
        var y = year;
        if (month <= 2) {
            y -= 1;
        }

        // Era = a 400 year Gregorian cycle, which is exactly 146097 days.
        var era = (y >= 0 ? y : y - 399) / 400;
        var yoe = y - era * 400;                                    // year of era, 0-399
        var mp = (month + (month > 2 ? -3 : 9));                    // March = 0 ... February = 11
        var doy = (153 * mp + 2) / 5 + day - 1;                     // day of that shifted year
        var doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;            // day of era, 0-146096

        return era * 146097 + doe - 719468;                         // 719468 rebases to 1970-01-01
    }

    //! Inverse of `daysFromCivil`. Returns `[year, month, day]`.
    function civilFromDays(days as Number) as Array<Number> {
        var z = days + 719468;
        var era = (z >= 0 ? z : z - 146096) / 146097;
        var doe = z - era * 146097;                                 // 0-146096
        var yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        var y = yoe + era * 400;
        var doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        var mp = (5 * doy + 2) / 153;                               // March = 0 ... February = 11
        var d = doy - (153 * mp + 2) / 5 + 1;
        var m = mp + (mp < 10 ? 3 : -9);

        if (m <= 2) {
            y += 1;                                                 // undo the March-start shift
        }
        return [y, m, d] as Array<Number>;
    }

    //! Day of week for a day number, 0 = Sunday. 1970-01-01 was a Thursday, hence the +4.
    function weekday(days as Number) as Number {
        var w = (days + 4) % 7;
        return w < 0 ? w + 7 : w;                                   // Monkey C % keeps the sign
    }

    //! Day number of the `n`th `targetWeekday` in a month, counting from 1.
    function nthWeekdayOf(year as Number, month as Number, targetWeekday as Number, n as Number) as Number {
        var first = daysFromCivil(year, month, 1);
        var shift = (targetWeekday - weekday(first) + 7) % 7;
        return first + shift + (n - 1) * 7;
    }

    //! Day number of the last `targetWeekday` in a month.
    function lastWeekdayOf(year as Number, month as Number, targetWeekday as Number) as Number {
        // Day 0 of the following month is the last day of this one, which sidesteps having to
        // know month lengths or leap years.
        var nextMonth = month == 12 ? 1 : month + 1;
        var nextYear = month == 12 ? year + 1 : year;
        var last = daysFromCivil(nextYear, nextMonth, 1) - 1;
        var shift = (weekday(last) - targetWeekday + 7) % 7;
        return last - shift;
    }

    //! Integer division that rounds towards negative infinity, unlike Monkey C's `/` which
    //! truncates towards zero. Needed to map a pre-1970 or pre-midnight instant onto its day.
    function floorDiv(a as Number, b as Number) as Number {
        var q = a / b;
        if ((a % b != 0) && ((a < 0) != (b < 0))) {
            q -= 1;
        }
        return q;
    }

    // ---------------------------------------------------------------------------------------
    // Offsets
    // ---------------------------------------------------------------------------------------

    //! The UTC offset in minutes that a zone is running at a given instant.
    //!
    //! @param standardMinutes the zone's offset outside daylight saving, minutes east of UTC
    //! @param rule one of the `RULE_*` constants
    //! @param utcSeconds the instant to resolve, UTC seconds since the epoch
    function offsetAt(standardMinutes as Number, rule as Number, utcSeconds as Number) as Number {
        if (rule == RULE_NONE) {
            return standardMinutes;
        }

        // Transitions never fall near a year boundary in any of these rules, so resolving the year
        // in UTC rather than in local time is safe.
        var year = civilFromDays(floorDiv(utcSeconds, SECONDS_PER_DAY))[0];
        var summer = standardMinutes + DST_SHIFT_MINUTES;

        if (rule == RULE_EU) {
            // Both edges are stated in UTC, so no offset correction is needed.
            var euFrom = lastWeekdayOf(year, 3, SUNDAY) * SECONDS_PER_DAY + SECONDS_PER_HOUR;
            var euTo = lastWeekdayOf(year, 10, SUNDAY) * SECONDS_PER_DAY + SECONDS_PER_HOUR;
            return (utcSeconds >= euFrom && utcSeconds < euTo) ? summer : standardMinutes;
        }

        if (rule == RULE_US) {
            // 02:00 local standard, so subtract the standard offset to reach UTC.
            var usFrom = nthWeekdayOf(year, 3, SUNDAY, 2) * SECONDS_PER_DAY
                + 2 * SECONDS_PER_HOUR - standardMinutes * SECONDS_PER_MINUTE;
            // 02:00 local daylight, so subtract the summer offset instead.
            var usTo = nthWeekdayOf(year, 11, SUNDAY, 1) * SECONDS_PER_DAY
                + 2 * SECONDS_PER_HOUR - summer * SECONDS_PER_MINUTE;
            return (utcSeconds >= usFrom && utcSeconds < usTo) ? summer : standardMinutes;
        }

        // RULE_AU. Daylight saving runs October to April, so it wraps the new year: the test is
        // an "or" across the two ends of the calendar year rather than an "and" between them.
        var auFrom = nthWeekdayOf(year, 10, SUNDAY, 1) * SECONDS_PER_DAY
            + 2 * SECONDS_PER_HOUR - standardMinutes * SECONDS_PER_MINUTE;
        var auTo = nthWeekdayOf(year, 4, SUNDAY, 1) * SECONDS_PER_DAY
            + 3 * SECONDS_PER_HOUR - summer * SECONDS_PER_MINUTE;
        return (utcSeconds >= auFrom || utcSeconds < auTo) ? summer : standardMinutes;
    }

    //! Convert a wall clock time in some zone to the UTC instant it names.
    //!
    //! The offset depends on the instant, and the instant is what we are solving for, so this
    //! iterates: guess with the standard offset, re-resolve, and settle. Two corrections are
    //! always enough because the offset only ever moves by an hour. This mirrors `localToUTC` in
    //! index.html, which does the same dance for the same reason.
    function localToUtc(
        standardMinutes as Number,
        rule as Number,
        year as Number,
        month as Number,
        day as Number,
        hour as Number,
        minute as Number
    ) as Number {
        var wall = daysFromCivil(year, month, day) * SECONDS_PER_DAY
            + hour * SECONDS_PER_HOUR
            + minute * SECONDS_PER_MINUTE;

        var guess = wall - standardMinutes * SECONDS_PER_MINUTE;
        var offset = offsetAt(standardMinutes, rule, guess);

        var settled = wall - offset * SECONDS_PER_MINUTE;
        offset = offsetAt(standardMinutes, rule, settled);

        return wall - offset * SECONDS_PER_MINUTE;
    }

    //! Break a UTC instant into a zone's wall clock fields.
    //! Returns `[year, month, day, hour, minute, second, weekday]`.
    function utcToCivil(standardMinutes as Number, rule as Number, utcSeconds as Number) as Array<Number> {
        var local = utcSeconds + offsetAt(standardMinutes, rule, utcSeconds) * SECONDS_PER_MINUTE;
        var days = floorDiv(local, SECONDS_PER_DAY);
        var secondOfDay = local - days * SECONDS_PER_DAY;
        var ymd = civilFromDays(days);

        return [
            ymd[0],
            ymd[1],
            ymd[2],
            secondOfDay / SECONDS_PER_HOUR,
            (secondOfDay % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE,
            secondOfDay % SECONDS_PER_MINUTE,
            weekday(days)
        ] as Array<Number>;
    }
}
