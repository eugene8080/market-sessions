# Market Sessions

Live trading hours for the world's stock exchanges, as a 24 hour dial.

- **Web app** — `index.html`, `manifest.webmanifest`, `sw.js` and the icons, served from GitHub
  Pages at <https://eugene8080.github.io/market-sessions/>. Installable and offline capable.
- **Android widget** — `android/`, a native home screen widget drawing the same dial. See
  [`android/README.md`](android/README.md) for how to build it without a desktop.
- **Garmin glance** — `garmin/`, a Connect IQ glance and 24 hour dial for the tactix 8. See
  [`garmin/README.md`](garmin/README.md).

Trading hours are written in each exchange's own local time in all three codebases, so daylight
saving is handled automatically. Weekends are treated as closed everywhere.

**Public holidays are modelled on the Garmin build only.** They are tabulated from each exchange's
published calendar by [`tools/generate_holidays.py`](tools/generate_holidays.py), and the table has
an edge the watch respects: an exchange publishes only a year or so ahead, so each market records
the last year it is good for and no holidays are applied beyond it. The web app and the Android
widget still treat every weekday as a trading day.

The web app and the Android widget get their zone rules from the platform. Connect IQ has no time
zone database, so the Garmin build states the daylight saving rules itself and
[`tools/verify_zones.py`](tools/verify_zones.py) checks them against real tzdata.

All times are indicative: regular cash sessions only, with no midday breaks. Not market data, and
not investment advice.

Editing the web app? Bump `CACHE` in `sw.js` so installed copies pick up the new page instead of
serving the old one from cache.
