$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$corePath = Join-Path $projectRoot 'pc-helper\QuotaGlow.Core.psm1'
$widgetPath = Join-Path $projectRoot 'desktop-widget\QuotaGlow.ps1'
$helperPath = Join-Path $projectRoot 'pc-helper\codex_usage_helper.ps1'

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', received '$Actual'." }
}

foreach ($path in @($corePath, $widgetPath, $helperPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "PowerShell parser errors in $path`: $($errors.Message -join '; ')" }
}
Write-Host 'PASS: PowerShell syntax'

Import-Module $corePath -Force
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

$widgetOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $widgetPath -ValidateOnly
if ($LASTEXITCODE -ne 0 -or $widgetOutput -notmatch 'XAML: OK') { throw 'Widget XAML validation failed.' }
Write-Host 'PASS: widget XAML'

$demoOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helperPath -Demo -DryRun -Once
if ($LASTEXITCODE -ne 0 -or @($demoOutput | Select-String '^SERIAL> LIMITS\|').Count -ne 3) { throw 'Legacy demo regression failed.' }
Write-Host 'PASS: legacy demo compatibility'

Write-Host 'All QuotaGlow checks passed.' -ForegroundColor Green
