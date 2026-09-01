# Market Sessions for Garmin

Updated: 2026-09-01

The third face of Market Sessions, after the web app and the Android widget: a Connect IQ **glance**
backed by a full screen 24 hour dial, for the **tactix 8** and the **Forerunner 255**.

- **Glance** — one strip in the glance carousel: how many markets are trading, which one moves next
  and when, and a 24 hour timeline of the local day with the open sessions filled in.
- **Dial** — open the glance and you get the same dial the web app draws: one band per session,
  green while it trades and grey while it waits, on a face where one revolution is one day.

Short labels are **Interactive Brokers' venue codes** — `ASX`, `TSEJ`, `SEHK`, `IBIS`, `NYSE` — so a
band is named the way the exchange column of an IBKR watchlist names it. They were checked against
IBKR's contract database, not written from memory; several are not what you would guess (Xetra is
`IBIS`, Zurich is `EBS`, Paris is `SBF`), and `TSE` is Toronto while `TSEJ` is Tokyo.

Store submission copy — including the disclaimer and why it is worded the way it is — lives in
[`store-listing.md`](store-listing.md).

## Install it on your watch

**You do not need to build anything.** The two files below are prebuilt.

You need a computer with a USB port and the cable that came with the watch. A phone will not do —
the watch has to appear as a drive, and it only does that on a computer.

### 1. Work out which watch you have

Both models come in 51mm, so the size does not tell them apart. **The screen does:**

| Your watch | How to tell |
| --- | --- |
| **tactix 8** (AMOLED) | glossy and vivid, like a phone screen |
| **tactix 8 Solar** | matte, and there is a faint ring around the edge of the display |
| **Forerunner 255** | 46mm, the larger of the two Forerunners |
| **Forerunner 255S** | 41mm, the smaller one |

Both tactix models come in 51mm, so size does not separate them — the screen does. The two
Forerunners are the other way round: same screen, different size.

To be certain, on any of them: **Settings → System → About**, and read the model name.

### 2. Download the one file for it

From this repository's [**Releases**](../../releases) page, open **Market Sessions for Garmin
(latest)** and download:

| Your watch | File to download |
| --- | --- |
| tactix 8 (AMOLED), 47mm or 51mm | `MarketSessions-tactix8-AMOLED-47mm-and-51mm.prg` |
| tactix 8 Solar 51mm | `MarketSessions-tactix8-SOLAR-51mm.prg` |
| Forerunner 255 **or** 255 Music | `MarketSessions-forerunner255-and-255-Music.prg` |
| Forerunner 255S **or** 255S Music | `MarketSessions-forerunner255s-and-255s-Music.prg` |

The Music editions take the same file as the plain ones — the display is identical, and that is all
the app cares about.

Download **one**. Putting both on the watch does not give you a choice of anything; it gives you the
app twice.

### 3. Copy it onto the watch

1. Plug the watch into the computer with its USB cable.
2. It appears as a device — on Windows, in **File Explorer** under *This PC*, named after the watch.
   On a Mac you need Garmin's free **Android File Transfer** or **Garmin Express** to see it.
3. Open **Internal Storage → GARMIN → APPS**.
4. Drag the `.prg` file into that folder. That is the whole installation.
5. Eject the watch and unplug it.

Nothing else goes on the device — not the `.iq` file, not the screenshots.

### 4. Find it on the watch

Market Sessions lives in the **glance carousel**: from the watch face, press **DOWN** to scroll
through your glances and it is one of them. Press **START** on it to open the full dial.

If it is not there, the watch has not added it to your carousel yet. Hold **MENU** on the watch face,
find **Glances**, and add *Market Sessions* to the list.

Once you are on the dial:

| Press | Does |
| --- | --- |
| **DOWN** | the scrolling list of every exchange and its hours |
| **MENU** | colour theme, and the colour open sessions are drawn in |
| **BACK** | back one screen, and out of the app |

### Updating it later

Download the new file and drop it into `GARMIN\APPS\` over the old one — same name, same folder.
Your theme and colour choices survive.

### If it does not appear

- **Check the folder.** It must be `GARMIN\APPS\`, not `GARMIN\` and not a folder you made.
- **Check you took the right file.** The Solar build will not run on the AMOLED watch or the other
  way round; it simply will not show up.
- **Restart the watch** — hold the top-left button until it powers down, then again to start it.

## Devices

Garmin ships the tactix line under the equivalent fēnix part numbers, so the two product ids in
[`manifest.xml`](manifest.xml) cover every tactix 8 — and the fēnix 8 and quatix 8 that share their
hardware come along with them.

| Product id        | Covers                                        | Panel              |
| ----------------- | --------------------------------------------- | ------------------ |
| `fenix847mm`      | tactix 8 47mm and 51mm (AMOLED)               | 454x454, 16 bit    |
| `fenix8solar51mm` | tactix 8 Solar 51mm                           | 280x280, 8 bit MIP |
| `fr255` `fr255m`  | Forerunner 255 and 255 Music                  | 260x260, 8 bit MIP |
| `fr255s` `fr255sm`| Forerunner 255S and 255S Music                | 218x218, 8 bit MIP |

The Forerunner is not simply a smaller tactix, and three differences shaped the code:

- **No `enhancedGraphicSupport`**, so `Graphics.getVectorFont` does not exist and both the dial's
  hour numerals and the market list fall back to system fonts. The fallback was written when the
  vector font went in and had never actually run until this device was added.
- **A slower processor** running the same drawing. Resolving all eleven markets in one frame tripped
  the watchdog here while fitting comfortably on the tactix, which is what forced the early exit in
  `Sessions.stateOf` — see below.
- **Four levels per channel** on its 8 bit panel, so colours snap to a coarse grid: the ring's
  midnight navy lands on a neutral grey and its noon end on a periwinkle. Legible, but not the
  palette the AMOLED shows.

On the Solar's MIP panel every colour snaps to Garmin's fixed 64 entry palette, so the open green
lands nearer teal than mint. The contrast the dial actually trades on survives; the AMOLED gets the
web app's colours exactly.

## Building it yourself

Everything below is for building from source. If you just want the app on your watch, the section
above is all you need.

### Requirements

Needs the Connect IQ SDK (9.2.0 or later), a JDK, and a developer key. With the SDK's `bin` on
`PATH`:

```sh
monkeyc -f monkey.jungle -d fenix847mm -o bin/MarketSessions.prg -y ~/.garmin-keys/developer_key.der
monkeydo bin/MarketSessions.prg fenix847mm
```

On Windows, [`build.ps1`](build.ps1) does the whole thing — both devices, the store package, the
unit tests — and stages `bin/store/` with only the files a person actually hands over. The compiler
drops a `.prg.debug.xml`, a `-settings.json` and three directories of intermediates beside whatever
`-o` points at, which is why the two are kept apart.

Keep the symbol maps it writes to `bin/symbols/`. They are what turns an address in a crash log off
the watch into a file and a line number, and they only decode the build they were made with.

## Sideloading a build you made yourself

Copy **one** `.prg` into `\GARMIN\APPS\` on the watch over USB. Nothing else goes on the device —
there is no documented way to sideload settings, which is why the theme picker is also on the watch
(open the app, press MENU).

Name the output for the watch rather than for the device id, or the file that lands in the folder
says `fenix8` and the person holding a tactix has to remember why:

```sh
monkeyc -f monkey.jungle -d fenix847mm      -o bin/store/MarketSessions-tactix8-AMOLED-47mm-and-51mm.prg -y <key> -r
monkeyc -f monkey.jungle -d fenix8solar51mm -o bin/store/MarketSessions-tactix8-SOLAR-51mm.prg           -y <key> -r
```

**Size does not tell the two apart** — the tactix 8 and the tactix 8 Solar both come in 51mm. The
screen does: AMOLED is glossy and vivid, Solar is matte with a solar ring around the display. On the
watch, Settings → System → About names the model outright.

The simulator starts a glance capable app **in glance mode**, which is what you want to see first.
Press START on the glance to open the dial.

To build the store package for both devices at once:

```sh
monkeyc -f monkey.jungle -e -o bin/MarketSessions.iq -y ~/.garmin-keys/developer_key.der
```

## The search window, and why it stops early

`Sessions.stateOf` looks up to sixteen days ahead for a market's next session. The window is sized
by holidays rather than weekends: Lunar New Year leaves a twelve day gap between Taipei sessions in
2026, and a window shorter than a real closure would leave a band finding nothing and vanishing off
the dial.

It walks that window in order and **stops at the first future open**. That is not an optimisation
bolted on afterwards; it is what makes the window affordable. Days ascend, so the first day whose
session starts after now is also the point past which nothing can change — every later day starts
later still, so none of them can be the session containing now either. Both answers are settled, and
the loop has nothing left to learn.

Walking all sixteen days regardless cost the Forerunner 255 its frame: eleven markets times eighteen
days of daylight saving arithmetic, done twice a market, tripped the watchdog on a processor slower
than the one this was written on. The tactix 8 absorbed it. The usual answer is one or two days
away, and now costs one or two days.

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

## Holidays

Weekends are a rule the watch can compute. Holidays are not — Lunar New Year and Diwali move with
lunar calendars, Easter with its own, and exchanges add one-off closures for national mourning or
systems testing. So they are tabulated in [`source/Holidays.mc`](source/Holidays.mc), generated from
each exchange's published calendar by
[`tools/generate_holidays.py`](../tools/generate_holidays.py):

```sh
pip install pandas_market_calendars
python tools/generate_holidays.py
```

**The table has an edge and the watch respects it.** An exchange publishes only a year or so ahead;
when this was last generated, neither Shanghai nor Mumbai had a 2027 calendar in existence. Each
market therefore records the last year it is good for in `LAST_COVERED_YEAR`, and beyond that no
holidays are applied rather than wrong ones. Re-run the generator when calendars are published.

Two bands are not a single exchange's calendar. **Shanghai** is reached over Stock Connect, which
settles through Hong Kong, so it takes the union of both — erring towards closed, which never shows
a market open that cannot be traded. **Europe** stands for five exchanges, so it takes the
intersection: 1 May shows as trading, which is right, because London is.

Midday breaks are still not modelled — Tokyo, Hong Kong and Shanghai each shut for lunch and are
drawn as trading straight through. Neither are half days: an exchange closing early is still open,
and the dial has no way to show it.

Holidays are a Garmin-only feature. The web app and the Android widget still treat every weekday as
a trading day.

## Layout

| File | What it holds |
| ---- | ------------- |
| `source/Zones.mc` | Civil date arithmetic and the daylight saving rules |
| `source/Markets.mc` | The exchange table, mirroring `MARKETS` in `index.html` |
| `source/Sessions.mc` | Which markets are trading, and what flips next |
| `source/MarketSessionsGlanceView.mc` | The glance strip |
| `source/DialView.mc` | The 24 hour dial |
| `source/Palette.mc` | The web app's dark theme |
| `source/Holidays.mc` | Generated exchange holiday table |
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
