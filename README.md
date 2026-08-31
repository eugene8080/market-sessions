# Market Sessions

Live trading hours for the world's stock exchanges, as a 24 hour dial.

- **Web app** — `index.html`, `manifest.webmanifest`, `sw.js` and the icons, served from GitHub
  Pages at <https://eugene8080.github.io/market-sessions/>. Installable and offline capable.
- **Android widget** — `android/`, a native home screen widget drawing the same dial. See
  [`android/README.md`](android/README.md) for how to build it without a desktop.

Trading hours are written in each exchange's own local time in both codebases, so daylight saving
is handled automatically. Weekends are treated as closed; public holidays are not.

Editing the web app? Bump `CACHE` in `sw.js` so installed copies pick up the new page instead of
serving the old one from cache.
