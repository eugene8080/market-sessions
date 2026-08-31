# Garmin: what a watch version would take

Findings from investigating a Connect IQ glance and app for the fenix 8 and tactix 8, showing the
same dial as the phone widget. **Not built.** One thing blocks it, recorded here so the question
does not have to be asked again.

## Blocked on device targets

Connect IQ compiles against per device definition files. A freshly downloaded SDK contains none:

```
$ monkeyc -d fenix843mm ...   ERROR: Invalid device id specified: 'fenix843mm'.
$ monkeyc -d nosuchwatch ...  ERROR: Invalid device id specified: 'nosuchwatch'.
```

A real device id the SDK ships reference art for fails exactly as a nonsense one does, so this is
not a matter of finding the right identifier. Device files are fetched by the SDK Manager, which
is a desktop GUI (it wants `libsecret` and `libwebkit2gtk`, and will not start on a build runner).

The endpoint it fetches them from, read out of the binary with `strings`:

```
%s/ciq-product-onboarding/devices?sdkManagerVersion=%d.%d.%d
%s/ciq-product-onboarding/devices/%s/ciqInfo
```

Probing each host the binary knows:

| Host | Result |
| --- | --- |
| `api.gcs.garmin.com` | **401** — the real endpoint, and it needs an account |
| `services.garmin.com` | 404 |
| `developer.garmin.com` | 404 |

So device targets require a signed in Garmin session. Automating that login in CI is not something
to do with someone's account credentials, so the practical routes are:

1. **Run the SDK Manager once on any computer.** It writes device files into
   `~/.Garmin/ConnectIQ/Devices/`. Those files then let CI compile indefinitely. Note they are
   Garmin's to license: putting them in a public repository is probably not permitted, so they
   would want a private repository or a private artifact store.
2. **Wait for desktop access** and build there directly.

## What is not blocked

Everything else checked out:

| Question | Answer |
| --- | --- |
| Can CI reach Garmin? | Yes, every host answers |
| Latest SDK | Connect IQ 9.2.0, released 9 June 2026 |
| Does the Linux SDK install headlessly? | Yes |
| Does the compiler run? | Yes — `Connect IQ Compiler version: 9.2.0` |
| Does the SDK name the watches? | Yes — `fenix843mm` appears in its device reference data |

## The time zone problem, solved

Connect IQ has no IANA database on device: a watch knows its own offset and UTC, nothing more. So
exchange hours need hand written daylight saving rules. `tools/` holds those rules and checks them
against Java's real tz data:

```
$ cd tools && gradle run

compared hand-rolled rules against the IANA database
  zones:       13          (14 markets; NASDAQ shares New York's zone)
  span:        2026-01-01 to 2031-01-01, hourly
  comparisons: 569712
  mismatches:  0

every zone agrees at every hour for five years
```

Four rule families cover all fourteen markets:

| Rule | Markets | Transition |
| --- | --- | --- |
| EU | London, Frankfurt, Zurich, Paris, Amsterdam | last Sunday March / October, 01:00 UTC |
| US | New York, NASDAQ, Toronto | 2nd Sunday March / 1st Sunday November |
| AU | Sydney | 1st Sunday October / 1st Sunday April |
| none | Tokyo, Singapore, Hong Kong, Shanghai, Mumbai | — |

These are five years of current law, not physics. If a country changes its rules the watch needs a
new build, where the phone gets the correction from the OS. Re-run the check to find out.

## Links, checked

| Link | Status |
| --- | --- |
| [SDK downloads, all platforms](https://developer.garmin.com/connect-iq/sdk/) | 200 |
| [Connect IQ overview](https://developer.garmin.com/connect-iq/overview/) | 200 |
| [SDK Manager, Windows](https://developer.garmin.com/downloads/connect-iq/sdk-manager/connectiq-sdk-manager-windows.zip) | 200 |
| [SDK Manager, Linux](https://developer.garmin.com/downloads/connect-iq/sdk-manager/connectiq-sdk-manager-linux.zip) | 200 |
| SDK Manager, macOS | no predictable direct url; take it from the SDK page |
| [SDK version index](https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json) | 200, lists every SDK and its per platform filename |
| `apps.garmin.com/en-US/developer/dashboard` | 403 — the store dashboard exists but needs a signed in account |

The device files the build needs land in `%APPDATA%\Garmin\ConnectIQ\Devices` on Windows, or
`~/.Garmin/ConnectIQ/Devices` on macOS and Linux, once the SDK Manager has been signed in to and
the fenix 8 and tactix 8 ticked in its Devices tab.

## Sketch of the app, when it happens

A device app with a glance view, one build covering both watches. `Dc.drawArc` maps closely onto
the band drawing in `index.html`, and a round screen suits the dial better than a phone does. The
glance has a tighter memory budget than the app, so it would carry the open count and the next
bell rather than the whole dial.

Alerts do not need building: phone notifications from the Android app already mirror to the watch
over Garmin Connect.
