import Toybox.Lang;
import Toybox.Test;

//! Run No Evil tests for the daylight saving engine.
//!
//! Zones.mc is the one piece of the Garmin port with no platform behind it — Connect IQ has no tz
//! database, so the rules are written out by hand and a mistake would show up as a market opening
//! an hour early rather than as a crash. These vectors were generated from the IANA database and
//! bracket every 2026 transition to the minute: the last minute on the old offset and the first
//! minute on the new one.
//!
//! `tools/verify_zones.py` checks the same algorithm exhaustively — every hour of every zone from
//! 2024 to 2031 — against tzdata on the desktop. This file is the narrower check that the Monkey C
//! transcription of it behaves identically on the device.
//!
//! Build and run with:
//!   monkeyc -f monkey.jungle -d fenix847mm -o bin/test.prg -y <key> --unit-test
//!   monkeydo bin/test.prg fenix847mm -t
(:test)
module ZonesTest {

    //! `[standardOffsetMinutes, rule, utcInstant, expectedOffsetMinutes]`
    const OFFSET_VECTORS = [
        [  600, Zones.RULE_AU,   1768435200,  660],   // Sydney, high summer, AEDT
        [  600, Zones.RULE_AU,   1775318340,  660],   // Sydney, last minute of AEDT
        [  600, Zones.RULE_AU,   1775318400,  600],   // Sydney, first minute of AEST
        [  600, Zones.RULE_AU,   1784073600,  600],   // Sydney, midwinter, AEST
        [  600, Zones.RULE_AU,   1791043140,  600],   // Sydney, last minute of AEST
        [  600, Zones.RULE_AU,   1791043200,  660],   // Sydney, first minute of AEDT
        [    0, Zones.RULE_EU,   1768435200,    0],   // London, midwinter, GMT
        [    0, Zones.RULE_EU,   1774745940,    0],   // London, last minute of GMT
        [    0, Zones.RULE_EU,   1774746000,   60],   // London, first minute of BST
        [    0, Zones.RULE_EU,   1784073600,   60],   // London, high summer, BST
        [    0, Zones.RULE_EU,   1792889940,   60],   // London, last minute of BST
        [    0, Zones.RULE_EU,   1792890000,    0],   // London, first minute of GMT
        [   60, Zones.RULE_EU,   1768435200,   60],   // Frankfurt, midwinter, CET
        [   60, Zones.RULE_EU,   1774745940,   60],   // Frankfurt, last minute of CET
        [   60, Zones.RULE_EU,   1774746000,  120],   // Frankfurt, first minute of CEST
        [   60, Zones.RULE_EU,   1792889940,  120],   // Frankfurt, last minute of CEST
        [   60, Zones.RULE_EU,   1792890000,   60],   // Frankfurt, first minute of CET
        [ -300, Zones.RULE_US,   1768435200, -300],   // New York, midwinter, EST
        [ -300, Zones.RULE_US,   1772953140, -300],   // New York, last minute of EST
        [ -300, Zones.RULE_US,   1772953200, -240],   // New York, first minute of EDT
        [ -300, Zones.RULE_US,   1784073600, -240],   // New York, high summer, EDT
        [ -300, Zones.RULE_US,   1793512740, -240],   // New York, last minute of EDT
        [ -300, Zones.RULE_US,   1793512800, -300],   // New York, first minute of EST
        [  540, Zones.RULE_NONE, 1768435200,  540],   // Tokyo never moves
        [  540, Zones.RULE_NONE, 1784073600,  540]    // Tokyo never moves
    ];

    //! `[standardOffsetMinutes, rule, year, month, day, hour, minute, expectedUtcInstant]`,
    //! sampled either side of a transition so the two pass settling in `localToUtc` is exercised.
    const LOCAL_VECTORS = [
        [ -300, Zones.RULE_US, 2026,  3,  6,  9, 30, 1772807400],   // NYSE opens on EST
        [ -300, Zones.RULE_US, 2026,  3,  9,  9, 30, 1773063000],   // NYSE opens on EDT
        [    0, Zones.RULE_EU, 2026,  3, 27,  8,  0, 1774598400],   // London opens on GMT
        [    0, Zones.RULE_EU, 2026,  3, 30,  8,  0, 1774854000],   // London opens on BST
        [  600, Zones.RULE_AU, 2026,  4,  3,  7,  0, 1775160000],   // Sydney opens on AEDT
        [  600, Zones.RULE_AU, 2026,  4,  6,  7,  0, 1775422800]    // Sydney opens on AEST
    ];

    (:test)
    function offsetsMatchTheTimeZoneDatabase(logger as Logger) as Boolean {
        for (var i = 0; i < OFFSET_VECTORS.size(); i += 1) {
            var v = OFFSET_VECTORS[i];
            var actual = Zones.offsetAt(v[0], v[1], v[2]);

            if (actual != v[3]) {
                logger.error(Lang.format("vector $1$: offsetAt($2$, $3$, $4$) = $5$, expected $6$",
                    [i, v[0], v[1], v[2], actual, v[3]]));
                return false;
            }
        }
        return true;
    }

    (:test)
    function localTimesResolveToTheRightInstant(logger as Logger) as Boolean {
        for (var i = 0; i < LOCAL_VECTORS.size(); i += 1) {
            var v = LOCAL_VECTORS[i];
            var actual = Zones.localToUtc(v[0], v[1], v[2], v[3], v[4], v[5], v[6]);

            if (actual != v[7]) {
                logger.error(Lang.format("vector $1$: localToUtc = $2$, expected $3$ (out by $4$s)",
                    [i, actual, v[7], actual - v[7]]));
                return false;
            }
        }
        return true;
    }

    //! Civil date conversion must round trip, including across leap days and century boundaries.
    (:test)
    function civilDatesRoundTrip(logger as Logger) as Boolean {
        var dates = [
            [1970, 1, 1], [1999, 12, 31], [2000, 1, 1], [2000, 2, 29],
            [2024, 2, 29], [2026, 9, 1], [2030, 12, 31], [2036, 2, 29]
        ];

        for (var i = 0; i < dates.size(); i += 1) {
            var d = dates[i];
            var back = Zones.civilFromDays(Zones.daysFromCivil(d[0], d[1], d[2]));

            if (back[0] != d[0] || back[1] != d[1] || back[2] != d[2]) {
                logger.error(Lang.format("$1$-$2$-$3$ round tripped to $4$-$5$-$6$",
                    [d[0], d[1], d[2], back[0], back[1], back[2]]));
                return false;
            }
        }
        return true;
    }

    //! Known weekdays, and the weekend test the session search depends on.
    (:test)
    function weekdaysAreCorrect(logger as Logger) as Boolean {
        // 1970-01-01 was a Thursday (4); 2026-09-01 is a Tuesday (2); 2026-09-05 a Saturday (6).
        var cases = [
            [Zones.daysFromCivil(1970, 1, 1), 4],
            [Zones.daysFromCivil(2026, 9, 1), 2],
            [Zones.daysFromCivil(2026, 9, 5), Zones.SATURDAY],
            [Zones.daysFromCivil(2026, 9, 6), Zones.SUNDAY]
        ];

        for (var i = 0; i < cases.size(); i += 1) {
            var actual = Zones.weekday(cases[i][0]);
            if (actual != cases[i][1]) {
                logger.error(Lang.format("case $1$: weekday = $2$, expected $3$",
                    [i, actual, cases[i][1]]));
                return false;
            }
        }
        return true;
    }

    //! The nth and last weekday helpers the DST rules are built on.
    (:test)
    function weekdayOfMonthHelpers(logger as Logger) as Boolean {
        // The 2026 transition dates: 2nd Sunday of March is the 8th, 1st Sunday of November the
        // 1st, last Sunday of March the 29th, last Sunday of October the 25th.
        var second = Zones.civilFromDays(Zones.nthWeekdayOf(2026, 3, Zones.SUNDAY, 2));
        var first = Zones.civilFromDays(Zones.nthWeekdayOf(2026, 11, Zones.SUNDAY, 1));
        var lastMarch = Zones.civilFromDays(Zones.lastWeekdayOf(2026, 3, Zones.SUNDAY));
        var lastOctober = Zones.civilFromDays(Zones.lastWeekdayOf(2026, 10, Zones.SUNDAY));

        if (second[2] != 8) {
            logger.error(Lang.format("2nd Sunday of March 2026 = $1$, expected 8", [second[2]]));
            return false;
        }
        if (first[2] != 1) {
            logger.error(Lang.format("1st Sunday of Nov 2026 = $1$, expected 1", [first[2]]));
            return false;
        }
        if (lastMarch[2] != 29) {
            logger.error(Lang.format("last Sunday of March 2026 = $1$, expected 29", [lastMarch[2]]));
            return false;
        }
        if (lastOctober[2] != 25) {
            logger.error(Lang.format("last Sunday of Oct 2026 = $1$, expected 25", [lastOctober[2]]));
            return false;
        }
        return true;
    }

    //! Position of a market in the table, or -1 if it is not there.
    function indexOf(name as String) as Number {
        for (var i = 0; i < Markets.count(); i += 1) {
            if (Markets.NAMES[i].equals(name)) {
                return i;
            }
        }
        return -1;
    }

    //! Every market's code must be present and distinct — the glance and the dial both fall back
    //! to them, and two markets sharing one would be indistinguishable on the watch.
    (:test)
    function marketCodesAreUsable(logger as Logger) as Boolean {
        if (Markets.CODES.size() != Markets.count() || Markets.NAMES.size() != Markets.count()) {
            logger.error(Lang.format("table lengths disagree: $1$ names, $2$ codes, $3$ specs",
                [Markets.NAMES.size(), Markets.CODES.size(), Markets.SPEC.size() / Markets.STRIDE]));
            return false;
        }

        for (var i = 0; i < Markets.count(); i += 1) {
            if (Markets.CODES[i].length() == 0) {
                logger.error(Lang.format("$1$ has no code", [Markets.NAMES[i]]));
                return false;
            }
            for (var j = i + 1; j < Markets.count(); j += 1) {
                if (Markets.CODES[i].equals(Markets.CODES[j])) {
                    logger.error(Lang.format("$1$ and $2$ share the code $3$",
                        [Markets.NAMES[i], Markets.NAMES[j], Markets.CODES[i]]));
                    return false;
                }
            }
        }
        return true;
    }

    //! A published holiday must actually close the market, and the next session must step over it.
    //!
    //! Good Friday, 3 April 2026, is the case to use for North America: it is one of the few days
    //! Toronto, New York and Nasdaq are all shut, so it closes the band. Trading resumes on Monday
    //! the 6th.
    (:test)
    function holidaysCloseTheMarket(logger as Logger) as Boolean {
        var america = indexOf("N.America");
        if (america == -1) {
            logger.error("N.America is missing from the market table");
            return false;
        }

        var duringThursday = 1775145600;   // 2026-04-02 12:00 ET, an ordinary session
        var goodFriday = 1775232000;       // 2026-04-03 12:00 ET, shut on both sides of the border
        var mondayOpens = 1775482200;      // 2026-04-06 09:30 ET

        if (Sessions.stateOf(america, duringThursday)[Sessions.STATE_IS_OPEN] != 1) {
            logger.error("North America reported shut on an ordinary Thursday");
            return false;
        }

        var holiday = Sessions.stateOf(america, goodFriday);
        if (holiday[Sessions.STATE_IS_OPEN] != 0) {
            logger.error("North America reported open on Good Friday");
            return false;
        }
        if (holiday[Sessions.STATE_TRANSITION] != mondayOpens) {
            logger.error(Lang.format("next North American open = $1$, expected $2$ (Monday the 6th)",
                [holiday[Sessions.STATE_TRANSITION], mondayOpens]));
            return false;
        }
        return true;
    }

    //! A region band is shut only when every exchange in it is shut.
    //!
    //! This is the whole reason `generate_holidays.py` intersects the three North American
    //! calendars instead of unioning them, and it is worth a test because the safe-looking choice
    //! is the wrong one here. Unioning is right for Shanghai, where the band cannot be traded
    //! unless both Shanghai and Hong Kong are open; it is wrong for a region, where the band stands
    //! for whichever of its exchanges is trading.
    //!
    //! The two days that separate the choices are the national holidays either side of the border:
    //! Canada Day closes Toronto while New York trades, and Independence Day does the reverse. A
    //! unioned table would show the continent shut on both.
    (:test)
    function regionBandsFollowWhicheverExchangeIsOpen(logger as Logger) as Boolean {
        var america = indexOf("N.America");
        if (america == -1) {
            logger.error("N.America is missing from the market table");
            return false;
        }

        var canadaDay = 1782921600;        // 2026-07-01 12:00 ET — Toronto shut, New York trading
        var independenceDay = 1783094400;  // 2026-07-03 12:00 ET — New York shut, Toronto trading

        if (Sessions.stateOf(america, canadaDay)[Sessions.STATE_IS_OPEN] != 1) {
            logger.error("North America reported shut on Canada Day, but New York trades");
            return false;
        }
        if (Sessions.stateOf(america, independenceDay)[Sessions.STATE_IS_OPEN] != 1) {
            logger.error("North America reported shut on Independence Day, but Toronto trades");
            return false;
        }

        // Tokyo and Seoul are the sharper case. The two keep the same hours to the minute, so the
        // band exists as one arc only because of geometry — but its calendar is the whole reason
        // the choice matters. Japan closed 36 weekdays in 2026 and Korea 29, and they agreed on
        // three. Intersecting leaves seven closures across two years; unioning would have left
        // more than sixty, and all but a handful would have been wrong.
        var asia = indexOf("Tokyo/Seoul");
        if (asia == -1) {
            logger.error("Tokyo/Seoul is missing from the market table");
            return false;
        }

        var showaDay = 1777431600;             // 2026-04-29 12:00 JST — Japan shut, Korea trading
        var independenceMovement = 1772420400; // 2026-03-02 12:00 KST — Korea shut, Japan trading
        var childrensDay = 1777950000;         // 2026-05-05 12:00 — a holiday in both countries

        if (Sessions.stateOf(asia, showaDay)[Sessions.STATE_IS_OPEN] != 1) {
            logger.error("Tokyo/Seoul reported shut on Showa Day, but Korea trades");
            return false;
        }
        if (Sessions.stateOf(asia, independenceMovement)[Sessions.STATE_IS_OPEN] != 1) {
            logger.error("Tokyo/Seoul reported shut on 1 March, but Japan trades");
            return false;
        }
        if (Sessions.stateOf(asia, childrensDay)[Sessions.STATE_IS_OPEN] != 0) {
            logger.error("Tokyo/Seoul reported open on Children's Day, shut in both countries");
            return false;
        }
        return true;
    }

    //! The search window must outlast the longest closure any calendar contains, or the band finds
    //! no next session and drops off the dial entirely.
    //!
    //! Taipei's Lunar New Year in 2026 is the worst case in the table: it trades on 11 February and
    //! not again until the 23rd, twelve days later.
    (:test)
    function longClosuresStillFindTheNextSession(logger as Logger) as Boolean {
        var taipei = indexOf("Taipei");
        if (taipei == -1) {
            logger.error("Taipei is missing from the market table");
            return false;
        }

        var midClosure = 1771128000;    // 2026-02-15 12:00 Taipei, four days into the shutdown
        var reopens = 1771808400;       // 2026-02-23 09:00 Taipei

        var state = Sessions.stateOf(taipei, midClosure);
        if (state[Sessions.STATE_IS_OPEN] != 0) {
            logger.error("Taipei reported open during Lunar New Year");
            return false;
        }
        if (state[Sessions.STATE_TRANSITION] == Sessions.NONE) {
            logger.error("Taipei found no next session across a twelve day closure");
            return false;
        }
        if (state[Sessions.STATE_TRANSITION] != reopens) {
            logger.error(Lang.format("Taipei reopens at $1$, expected $2$",
                [state[Sessions.STATE_TRANSITION], reopens]));
            return false;
        }
        return true;
    }

    //! The generated table has to be the shape the lookup assumes: one offset per market plus a
    //! terminator, and each market's dates ascending so the bisection is valid.
    (:test)
    function holidayTableIsWellFormed(logger as Logger) as Boolean {
        if (Holidays.OFFSETS.size() != Markets.count() + 1) {
            logger.error(Lang.format("OFFSETS has $1$ entries, expected $2$",
                [Holidays.OFFSETS.size(), Markets.count() + 1]));
            return false;
        }
        if (Holidays.LAST_COVERED_YEAR.size() != Markets.count()) {
            logger.error("LAST_COVERED_YEAR does not have one entry per market");
            return false;
        }
        if (Holidays.OFFSETS[Markets.count()] != Holidays.DAYS.size()) {
            logger.error("the final offset does not match the number of dates");
            return false;
        }

        for (var i = 0; i < Markets.count(); i += 1) {
            var from = Holidays.OFFSETS[i];
            var to = Holidays.OFFSETS[i + 1];
            if (to < from) {
                logger.error(Lang.format("$1$ has a negative length slice", [Markets.NAMES[i]]));
                return false;
            }
            for (var j = from + 1; j < to; j += 1) {
                if (Holidays.DAYS[j] <= Holidays.DAYS[j - 1]) {
                    logger.error(Lang.format("$1$ dates are not ascending at index $2$",
                        [Markets.NAMES[i], j]));
                    return false;
                }
            }
        }
        return true;
    }

    //! Past the published calendar the watch must assume nothing rather than invent closures.
    (:test)
    function nothingIsClaimedBeyondTheCalendar(logger as Logger) as Boolean {
        for (var i = 0; i < Markets.count(); i += 1) {
            var beyond = Holidays.LAST_COVERED_YEAR[i] + 1;
            // 1 January of the first uncovered year: a holiday almost everywhere, and it must
            // still come back false because the data does not reach that far.
            var day = Zones.daysFromCivil(beyond, 1, 1);
            if (Holidays.isClosed(i, day, beyond)) {
                logger.error(Lang.format("$1$ claimed a holiday in $2$, past its calendar",
                    [Markets.NAMES[i], beyond]));
                return false;
            }
        }
        return true;
    }

    //! A market's session must land on the right side of "open" at instants either side of its
    //! own bell, and must never report a weekend session.
    (:test)
    function sessionsOpenAndCloseOnTime(logger as Logger) as Boolean {
        // 2026-09-01 is a Tuesday. The European band trades 09:00-17:30 CEST, so 07:00 UTC to
        // 15:30 UTC that day — which is also exactly when London trades it at 08:00-16:30 BST,
        // the coincidence the merged band rests on. The index is looked up rather than written
        // down: inserting a market ahead of it would otherwise leave this test quietly checking a
        // different exchange, as it did when Taipei was added.
        var europe = indexOf("Europe");
        if (europe == -1) {
            logger.error("Europe is missing from the market table");
            return false;
        }

        var europeOpens = 1788246000;    // 2026-09-01 07:00 UTC
        var europeCloses = 1788276600;   // 2026-09-01 15:30 UTC

        var justBefore = Sessions.stateOf(europe, europeOpens - 60);
        var justAfter = Sessions.stateOf(europe, europeOpens + 60);
        var afterClose = Sessions.stateOf(europe, europeCloses + 60);

        if (justBefore[Sessions.STATE_IS_OPEN] != 0) {
            logger.error("Europe reported open a minute before the bell");
            return false;
        }
        if (justBefore[Sessions.STATE_TRANSITION] != europeOpens) {
            logger.error(Lang.format("Europe next open = $1$, expected $2$",
                [justBefore[Sessions.STATE_TRANSITION], europeOpens]));
            return false;
        }
        if (justAfter[Sessions.STATE_IS_OPEN] != 1) {
            logger.error("Europe reported closed a minute after the bell");
            return false;
        }
        if (justAfter[Sessions.STATE_TRANSITION] != europeCloses) {
            logger.error(Lang.format("Europe close = $1$, expected $2$",
                [justAfter[Sessions.STATE_TRANSITION], europeCloses]));
            return false;
        }
        if (afterClose[Sessions.STATE_IS_OPEN] != 0) {
            logger.error("Europe reported open after the close");
            return false;
        }

        // The next session after Friday's close must be Monday's open, never Saturday's.
        var saturday = 1788631200;       // 2026-09-05 18:00 UTC, a Saturday
        var weekend = Sessions.stateOf(europe, saturday);
        if (weekend[Sessions.STATE_IS_OPEN] != 0) {
            logger.error("Europe reported open at the weekend");
            return false;
        }

        var opensOn = Zones.utcToCivil(60, Zones.RULE_EU, weekend[Sessions.STATE_TRANSITION]);
        if (opensOn[6] == Zones.SATURDAY || opensOn[6] == Zones.SUNDAY) {
            logger.error(Lang.format("next European session falls on weekday $1$", [opensOn[6]]));
            return false;
        }
        return true;
    }

    //! The market list builds, and builds one row per market.
    //!
    //! The list is reached with a DOWN press, and **synthetic input does not reach the simulator
    //! from a non-interactive session**, so the button itself cannot be exercised here. What can be
    //! is the part that would actually break: constructing the list resolves every market through
    //! `Sessions.stateOf` up front — one calendar search per market — and formats a row from each. A
    //! market table that had grown, or a state array read with the wrong index, would throw here
    //! rather than on the watch.
    (:test)
    function marketListBuilds(logger as Logger) as Boolean {
        var list = new MarketList();

        // One item per market. The title is passed as `:title` and is not an item, which this test
        // got wrong first time round and is the reason it says so here.
        var count = Markets.count();
        if (list.getItem(count - 1) == null) {
            logger.error(Lang.format("market list holds fewer than $1$ rows", [count]));
            return false;
        }
        if (list.getItem(count) != null) {
            logger.error("market list holds more rows than there are markets");
            return false;
        }
        return true;
    }

}
