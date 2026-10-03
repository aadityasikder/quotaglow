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
$script:IsCompact = $false
$script:LoadingSettings = $true
$script:Closing = $false

function Read-WidgetSettings {
    $defaults = [ordered]@{ Port = ''; Left = $null; Top = $null; StartWithWindows = $false; Compact = $false }
    try {
        if (Test-Path -LiteralPath $settingsPath) {
            $saved = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
            if ($null -ne $saved.Port) { $defaults.Port = [string]$saved.Port }
            if ($null -ne $saved.Left) { $defaults.Left = [double]$saved.Left }
            if ($null -ne $saved.Top) { $defaults.Top = [double]$saved.Top }
            if ($null -ne $saved.StartWithWindows) { $defaults.StartWithWindows = [bool]$saved.StartWithWindows }
            if ($null -ne $saved.Compact) { $defaults.Compact = [bool]$saved.Compact }
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
            Compact = [bool]$script:IsCompact
        } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    } catch {}
}

function Set-StartupPreference([bool]$Enabled) {
    if ($Enabled) {
        $silentLauncher = Join-Path $projectRoot 'start_quotaglow.vbs'
        $value = "wscript.exe `"$silentLauncher`""
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
        Width="360" Height="500" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize">
  <Border CornerRadius="22" Background="#FF12151E" BorderBrush="#FF303541" BorderThickness="1">
    <Border.Effect><DropShadowEffect BlurRadius="25" ShadowDepth="6" Opacity="0.65" Color="#FF000000"/></Border.Effect>
    <Grid>
      <Grid x:Name="CompactView" Visibility="Collapsed" Margin="16,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="22"/><ColumnDefinition Width="*"/><ColumnDefinition Width="1"/>
          <ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="28"/>
        </Grid.ColumnDefinitions>
        <Grid x:Name="CompactDragArea" Grid.ColumnSpan="4" Background="Transparent" Cursor="SizeAll"/>
        <Ellipse x:Name="CompactStatusDot" Grid.Column="0" Width="9" Height="9" Fill="#FFF5A524" HorizontalAlignment="Left"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="5h" Foreground="#FF8E97A8" FontSize="11" Margin="0,0,7,0"/>
          <TextBlock x:Name="CompactPrimary" Text="--%" Foreground="#FFFFFFFF" FontSize="19" FontWeight="Bold"/>
        </StackPanel>
        <Border Grid.Column="2" Width="1" Height="26" Background="#FF343946" VerticalAlignment="Center"/>
        <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Center">
          <TextBlock Text="7d" Foreground="#FF8E97A8" FontSize="11" Margin="0,0,7,0"/>
          <TextBlock x:Name="CompactSecondary" Text="--%" Foreground="#FFFFFFFF" FontSize="19" FontWeight="Bold"/>
        </StackPanel>
        <Button x:Name="ExpandButton" Grid.Column="4" Content="+" Width="27" Height="27" FontSize="17" Foreground="#FFC9CFDA" Background="#FF282D38" BorderThickness="0" Cursor="Hand" ToolTip="Expand"/>
        <Button x:Name="CompactCloseButton" Grid.Column="5" Content="X" Width="24" Height="24" FontSize="10" Foreground="#FF7F8899" Background="Transparent" BorderThickness="0" Cursor="Hand"/>
      </Grid>

      <Grid x:Name="ExpandedView" Margin="20,16,20,18">
        <Grid.RowDefinitions>
          <RowDefinition Height="48"/><RowDefinition Height="82"/><RowDefinition Height="82"/>
          <RowDefinition Height="42"/><RowDefinition Height="40"/><RowDefinition Height="54"/>
          <RowDefinition Height="46"/><RowDefinition Height="36"/><RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Grid x:Name="DragArea" Grid.Row="0" Background="Transparent" Cursor="SizeAll">
          <Grid.ColumnDefinitions><ColumnDefinition Width="38"/><ColumnDefinition/><ColumnDefinition Width="34"/><ColumnDefinition Width="28"/></Grid.ColumnDefinitions>
          <Border Width="32" Height="32" CornerRadius="10" Background="#FF625BFF" VerticalAlignment="Center"><TextBlock Text="Q" Foreground="White" FontWeight="Bold" FontSize="17" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="9,0,0,0"><TextBlock Text="QuotaGlow" Foreground="White" FontSize="19" FontWeight="SemiBold"/><StackPanel Orientation="Horizontal"><Ellipse x:Name="StatusDot" Width="7" Height="7" Fill="#FFF5A524" Margin="0,0,6,0"/><TextBlock x:Name="HeaderStatus" Text="Starting" Foreground="#FF8E97A8" FontSize="10"/></StackPanel></StackPanel>
          <Button x:Name="CollapseButton" Grid.Column="2" Content="-" Width="27" Height="27" FontSize="17" Foreground="#FFC9CFDA" Background="#FF282D38" BorderThickness="0" Cursor="Hand" ToolTip="Compact mode"/>
          <Button x:Name="CloseButton" Grid.Column="3" Content="X" Width="24" Height="24" FontSize="10" Foreground="#FF7F8899" Background="Transparent" BorderThickness="0" Cursor="Hand"/>
        </Grid>

        <Border Grid.Row="1" CornerRadius="13" Background="#FF1B1F2A" Padding="14,11" Margin="0,4,0,4"><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="82"/></Grid.ColumnDefinitions><StackPanel><TextBlock x:Name="PrimaryLabel" Text="5h window" Foreground="#FFADB5C5" FontSize="12"/><ProgressBar x:Name="PrimaryBar" Height="8" Margin="0,11,10,0" Maximum="100" Value="0" Foreground="#FF63D7AE" Background="#FF343946"/></StackPanel><StackPanel Grid.Column="1"><TextBlock x:Name="PrimaryPercent" Text="--%" Foreground="White" FontSize="24" FontWeight="Bold" HorizontalAlignment="Right"/><TextBlock x:Name="PrimaryReset" Text="Reset --" Foreground="#FF7F8899" FontSize="10" HorizontalAlignment="Right"/></StackPanel></Grid></Border>
        <Border Grid.Row="2" CornerRadius="13" Background="#FF1B1F2A" Padding="14,11" Margin="0,4,0,4"><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="82"/></Grid.ColumnDefinitions><StackPanel><TextBlock x:Name="SecondaryLabel" Text="7d window" Foreground="#FFADB5C5" FontSize="12"/><ProgressBar x:Name="SecondaryBar" Height="8" Margin="0,11,10,0" Maximum="100" Value="0" Foreground="#FF8D8CFF" Background="#FF343946"/></StackPanel><StackPanel Grid.Column="1"><TextBlock x:Name="SecondaryPercent" Text="--%" Foreground="White" FontSize="24" FontWeight="Bold" HorizontalAlignment="Right"/><TextBlock x:Name="SecondaryReset" Text="Reset --" Foreground="#FF7F8899" FontSize="10" HorizontalAlignment="Right"/></StackPanel></Grid></Border>
        <Grid Grid.Row="3" Margin="0,4,0,0"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="92"/></Grid.ColumnDefinitions><TextBlock x:Name="LastRefresh" Text="Not refreshed yet" Foreground="#FF7F8899" FontSize="11" VerticalAlignment="Center"/><Button x:Name="RefreshButton" Grid.Column="1" Content="Refresh" Background="#FF282D38" Foreground="White" BorderThickness="0" Padding="8" Cursor="Hand"/></Grid>
        <TextBlock x:Name="MessageText" Grid.Row="4" Text="Starting Codex service..." Foreground="#FFF5A524" FontSize="11" TextWrapping="Wrap" VerticalAlignment="Center"/>
        <Grid Grid.Row="5"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="62"/></Grid.ColumnDefinitions><ComboBox x:Name="PortCombo" Height="32" VerticalAlignment="Center" Background="#FF222631" Foreground="#FF11141D"/><Button x:Name="ScanButton" Grid.Column="1" Content="Scan" Margin="8,0,0,0" Height="32" Background="#FF282D38" Foreground="White" BorderThickness="0" Cursor="Hand" ToolTip="Rescan COM ports"/></Grid>
        <Button x:Name="ConnectButton" Grid.Row="6" Content="Connect Module" Background="#FF625BFF" Foreground="White" BorderThickness="0" Margin="0,4" FontWeight="SemiBold" Cursor="Hand"/>
        <CheckBox x:Name="StartupCheck" Grid.Row="7" Content="Start with Windows" Foreground="#FFADB5C5" VerticalAlignment="Center"/>
        <Button x:Name="PowerButton" Grid.Row="8" Content="Pause Monitoring" Height="38" VerticalAlignment="Bottom" Background="#FF282D38" Foreground="#FFFF8D8D" BorderThickness="0" Cursor="Hand"/>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)
$names = 'CompactView','CompactDragArea','CompactStatusDot','CompactPrimary','CompactSecondary','ExpandButton','CompactCloseButton','ExpandedView','DragArea','StatusDot','HeaderStatus','CollapseButton','CloseButton','PrimaryLabel','PrimaryBar','PrimaryPercent','PrimaryReset','SecondaryLabel','SecondaryBar','SecondaryPercent','SecondaryReset','LastRefresh','RefreshButton','MessageText','PortCombo','ScanButton','ConnectButton','StartupCheck','PowerButton'
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

function Set-WidgetMessage([string]$Text, [string]$Color = '#AEB6C8', [string]$Header = 'Live') {
    $MessageText.Text = $Text
    $MessageText.Foreground = $Color
    $StatusDot.Fill = $Color
    $CompactStatusDot.Fill = $Color
    $HeaderStatus.Text = $Header
}

function Set-CompactMode([bool]$Compact, [bool]$Persist = $true) {
    $script:IsCompact = $Compact
    if ($Compact) {
        $ExpandedView.Visibility = 'Collapsed'
        $CompactView.Visibility = 'Visible'
        $Window.Height = 76
    } else {
        $CompactView.Visibility = 'Collapsed'
        $ExpandedView.Visibility = 'Visible'
        $Window.Height = 500
    }
    if ($Persist) { Save-WidgetSettings }
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
    $CompactPrimary.Text = "$($Snapshot.PrimaryRemaining)%"
    if ($Snapshot.SecondaryRemaining -ge 0) {
        $SecondaryLabel.Text = "$($Snapshot.SecondaryLabel) window"
        $SecondaryPercent.Text = "$($Snapshot.SecondaryRemaining)%"
        $SecondaryBar.Value = $Snapshot.SecondaryRemaining
        $SecondaryReset.Text = "Reset $($Snapshot.SecondaryReset)"
        $CompactSecondary.Text = "$($Snapshot.SecondaryRemaining)%"
    } else {
        $SecondaryLabel.Text = 'Secondary unavailable'; $SecondaryPercent.Text = '--%'; $SecondaryBar.Value = 0; $SecondaryReset.Text = 'Reset --'
        $CompactSecondary.Text = '--%'
    }
    $LastRefresh.Text = "Last refreshed $($Snapshot.RefreshedAt.ToString('HH:mm:ss'))"
    if (-not $Snapshot.UsageAllowed) { Set-WidgetMessage 'Usage limit reached' '#FF8D8D' 'Limit reached' }
    elseif ($null -ne $script:SerialPort) { Set-WidgetMessage "Live - module connected on $($script:SerialPort.PortName)" '#65D6AD' 'Module connected' }
    else { Set-WidgetMessage 'Live - desktop only' '#65D6AD' 'Desktop only' }
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
        elseif ($eventItem.Type -eq 'Error') { Set-WidgetMessage $eventItem.Message '#FF8D8D' 'Error' }
    }
    if ($null -ne $script:LastSnapshot -and -not $script:IsPaused -and ((Get-Date) - $script:LastSnapshot.RefreshedAt).TotalMinutes -ge 3) {
        Set-WidgetMessage 'Data stale - try Refresh' '#F5A524' 'Stale'
    }
})

$DragArea.Add_MouseLeftButtonDown({ try { $Window.DragMove() } catch {} })
$CompactDragArea.Add_MouseLeftButtonDown({ try { $Window.DragMove() } catch {} })
$CloseButton.Add_Click({ $Window.Close() })
$CompactCloseButton.Add_Click({ $Window.Close() })
$CollapseButton.Add_Click({ Set-CompactMode $true })
$ExpandButton.Add_Click({ Set-CompactMode $false })
$RefreshButton.Add_Click({ if (-not $script:IsPaused) { Set-WidgetMessage 'Refreshing...' '#F5A524' 'Refreshing'; $commands.Enqueue('Refresh') } })
$ScanButton.Add_Click({ Refresh-PortList })
$ConnectButton.Add_Click({
    if ($null -ne $script:SerialPort) { Disconnect-WidgetModule $false; Set-WidgetMessage 'Module disconnected - desktop monitoring continues' '#AEB6C8' 'Desktop only'; return }
    $selectedPort = [string]$PortCombo.SelectedItem
    if ([string]::IsNullOrWhiteSpace($selectedPort)) { Set-WidgetMessage 'Select a COM port first' '#FF8D8D'; return }
    try {
        Set-WidgetMessage "Connecting to $selectedPort..." '#F5A524' 'Connecting'
        $script:SerialPort = Open-QuotaGlowSerialPort -Port $selectedPort
        Send-QuotaGlowSerialLine -SerialPort $script:SerialPort -Line 'POWER|ON'
        if ($null -ne $script:LastSnapshot) { Send-QuotaGlowSerialLine -SerialPort $script:SerialPort -Line $script:LastSnapshot.SerialLine }
        $ConnectButton.Content = 'Disconnect Module'
        Set-WidgetMessage "Live - module connected on $selectedPort" '#65D6AD' 'Module connected'
        Save-WidgetSettings
    } catch { Disconnect-WidgetModule $false; Set-WidgetMessage $_.Exception.Message '#FF8D8D' }
})
$PowerButton.Add_Click({
    if (-not $script:IsPaused) {
        $script:IsPaused = $true; Disconnect-WidgetModule $true; $commands.Enqueue('Pause')
        $PowerButton.Content = 'Resume Monitoring'; $RefreshButton.IsEnabled = $false; Set-WidgetMessage 'Paused - OLED is off' '#8F98AA' 'Paused'
    } else {
        $script:IsPaused = $false; $commands.Enqueue('Resume')
        $PowerButton.Content = 'Pause Monitoring'; $RefreshButton.IsEnabled = $true; Set-WidgetMessage 'Resuming...' '#F5A524' 'Resuming'
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
Set-CompactMode ([bool]$settings.Compact) $false
$script:LoadingSettings = $false
$uiTimer.Start()
$commands.Enqueue('Refresh')
[void]$Window.ShowDialog()
