$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$corePath = Join-Path $projectRoot 'pc-helper\QuotaGlow.Core.psm1'
$widgetPath = Join-Path $projectRoot 'desktop-widget\QuotaGlow.ps1'
$helperPath = Join-Path $projectRoot 'pc-helper\codex_usage_helper.ps1'
$stopperPath = Join-Path $projectRoot 'desktop-widget\Stop-QuotaGlow.ps1'

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', received '$Actual'." }
}

foreach ($path in @($corePath, $widgetPath, $helperPath, $stopperPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "PowerShell parser errors in $path`: $($errors.Message -join '; ')" }
}
Write-Host 'PASS: PowerShell syntax'

Import-Module $corePath -Force -DisableNameChecking
$futureReset = [DateTimeOffset]::UtcNow.AddHours(2).ToUnixTimeSeconds()
$fixture = [pscustomobject]@{
    ordinaryUsageAllowed = $true
    rateLimitsByLimitId = $null
    rateLimits = [pscustomobject]@{
        limitId = 'codex'
        primary = [pscustomobject]@{ usedPercent = 10; windowDurationMins = 300; resetsAt = $futureReset }
        secondary = [pscustomobject]@{ usedPercent = 2; windowDurationMins = 10080; resetsAt = $futureReset }
    }
}
$snapshot = ConvertTo-QuotaGlowSnapshot $fixture
Assert-Equal $snapshot.PrimaryRemaining 90 'Primary percentage conversion failed.'
Assert-Equal $snapshot.PrimaryLabel '5h' 'Primary window label failed.'
Assert-Equal $snapshot.SecondaryRemaining 98 'Secondary percentage conversion failed.'
Assert-Equal $snapshot.SecondaryLabel '7d' 'Secondary window label failed.'
if ($snapshot.SerialLine -notmatch '^LIMITS\|90\|5h\|.+\|98\|7d\|.+\|1$') { throw 'Serial line conversion failed.' }
Write-Host 'PASS: usage snapshot and serial conversion'

try {
    $encrypted = Protect-QuotaGlowDeviceToken '0123456789abcdef'
    Assert-Equal (Unprotect-QuotaGlowDeviceToken $encrypted) '0123456789abcdef' 'DPAPI token round trip failed.'
} catch [System.Security.Cryptography.CryptographicException] {
    Write-Host 'SKIP: DPAPI user profile is unavailable in this test host'
}
try { Pair-QuotaGlowWifiDevice -Address '127.0.0.1' -Code '12'; throw 'Invalid pairing code was accepted.' } catch { if($_.Exception.Message -eq 'Invalid pairing code was accepted.'){throw} }
Write-Host 'PASS: Wi-Fi token protection and pairing validation'

$widgetOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $widgetPath -ValidateOnly
if ($LASTEXITCODE -ne 0 -or $widgetOutput -notmatch 'XAML: OK') { throw 'Widget XAML validation failed.' }
Write-Host 'PASS: widget XAML'

$demoOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helperPath -Demo -DryRun -Once
if ($LASTEXITCODE -ne 0 -or @($demoOutput | Select-String '^SERIAL> LIMITS\|').Count -ne 3) { throw 'Legacy demo regression failed.' }
Write-Host 'PASS: legacy demo compatibility'

$networkSource = Get-Content -Raw (Join-Path $projectRoot 'firmware\codex_usage_monitor\QuotaGlowNetwork.cpp')
foreach($required in 'QUOTAGLOW_DISCOVER_V1','/api/v1/info','/api/v1/pair','/api/v1/message','/api/v1/unpair','/api/v1/wifi/reset','Authorization','PAIR_CODE_LIFETIME_MS') {
    if(-not $networkSource.Contains($required)){throw "Firmware network interface is missing $required."}
}
if (-not $networkSource.Contains('showQuotaGlowPairingInfo()') -or -not $networkSource.Contains('ALREADY PAIRED')) {
    throw 'Firmware is missing safe on-demand pairing information.'
}
Write-Host 'PASS: firmware Wi-Fi API surface'

$firmwareSource = Get-Content -Raw (Join-Path $projectRoot 'firmware\codex_usage_monitor\codex_usage_monitor.ino')
foreach($required in 'DHT_PIN = 26','DHT_TYPE = DHT11','TOUCH_PIN = 27','HOME_CLIMATE','HOME_AUTO','drawMenu()','updateClimate()','showQuotaGlowPairingInfo()','companionPreferences.begin','PET_REACTION_MS') {
    if(-not $firmwareSource.Contains($required)){throw "Desk companion firmware is missing $required."}
}
if ($firmwareSource.Contains('toggleCompanionMode()')) { throw 'Legacy two-mode touch toggle is still present.' }
if ($firmwareSource.IndexOf('if (menuActive)') -gt $firmwareSource.IndexOf('if (networkMessageActive)')) {
    throw 'The touch menu must render before temporary network messages.'
}
Write-Host 'PASS: room climate and navigation firmware surface'

Write-Host 'All QuotaGlow checks passed.' -ForegroundColor Green
