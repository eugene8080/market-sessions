<#
.SYNOPSIS
    Builds Market Sessions for both tactix 8 variants and stages the handover folder.

.DESCRIPTION
    monkeyc drops its by-products next to whatever -o points at: a .prg.debug.xml symbol map, a
    -settings.json descriptor, and three directories of compiler intermediates. Pointing -o straight
    at the handover folder therefore fills it with files nobody is meant to copy, and the folder's
    whole job is to be unambiguous about what goes on the watch. So the compiler writes to bin\ and
    this script copies across only the things a person actually hands over.

    The symbol maps are kept, in bin\symbols\, because they are not junk: they are what turns an
    address in a crash log off the watch into a source file and a line number. They only decode the
    build they came from, so they are refreshed here in lockstep with the .prg files.

.PARAMETER SkipTests
    Skip the on-device unit tests. They need the simulator and take about a minute.
#>
[CmdletBinding()]
param(
    [switch] $SkipTests
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = $PSScriptRoot
$bin = Join-Path $root "bin"
$store = Join-Path $bin "store"
$symbols = Join-Path $bin "symbols"

# The SDK is versioned in its own directory name, so resolve whichever one is installed rather than
# pinning a version that will be wrong after the next SDK update.
$sdkRoot = Join-Path $env:APPDATA "Garmin\ConnectIQ\Sdks"
$sdk = Get-ChildItem -Path $sdkRoot -Directory -Filter "connectiq-sdk-*" |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $sdk) { throw "No Connect IQ SDK found under $sdkRoot" }

$monkeyc = Join-Path $sdk.FullName "bin\monkeyc.bat"
$monkeydo = Join-Path $sdk.FullName "bin\monkeydo.bat"
$key = Join-Path $env:USERPROFILE ".garmin-keys\developer_key.der"
if (-not (Test-Path $key)) { throw "Developer key not found at $key" }

# monkeyc is a Java program and does not find its own JDK.
$jdk = Get-ChildItem -Path "C:\Program Files\Microsoft" -Directory -Filter "jdk-*" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($jdk) { $env:Path = (Join-Path $jdk.FullName "bin") + ";" + $env:Path }

Write-Host "SDK: $($sdk.Name)" -ForegroundColor Cyan

# device id -> the name the file carries into the handover folder. Garmin has no tactix device
# profiles; the tactix 8 ships under the equivalent fenix part numbers, so the build targets are
# named for fenix and the handover files are named for what is engraved on the watch.
$targets = [ordered]@{
    "fenix847mm"      = "MarketSessions-tactix8-AMOLED-47mm-and-51mm"
    "fenix8solar51mm" = "MarketSessions-tactix8-SOLAR-51mm"
    "fr255"           = "MarketSessions-forerunner255-and-255-Music"
    "fr255s"          = "MarketSessions-forerunner255s-and-255s-Music"
}

# The Music variants are separate products to Connect IQ but identical displays, so they build from
# the same source and their binaries are interchangeable with the plain ones. Only the two screen
# sizes are handed over; naming the files for the screen rather than for four product ids keeps the
# folder honest about what a person actually has to choose between.
$aliases = [ordered]@{
    "fr255m"  = "fr255"
    "fr255sm" = "fr255s"
}

New-Item -ItemType Directory -Force -Path $bin, $store, $symbols | Out-Null

foreach ($device in $targets.Keys) {
    $handoverName = $targets[$device]
    $out = Join-Path $bin "$device.prg"

    Write-Host "Building $device ..." -NoNewline
    & $monkeyc -f (Join-Path $root "monkey.jungle") -d $device -o $out -y $key -r -w
    if ($LASTEXITCODE -ne 0) { throw "Build failed for $device" }
    Write-Host " ok" -ForegroundColor Green

    Copy-Item $out (Join-Path $store "$handoverName.prg") -Force
    Copy-Item "$out.debug.xml" (Join-Path $symbols "$handoverName.prg.debug.xml") -Force
}

# Compile the Music variants too. Nothing is staged from them — the handover file is the one named
# for the screen — but a product listed in the manifest that has never been compiled is a product
# nobody has checked.
foreach ($alias in $aliases.Keys) {
    Write-Host "Checking $alias ..." -NoNewline
    & $monkeyc -f (Join-Path $root "monkey.jungle") -d $alias -o (Join-Path $bin "$alias.prg") -y $key -r -w
    if ($LASTEXITCODE -ne 0) { throw "Build failed for $alias" }
    Write-Host " ok" -ForegroundColor Green
}

# The store package: every supported device in one signed bundle, for upload to Connect IQ.
Write-Host "Building store package ..." -NoNewline
$iq = Join-Path $bin "MarketSessions.iq"
& $monkeyc -f (Join-Path $root "monkey.jungle") -e -o $iq -y $key -w
if ($LASTEXITCODE -ne 0) { throw "Store package build failed" }
Write-Host " ok" -ForegroundColor Green
Copy-Item $iq (Join-Path $store "MarketSessions.iq") -Force

if (-not $SkipTests) {
    Write-Host "Running on-device tests (needs the simulator) ..."
    $tests = Join-Path $bin "tests.prg"
    & $monkeyc -f (Join-Path $root "monkey.jungle") -d fenix847mm -o $tests -y $key --unit-test
    if ($LASTEXITCODE -ne 0) { throw "Test build failed" }

    if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath (Join-Path $sdk.FullName "bin\connectiq.bat") -NoNewWindow
        Start-Sleep -Seconds 15
    }
    # The flag is /t, not -t: monkeydo takes Windows-style switches.
    & $monkeydo $tests fenix847mm /t
}

# WHICH-FILE.txt is generated rather than kept by hand, because it names the very files this script
# produces. Written once by hand, it went stale the first time a device was added.
$which = @"
Market Sessions — sideloading
=============================

Built: $(Get-Date -Format 'yyyy-MM-dd')

Everything in this folder is either copied to a watch or uploaded to the
store. Nothing here is a build by-product — build.ps1 keeps it that way.

Copy ONE .prg into  \GARMIN\APPS\  on the watch over USB. Nothing else goes
on the device.

  MarketSessions-tactix8-AMOLED-47mm-and-51mm.prg
      tactix 8, both 47mm and 51mm. Glossy, vivid AMOLED screen.

  MarketSessions-tactix8-SOLAR-51mm.prg
      tactix 8 Solar only. Matte screen with a solar ring around the display.

  MarketSessions-forerunner255-and-255-Music.prg
      Forerunner 255 and 255 Music — the 46mm one.

  MarketSessions-forerunner255s-and-255s-Music.prg
      Forerunner 255S and 255S Music — the 41mm one.

Both tactix models come in 51mm, so size does not tell them apart; the screen
does. The two Forerunners are the other way round: same screen, different size.
On any of them, Settings > System > About names the model outright.

The Music editions take the same file as the plain ones. The display is
identical and that is all the app cares about.

MarketSessions.iq is for submitting to the Connect IQ store. It is not used
for sideloading. The .png files are the store listing screenshots. Neither
goes on a watch.

On the watch: START on the glance opens the dial. From the dial, DOWN opens
the scrolling list of every market, and BACK returns.

Settings: a sideloaded app may never appear in Garmin Connect's settings
list, so the theme and session colour are also on the watch — open the app
and press MENU.

Reinstalling: copy the new .prg over the old one, same name, same folder.
Your theme and session colour survive the swap.

If the app ever crashes on the watch, the log it leaves under
\GARMIN\APPS\LOGS\ only names raw addresses. The symbol maps in ..\symbolsturn those into a file and a line number, and they only decode the build they
were made with — so keep the pair together.
"@
Set-Content -Path (Join-Path $store "WHICH-FILE.txt") -Value $which -Encoding UTF8

Write-Host ""
Write-Host "Handover folder — these are the files you copy:" -ForegroundColor Cyan
Get-ChildItem $store | Sort-Object Name | Format-Table Name, @{ N = "KB"; E = { [math]::Round($_.Length / 1KB, 1) } } -AutoSize
Write-Host "Crash-log symbols (not for the watch): $symbols" -ForegroundColor DarkGray

# The two listing screenshots are captured from the simulator by hand and are not rebuilt here,
# so they can go stale after a visual change without anything complaining. Say so.
foreach ($shot in @("store-dial-454.png", "store-glance-454.png")) {
    $path = Join-Path $store $shot
    if (-not (Test-Path $path)) {
        Write-Host "MISSING: $shot — capture it from the simulator before submitting." -ForegroundColor Yellow
    } elseif ((Get-Item $path).LastWriteTime -lt (Get-Item (Join-Path $store "MarketSessions.iq")).LastWriteTime.AddMinutes(-10)) {
        Write-Host "STALE: $shot predates this build — recapture it if the dial changed." -ForegroundColor Yellow
    }
}
