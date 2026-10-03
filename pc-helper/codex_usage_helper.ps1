[CmdletBinding()]
param(
    [string]$Port,
    [switch]$Demo,
    [switch]$DryRun,
    [switch]$Once,
    [ValidateRange(10, 3600)]
    [int]$RefreshSeconds = 60
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'QuotaGlow.Core.psm1') -Force -DisableNameChecking
$appServer = $null
$serialPort = $null

function Write-Info([string]$Message) { Write-Host "[Codex Monitor] $Message" }

function Send-LegacyLine([string]$Line) {
    if ($DryRun) { Write-Host "SERIAL> $Line" }
    else { Send-QuotaGlowSerialLine -SerialPort $serialPort -Line $Line }
}

try {
    Write-Info 'Starting ESP32 Codex Usage Monitor helper.'
    if (-not $DryRun) {
        if ([string]::IsNullOrWhiteSpace($Port)) { throw 'No COM port was supplied. Set COM_PORT in start_monitor.cmd.' }
        $serialPort = Open-QuotaGlowSerialPort -Port $Port
        Write-Info "Connected to ESP32 on $Port at 115200 baud."
    }

    if ($Demo) {
        Write-Info 'Demo mode is active; no Codex account data will be requested.'
        $demoLines = @(
            'LIMITS|0|5h|2h18m|100|7d|3d04h|1',
            'LIMITS|50|5h|2h17m|50|7d|3d04h|1',
            'LIMITS|100|5h|2h16m|0|7d|3d04h|1'
        )
        for ($index = 0; $index -lt $demoLines.Count; $index++) {
            Send-LegacyLine $demoLines[$index]
            Write-Info "Sent demo sample $($index + 1) of $($demoLines.Count)."
            if (-not $Once) { Start-Sleep -Seconds 5 }
        }
        Write-Info 'Demo messages sent successfully.'
        exit 0
    }

    $appServer = Start-QuotaGlowAppServer
    Write-Info "Using Codex from $($appServer.Executable)"
    Write-Info 'Connected to the local Codex app-server.'
    do {
        try {
            $snapshot = Get-QuotaGlowUsageSnapshot -Client $appServer
            if ($null -eq $snapshot) {
                Send-LegacyLine 'STATUS|NO_LIMIT_DATA'
                Write-Warning 'Codex returned no primary rate-limit window.'
            } else {
                Send-LegacyLine $snapshot.SerialLine
                Write-Info "Usage updated at $($snapshot.RefreshedAt.ToString('HH:mm:ss'))."
            }
        } catch {
            Send-LegacyLine 'STATUS|CODEX_ERROR'
            Write-Warning $_.Exception.Message
        }
        if (-not $Once) { Start-Sleep -Seconds $RefreshSeconds }
    } while (-not $Once)
} catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'See README.md for troubleshooting.' -ForegroundColor Yellow
    exit 1
} finally {
    Close-QuotaGlowSerialPort -SerialPort $serialPort
    Stop-QuotaGlowAppServer -Client $appServer
}
