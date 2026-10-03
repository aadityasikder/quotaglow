[CmdletBinding()]
param([int]$RefreshSeconds = 60, [switch]$ValidateOnly)

$ErrorActionPreference = 'Stop'
$script:InstanceMutex = $null
$script:ActivateEvent = $null
$script:StopEvent = $null

if (-not $ValidateOnly) {
    $createdNew = $false
    $script:InstanceMutex = [System.Threading.Mutex]::new($true, 'Local\QuotaGlow.Widget.Singleton', [ref]$createdNew)
    if (-not $createdNew) {
        try {
            $activateExisting = [System.Threading.EventWaitHandle]::OpenExisting('Local\QuotaGlow.Widget.Activate')
            [void]$activateExisting.Set()
            $activateExisting.Dispose()
        } catch {}
        $script:InstanceMutex.Dispose()
        return
    }
    $script:ActivateEvent = [System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::AutoReset, 'Local\QuotaGlow.Widget.Activate')
    $script:StopEvent = [System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::AutoReset, 'Local\QuotaGlow.Widget.Stop')
}

$script:WidgetScriptPath = $PSCommandPath
$projectRoot = Split-Path -Parent $PSScriptRoot
$coreModule = Join-Path $projectRoot 'pc-helper\QuotaGlow.Core.psm1'
Import-Module $coreModule -Force -DisableNameChecking

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$settingsDirectory = Join-Path $env:LOCALAPPDATA 'QuotaGlow'
$settingsPath = Join-Path $settingsDirectory 'settings.json'
$pidPath = Join-Path $settingsDirectory 'widget.pid'
$startupRegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupName = 'QuotaGlow'
$script:ModuleConnected = $false
$script:ModuleTransport = ''
$script:LastSnapshot = $null
$script:IsPaused = $false
$script:IsCompact = $false
$script:LoadingSettings = $true
$script:Closing = $false

function Read-WidgetSettings {
    $defaults = [ordered]@{ Port=''; Left=$null; Top=$null; StartWithWindows=$false; Compact=$false; ModuleTransport='USB'; WifiDeviceId=''; WifiDeviceName=''; WifiAddress=''; EncryptedPairingToken='' }
    try {
        if (Test-Path -LiteralPath $settingsPath) {
            $saved = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
            if ($null -ne $saved.Port) { $defaults.Port = [string]$saved.Port }
            if ($null -ne $saved.Left) { $defaults.Left = [double]$saved.Left }
            if ($null -ne $saved.Top) { $defaults.Top = [double]$saved.Top }
            if ($null -ne $saved.StartWithWindows) { $defaults.StartWithWindows = [bool]$saved.StartWithWindows }
            if ($null -ne $saved.Compact) { $defaults.Compact = [bool]$saved.Compact }
            foreach ($name in 'ModuleTransport','WifiDeviceId','WifiDeviceName','WifiAddress','EncryptedPairingToken') { if ($null -ne $saved.$name) { $defaults[$name] = [string]$saved.$name } }
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
            ModuleTransport = [string]$TransportCombo.SelectedItem
            WifiDeviceId = [string]$settings.WifiDeviceId
            WifiDeviceName = [string]$settings.WifiDeviceName
            WifiAddress = [string]$WifiAddress.Text
            EncryptedPairingToken = [string]$settings.EncryptedPairingToken
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
        Width="380" Height="620" WindowStyle="None" AllowsTransparency="True"
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
          <RowDefinition Height="42"/><RowDefinition Height="40"/><RowDefinition Height="36"/>
          <RowDefinition Height="100"/><RowDefinition Height="46"/><RowDefinition Height="36"/><RowDefinition Height="*"/>
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
        <ComboBox x:Name="TransportCombo" Grid.Row="5" Height="30" Background="#FF222631" Foreground="#FF11141D"/>
        <Grid Grid.Row="6" Grid.RowSpan="2">
          <Grid x:Name="UsbPanel"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="66"/></Grid.ColumnDefinitions><ComboBox x:Name="PortCombo" Height="32" Background="#FF222631" Foreground="#FF11141D"/><Button x:Name="ScanButton" Grid.Column="1" Content="Rescan" Margin="8,0,0,0" Background="#FF282D38" Foreground="White" BorderThickness="0"/></Grid>
          <Grid x:Name="WifiPanel" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="32"/><RowDefinition Height="32"/><RowDefinition Height="32"/></Grid.RowDefinitions><Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="66"/></Grid.ColumnDefinitions><ComboBox x:Name="WifiDeviceCombo" DisplayMemberPath="DisplayName" Height="29" Background="#FF222631" Foreground="#FF11141D"/><Button x:Name="WifiScanButton" Grid.Column="1" Content="Rescan" Margin="8,0,0,0" Background="#FF282D38" Foreground="White" BorderThickness="0"/></Grid><TextBox x:Name="WifiAddress" Grid.Row="1" Height="27" ToolTip="Module IP address" Background="#FF222631" Foreground="White" Padding="6,3"/><Grid Grid.Row="2"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="64"/><ColumnDefinition Width="68"/></Grid.ColumnDefinitions><PasswordBox x:Name="PairCode" MaxLength="6" ToolTip="Six-digit OLED code" Background="#FF222631" Foreground="White" Padding="6,3"/><Button x:Name="PairButton" Grid.Column="1" Content="Pair" Margin="7,0,0,0" Background="#FF625BFF" Foreground="White" BorderThickness="0"/><Button x:Name="ForgetButton" Grid.Column="2" Content="Forget" Margin="7,0,0,0" Background="#FF282D38" Foreground="#FFFFA0A0" BorderThickness="0"/></Grid></Grid>
        </Grid>
        <Button x:Name="ConnectButton" Grid.Row="8" Content="Connect Module" Background="#FF625BFF" Foreground="White" BorderThickness="0" Margin="0,4" FontWeight="SemiBold" Cursor="Hand"/>
        <CheckBox x:Name="StartupCheck" Grid.Row="9" Content="Start with Windows" Foreground="#FFADB5C5" VerticalAlignment="Center"/>
        <Button x:Name="PowerButton" Grid.Row="10" Content="Pause Monitoring" Height="38" VerticalAlignment="Bottom" Background="#FF282D38" Foreground="#FFFF8D8D" BorderThickness="0" Cursor="Hand"/>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
$Window = [Windows.Markup.XamlReader]::Load($reader)
$names = 'CompactView','CompactDragArea','CompactStatusDot','CompactPrimary','CompactSecondary','ExpandButton','CompactCloseButton','ExpandedView','DragArea','StatusDot','HeaderStatus','CollapseButton','CloseButton','PrimaryLabel','PrimaryBar','PrimaryPercent','PrimaryReset','SecondaryLabel','SecondaryBar','SecondaryPercent','SecondaryReset','LastRefresh','RefreshButton','MessageText','TransportCombo','UsbPanel','WifiPanel','PortCombo','ScanButton','WifiDeviceCombo','WifiScanButton','WifiAddress','PairCode','PairButton','ForgetButton','ConnectButton','StartupCheck','PowerButton'
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

if (-not (Test-Path -LiteralPath $settingsDirectory)) { [void](New-Item -ItemType Directory -Path $settingsDirectory -Force) }
Set-Content -LiteralPath $pidPath -Value $PID -Encoding ASCII

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
        $Window.Height = 620
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

function Set-TransportView { $wifi=([string]$TransportCombo.SelectedItem -eq 'Wi-Fi');$WifiPanel.Visibility=if($wifi){'Visible'}else{'Collapsed'};$UsbPanel.Visibility=if($wifi){'Collapsed'}else{'Visible'};if(-not$script:LoadingSettings){Save-WidgetSettings} }
function Queue-Module($Command) { $moduleCommands.Enqueue($Command) }
function Disconnect-WidgetModule([bool]$PowerOff) { if($PowerOff){Queue-Module ([pscustomobject]@{Type='PowerOff'})}else{Queue-Module ([pscustomobject]@{Type='Disconnect'})};$script:ModuleConnected=$false;$script:ModuleTransport='';$ConnectButton.Content='Connect Module' }

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
    elseif ($script:ModuleConnected) { Set-WidgetMessage "Live - $($script:ModuleTransport) module connected" '#65D6AD' 'Module connected' }
    else { Set-WidgetMessage 'Live - desktop only' '#65D6AD' 'Desktop only' }
    if ($script:ModuleConnected) { Queue-Module ([pscustomobject]@{Type='Send';Line=$Snapshot.SerialLine}) }
}

$commands = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$events = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$worker = [PowerShell]::Create()
[void]$worker.AddScript({
    param($ModulePath, $Commands, $Events, $Interval)
    Import-Module $ModulePath -Force -DisableNameChecking
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

# This worker owns every module connection so network scans and I/O never block WPF.
$moduleCommands = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$moduleEvents = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
$moduleWorker = [PowerShell]::Create()
[void]$moduleWorker.AddScript({
    param($ModulePath, $Commands, $Events)
    Import-Module $ModulePath -Force -DisableNameChecking
    $serial=$null; $transport=''; $address=''; $token=''; $wantWifi=$false; $stop=$false
    $retry=0; $nextRetry=[DateTime]::MaxValue; $delays=@(5,15,30,60)
    function Emit($type,$message,$data=$null) { $Events.Enqueue([pscustomobject]@{Type=$type;Message=$message;Data=$data}) }
    function CloseUsb { if($null-ne$script:serial){Close-QuotaGlowSerialPort $script:serial;$script:serial=$null} }
    function ConnectWifi {
        try {
            $info=Get-QuotaGlowWifiInfo $script:address
            if([string]::IsNullOrWhiteSpace($script:token)){Emit 'NeedsPairing' 'Enter the six-digit code shown on the OLED.' $info;return}
            Send-QuotaGlowWifiLine $script:address $script:token 'POWER|ON'|Out-Null
            $script:transport='Wi-Fi';$script:retry=0;Emit 'Connected' "Wi-Fi module $($info.name) connected." $info
        } catch {
            $delay=$delays[[Math]::Min($script:retry,$delays.Count-1)];$script:retry++;$script:nextRetry=[DateTime]::UtcNow.AddSeconds($delay)
            Emit 'Disconnected' "Wi-Fi unavailable; retrying in $delay seconds."
        }
    }
    while(-not$stop){
        $command=$null
        while($Commands.TryDequeue([ref]$command)){
            try {
                switch($command.Type){
                    'Discover' { Emit 'Busy' 'Looking for QuotaGlow modules...';$found=Find-QuotaGlowWifiDevices;Emit 'Devices' "$($found.Count) module(s) found." $found }
                    'ConnectUsb' { CloseUsb;$wantWifi=$false;$serial=Open-QuotaGlowSerialPort $command.Port;Send-QuotaGlowSerialLine $serial 'POWER|ON';$transport='USB';Emit 'Connected' "USB module connected on $($command.Port)." }
                    'ConnectWifi' { CloseUsb;$address=$command.Address;$token=$command.Token;$wantWifi=$true;$retry=0;ConnectWifi }
                    'PairWifi' { $result=Pair-QuotaGlowWifiDevice $command.Address $command.Code;$address=$command.Address;$token=[string]$result.token;$wantWifi=$true;$transport='Wi-Fi';Send-QuotaGlowWifiLine $address $token 'POWER|ON'|Out-Null;Emit 'Paired' 'Module paired and connected.' $result }
                    'Send' { if($transport-eq'USB'){Send-QuotaGlowSerialLine $serial $command.Line}elseif($transport-eq'Wi-Fi'){Send-QuotaGlowWifiLine $address $token $command.Line|Out-Null} }
                    'Disconnect' { $wantWifi=$false;CloseUsb;$transport='';Emit 'Disconnected' 'Module disconnected; desktop monitoring continues.' }
                    'PowerOff' { $wantWifi=$false;if($transport-eq'USB'-and$serial){Close-QuotaGlowSerialPort $serial -PowerOff;$serial=$null}elseif($transport-eq'Wi-Fi'){try{Send-QuotaGlowWifiLine $address $token 'POWER|OFF'|Out-Null}catch{}};$transport='';Emit 'Disconnected' 'Monitoring paused; module display is off.' }
                    'Forget' { if($command.Token){try{Unpair-QuotaGlowWifiDevice $command.Address $command.Token|Out-Null}catch{}};$wantWifi=$false;$address='';$token='';$transport='';Emit 'Forgotten' 'Saved Wi-Fi module forgotten.' }
                    'Stop' { $wantWifi=$false;if($serial){Close-QuotaGlowSerialPort $serial -PowerOff};$stop=$true }
                }
            } catch {
                CloseUsb;$transport='';Emit 'Error' $_.Exception.Message
                if($wantWifi-and$address){$delay=$delays[[Math]::Min($retry,$delays.Count-1)];$retry++;$nextRetry=[DateTime]::UtcNow.AddSeconds($delay)}
            }
        }
        if($wantWifi-and$address-and$transport-ne'Wi-Fi'-and[DateTime]::UtcNow-ge$nextRetry){ConnectWifi}
        Start-Sleep -Milliseconds 100
    }
}).AddArgument($coreModule).AddArgument($moduleCommands).AddArgument($moduleEvents)
$moduleHandle = $moduleWorker.BeginInvoke()

$uiTimer = [Windows.Threading.DispatcherTimer]::new()
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$uiTimer.Add_Tick({
    if ($script:ActivateEvent.WaitOne(0)) {
        if ($Window.WindowState -eq 'Minimized') { $Window.WindowState = 'Normal' }
        $Window.Topmost = $false; $Window.Topmost = $true
        [void]$Window.Activate()
    }
    if ($script:StopEvent.WaitOne(0)) { $Window.Close(); return }
    $eventItem = $null
    while ($events.TryDequeue([ref]$eventItem)) {
        if ($eventItem.Type -eq 'Snapshot') { Update-WidgetSnapshot $eventItem.Data }
        elseif ($eventItem.Type -eq 'Error') { Set-WidgetMessage $eventItem.Message '#FF8D8D' 'Error' }
    }
    while ($moduleEvents.TryDequeue([ref]$eventItem)) {
        switch ($eventItem.Type) {
            'Devices' {
                $WifiDeviceCombo.Items.Clear()
                foreach($device in @($eventItem.Data)){$device|Add-Member -NotePropertyName DisplayName -NotePropertyValue "$($device.Name) - $($device.Address)" -Force;[void]$WifiDeviceCombo.Items.Add($device)}
                if($WifiDeviceCombo.Items.Count -gt 0){$WifiDeviceCombo.SelectedIndex=0}
                Set-WidgetMessage $eventItem.Message '#AEB6C8' 'Wi-Fi scan'
            }
            'Connected' { $script:ModuleConnected=$true;$script:ModuleTransport=[string]$TransportCombo.SelectedItem;$ConnectButton.Content='Disconnect Module';Set-WidgetMessage $eventItem.Message '#65D6AD' 'Module connected';if($script:LastSnapshot){Queue-Module ([pscustomobject]@{Type='Send';Line=$script:LastSnapshot.SerialLine})};Save-WidgetSettings }
            'Paired' { $settings.EncryptedPairingToken=Protect-QuotaGlowDeviceToken ([string]$eventItem.Data.token);$settings.WifiDeviceId=[string]$eventItem.Data.deviceId;$script:ModuleConnected=$true;$script:ModuleTransport='Wi-Fi';$ConnectButton.Content='Disconnect Module';Save-WidgetSettings;Set-WidgetMessage $eventItem.Message '#65D6AD' 'Paired';if($script:LastSnapshot){Queue-Module ([pscustomobject]@{Type='Send';Line=$script:LastSnapshot.SerialLine})} }
            'Forgotten' { $settings.EncryptedPairingToken='';$settings.WifiDeviceId='';$settings.WifiDeviceName='';Save-WidgetSettings;Set-WidgetMessage $eventItem.Message '#AEB6C8' 'Desktop only' }
            'NeedsPairing' { Set-WidgetMessage $eventItem.Message '#F5A524' 'Pair module' }
            'Busy' { Set-WidgetMessage $eventItem.Message '#F5A524' 'Working' }
            'Disconnected' { $script:ModuleConnected=$false;$script:ModuleTransport='';$ConnectButton.Content='Connect Module';Set-WidgetMessage $eventItem.Message '#AEB6C8' 'Desktop only' }
            'Error' { $script:ModuleConnected=$false;$ConnectButton.Content='Connect Module';Set-WidgetMessage $eventItem.Message '#FF8D8D' 'Module error' }
        }
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
$WifiScanButton.Add_Click({ Queue-Module ([pscustomobject]@{Type='Discover'}) })
$TransportCombo.Add_SelectionChanged({ if(-not$script:LoadingSettings){if($script:ModuleConnected){Disconnect-WidgetModule $false};Set-TransportView} })
$WifiDeviceCombo.Add_SelectionChanged({if($WifiDeviceCombo.SelectedItem){$d=$WifiDeviceCombo.SelectedItem;$WifiAddress.Text=$d.Address;$settings.WifiDeviceId=$d.DeviceId;$settings.WifiDeviceName=$d.Name}})
$PairButton.Add_Click({$address=$WifiAddress.Text.Trim();if(-not$address){Set-WidgetMessage 'Discover a module or enter its IP address.' '#FF8D8D';return};Queue-Module ([pscustomobject]@{Type='PairWifi';Address=$address;Code=$PairCode.Password});Set-WidgetMessage 'Pairing...' '#F5A524' 'Pairing'})
$ForgetButton.Add_Click({$token=Unprotect-QuotaGlowDeviceToken $settings.EncryptedPairingToken;Queue-Module ([pscustomobject]@{Type='Forget';Address=$WifiAddress.Text.Trim();Token=$token})})
$ConnectButton.Add_Click({
    if($script:ModuleConnected){Disconnect-WidgetModule $false;return}
    if([string]$TransportCombo.SelectedItem -eq 'USB'){$port=[string]$PortCombo.SelectedItem;if(-not$port){Set-WidgetMessage 'Select a COM port first.' '#FF8D8D';return};Queue-Module ([pscustomobject]@{Type='ConnectUsb';Port=$port})}
    else{$address=$WifiAddress.Text.Trim();if(-not$address){Set-WidgetMessage 'Discover a module or enter its IP address.' '#FF8D8D';return};$token=Unprotect-QuotaGlowDeviceToken $settings.EncryptedPairingToken;Queue-Module ([pscustomobject]@{Type='ConnectWifi';Address=$address;Token=$token})}
    Set-WidgetMessage 'Connecting...' '#F5A524' 'Connecting'
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
    $script:Closing = $true; Save-WidgetSettings; $commands.Enqueue('Stop'); Queue-Module ([pscustomobject]@{Type='Stop'}); $uiTimer.Stop()
    try {
        if ($workerHandle.AsyncWaitHandle.WaitOne(2000)) { [void]$worker.EndInvoke($workerHandle) }
        else { $worker.Stop() }
    } catch {}
    $worker.Dispose()
    try { if($moduleHandle.AsyncWaitHandle.WaitOne(2500)){[void]$moduleWorker.EndInvoke($moduleHandle)}else{$moduleWorker.Stop()} } catch {}
    $moduleWorker.Dispose()
    try { if((Test-Path -LiteralPath $pidPath) -and ([int](Get-Content -Raw -LiteralPath $pidPath)) -eq $PID){Remove-Item -LiteralPath $pidPath -Force} } catch {}
    try { $script:ActivateEvent.Dispose() } catch {}
    try { $script:StopEvent.Dispose() } catch {}
    try { $script:InstanceMutex.ReleaseMutex() } catch {}
    try { $script:InstanceMutex.Dispose() } catch {}
})

Refresh-PortList
$TransportCombo.Items.Add('USB')|Out-Null;$TransportCombo.Items.Add('Wi-Fi')|Out-Null
$TransportCombo.SelectedItem=if([string]$settings.ModuleTransport-eq'Wi-Fi'){'Wi-Fi'}else{'USB'}
$WifiAddress.Text=[string]$settings.WifiAddress
Set-TransportView
Set-CompactMode ([bool]$settings.Compact) $false
$script:LoadingSettings = $false
$uiTimer.Start()
$commands.Enqueue('Refresh')
if([string]$settings.ModuleTransport-eq'Wi-Fi'-and$settings.WifiAddress-and$settings.EncryptedPairingToken){$token=Unprotect-QuotaGlowDeviceToken $settings.EncryptedPairingToken;if($token){Queue-Module ([pscustomobject]@{Type='ConnectWifi';Address=[string]$settings.WifiAddress;Token=$token})}}
[void]$Window.ShowDialog()
