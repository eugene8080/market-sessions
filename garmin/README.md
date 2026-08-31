# Market Sessions for Garmin

Updated: 2026-09-01

The third face of Market Sessions, after the web app and the Android widget: a Connect IQ **glance**
backed by a full screen 24 hour dial, for the **tactix 8**.

- **Glance** — one strip in the glance carousel: how many markets are trading, which one moves next
  and when, and a 24 hour timeline of the local day with the open sessions filled in.
- **Dial** — open the glance and you get the same dial the web app draws: one band per session,
  green while it trades and grey while it waits, on a face where one revolution is one day.

Short labels are **Interactive Brokers' venue codes** — `ASX`, `TSEJ`, `SEHK`, `IBIS`, `NYSE` — so a
band is named the way the exchange column of an IBKR watchlist names it. They were checked against
IBKR's contract database, not written from memory; several are not what you would guess (Xetra is
`IBIS`, Zurich is `EBS`, Paris is `SBF`), and `TSE` is Toronto while `TSEJ` is Tokyo.

## Devices

Garmin ships the tactix line under the equivalent fēnix part numbers, so the two product ids in
[`manifest.xml`](manifest.xml) cover every tactix 8 — and the fēnix 8 and quatix 8 that share their
hardware come along with them.

| Product id        | Covers                                        | Panel              |
| ----------------- | --------------------------------------------- | ------------------ |
| `fenix847mm`      | tactix 8 47mm and 51mm (AMOLED)               | 454x454, 16 bit    |
| `fenix8solar51mm` | tactix 8 Solar 51mm                           | 280x280, 8 bit MIP |

On the Solar's MIP panel every colour snaps to Garmin's fixed 64 entry palette, so the open green
lands nearer teal than mint. The contrast the dial actually trades on survives; the AMOLED gets the
web app's colours exactly.

## Building

Needs the Connect IQ SDK (9.2.0 or later), a JDK, and a developer key. With the SDK's `bin` on
`PATH`:

```sh
monkeyc -f monkey.jungle -d fenix847mm -o bin/MarketSessions.prg -y ~/.garmin-keys/developer_key.der
monkeydo bin/MarketSessions.prg fenix847mm
```

The simulator starts a glance capable app **in glance mode**, which is what you want to see first.
Press START on the glance to open the dial.

To build the store package for both devices at once:

```sh
monkeyc -f monkey.jungle -e -o bin/MarketSessions.iq -y ~/.garmin-keys/developer_key.der
```

## Time zones, and why there is a whole module for them

This is the one place the Garmin port cannot follow the other two. The web app leans on
`Intl.DateTimeFormat` and the Android widget on `java.time.ZoneId`; both get the full IANA database
for free, and daylight saving simply falls out of it. **Connect IQ ships no time zone database** —
`Toybox.Time` knows the device's own offset and nothing else.

So [`source/Zones.mc`](source/Zones.mc) states the rules directly: a standard offset per zone plus
one of four rule families (none, EU, US, Australia), with the civil date arithmetic underneath it.
A market's session is then resolved the same way `localToUTC` does it in `index.html` — guess with
the standard offset, re-resolve, settle.

Getting this wrong would not crash anything; it would quietly show a market opening an hour early
twice a year. It is therefore checked two ways:

- **[`tools/verify_zones.py`](../tools/verify_zones.py)** transcribes the algorithm line for line —
  including Monkey C's truncate-toward-zero division and sign preserving modulo — and compares it
  against real tzdata. Every hour of every zone from 2024 to 2031, plus the exact instant each
  market opens and closes on every business day. Run it with `python tools/verify_zones.py`
  (needs `tzdata` on Windows).
- **[`source/ZonesTest.mc`](source/ZonesTest.mc)** checks that the Monkey C behaves like the
  transcription, on the device, with vectors bracketing every 2026 transition to the minute:

  ```sh
  monkeyc -f monkey.jungle -d fenix847mm -o bin/test.prg -y <key> --unit-test
  monkeydo bin/test.prg fenix847mm /t
  ```

Public holidays are not modelled and weekends are closed — the same simplifications the web app and
the Android widget make. Keeping all three wrong in the same way is deliberate; they are meant to
agree with each other.

## Layout

| File | What it holds |
| ---- | ------------- |
| `source/Zones.mc` | Civil date arithmetic and the daylight saving rules |
| `source/Markets.mc` | The exchange table, mirroring `MARKETS` in `index.html` |
| `source/Sessions.mc` | Which markets are trading, and what flips next |
| `source/MarketSessionsGlanceView.mc` | The glance strip |
| `source/DialView.mc` | The 24 hour dial |
| `source/Palette.mc` | The web app's dark theme |
| `source/ZonesTest.mc` | Run No Evil tests |

Everything the glance needs carries the `(:glance)` annotation, which is what keeps the glance build
inside the 64 KB ceiling the tactix 8 allows. `DialView` deliberately sits outside that set and is
never loaded in glance mode.

## Where this differs from the web app

The dial is a port, not a copy, and four things changed on purpose:

- **No minute or second hand.** On a face where one revolution is a day, they sweep a scale they do
  not belong to. A single now marker replaces all three.
- **A tighter band stack.** The web app runs its bands down to a radius of 36 and sweeps hands over
  them. On a watch that leaves nowhere legible for the summary, so the stack is narrowed to clear a
  disc in the middle — showing the open count, the next market, and its countdown — without hiding
  any market. Spacing is solved from the market count in `onLayout`, so adding one tightens the
  stack rather than burying the innermost band under the disc.
- **Europe is a single band.** London, Frankfurt, Zurich, Paris and Amsterdam open and close at the
  same instant to the second, all year — London trades an hour earlier by its own clock and sits an
  hour behind CET, and the UK and EU move their clocks together. In a browser they are worth listing
  separately because their wall clocks differ; on a dial they would be five arcs drawn on top of one
  another, so the watch draws one band labelled `EUR`. `tools/verify_zones.py` proves the
  coincidence rather than assuming it. Toronto, New York and NASDAQ coincide the same way and are
  deliberately left as three.
- **The open count counts sessions, not exchanges.** A consequence of the above: with Europe merged,
  a moment that would once have read "7 open" reads "3 open".

Adding or changing a market means editing `Markets.mc` here and `MARKETS` in `index.html`, and
`Markets.kt` on Android. The zone's rule family has to be picked by hand in the Garmin table; add
the zone to `tools/verify_zones.py` at the same time and the checker will confirm you picked right.

The tables are not identical by design: the web app and the Android widget list all fifteen markets
by city, because their clock lists show London and Frankfurt an hour apart and that is real
information. Only the dial merges Europe, and only because it has to fit its rings into 80 pixels of
radius.

There are **no app settings** — no per-market toggles, nothing in Garmin Connect. Every band always
draws.
