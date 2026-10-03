[CmdletBinding()]
param([int]$RefreshSeconds = 60, [switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
$script:WidgetScriptPath = $PSCommandPath
$projectRoot = Split-Path -Parent $PSScriptRoot
$coreModule = Join-Path $projectRoot 'pc-helper\QuotaGlow.Core.psm1'
Import-Module $coreModule -Force

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$settingsDirectory = Join-Path $env:LOCALAPPDATA 'QuotaGlow'
$settingsPath = Join-Path $settingsDirectory 'settings.json'
$startupRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupName = 'QuotaGlow'
$script:SerialPort = $null
$script:LastSnapshot = $null
$script:IsPaused = $false
$script:LoadingSettings = $true
$script:Closing = $false

function Read-WidgetSettings {
    $defaults = [ordered]@{ Port = ''; Left = $null; Top = $null; StartWithWindows = $false }
    try {
        if (Test-Path -LiteralPath $settingsPath) {
            $saved = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
            if ($null -ne $saved.Port) { $defaults.Port = [string]$saved.Port }
            if ($null -ne $saved.Left) { $defaults.Left = [double]$saved.Left }
            if ($null -ne $saved.Top) { $defaults.Top = [double]$saved.Top }
            if ($null -ne $saved.StartWithWindows) { $defaults.StartWithWindows = [bool]$saved.StartWithWindows }
        }
    } catch {}
    return [pscustomobject]$defaults
}

function Save-WidgetSettings {
    try {
        if (-not (Test-Path -LiteralPath $settingsDirectory)) {
            [void](New-Item -ItemType Directory -Path $settingsDirectory -Force)
        }
        [ordered]@{
            Port = [string]$PortCombo.SelectedItem
            Left = [Math]::Round($Window.Left, 0)
            Top = [Math]::Round($Window.Top, 0)
            StartWithWindows = [bool]$StartupCheck.IsChecked
        } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    } catch {}
}

function Set-StartupPreference([bool]$Enabled) {
    if ($Enabled) {
        $value = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:WidgetScriptPath`""
        New-ItemProperty -Path $startupRegistryPath -Name $startupName -Value $value -PropertyType String -Force | Out-Null
    } else {
        Remove-ItemProperty -Path $startupRegistryPath -Name $startupName -ErrorAction SilentlyContinue
    }
}

function Test-WindowPosition([double]$Left, [double]$Top) {
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $bounds = $screen.WorkingArea
        if ($Left -ge ($bounds.Left - 40) -and $Left -lt ($bounds.Right - 40) -and
            $Top -ge ($bounds.Top - 40) -and $Top -lt ($bounds.Bottom - 40)) { return $true }
    }
    return $false
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="340" Height="448" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize">
  <Border CornerRadius="20" Background="#F51B1D28" BorderBrush="#3CFFFFFF" BorderThickness="1" Padding="18">
    <Border.Effect><DropShadowEffect BlurRadius="22" ShadowDepth="5" Opacity="0.55"/></Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="44"/><RowDefinition Height="62"/><RowDefinition Height="62"/>
        <RowDefinition Height="36"/><RowDefinition Height="38"/><RowDefinition Height="48"/>
        <RowDefinition Height="42"/><RowDefinition Height="32"/><RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Grid x:Name="DragArea" Grid.Row="0" Background="Transparent">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Ellipse x:Name="StatusDot" Width="10" Height="10" Fill="#F5A524" Margin="0,0,10,0"/>
          <TextBlock Text="QuotaGlow" Foreground="White" FontSize="20" FontWeight="SemiBold"/>
        </StackPanel>
        <Button x:Name="CloseButton" Grid.Column="1" Content="×" Width="30" Height="30" FontSize="18" Foreground="#BFC5D2" Background="Transparent" BorderThickness="0" Cursor="Hand"/>
      </Grid>
      <Grid Grid.Row="1" Margin="0,5,0,3">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
        <StackPanel><TextBlock x:Name="PrimaryLabel" Text="5h window" Foreground="#AEB6C8" FontSize="12"/><ProgressBar x:Name="PrimaryBar" Height="9" Margin="0,8,8,0" Maximum="100" Value="0" Foreground="#65D6AD" Background="#303440"/></StackPanel>
        <StackPanel Grid.Column="1"><TextBlock x:Name="PrimaryPercent" Text="--%" Foreground="White" FontSize="22" FontWeight="Bold" HorizontalAlignment="Right"/><TextBlock x:Name="PrimaryReset" Text="Reset --" Foreground="#8F98AA" FontSize="10" HorizontalAlignment="Right"/></StackPanel>
      </Grid>
      <Grid Grid.Row="2" Margin="0,5,0,3">
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="70"/></Grid.ColumnDefinitions>
        <StackPanel><TextBlock x:Name="SecondaryLabel" Text="7d window" Foreground="#AEB6C8" FontSize="12"/><ProgressBar x:Name="SecondaryBar" Height="9" Margin="0,8,8,0" Maximum="100" Value="0" Foreground="#8B8CFF" Background="#303440"/></StackPanel>
        <StackPanel Grid.Column="1"><TextBlock x:Name="SecondaryPercent" Text="--%" Foreground="White" FontSize="22" FontWeight="Bold" HorizontalAlignment="Right"/><TextBlock x:Name="SecondaryReset" Text="Reset --" Foreground="#8F98AA" FontSize="10" HorizontalAlignment="Right"/></StackPanel>
      </Grid>
      <Grid Grid.Row="3"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="92"/></Grid.ColumnDefinitions><TextBlock x:Name="LastRefresh" Text="Not refreshed yet" Foreground="#8F98AA" FontSize="11" VerticalAlignment="Center"/><Button x:Name="RefreshButton" Grid.Column="1" Content="↻  Refresh" Background="#343846" Foreground="White" BorderThickness="0" Padding="8" Cursor="Hand"/></Grid>
      <TextBlock x:Name="MessageText" Grid.Row="4" Text="Starting Codex service…" Foreground="#F5A524" FontSize="11" TextWrapping="Wrap" VerticalAlignment="Center"/>
      <Grid Grid.Row="5"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="42"/></Grid.ColumnDefinitions><ComboBox x:Name="PortCombo" Height="30" VerticalAlignment="Center" Background="#2A2D38" Foreground="White"/><Button x:Name="ScanButton" Grid.Column="1" Content="↻" Margin="7,0,0,0" Height="30" Background="#343846" Foreground="White" BorderThickness="0" Cursor="Hand" ToolTip="Rescan COM ports"/></Grid>
      <Button x:Name="ConnectButton" Grid.Row="6" Content="Connect Module" Background="#635BFF" Foreground="White" BorderThickness="0" Margin="0,4" FontWeight="SemiBold" Cursor="Hand"/>
      <CheckBox x:Name="StartupCheck" Grid.Row="7" Content="Start with Windows" Foreground="#BFC5D2" VerticalAlignment="Center"/>
      <Button x:Name="PowerButton" Grid.Row="8" Content="Pause Monitoring" Height="36" VerticalAlignment="Bottom" Background="#2C303B" Foreground="#FF8D8D" BorderThickness="0" Cursor="Hand"/>
    </Grid>
  </Border>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)
$names = 'DragArea','CloseButton','StatusDot','PrimaryLabel','PrimaryBar','PrimaryPercent','PrimaryReset','SecondaryLabel','SecondaryBar','SecondaryPercent','SecondaryReset','LastRefresh','RefreshButton','MessageText','PortCombo','ScanButton','ConnectButton','StartupCheck','PowerButton'
foreach ($name in $names) { Set-Variable -Name $name -Value $Window.FindName($name) }

$settings = Read-WidgetSettings
if ($null -ne $settings.Left -and $null -ne $settings.Top -and (Test-WindowPosition $settings.Left $settings.Top)) {
    $Window.WindowStartupLocation = 'Manual'; $Window.Left = $settings.Left; $Window.Top = $settings.Top
} else { $Window.WindowStartupLocation = 'CenterScreen' }
$StartupCheck.IsChecked = $settings.StartWithWindows

if ($ValidateOnly) {
    Write-Output "QuotaGlow widget XAML: OK ($($names.Count) named controls)"
    return
}

function Set-WidgetMessage([string]$Text, [string]$Color = '#AEB6C8') {
    $MessageText.Text = $Text
    $MessageText.Foreground = $Color
}

function Refresh-PortList {
    $selected = if ($null -ne $PortCombo.SelectedItem) { [string]$PortCombo.SelectedItem } else { [string]$settings.Port }
    $PortCombo.Items.Clear()
    foreach ($port in (Get-QuotaGlowSerialPorts)) { [void]$PortCombo.Items.Add($port) }
    if ($PortCombo.Items.Contains($selected)) { $PortCombo.SelectedItem = $selected }
    elseif ($PortCombo.Items.Count -gt 0) { $PortCombo.SelectedIndex = 0 }
}

function Disconnect-WidgetModule([bool]$PowerOff) {
    if ($null -ne $script:SerialPort) {
        Close-QuotaGlowSerialPort -SerialPort $script:SerialPort -PowerOff:$PowerOff
        $script:SerialPort = $null
    }
    $ConnectButton.Content = 'Connect Module'
}

function Update-WidgetSnapshot($Snapshot) {
    $script:LastSnapshot = $Snapshot
    $PrimaryLabel.Text = "$($Snapshot.PrimaryLabel) window"
    $PrimaryPercent.Text = "$($Snapshot.PrimaryRemaining)%"
    $PrimaryBar.Value = [Math]::Max(0, $Snapshot.PrimaryRemaining)
    $PrimaryReset.Text = "Reset $($Snapshot.PrimaryReset)"
    if ($Snapshot.SecondaryRemaining -ge 0) {
        $SecondaryLabel.Text = "$($Snapshot.SecondaryLabel) window"
        $SecondaryPercent.Text = "$($Snapshot.SecondaryRemaining)%"
        $SecondaryBar.Value = $Snapshot.SecondaryRemaining
        $SecondaryReset.Text = "Reset $($Snapshot.SecondaryReset)"
    } else {
        $SecondaryLabel.Text = 'Secondary unavailable'; $SecondaryPercent.Text = '--%'; $SecondaryBar.Value = 0; $SecondaryReset.Text = 'Reset --'
    }
    $LastRefresh.Text = "Last refreshed $($Snapshot.RefreshedAt.ToString('HH:mm:ss'))"
    if (-not $Snapshot.UsageAllowed) { Set-WidgetMessage 'Usage limit reached' '#FF8D8D' }
    elseif ($null -ne $script:SerialPort) { Set-WidgetMessage "Live · module connected on $($script:SerialPort.PortName)" '#65D6AD' }
    else { Set-WidgetMessage 'Live · desktop only' '#65D6AD' }
    $StatusDot.Fill = '#65D6AD'
    if ($null -ne $script:SerialPort) {
        try { Send-QuotaGlowSerialLine -SerialPort $script:SerialPort -Line $Snapshot.SerialLine }
        catch { Disconnect-WidgetModule $false; Set-WidgetMessage "Module disconnected: $($_.Exception.Message)" '#FF8D8D' }
    }
}

$commands = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$events = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$worker = [PowerShell]::Create()
[void]$worker.AddScript({
    param($ModulePath, $Commands, $Events, $Interval)
    Import-Module $ModulePath -Force
    $client = $null; $paused = $false; $stopping = $false; $nextRefresh = [DateTime]::MinValue
    try {
        while (-not $stopping) {
            $command = $null
            while ($Commands.TryDequeue([ref]$command)) {
                switch ([string]$command) {
                    'Refresh' { if (-not $paused) { $nextRefresh = [DateTime]::MinValue } }
                    'Pause' { $paused = $true; if ($null -ne $client) { Stop-QuotaGlowAppServer $client; $client = $null } }
                    'Resume' { $paused = $false; $nextRefresh = [DateTime]::MinValue }
                    'Stop' { $stopping = $true }
                }
            }
            if (-not $stopping -and -not $paused -and [DateTime]::UtcNow -ge $nextRefresh) {
                try {
                    if ($null -eq $client) { $client = Start-QuotaGlowAppServer }
                    $snapshot = Get-QuotaGlowUsageSnapshot $client
                    if ($null -eq $snapshot) { throw 'Codex returned no primary usage window.' }
                    $Events.Enqueue([pscustomobject]@{ Type = 'Snapshot'; Data = $snapshot })
                } catch {
                    $Events.Enqueue([pscustomobject]@{ Type = 'Error'; Message = $_.Exception.Message })
                    if ($null -ne $client) { Stop-QuotaGlowAppServer $client; $client = $null }
                }
                $nextRefresh = [DateTime]::UtcNow.AddSeconds($Interval)
            }
            Start-Sleep -Milliseconds 100
        }
    } finally { if ($null -ne $client) { Stop-QuotaGlowAppServer $client } }
}).AddArgument($coreModule).AddArgument($commands).AddArgument($events).AddArgument($RefreshSeconds)
$workerHandle = $worker.BeginInvoke()

$uiTimer = [Windows.Threading.DispatcherTimer]::new()
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$uiTimer.Add_Tick({
    $eventItem = $null
    while ($events.TryDequeue([ref]$eventItem)) {
        if ($eventItem.Type -eq 'Snapshot') { Update-WidgetSnapshot $eventItem.Data }
        elseif ($eventItem.Type -eq 'Error') { $StatusDot.Fill = '#FF8D8D'; Set-WidgetMessage $eventItem.Message '#FF8D8D' }
    }
    if ($null -ne $script:LastSnapshot -and -not $script:IsPaused -and ((Get-Date) - $script:LastSnapshot.RefreshedAt).TotalMinutes -ge 3) {
        $StatusDot.Fill = '#F5A524'; Set-WidgetMessage 'Data stale · try Refresh' '#F5A524'
    }
})

$DragArea.Add_MouseLeftButtonDown({ try { $Window.DragMove() } catch {} })
$CloseButton.Add_Click({ $Window.Close() })
$RefreshButton.Add_Click({ if (-not $script:IsPaused) { Set-WidgetMessage 'Refreshing…' '#F5A524'; $commands.Enqueue('Refresh') } })
$ScanButton.Add_Click({ Refresh-PortList })
$ConnectButton.Add_Click({
    if ($null -ne $script:SerialPort) { Disconnect-WidgetModule $false; Set-WidgetMessage 'Module disconnected · desktop monitoring continues'; return }
    $selectedPort = [string]$PortCombo.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selectedPort)) { Set-WidgetMessage 'Select a COM port first' '#FF8D8D'; return }
    try {
        Set-WidgetMessage "Connecting to $selectedPort…" '#F5A524'
        $script:SerialPort = Open-QuotaGlowSerialPort -Port $selectedPort
        Send-QuotaGlowSerialLine -SerialPort $script:SerialPort -Line 'POWER|ON'
        if ($null -ne $script:LastSnapshot) { Send-QuotaGlowSerialLine -SerialPort $script:SerialPort -Line $script:LastSnapshot.SerialLine }
        $ConnectButton.Content = 'Disconnect Module'
        Set-WidgetMessage "Live · module connected on $selectedPort" '#65D6AD'
        Save-WidgetSettings
    } catch { Disconnect-WidgetModule $false; Set-WidgetMessage $_.Exception.Message '#FF8D8D' }
})
$PowerButton.Add_Click({
    if (-not $script:IsPaused) {
        $script:IsPaused = $true; Disconnect-WidgetModule $true; $commands.Enqueue('Pause')
        $PowerButton.Content = 'Resume Monitoring'; $RefreshButton.IsEnabled = $false; $StatusDot.Fill = '#8F98AA'; Set-WidgetMessage 'Paused · OLED is off' '#8F98AA'
    } else {
        $script:IsPaused = $false; $commands.Enqueue('Resume')
        $PowerButton.Content = 'Pause Monitoring'; $RefreshButton.IsEnabled = $true; $StatusDot.Fill = '#F5A524'; Set-WidgetMessage 'Resuming…' '#F5A524'
    }
})
$StartupCheck.Add_Click({
    if (-not $script:LoadingSettings) {
        try { Set-StartupPreference ([bool]$StartupCheck.IsChecked); Save-WidgetSettings }
        catch { $StartupCheck.IsChecked = -not $StartupCheck.IsChecked; Set-WidgetMessage "Startup setting failed: $($_.Exception.Message)" '#FF8D8D' }
    }
})
$Window.Add_Closing({
    $script:Closing = $true; Save-WidgetSettings; Disconnect-WidgetModule $true; $commands.Enqueue('Stop'); $uiTimer.Stop()
    try {
        if ($workerHandle.AsyncWaitHandle.WaitOne(2000)) { [void]$worker.EndInvoke($workerHandle) }
        else { $worker.Stop() }
    } catch {}
    $worker.Dispose()
})

Refresh-PortList
$script:LoadingSettings = $false
$uiTimer.Start()
$commands.Enqueue('Refresh')
[void]$Window.ShowDialog()
