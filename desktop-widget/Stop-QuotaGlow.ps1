[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$settingsDirectory = Join-Path $env:LOCALAPPDATA 'QuotaGlow'
$pidPath = Join-Path $settingsDirectory 'widget.pid'

try {
    $stopEvent = [System.Threading.EventWaitHandle]::OpenExisting('Local\QuotaGlow.Widget.Stop')
    [void]$stopEvent.Set()
    $stopEvent.Dispose()
    Write-Host 'QuotaGlow was asked to close.'
    Start-Sleep -Seconds 3
} catch [System.Threading.WaitHandleCannotBeOpenedException] {
    # Older or hung instances may not expose the clean-stop event.
}

$remaining = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    ([string]$_.Name -match '^powershell(\.exe)?$') -and
    ([string]$_.CommandLine -match 'desktop-widget[\\/]QuotaGlow\.ps1(?:\s|"|$)')
})
foreach ($processInfo in $remaining) { Stop-Process -Id $processInfo.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
if ($remaining.Count -gt 0) { Write-Host "Force-stopped $($remaining.Count) remaining QuotaGlow instance(s)." }
else { Write-Host 'QuotaGlow is stopped.' }
