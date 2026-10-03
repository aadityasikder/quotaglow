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
$script:NextRequestId = 1
$script:AppServer = $null
$script:SerialPort = $null

function Write-Info([string]$Message) {
    Write-Host "[Codex Monitor] $Message"
}

function Write-AppServerJson($Value) {
    $json = $Value | ConvertTo-Json -Compress -Depth 20
    $script:AppServer.StandardInput.WriteLine($json)
    $script:AppServer.StandardInput.Flush()
}

function Read-AppServerLine([int]$TimeoutSeconds = 30) {
    $task = $script:AppServer.StandardOutput.ReadLineAsync()
    if (-not $task.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
        throw "Codex app-server did not respond within $TimeoutSeconds seconds."
    }
    if ($null -eq $task.Result) {
        throw 'Codex app-server closed unexpectedly.'
    }
    return $task.Result
}

function Invoke-AppServerRequest([string]$Method, $Params) {
    $id = $script:NextRequestId
    $script:NextRequestId++
    $request = [ordered]@{ id = $id; method = $Method; params = $Params }
    Write-AppServerJson $request

    while ($true) {
        $line = Read-AppServerLine
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $message = $line | ConvertFrom-Json
        } catch {
            continue
        }
        if ($null -ne $message.id -and [string]$message.id -eq [string]$id) {
            if ($null -ne $message.error) {
                $detail = $message.error | ConvertTo-Json -Compress -Depth 10
                throw "Codex app-server returned an error: $detail"
            }
            return $message.result
        }
    }
}

function Find-CodexExecutable {
    $pathCommand = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $pathCommand) {
        return $pathCommand.Source
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $desktopBin = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
        if (Test-Path -LiteralPath $desktopBin) {
            $desktopCodex = Get-ChildItem -LiteralPath $desktopBin -Filter 'codex.exe' -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($null -ne $desktopCodex) {
                return $desktopCodex.FullName
            }
        }
    }

    throw 'Codex was not found. Install or update the Codex desktop app, then restart this helper.'
}

function Start-CodexAppServer {
    $codexExecutable = Find-CodexExecutable
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $codexExecutable
    $startInfo.Arguments = 'app-server --listen stdio://'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.CreateNoWindow = $true
    # Some Windows launchers provide USERPROFILE but omit HOME. Codex accepts
    # the same real profile directory through HOME when locating its sign-in.
    if ([string]::IsNullOrWhiteSpace($startInfo.EnvironmentVariables['HOME']) -and
        -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $startInfo.EnvironmentVariables['HOME'] = $env:USERPROFILE
    }

    $script:AppServer = [System.Diagnostics.Process]::new()
    $script:AppServer.StartInfo = $startInfo
    if (-not $script:AppServer.Start()) {
        throw 'Could not start Codex app-server.'
    }
    Write-Info "Using Codex from $codexExecutable"

    $initializeParams = [ordered]@{
        clientInfo = [ordered]@{
            name = 'esp32_codex_usage_monitor'
            title = 'ESP32 Codex Usage Monitor'
            version = '1.0.0'
        }
        capabilities = [ordered]@{ experimentalApi = $true }
    }
    [void](Invoke-AppServerRequest -Method 'initialize' -Params $initializeParams)
    Write-AppServerJson ([ordered]@{ method = 'initialized' })
    Write-Info 'Connected to the local Codex app-server.'
}

function Open-MonitorSerialPort {
    if ($DryRun) { return }
    if ([string]::IsNullOrWhiteSpace($Port)) {
        throw 'No COM port was supplied. Set COM_PORT in start_monitor.cmd.'
    }

    $availablePorts = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($Port -notin $availablePorts) {
        $shownPorts = if ($availablePorts.Count -gt 0) { $availablePorts -join ', ' } else { 'none' }
        throw "Port $Port was not found. Available ports: $shownPorts"
    }

    $script:SerialPort = [System.IO.Ports.SerialPort]::new($Port, 115200, 'None', 8, 'One')
    $script:SerialPort.NewLine = "`n"
    $script:SerialPort.WriteTimeout = 3000
    $script:SerialPort.DtrEnable = $false
    $script:SerialPort.RtsEnable = $false
    $script:SerialPort.Open()
    Start-Sleep -Milliseconds 1500
    Write-Info "Connected to ESP32 on $Port at 115200 baud."
}

function Send-MonitorLine([string]$Line) {
    if ($Line.Contains("`r") -or $Line.Contains("`n")) {
        throw 'Refusing to send a multi-line serial message.'
    }
    if ($DryRun) {
        Write-Host "SERIAL> $Line"
    } else {
        $script:SerialPort.WriteLine($Line)
    }
}

function Get-WindowLabel($Window) {
    if ($null -eq $Window -or $null -eq $Window.windowDurationMins) { return '-' }
    $minutes = [long]$Window.windowDurationMins
    if ($minutes -ge 1440 -and $minutes % 1440 -eq 0) { return "$(($minutes / 1440))d" }
    if ($minutes -ge 60 -and $minutes % 60 -eq 0) { return "$(($minutes / 60))h" }
    return "${minutes}m"
}

function Get-ResetCountdown($Window) {
    if ($null -eq $Window -or $null -eq $Window.resetsAt) { return '--' }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $seconds = [long]$Window.resetsAt - $now
    if ($seconds -le 0) { return 'now' }
    $minutes = [long][Math]::Ceiling($seconds / 60.0)
    $days = [Math]::Floor($minutes / 1440)
    $hours = [Math]::Floor(($minutes % 1440) / 60)
    $remainingMinutes = $minutes % 60
    if ($days -gt 0) { return "${days}d${hours}h" }
    if ($hours -gt 0) { return "${hours}h${remainingMinutes}m" }
    return "${remainingMinutes}m"
}

function Get-RemainingPercent($Window) {
    if ($null -eq $Window -or $null -eq $Window.usedPercent) { return -1 }
    $used = [int]$Window.usedPercent
    return [Math]::Max(0, [Math]::Min(100, 100 - $used))
}

function Select-CodexRateLimit($Response) {
    if ($null -ne $Response.rateLimitsByLimitId) {
        $properties = @($Response.rateLimitsByLimitId.PSObject.Properties)
        $codexProperty = $properties | Where-Object {
            $_.Name -eq 'codex' -or $_.Value.limitId -eq 'codex' -or $_.Value.limitName -match 'Codex'
        } | Select-Object -First 1
        if ($null -ne $codexProperty) { return $codexProperty.Value }
        if ($properties.Count -gt 0) { return $properties[0].Value }
    }
    return $Response.rateLimits
}

function Convert-RateLimitsToSerialLine($Response) {
    $limit = Select-CodexRateLimit $Response
    if ($null -eq $limit -or $null -eq $limit.primary) { return $null }

    $primaryRemaining = Get-RemainingPercent $limit.primary
    $primaryLabel = Get-WindowLabel $limit.primary
    $primaryReset = Get-ResetCountdown $limit.primary
    $secondaryRemaining = Get-RemainingPercent $limit.secondary
    $secondaryLabel = Get-WindowLabel $limit.secondary
    $secondaryReset = Get-ResetCountdown $limit.secondary
    $allowed = if ($Response.ordinaryUsageAllowed -eq $false) { 0 } else { 1 }

    return "LIMITS|$primaryRemaining|$primaryLabel|$primaryReset|$secondaryRemaining|$secondaryLabel|$secondaryReset|$allowed"
}

function Stop-MonitorResources {
    if ($null -ne $script:SerialPort) {
        try { if ($script:SerialPort.IsOpen) { $script:SerialPort.Close() } } catch {}
        try { $script:SerialPort.Dispose() } catch {}
        $script:SerialPort = $null
    }
    if ($null -ne $script:AppServer) {
        try { $script:AppServer.StandardInput.Close() } catch {}
        try {
            if (-not $script:AppServer.HasExited) {
                $script:AppServer.Kill()
                $script:AppServer.WaitForExit(3000)
            }
        } catch {}
        try { $script:AppServer.Dispose() } catch {}
        $script:AppServer = $null
    }
}

try {
    Write-Info 'Starting ESP32 Codex Usage Monitor helper.'
    Open-MonitorSerialPort

    if ($Demo) {
        Write-Info 'Demo mode is active; no Codex account data will be requested.'
        $demoLines = @(
            'LIMITS|0|5h|2h18m|100|7d|3d04h|1',
            'LIMITS|50|5h|2h17m|50|7d|3d04h|1',
            'LIMITS|100|5h|2h16m|0|7d|3d04h|1'
        )
        $demoNumber = 0
        foreach ($line in $demoLines) {
            $demoNumber++
            Send-MonitorLine $line
            Write-Info "Sent demo sample $demoNumber of $($demoLines.Count)."
            if (-not $Once) { Start-Sleep -Seconds 5 }
        }
        Write-Info 'Demo messages sent successfully.'
        exit 0
    }

    Start-CodexAppServer
    do {
        try {
            $response = Invoke-AppServerRequest -Method 'account/rateLimits/read' -Params @{
                excludeResetCreditDetails = $true
                supportsLunaReserve = $false
            }
            $line = Convert-RateLimitsToSerialLine $response
            if ($null -eq $line) {
                Send-MonitorLine 'STATUS|NO_LIMIT_DATA'
                Write-Warning 'Codex returned no primary rate-limit window.'
            } else {
                Send-MonitorLine $line
                Write-Info "Usage updated at $(Get-Date -Format 'HH:mm:ss')."
            }
        } catch {
            Send-MonitorLine 'STATUS|CODEX_ERROR'
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
    Stop-MonitorResources
}
