"""
Generate garmin/source/Holidays.mc from published exchange calendars.

The watch cannot compute holidays. Weekends are a rule; holidays are not — Chinese New Year and
Diwali move with lunar calendars, Easter moves with its own, and exchanges add one-off closures for
national mourning or systems testing. The only honest source is each exchange's published calendar,
so this script reads them from `pandas_market_calendars` and emits a table.

Two things this deliberately does NOT do:

  * Guess beyond what an exchange has published. China's State Council and India's NSE publish only
    a few months ahead, so at the time of writing neither has a 2027 calendar to read. Those markets
    therefore carry a shorter coverage window, recorded per market in the generated file, and the
    watch applies no holidays outside it rather than inventing them.
  * Model half days. An exchange closing early is still open, and the dial has no way to show it.

Run it with the repo root as the working directory:

    pip install pandas_market_calendars
    python tools/generate_holidays.py
"""

from __future__ import annotations

import sys
from datetime import date
from pathlib import Path

import pandas as pd

try:
    import pandas_market_calendars as mcal
except ImportError:  # pragma: no cover - a setup problem, not a logic one
    sys.exit("pandas_market_calendars is not installed:  pip install pandas_market_calendars")

#: First year the table covers. There is no value in carrying dates already past.
FROM_YEAR = 2026

#: Last year the table may cover. Individual markets stop earlier when their exchange has not
#: published that far ahead; the generated file records where each one runs out.
TO_YEAR = 2027

OUTPUT = Path("garmin/source/Holidays.mc")

#: Must match Sessions.SEARCH_FORWARD in garmin/source/Sessions.mc. The watch looks this many days
#: ahead for a market's next session, so a closure longer than this would leave it finding none at
#: all and dropping the band off the dial. Lunar New Year already puts twelve days between Taipei
#: sessions in 2026, so this is checked rather than assumed.
SEARCH_FORWARD_DAYS = 16

#: In the order of NAMES in garmin/source/Markets.mc. The order is load bearing: the generated
#: table is indexed by market position, and `Holidays.isClosed` is called with that index.
#:
#: Two entries are not a single exchange calendar:
#:   Shanghai  — reached over Stock Connect, which settles through Hong Kong, so it is shut when
#:               either side is. Taking the union of both calendars errs towards "closed", which
#:               is the safe direction: it never shows a market open that cannot be traded.
#:   Europe    — one band standing for five exchanges, so it is only shut when all five are. Taking
#:               the intersection means 1 May shows as trading, which is right: London is.
#:   Tokyo/     — Tokyo and Seoul keep the same hours to the minute but nothing like the same
#:   Seoul        calendar, so the band is open whenever either is: Japan trades through the
#:                Korean holidays and Korea through the Japanese ones.
#:   North      — the same, for Toronto, New York and Nasdaq. The intersection matters more here
#:   America      than it looks: the three share a session to the minute but not a calendar, so
#:                Canada Day closes Toronto while New York trades, and Thanksgiving and
#:                Independence Day close New York while Toronto trades. A union would shut the band
#:                on all of them and show the continent closed on days it is open.
MARKETS = [
    ("Sydney",        ["XASX"],  "union"),
    ("Tokyo/Seoul",   ["XTKS", "XKRX"], "intersection"),
    ("Taipei",        ["XTAI"],  "union"),
    ("Singapore",     ["XSES"],  "union"),
    ("Hong Kong",     ["XHKG"],  "union"),
    ("Shanghai",      ["XSHG", "XHKG"], "union"),
    ("Mumbai",        ["XNSE"],  "union"),
    ("Europe",        ["XLON", "XETR", "XSWX", "XPAR", "XAMS"], "intersection"),
    ("N.America",     ["XTSE", "XNYS", "NASDAQ"], "intersection"),
]


def closed_weekdays(code: str, year: int) -> set[pd.Timestamp]:
    """Weekdays in `year` on which this exchange does not trade."""
    start, end = f"{year}-01-01", f"{year}-12-31"
    calendar = mcal.get_calendar(code)
    trading = set(calendar.valid_days(start, end).tz_localize(None).normalize())
    return {day for day in pd.bdate_range(start, end) if day not in trading}


def resolve(codes: list[str], combine: str, year: int) -> set[pd.Timestamp]:
    parts = [closed_weekdays(code, year) for code in codes]
    return set.union(*parts) if combine == "union" else set.intersection(*parts)


def last_published_year(code: str) -> int:
    """The last year this exchange has actually published a calendar for.

    An exchange with a real calendar always has holidays in it, so the first year that comes back
    empty is the first year beyond the data. This has to be asked of each underlying calendar
    rather than of a combined result: Shanghai is unioned with Hong Kong, and Hong Kong publishing
    further ahead would otherwise disguise the fact that the Chinese calendar had run out — the
    band would claim a year of coverage while missing every Chinese holiday in it.
    """
    year = FROM_YEAR
    while year <= TO_YEAR and closed_weekdays(code, year):
        year += 1
    return year - 1


def longest_gap(closed: list[pd.Timestamp], through: int) -> int:
    """The most calendar days this market ever goes between two sessions, weekends included."""
    shut = set(closed)
    trading = [
        day for day in pd.date_range(f"{FROM_YEAR}-01-01", f"{through}-12-31")
        if day.weekday() < 5 and day not in shut
    ]
    return max(
        (trading[i + 1] - trading[i]).days for i in range(len(trading) - 1)
    ) if len(trading) > 1 else 0


def days_from_civil(year: int, month: int, day: int) -> int:
    """Days since 1970-01-01 — the same representation Zones.daysFromCivil produces on the watch."""
    return (date(year, month, day) - date(1970, 1, 1)).days


def main() -> int:
    rows, coverage = [], []

    for name, codes, combine in MARKETS:
        # A band is only covered as far as its *shortest* constituent calendar, so a market built
        # from two exchanges is no better informed than the one that stops first.
        per_code = {code: last_published_year(code) for code in codes}
        last_covered = min(per_code.values())

        if last_covered < FROM_YEAR:
            sys.exit(f"no calendar data at all for {name} — refusing to emit an empty table")

        days: list[pd.Timestamp] = []
        for year in range(FROM_YEAR, last_covered + 1):
            days.extend(sorted(resolve(codes, combine, year)))

        if last_covered < TO_YEAR:
            limiting = [c for c, y in per_code.items() if y == last_covered]
            print(f"  {name:11} limited to {last_covered} by {', '.join(limiting)}")

        gap = longest_gap(sorted(days), last_covered)
        if gap > SEARCH_FORWARD_DAYS:
            sys.exit(
                f"{name}: {gap} days between sessions exceeds Sessions.SEARCH_FORWARD "
                f"({SEARCH_FORWARD_DAYS}). Raise it in garmin/source/Sessions.mc and here, or the "
                f"band will find no next session and disappear from the dial.")

        rows.append((name, sorted(days)))
        coverage.append(last_covered)
        print(f"  {name:11} {len(days):3} closures through {last_covered}, longest gap {gap}d")

    # Flatten into one array with per-market start offsets, the same shape Markets.SPEC uses. One
    # array of numbers costs far less on the watch than one per market.
    flat, offsets = [], []
    for _, days in rows:
        offsets.append(len(flat))
        flat.extend(days_from_civil(d.year, d.month, d.day) for d in days)
    offsets.append(len(flat))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8", newline="\n") as f:
        f.write(render(rows, coverage, flat, offsets))

    print(f"\nwrote {OUTPUT} — {len(flat)} dates, {FROM_YEAR}-{max(coverage)}")
    return 0


def render(rows, coverage, flat, offsets) -> str:
    generated = date.today().isoformat()
    lines = []
    add = lines.append

    add("import Toybox.Lang;")
    add("")
    add("//! Exchange holidays, generated by tools/generate_holidays.py — do not edit by hand.")
    add(f"//! Generated: {generated}")
    add("//!")
    add("//! Weekends are a rule the watch can compute; holidays are not. Chinese New Year and")
    add("//! Diwali move with lunar calendars, Easter moves with its own, and exchanges add one-off")
    add("//! closures for national mourning or systems testing. So they are tabulated, from each")
    add("//! exchange's own published calendar.")
    add("//!")
    add("//! **The table has an edge, and the watch respects it.** An exchange only publishes a year")
    add("//! or so ahead — when this was generated neither Shanghai nor Mumbai had a 2027 calendar in")
    add("//! existence. Each market therefore records the last year it is good for, and outside that")
    add("//! range no holidays are applied rather than wrong ones. Re-run the generator when the")
    add("//! calendars are published; `LAST_COVERED_YEAR` below is what tells you it is time.")
    add("(:glance)")
    add("module Holidays {")
    add("")
    add("    //! The last calendar year each market has holiday data for, in Markets.NAMES order.")
    add("    //! Outside it the market is treated as having no holidays at all.")
    add("    var LAST_COVERED_YEAR as Array<Number> = [")
    for i, (name, _) in enumerate(rows):
        comma = "," if i < len(rows) - 1 else ""
        add(f"        {coverage[i]}{comma}".ljust(14) + f"// {name}")
    add("    ] as Array<Number>;")
    add("")
    add("    //! Where each market's run of dates starts in DAYS. One extra entry on the end holds")
    add("    //! the total, so a market's slice is always OFFSETS[i] to OFFSETS[i + 1].")
    add("    var OFFSETS as Array<Number> = [")
    add("        " + ", ".join(str(o) for o in offsets))
    add("    ] as Array<Number>;")
    add("")
    add("    //! Every closure, as days since 1970-01-01, market by market and ascending within each")
    add("    //! so the lookup can bisect. Same representation Zones.daysFromCivil returns.")
    add("    var DAYS as Array<Number> = [")

    cursor = 0
    for i, (name, days) in enumerate(rows):
        if not days:
            continue
        add(f"        // {name} — {len(days)} closures through {coverage[i]}")
        chunk = [str(flat[cursor + n]) for n in range(len(days))]
        for start in range(0, len(chunk), 8):
            piece = ", ".join(chunk[start:start + 8])
            last = start + 8 >= len(chunk) and i == len(rows) - 1
            add(f"        {piece}{'' if last else ','}")
        cursor += len(days)
    add("    ] as Array<Number>;")
    add("")
    add("    //! Is this market shut for a holiday on this day?")
    add("    //!")
    add("    //! `day` is a day number in the market's own local calendar, which is what the table")
    add("    //! holds — a holiday is a date where the exchange is, not an instant.")
    add("    function isClosed(market as Number, day as Number, year as Number) as Boolean {")
    add("        if (year > LAST_COVERED_YEAR[market]) {")
    add("            return false;   // past the published calendar: assume nothing")
    add("        }")
    add("")
    add("        // Bisect the market's slice. Fourteen markets times a linear scan of thirty odd")
    add("        // dates, twelve days deep, is enough work to matter inside a glance.")
    add("        var low = OFFSETS[market];")
    add("        var high = OFFSETS[market + 1] - 1;")
    add("")
    add("        while (low <= high) {")
    add("            var mid = low + (high - low) / 2;")
    add("            var value = DAYS[mid];")
    add("            if (value == day) {")
    add("                return true;")
    add("            }")
    add("            if (value < day) {")
    add("                low = mid + 1;")
    add("            } else {")
    add("                high = mid - 1;")
    add("            }")
    add("        }")
    add("        return false;")
    add("    }")
    add("}")
    add("")
    return "\n".join(lines)


if __name__ == "__main__":
    sys.exit(main())
