import Toybox.Lang;
import Toybox.System;

//! Turns the market table into "what is open right now, and what flips next".
//!
//! A port of the `Sessions` object in Markets.kt. Weekends are closed; public holidays are not
//! modelled, so a market shows as open on Christmas Day, exactly as the web app and the Android
//! widget do. Keeping the three implementations wrong in the same way is deliberate — they are
//! meant to agree with each other.
(:glance)
module Sessions {

    // Layout of the array `stateOf` returns.
    const STATE_IS_OPEN = 0;        //! 1 when trading now, 0 otherwise
    const STATE_START = 1;          //! start of the drawn window, UTC seconds
    const STATE_END = 2;            //! end of the drawn window, UTC seconds
    const STATE_TRANSITION = 3;     //! when this market next flips, UTC seconds
    const STATE_FIELDS = 4;

    //! Absent value for any of the instant fields above.
    const NONE = -1;

    //! How far either side of today to look for sessions. One day back covers a session that
    //! opened before midnight UTC.
    //!
    //! Sixteen forward is set by holidays, not weekends: Lunar New Year leaves a twelve day gap
    //! between Taipei sessions in 2026 and eleven in Shanghai, once the flanking weekends are
    //! counted. Four was enough when only weekends closed a market. Overshooting the longest known
    //! gap is deliberate — if the window were ever shorter than a real closure the band would find
    //! no next session and quietly vanish from the dial — and the extra days cost almost nothing,
    //! since a closed day is rejected on a weekday test and a table lookup long before any daylight
    //! saving arithmetic happens. tools/generate_holidays.py fails the build if a published
    //! calendar ever exceeds this.
    const SEARCH_BACK = -1;
    const SEARCH_FORWARD = 16;

    //! Current and upcoming session for one market.
    //!
    //! Returns `[isOpen, windowStart, windowEnd, transitionAt]`. The window is the live session
    //! when the market is trading and the next one when it is not — the same "current else next"
    //! choice the dial in the web app makes, so a closed market still shows where its session
    //! sits on the clock face.
    function stateOf(index as Number, nowUtc as Number) as Array<Number> {
        var standard = Markets.field(index, Markets.FIELD_STANDARD_OFFSET);
        var rule = Markets.field(index, Markets.FIELD_RULE);
        var openMinute = Markets.field(index, Markets.FIELD_OPEN_MINUTE);
        var closeMinute = Markets.field(index, Markets.FIELD_CLOSE_MINUTE);

        // Anchor the search on the market's own calendar date, not the device's. In Sydney it can
        // be Tuesday while the watch still says Monday, and the session belongs to Sydney's day.
        var here = Zones.utcToCivil(standard, rule, nowUtc);
        var anchorDay = Zones.daysFromCivil(here[0], here[1], here[2]);

        var currentStart = NONE;
        var currentEnd = NONE;
        var nextStart = NONE;
        var nextEnd = NONE;

        for (var offset = SEARCH_BACK; offset <= SEARCH_FORWARD; offset += 1) {
            var day = anchorDay + offset;
            var dayOfWeek = Zones.weekday(day);
            if (dayOfWeek == Zones.SATURDAY || dayOfWeek == Zones.SUNDAY) {
                continue;
            }

            var ymd = Zones.civilFromDays(day);

            // Holidays are a date in the exchange's own calendar, which is what `day` already is.
            // Beyond the published calendar this returns false, so the dial falls back to weekends
            // only rather than inventing closures.
            if (Holidays.isClosed(index, day, ymd[0])) {
                continue;
            }

            var start = Zones.localToUtc(
                standard, rule, ymd[0], ymd[1], ymd[2], openMinute / 60, openMinute % 60);
            var end = Zones.localToUtc(
                standard, rule, ymd[0], ymd[1], ymd[2], closeMinute / 60, closeMinute % 60);

            if (nowUtc >= start && nowUtc < end) {
                currentStart = start;
                currentEnd = end;
            } else if (start > nowUtc) {
                // Days are walked in order, so the first future open found is the soonest — and
                // it is also the point after which nothing can change. Every later day opens later
                // still, so none of them can contain `now` either, which means `currentStart` is
                // settled as well. Stop.
                //
                // This is what makes the window affordable. Sixteen days forward is sized for
                // Lunar New Year, and walking all sixteen every time cost the Forerunner 255 its
                // frame: eleven markets times eighteen days of daylight saving arithmetic tripped
                // the watchdog on a processor slower than the one this was written on. The usual
                // answer is one or two days away and now costs one or two days.
                nextStart = start;
                nextEnd = end;
                break;
            }
        }

        if (currentStart != NONE) {
            return [1, currentStart, currentEnd, currentEnd] as Array<Number>;
        }
        return [0, nextStart, nextEnd, nextStart] as Array<Number>;
    }

    // Layout of the array `summary` returns.
    const SUMMARY_OPEN_COUNT = 0;   //! how many markets are trading
    const SUMMARY_INDEX = 1;        //! market that flips soonest, or NONE
    const SUMMARY_AT = 2;           //! when it flips, UTC seconds, or NONE
    const SUMMARY_IS_CLOSE = 3;     //! 1 when that flip is a close, 0 when it is an open

    //! One pass over every market: how many are trading, and which one moves next.
    //!
    //! When `windowsOut` is supplied it is filled with the live sessions as a flat
    //! `[start, end, start, end, ...]` run, one pair per open market, in table order. Collecting
    //! them here rather than in a second sweep halves the work: resolving fourteen markets means
    //! several hundred daylight saving lookups, and a glance is meant to be cheap to draw.
    //!
    //! `windowsOut` must have room for `2 * Markets.count()` entries. The first
    //! `2 * openCount` of them are meaningful; the rest are left as the caller set them.
    function scan(nowUtc as Number, windowsOut as Array<Number>?) as Array<Number> {
        var openCount = 0;
        var soonestIndex = NONE;
        var soonestAt = NONE;
        var soonestIsClose = 0;

        for (var i = 0; i < Markets.count(); i += 1) {
            var state = stateOf(i, nowUtc);

            if (state[STATE_IS_OPEN] == 1) {
                if (windowsOut != null) {
                    windowsOut[openCount * 2] = state[STATE_START];
                    windowsOut[openCount * 2 + 1] = state[STATE_END];
                }
                openCount += 1;
            }

            var at = state[STATE_TRANSITION];
            if (at != NONE && (soonestAt == NONE || at < soonestAt)) {
                soonestAt = at;
                soonestIndex = i;
                soonestIsClose = state[STATE_IS_OPEN];
            }
        }

        return [openCount, soonestIndex, soonestAt, soonestIsClose] as Array<Number>;
    }

    //! The aggregate alone, for callers with nowhere to put the open sessions.
    function summary(nowUtc as Number) as Array<Number> {
        return scan(nowUtc, null);
    }

    //! A gap in seconds as "3h 07m", or "42m" under an hour. Never returns zero minutes, so a
    //! transition a few seconds away still reads as imminent rather than as already past.
    function formatGap(seconds as Number) as String {
        return formatGapWith(seconds, " ");
    }

    //! The same gap with the space squeezed out — "3h07m". Worth about a character and a half,
    //! which on the dial's summary disc is the difference between showing which market is next
    //! and showing only how long until something happens.
    function formatGapCompact(seconds as Number) as String {
        return formatGapWith(seconds, "");
    }

    //! The gap rounded down to whole hours — "60h" — for the narrowest row on the dial. Only ever
    //! reached when neither fuller form fits, which in practice means a Friday evening looking at
    //! Monday's open: a two digit hour count and a code beside it is more than a circle this size
    //! can hold. Under an hour it stays in minutes, where the precision actually matters.
    function formatGapHours(seconds as Number) as String {
        var minutes = seconds / 60;
        if (minutes < 60) {
            return formatGapWith(seconds, " ");
        }
        return Lang.format("$1$h", [minutes / 60]);
    }

    //! Shared body of the two formatters above. Monkey C has no `private` at module scope, so the
    //! separation here is by convention: callers want `formatGap` or `formatGapCompact`.
    function formatGapWith(seconds as Number, separator as String) as String {
        var minutes = seconds / 60;
        if (minutes < 1) {
            minutes = 1;
        }

        var hours = minutes / 60;
        var rest = minutes % 60;

        if (hours > 0) {
            return Lang.format("$1$h$2$$3$m", [hours, separator, rest.format("%02d")]);
        }
        return Lang.format("$1$m", [rest]);
    }

    //! Minute of day on the dial, in the device's own zone.
    //!
    //! The dial is drawn in local time so it agrees with the watch face, matching
    //! `Config.displayZone()` on Android. The offset is read fresh on every call rather than
    //! cached, so travelling or a clock change takes effect on the next redraw.
    function displayMinuteOfDay(utcSeconds as Number) as Float {
        var offsetSeconds = System.getClockTime().timeZoneOffset;
        var local = utcSeconds + offsetSeconds;
        var secondOfDay = local % Zones.SECONDS_PER_DAY;
        if (secondOfDay < 0) {
            secondOfDay += Zones.SECONDS_PER_DAY;
        }
        return secondOfDay / 60.0;
    }
}
