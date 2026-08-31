# Market Sessions — Android home screen widget

A native widget that draws the same 24 hour dial as the web app: one band per exchange, green
while it is trading, grey for the session coming up, with hour and minute hands over the top.

It is an app as well as a widget. The app's main screen is the sessions view itself — the same
page the web app serves, copied into the APK at build time and run from there, so it needs no
network and no browser. Tapping the widget or one of its notifications opens that screen; the
hosted page stays available behind an explicit "open in a browser" button in the settings screen,
reached from the overflow menu.

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
4. Open **Market Sessions**, tap the button for the size you want, and grant exact alarms if the
   app asks.

The workflow also runs automatically on any push to `main` that touches `android/`.

## Building on a desktop

Open the `android/` directory in Android Studio and press Run, or:

```
cd android
./gradlew assembleDebug        # app/build/outputs/apk/debug/app-debug.apk
./gradlew installDebug         # straight onto an attached device
```

## Signing

The APK is signed with a key restored from the `ANDROID_KEYSTORE_BASE64` and
`ANDROID_KEYSTORE_PASSWORD` repository secrets, under the alias `market-sessions`. That matters
for more than tidiness: a debug APK is otherwise signed with whatever throwaway key the build
machine has, those differ between machines, and Android refuses to install an APK over one signed
by a different key — the update fails with "package conflicts with an existing package".

Without the secrets — a local checkout, or a fork — the build falls back to the usual debug key
and prints a warning. It still runs; its APKs just will not install over one signed by another
key.

The signing certificate is printed at the end of every build, so the log says which key was used.
The key is self signed and fine for sideloading; publishing to Play would need its own.

## Sizes

Three entries appear in the launcher's widget picker, because the picker lists providers rather
than sizes. Each drops decoration rather than shrinking it, so the smaller ones stay legible:

| Picker entry | Cells | What it draws |
| --- | --- | --- |
| Market Sessions 3×3 | 3×3, min 180dp | The full dial: hour ring, grid, band labels, hands, digital clock and status line |
| Market Sessions 2×2 | 2×2, min 110dp | Hour ring at six hour intervals, no grid, no band labels, hands, one short status line |
| Market Sessions 1×1 | 1×1, min 40dp | Bands and hands only, zoomed into the space the hour ring would have taken |

All three stay resizable after placing, and all three are redrawn by the one alarm the 3×3
provider owns, so adding more widgets does not add more wakeups.

The dp minimums follow Android's `70 × cells − 30` cell formula, so each entry lands on whole
cells in a standard launcher grid.

## Alerts

Optional notifications a settable number of minutes before and after each bell. Open the app and
tick **Notify me about sessions**, then choose:

- **Minutes before** and **minutes after** — either can be zero to turn that side off; both zero
  schedules nothing at all.
- **Opens** and **closes** — which bells count.
- **The markets** — nothing is selected to begin with, deliberately. All fourteen markets on both
  bells at both offsets would be over fifty notifications a day.

One alarm is outstanding at a time: the next alert due across every chosen market. When it fires,
everything owed since the last check is posted and the following alarm is set. That alarm is
`RTC_WAKEUP` — being told fifteen minutes before the open is worthless if it waits for the phone
to wake on its own — unlike the widget's tick, which deliberately does not wake the device.

A watermark records how far alerts have been consumed, so a late alarm still posts and never posts
twice. Anything more than thirty minutes stale is dropped: a phone that was off overnight should
not wake to a queue of bells it already missed.

Alerts need the notification permission (Android 13 and above asks on first enable) and the same
exact alarm permission the widget uses; without the latter they still arrive, just minutes late.

## Why the app asks for exact alarms

The hands move once a minute, so the widget has to redraw once a minute. `ACTION_TIME_TICK`
cannot be delivered to a manifest declared receiver, and Android 12 clamps inexact alarm windows
to ten minutes, so a self rescheduling exact alarm is the only way to keep a minute hand honest.
The alarm is `RTC`, not `RTC_WAKEUP` — it never wakes the device, it just redraws at the next
wake.

The app declares `SCHEDULE_EXACT_ALARM`, which is what makes the **Alarms & reminders** toggle in
system settings grantable at all — without the declaration that switch is greyed out. Apps
targeting API 34 and above are not granted it on install, so it starts off and you turn it on,
either from the button in the app or from Settings → Apps → Market Sessions → Alarms & reminders.

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
  DialRenderer.kt           the dial, drawn to a Bitmap on a 400 unit grid, at three detail levels
  MarketWidgetProvider.kt   the three providers, one per picker size, and the RemoteViews they push
  WidgetScheduler.kt        the once a minute redraw alarm
  SessionsActivity.kt       the sessions view, a WebView over the page held in assets
  MainActivity.kt           settings: add a widget of any size, grant permissions, tune alerts
  Alerts.kt                 what to be notified about and when                    (pure JVM, no Android)
  AlertScheduler.kt         the alert alarm and the notifications it posts
  AlertStore.kt             alert settings and the fired-up-to watermark
  AlertReceiver.kt          the alarm, boot and clock change entry point
```

`Markets.kt` and `Alerts.kt` deliberately have no Android imports, so the session logic and the
whole alert schedule can be compiled and exercised on a plain JVM.

`index.html` and its icons are copied from the repository root into the app's assets by a Gradle
task, so the page in the app cannot drift from the page on Pages. Edit the one at the root.
