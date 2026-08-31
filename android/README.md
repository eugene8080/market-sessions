# Market Sessions — Android home screen widget

A native widget that draws the same 24 hour dial as the web app: one band per exchange, green
while it is trading, grey for the session coming up, with hour and minute hands over the top.
Tapping it opens the web app.

The trading hours and the session logic are a direct port of the `MARKETS` table in
`../index.html`. Hours are written in each exchange's own local time and converted with
`java.time`, so daylight saving is handled by the zone rules. Weekends are treated as closed;
public holidays are not.

## Building without a desktop

Android Studio is desktop only, but you never have to open it. GitHub Actions builds the APK:

1. Go to the **Actions** tab → **Build Android widget APK** → **Run workflow**.
2. When it finishes, open the repository's **Releases** → **Market Sessions widget (latest)**.
3. Download `market-sessions-widget.apk` on your phone and open it to install. Android will ask
   you to allow installing unknown apps from your browser; that prompt is expected for a
   sideloaded build.
4. Open **Market Sessions**, tap **Add the widget to my home screen**, and grant exact alarms if
   the app asks.

The workflow also runs automatically on any push to `main` that touches `android/`.

## Building on a desktop

Open the `android/` directory in Android Studio and press Run, or:

```
cd android
./gradlew assembleDebug        # app/build/outputs/apk/debug/app-debug.apk
./gradlew installDebug         # straight onto an attached device
```

The APK is signed with the standard debug key. That is fine for sideloading onto your own phone;
it cannot be published to Play without a real signing key.

## Why the app asks for exact alarms

The hands move once a minute, so the widget has to redraw once a minute. `ACTION_TIME_TICK`
cannot be delivered to a manifest declared receiver, and Android 12 clamps inexact alarm windows
to ten minutes, so a self rescheduling exact alarm is the only way to keep a minute hand honest.
The alarm is `RTC`, not `RTC_WAKEUP` — it never wakes the device, it just redraws at the next
wake.

Declining the permission is not fatal. The redraw then happens whenever Android gets round to the
inexact alarm, plus every 30 minutes from `updatePeriodMillis`, and the digital time in the
widget is a `TextClock` that ticks by itself regardless.

## Customising

- `Config.displayZone()` — the dial is drawn in the phone's own zone, so it agrees with the
  status bar clock. Return `ZoneId.of("UTC")` to pin it to GMT+0, matching the web app's default
  setting. It is read on every redraw, so travelling or a clock change is picked up on the next
  tick.
- `Config.WEB_APP_URL` — where tapping the widget goes.
- `MARKETS` in `Markets.kt` — add, remove, or re-time an exchange. Keep it under about 16 entries;
  each band is a 9 unit ring inside a 157 unit radius, so the innermost band runs out of room
  after that.

## What differs from the web app

The minute ring labels and the second hand are dropped — both are illegible at widget size, and a
second hand would mean redrawing every second. Per market visibility and the light theme are not
carried over; the widget always draws the dark palette, which reads better over a wallpaper.

## Layout

```
app/src/main/java/com/marketsessions/widget/
  Config.kt                 constants worth changing
  Markets.kt                the exchange table, session maths, status line     (pure JVM, no Android)
  DialRenderer.kt           the dial, drawn to a Bitmap on a 400 unit grid
  MarketWidgetProvider.kt   the AppWidgetProvider, sizes and pushes RemoteViews
  WidgetScheduler.kt        the once a minute redraw alarm
  MainActivity.kt           add the widget, grant alarms, open the web app
```

`Markets.kt` deliberately has no Android imports, so the session logic can be compiled and
exercised on a plain JVM.
