function Find-QuotaGlowCodexExecutable {
    $pathCommand = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $pathCommand) { return $pathCommand.Source }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $desktopBin = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
        if (Test-Path -LiteralPath $desktopBin) {
            $desktopCodex = Get-ChildItem -LiteralPath $desktopBin -Filter 'codex.exe' -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($null -ne $desktopCodex) { return $desktopCodex.FullName }
        }
    }

    throw 'Codex was not found. Install or update the Codex desktop app, then try again.'
}

function Write-QuotaGlowAppServerJson {
    param([Parameter(Mandatory)]$Client, [Parameter(Mandatory)]$Value)
    $json = $Value | ConvertTo-Json -Compress -Depth 20
    $Client.Process.StandardInput.WriteLine($json)
    $Client.Process.StandardInput.Flush()
}

function Read-QuotaGlowAppServerLine {
    param([Parameter(Mandatory)]$Client, [int]$TimeoutSeconds = 30)
    $task = $Client.Process.StandardOutput.ReadLineAsync()
    if (-not $task.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
        throw "Codex app-server did not respond within $TimeoutSeconds seconds."
    }
    if ($null -eq $task.Result) { throw 'Codex app-server closed unexpectedly.' }
    return $task.Result
}

function Invoke-QuotaGlowAppServerRequest {
    param([Parameter(Mandatory)]$Client, [Parameter(Mandatory)][string]$Method, $Params)
    $id = $Client.NextRequestId
    $Client.NextRequestId++
    Write-QuotaGlowAppServerJson -Client $Client -Value ([ordered]@{ id = $id; method = $Method; params = $Params })

    while ($true) {
        $line = Read-QuotaGlowAppServerLine -Client $Client
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $message = $line | ConvertFrom-Json } catch { continue }
        if ($null -ne $message.id -and [string]$message.id -eq [string]$id) {
            if ($null -ne $message.error) {
                $detail = $message.error | ConvertTo-Json -Compress -Depth 10
                throw "Codex app-server returned an error: $detail"
            }
            return $message.result
        }
    }
}

function Start-QuotaGlowAppServer {
    $codexExecutable = Find-QuotaGlowCodexExecutable
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $codexExecutable
    $startInfo.Arguments = 'app-server --listen stdio://'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.CreateNoWindow = $true
    if ([string]::IsNullOrWhiteSpace($startInfo.EnvironmentVariables['HOME']) -and
        -not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $startInfo.EnvironmentVariables['HOME'] = $env:USERPROFILE
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'Could not start Codex app-server.' }

    $client = @{ Process = $process; NextRequestId = 1; Executable = $codexExecutable }
    try {
        $initializeParams = [ordered]@{
            clientInfo = [ordered]@{
                name = 'quotaglow'
                title = 'QuotaGlow'
                version = '1.1.0-dev'
            }
            capabilities = [ordered]@{ experimentalApi = $true }
        }
        [void](Invoke-QuotaGlowAppServerRequest -Client $client -Method 'initialize' -Params $initializeParams)
        Write-QuotaGlowAppServerJson -Client $client -Value ([ordered]@{ method = 'initialized' })
        return $client
    } catch {
        Stop-QuotaGlowAppServer -Client $client
        throw
    }
}

function Stop-QuotaGlowAppServer {
    param($Client)
    if ($null -eq $Client -or $null -eq $Client.Process) { return }
    try { $Client.Process.StandardInput.Close() } catch {}
    try {
        if (-not $Client.Process.HasExited) {
            $Client.Process.Kill()
            [void]$Client.Process.WaitForExit(3000)
        }
    } catch {}
    try { $Client.Process.Dispose() } catch {}
}

function Get-QuotaGlowWindowLabel {
    param($Window)
    if ($null -eq $Window -or $null -eq $Window.windowDurationMins) { return '-' }
    $minutes = [long]$Window.windowDurationMins
    if ($minutes -ge 1440 -and $minutes % 1440 -eq 0) { return "$(($minutes / 1440))d" }
    if ($minutes -ge 60 -and $minutes % 60 -eq 0) { return "$(($minutes / 60))h" }
    return "${minutes}m"
}

function Get-QuotaGlowResetCountdown {
    param($Window)
    if ($null -eq $Window -or $null -eq $Window.resetsAt) { return '--' }
    $seconds = [long]$Window.resetsAt - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($seconds -le 0) { return 'now' }
    $minutes = [long][Math]::Ceiling($seconds / 60.0)
    $days = [Math]::Floor($minutes / 1440)
    $hours = [Math]::Floor(($minutes % 1440) / 60)
    $remainingMinutes = $minutes % 60
    if ($days -gt 0) { return "${days}d${hours}h" }
    if ($hours -gt 0) { return "${hours}h${remainingMinutes}m" }
    return "${remainingMinutes}m"
}

function Get-QuotaGlowRemainingPercent {
    param($Window)
    if ($null -eq $Window -or $null -eq $Window.usedPercent) { return -1 }
    return [Math]::Max(0, [Math]::Min(100, 100 - [int]$Window.usedPercent))
}

function Select-QuotaGlowCodexRateLimit {
    param([Parameter(Mandatory)]$Response)
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

function ConvertTo-QuotaGlowSnapshot {
    param([Parameter(Mandatory)]$Response)
    $limit = Select-QuotaGlowCodexRateLimit -Response $Response
    if ($null -eq $limit -or $null -eq $limit.primary) { return $null }

    $primaryRemaining = Get-QuotaGlowRemainingPercent $limit.primary
    $primaryLabel = Get-QuotaGlowWindowLabel $limit.primary
    $primaryReset = Get-QuotaGlowResetCountdown $limit.primary
    $secondaryRemaining = Get-QuotaGlowRemainingPercent $limit.secondary
    $secondaryLabel = Get-QuotaGlowWindowLabel $limit.secondary
    $secondaryReset = Get-QuotaGlowResetCountdown $limit.secondary
    $allowed = $Response.ordinaryUsageAllowed -ne $false
    $allowedNumber = if ($allowed) { 1 } else { 0 }
    $serialLine = "LIMITS|$primaryRemaining|$primaryLabel|$primaryReset|$secondaryRemaining|$secondaryLabel|$secondaryReset|$allowedNumber"

    [pscustomobject]@{
        PrimaryRemaining = $primaryRemaining
        PrimaryLabel = $primaryLabel
        PrimaryReset = $primaryReset
        SecondaryRemaining = $secondaryRemaining
        SecondaryLabel = $secondaryLabel
        SecondaryReset = $secondaryReset
        UsageAllowed = $allowed
        SerialLine = $serialLine
        RefreshedAt = [DateTime]::Now
    }
}

function Get-QuotaGlowUsageSnapshot {
    param([Parameter(Mandatory)]$Client)
    $response = Invoke-QuotaGlowAppServerRequest -Client $Client -Method 'account/rateLimits/read' -Params @{
        excludeResetCreditDetails = $true
        supportsLunaReserve = $false
    }
    return ConvertTo-QuotaGlowSnapshot -Response $response
}

function Get-QuotaGlowSerialPorts {
    return @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object)
}

function Open-QuotaGlowSerialPort {
    param([Parameter(Mandatory)][string]$Port)
    if ($Port -notin (Get-QuotaGlowSerialPorts)) { throw "Port $Port was not found." }
    $serial = [System.IO.Ports.SerialPort]::new($Port, 115200, 'None', 8, 'One')
    $serial.NewLine = "`n"
    $serial.WriteTimeout = 3000
    $serial.DtrEnable = $false
    $serial.RtsEnable = $false
    $serial.Open()
    Start-Sleep -Milliseconds 1500
    return $serial
}

function Send-QuotaGlowSerialLine {
    param([Parameter(Mandatory)]$SerialPort, [Parameter(Mandatory)][string]$Line)
    if ($Line.Contains("`r") -or $Line.Contains("`n")) { throw 'Refusing to send a multi-line serial message.' }
    if (-not $SerialPort.IsOpen) { throw 'The serial port is not open.' }
    $SerialPort.WriteLine($Line)
}

function Close-QuotaGlowSerialPort {
    param($SerialPort, [switch]$PowerOff)
    if ($null -eq $SerialPort) { return }
    if ($PowerOff) {
        try { Send-QuotaGlowSerialLine -SerialPort $SerialPort -Line 'POWER|OFF' } catch {}
    }
    try { if ($SerialPort.IsOpen) { $SerialPort.Close() } } catch {}
    try { $SerialPort.Dispose() } catch {}
}

Export-ModuleMember -Function Find-QuotaGlowCodexExecutable, Start-QuotaGlowAppServer, Stop-QuotaGlowAppServer, Get-QuotaGlowUsageSnapshot, ConvertTo-QuotaGlowSnapshot, Get-QuotaGlowSerialPorts, Open-QuotaGlowSerialPort, Send-QuotaGlowSerialLine, Close-QuotaGlowSerialPort
