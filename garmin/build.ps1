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
