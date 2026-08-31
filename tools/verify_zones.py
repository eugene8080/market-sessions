"""
Cross-check the hand written daylight saving engine in garmin/source/Zones.mc against the real
IANA time zone database.

Connect IQ ships no tz database, so Zones.mc derives every market's UTC offset from a standard
offset plus a rule. That is the one place in the Garmin port where a silent wrong answer is
possible, so the algorithm is transcribed here line for line -- including Monkey C's
truncate-toward-zero integer division and sign preserving modulo, which differ from Python's --
and compared hour by hour against zoneinfo.

Two things are checked:
  1. offsetAt()   -- the offset every hour across several years, for every zone in the table.
  2. localToUtc() -- the actual instant each market opens and closes, every business day.
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

# --------------------------------------------------------------------------------------------
# Monkey C integer semantics
# --------------------------------------------------------------------------------------------

def tdiv(a: int, b: int) -> int:
    """Monkey C '/' on Numbers truncates toward zero; Python '//' floors."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def tmod(a: int, b: int) -> int:
    """Monkey C '%' keeps the sign of the dividend."""
    return a - tdiv(a, b) * b


# --------------------------------------------------------------------------------------------
# Transcription of Zones.mc
# --------------------------------------------------------------------------------------------

RULE_NONE, RULE_EU, RULE_US, RULE_AU = 0, 1, 2, 3
DST_SHIFT_MINUTES = 60
SECONDS_PER_DAY = 86400
SECONDS_PER_HOUR = 3600
SECONDS_PER_MINUTE = 60
SUNDAY = 0


def days_from_civil(year: int, month: int, day: int) -> int:
    y = year - 1 if month <= 2 else year
    era = tdiv(y if y >= 0 else y - 399, 400)
    yoe = y - era * 400
    mp = month + (-3 if month > 2 else 9)
    doy = tdiv(153 * mp + 2, 5) + day - 1
    doe = yoe * 365 + tdiv(yoe, 4) - tdiv(yoe, 100) + doy
    return era * 146097 + doe - 719468


def civil_from_days(days: int) -> tuple[int, int, int]:
    z = days + 719468
    era = tdiv(z if z >= 0 else z - 146096, 146097)
    doe = z - era * 146097
    yoe = tdiv(doe - tdiv(doe, 1460) + tdiv(doe, 36524) - tdiv(doe, 146096), 365)
    y = yoe + era * 400
    doy = doe - (365 * yoe + tdiv(yoe, 4) - tdiv(yoe, 100))
    mp = tdiv(5 * doy + 2, 153)
    d = doy - tdiv(153 * mp + 2, 5) + 1
    m = mp + (3 if mp < 10 else -9)
    if m <= 2:
        y += 1
    return (y, m, d)


def weekday(days: int) -> int:
    w = tmod(days + 4, 7)
    return w + 7 if w < 0 else w


def nth_weekday_of(year: int, month: int, target: int, n: int) -> int:
    first = days_from_civil(year, month, 1)
    shift = tmod(target - weekday(first) + 7, 7)
    return first + shift + (n - 1) * 7


def last_weekday_of(year: int, month: int, target: int) -> int:
    next_month = 1 if month == 12 else month + 1
    next_year = year + 1 if month == 12 else year
    last = days_from_civil(next_year, next_month, 1) - 1
    shift = tmod(weekday(last) - target + 7, 7)
    return last - shift


def floor_div(a: int, b: int) -> int:
    q = tdiv(a, b)
    if tmod(a, b) != 0 and ((a < 0) != (b < 0)):
        q -= 1
    return q


def offset_at(standard_minutes: int, rule: int, utc_seconds: int) -> int:
    if rule == RULE_NONE:
        return standard_minutes

    year = civil_from_days(floor_div(utc_seconds, SECONDS_PER_DAY))[0]
    summer = standard_minutes + DST_SHIFT_MINUTES

    if rule == RULE_EU:
        eu_from = last_weekday_of(year, 3, SUNDAY) * SECONDS_PER_DAY + SECONDS_PER_HOUR
        eu_to = last_weekday_of(year, 10, SUNDAY) * SECONDS_PER_DAY + SECONDS_PER_HOUR
        return summer if (eu_from <= utc_seconds < eu_to) else standard_minutes

    if rule == RULE_US:
        us_from = (nth_weekday_of(year, 3, SUNDAY, 2) * SECONDS_PER_DAY
                   + 2 * SECONDS_PER_HOUR - standard_minutes * SECONDS_PER_MINUTE)
        us_to = (nth_weekday_of(year, 11, SUNDAY, 1) * SECONDS_PER_DAY
                 + 2 * SECONDS_PER_HOUR - summer * SECONDS_PER_MINUTE)
        return summer if (us_from <= utc_seconds < us_to) else standard_minutes

    au_from = (nth_weekday_of(year, 10, SUNDAY, 1) * SECONDS_PER_DAY
               + 2 * SECONDS_PER_HOUR - standard_minutes * SECONDS_PER_MINUTE)
    au_to = (nth_weekday_of(year, 4, SUNDAY, 1) * SECONDS_PER_DAY
             + 3 * SECONDS_PER_HOUR - summer * SECONDS_PER_MINUTE)
    return summer if (utc_seconds >= au_from or utc_seconds < au_to) else standard_minutes


def local_to_utc(standard_minutes, rule, year, month, day, hour, minute) -> int:
    wall = (days_from_civil(year, month, day) * SECONDS_PER_DAY
            + hour * SECONDS_PER_HOUR + minute * SECONDS_PER_MINUTE)
    guess = wall - standard_minutes * SECONDS_PER_MINUTE
    offset = offset_at(standard_minutes, rule, guess)
    settled = wall - offset * SECONDS_PER_MINUTE
    offset = offset_at(standard_minutes, rule, settled)
    return wall - offset * SECONDS_PER_MINUTE


# --------------------------------------------------------------------------------------------
# The market table from garmin/source/Markets.mc
# --------------------------------------------------------------------------------------------

MARKETS = [
    # name,        iana zone,            std,  rule,      open,        close
    ("Sydney",     "Australia/Sydney",   600,  RULE_AU,   (10, 0),     (16, 0)),
    ("Tokyo",      "Asia/Tokyo",         540,  RULE_NONE, (9, 0),      (15, 30)),
    ("Taipei",     "Asia/Taipei",        480,  RULE_NONE, (9, 0),      (13, 30)),
    ("Singapore",  "Asia/Singapore",     480,  RULE_NONE, (9, 0),      (17, 0)),
    ("Hong Kong",  "Asia/Hong_Kong",     480,  RULE_NONE, (9, 30),     (16, 0)),
    ("Shanghai",   "Asia/Shanghai",      480,  RULE_NONE, (9, 30),     (15, 0)),
    ("Mumbai",     "Asia/Kolkata",       330,  RULE_NONE, (9, 15),     (15, 30)),
    ("Frankfurt",  "Europe/Berlin",       60,  RULE_EU,   (9, 0),      (17, 30)),
    ("London",     "Europe/London",        0,  RULE_EU,   (8, 0),      (16, 30)),
    ("Zurich",     "Europe/Zurich",       60,  RULE_EU,   (9, 0),      (17, 30)),
    ("Paris",      "Europe/Paris",        60,  RULE_EU,   (9, 0),      (17, 30)),
    ("Amsterdam",  "Europe/Amsterdam",    60,  RULE_EU,   (9, 0),      (17, 30)),
    ("Toronto",    "America/Toronto",   -300,  RULE_US,   (9, 30),     (16, 0)),
    ("New York",   "America/New_York",  -300,  RULE_US,   (9, 30),     (16, 0)),
    ("NASDAQ",     "America/New_York",  -300,  RULE_US,   (9, 30),     (16, 0)),
]

FROM_YEAR = 2024
TO_YEAR = 2031


def check_offsets() -> list[str]:
    """Every hour of every zone, our offset against the tz database's."""
    failures = []
    start = int(datetime(FROM_YEAR, 1, 1, tzinfo=timezone.utc).timestamp())
    end = int(datetime(TO_YEAR, 1, 1, tzinfo=timezone.utc).timestamp())

    seen = set()
    for name, zone_name, std, rule, _open, _close in MARKETS:
        if zone_name in seen:
            continue
        seen.add(zone_name)
        zone = ZoneInfo(zone_name)

        mismatches = 0
        first_bad = None
        for utc in range(start, end, SECONDS_PER_HOUR):
            mine = offset_at(std, rule, utc)
            theirs = int(datetime.fromtimestamp(utc, tz=zone).utcoffset().total_seconds()) // 60
            if mine != theirs:
                mismatches += 1
                if first_bad is None:
                    first_bad = (utc, mine, theirs)

        hours = (end - start) // SECONDS_PER_HOUR
        if mismatches:
            when = datetime.fromtimestamp(first_bad[0], tz=timezone.utc)
            failures.append(
                f"{zone_name}: {mismatches}/{hours} hourly offsets wrong, "
                f"first at {when:%Y-%m-%d %H:%M} UTC (ours {first_bad[1]}, tzdb {first_bad[2]})")
        else:
            print(f"  ok  {zone_name:<20} {hours:>6} hourly offsets match")
    return failures


def check_session_instants() -> list[str]:
    """The instant each market opens and closes, every weekday, against the tz database."""
    failures = []
    day = datetime(FROM_YEAR, 1, 1)
    last = datetime(TO_YEAR, 1, 1)

    checked = 0
    while day < last:
        if day.weekday() < 5:  # Monday-Friday, matching Sessions.mc
            for name, zone_name, std, rule, open_hm, close_hm in MARKETS:
                zone = ZoneInfo(zone_name)
                for hour, minute in (open_hm, close_hm):
                    mine = local_to_utc(std, rule, day.year, day.month, day.day, hour, minute)
                    naive = datetime(day.year, day.month, day.day, hour, minute)
                    theirs = int(naive.replace(tzinfo=zone).timestamp())
                    checked += 1
                    if mine != theirs:
                        failures.append(
                            f"{name} {day:%Y-%m-%d} {hour:02d}:{minute:02d} -> "
                            f"ours {mine}, tzdb {theirs} (out by {(mine - theirs) // 60} min)")
        day += timedelta(days=1)

    if not failures:
        print(f"  ok  {checked} session boundaries match to the second")
    return failures


def main() -> int:
    print(f"Checking {FROM_YEAR}-01-01 to {TO_YEAR}-01-01\n")
    print("offsetAt():")
    failures = check_offsets()
    print("\nlocalToUtc():")
    failures += check_session_instants()

    if failures:
        print(f"\nFAILED: {len(failures)} problem(s)")
        for line in failures[:25]:
            print("  -", line)
        return 1

    print("\nPASSED: the Monkey C zone engine agrees with the IANA database everywhere tested.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
