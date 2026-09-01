# Connect IQ store listing

Updated: 2026-09-01

Copy for the Connect IQ store submission form at
<https://apps.garmin.com/developer/dashboard>. Kept here rather than retyped each time, so the
disclaimer in particular stays reviewed rather than improvised.

| Field | Value |
| ----- | ----- |
| Name | Market Sessions |
| Type | Watch App |
| Price | Free |
| Devices | Populated from `manifest.xml` — fēnix 8 47/51mm and fēnix 8 Solar 51mm, which is what covers the tactix 8, plus Forerunner 255/255S and their Music editions |
| Screenshots | `bin/store/store-glance-454.png`, `bin/store/store-dial-454.png`, `bin/store/store-list-454.png` |
| Package | `bin/store/MarketSessions.iq` |

## Description

> A 24-hour dial showing which of the world's stock exchanges are trading right now.
>
> The glance tells you how many markets are open, which one moves next and when. Open it for the
> full dial: one band per session, green while it trades and grey while it waits, on a face where
> one revolution is a whole day — midnight at the top, noon at the bottom.
>
> Eleven sessions: Sydney, Tokyo, Taipei, Singapore, Hong Kong, Shanghai, Mumbai, Europe, Toronto,
> New York and Nasdaq. Trading hours are held in each exchange's own local time, so daylight saving
> is handled automatically wherever you are, and published exchange holidays are built in.
>
> No account, no network, no permissions. It reads the clock and nothing else.
>
> Market Sessions shows scheduled regular trading hours only — no prices, market data, or
> investment advice. Hours and holidays are built into the app and can go out of date: holiday
> calendars run only as far as each exchange has published, and midday breaks (Tokyo, Hong Kong,
> Shanghai) are not shown. Confirm times with the exchange before relying on them. This is a free
> personal project, not affiliated with or endorsed by any exchange, broker, or financial firm.

## Notes on the disclaimer

The last paragraph is the disclaimer and is deliberately four sentences. Garmin's App Review
Guidelines, section 1(b) *Regulated Activities*, names financial services and puts responsibility
for any legally-required disclaimer on the developer.

What each clause is doing:

- **"scheduled regular trading hours only — no prices, market data, or investment advice"** —
  forecloses the one reading that maps onto a regulated activity. Cheap, and the clause a reviewer
  looks for.
- **"run only as far as each exchange has published"** — staleness is the real risk, and this is
  phrased so it stays true as `Holidays.mc` is regenerated. An earlier draft said "covers
  2026–2027", which was already wrong for Singapore, Shanghai and Mumbai on the day it was written:
  their exchanges had not published 2027. Do not reintroduce a year range here. The per-market
  detail belongs in `LAST_COVERED_YEAR`, where it is generated rather than typed.
- **"not affiliated with or endorsed by any exchange, broker, or financial firm"** — severs any
  implication of employer endorsement by generic denial rather than by naming an employer, which
  would create the association the line exists to prevent. "Broker" also covers the exchange codes
  the bands are labelled with.

Deliberately absent: warranty and liability boilerplate, governing law, and per-exchange trademark
disclaimers. Trading hours are uncopyrightable facts, and over-lawyering a free clock would be its
own kind of mistake.

## Before each submission

1. Rebuild the package from a clean tree: `monkeyc -f monkey.jungle -e -r -o bin/MarketSessions.iq -y <key>`
2. Run the tests: `monkeydo bin/MarketSessions-test.prg fenix847mm /t`
3. Check `LAST_COVERED_YEAR` in [`source/Holidays.mc`](source/Holidays.mc). If any market's calendar
   has lapsed, re-run `python tools/generate_holidays.py` before shipping.
4. If the app ever gains market data, quotes, or paid features, the disclaimer above stops being
   adequate and the question becomes a legal one rather than a drafting one.
