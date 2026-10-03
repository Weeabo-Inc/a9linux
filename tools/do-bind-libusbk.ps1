<#
  do-bind-libusbk.ps1 — bind the A9 DFU node to libusbK, WITH FULL LOGGING.

  bind-libusbk.ps1 failed under elevation and its console output was lost in the elevated
  window, so this version logs every step to E:\WSL\bind-libusbk.log and tries three
  mechanisms in order, recording the exact Win32 error of each:

    1. our own a9drv, update method, with an EXPLICIT INF  (a9drv's own auto-detect
       reported "no usable package", which contradicts pnputil — so we bypass its matching)
    2. newdev!UpdateDriverForPlugAndPlayDevicesW with INSTALLFLAG_FORCE
    3. SetupAPI DiInstallDevice via a9drv's `di` method

  Run elevated. Everything is logged; the interesting artefact is the log.
#>
[CmdletBinding()]
param([string]$Inf = 'C:\Windows\INF\oem46.inf', [string]$Hwid = 'USB\VID_05AC&PID_1227')

$logDir = 'E:\WSL'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'bind-libusbk.log'

function Say($m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $m
    Write-Host $line
    Add-Content -Path $log -Value $line
}
Set-Content -Path $log -Value "=== bind attempt $(Get-Date -Format s) ==="

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say "elevated = $isAdmin"
if (-not $isAdmin) { Say "NOT ELEVATED - aborting"; exit 5 }

function Show-Node($tag) {
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
      Where-Object { $_.InstanceId -match 'VID_05AC&PID_1227' } | ForEach-Object {
        $inf = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction SilentlyContinue).Data
        $prv = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_DriverProvider' -ErrorAction SilentlyContinue).Data
        Say ("$tag service={0}  inf={1}  provider={2}" -f $_.Service, $inf, $prv)
      }
    $n = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_05AC&PID_1227' }).Count
    if ($n -eq 0) { Say "$tag NO NODE PRESENT (re-enumerating?)" }
}

Say "--- state before ---"
Show-Node 'BEFORE'

Say "--- [A] is the package really there? ---"
foreach ($f in @($Inf, 'C:\Windows\INF\oem45.inf', 'C:\Windows\INF\oem47.inf')) {
    Say ("  {0} exists={1}" -f $f, (Test-Path $f))
}
$allOem = Get-ChildItem "$env:SystemRoot\INF\oem*.inf" -ErrorAction SilentlyContinue
Say ("  oem*.inf files: {0}" -f (($allOem | ForEach-Object { $_.Name }) -join ', '))
$libusbInfs = @()
foreach ($f in $allOem) {
    $txt = $null
    try { $txt = Get-Content $f.FullName -Raw -ErrorAction Stop } catch { continue }
    if (-not $txt) { continue }
    $hasLk = $txt -match 'libusbK'
    $hasHw = $txt -match [regex]::Escape($Hwid)
    if ($hasLk -or $hasHw) {
        Say ("  {0}: libusbK={1} hwid={2} size={3}" -f $f.Name, $hasLk, $hasHw, $f.Length)
        if ($hasLk -and $hasHw) { $libusbInfs += $f.FullName }
    }
}
Say ("  candidate libusbK INFs: {0}" -f (($libusbInfs) -join ', '))

Say "--- [B] our own a9drv, update method, explicit INF ---"
$a9drv = '<REPO_ROOT>\a9drv\target\release\a9drv.exe'
if (Test-Path $a9drv) {
    $target = if ($libusbInfs.Count -gt 0) { $libusbInfs[0] } else { $Inf }
    Say ("  a9drv bind --pid 1227 --method update --inf $target")
    $out = & $a9drv bind --pid 1227 --method update --inf $target 2>&1 | Out-String
    Say ("  exit={0}" -f $LASTEXITCODE)
    foreach ($l in ($out -split "`r?`n")) { if ($l.Trim()) { Say ("    | " + $l.Trim()) } }
    Start-Sleep -Seconds 2
    Show-Node 'AFTER-A'
} else { Say "  a9drv.exe not found" }

# if it already took, stop
$svc = (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_05AC&PID_1227' } | Select-Object -First 1).Service
if ($svc -match 'libusb') { Say "SUCCESS via a9drv: service=$svc"; exit 0 }

Say "--- [C] newdev!UpdateDriverForPlugAndPlayDevicesW, INSTALLFLAG_FORCE ---"
if (-not ('NewDev2' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NewDev2 {
    [DllImport("newdev.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UpdateDriverForPlugAndPlayDevicesW(
        IntPtr hwndParent, string hardwareId, string fullInfPath,
        uint installFlags, out bool needsReboot);
}
'@
}
foreach ($cand in @($libusbInfs) + @($Inf)) {
    if (-not (Test-Path $cand)) { continue }
    foreach ($hw in @($Hwid, "$Hwid&REV_0000")) {
        $reboot = $false
        $ok = [NewDev2]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, $hw, $cand, 0x1, [ref]$reboot)
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Say ("  hw={0} inf={1} -> ok={2} win32={3} reboot={4}" -f $hw, (Split-Path $cand -Leaf), $ok, $err, $reboot)
        if ($ok) { Start-Sleep -Seconds 3; Show-Node 'AFTER-C' }
        $svc = (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_05AC&PID_1227' } | Select-Object -First 1).Service
        if ($svc -match 'libusb') { Say "SUCCESS via UpdateDriverForPlugAndPlayDevices: service=$svc"; exit 0 }
    }
}

Say "--- [D] a9drv di method ---"
if (Test-Path $a9drv) {
    $out = & $a9drv bind --pid 1227 --method di 2>&1 | Out-String
    Say ("  exit={0}" -f $LASTEXITCODE)
    foreach ($l in ($out -split "`r?`n")) { if ($l.Trim()) { Say ("    | " + $l.Trim()) } }
    Start-Sleep -Seconds 2
    Show-Node 'AFTER-D'
}

Say "--- final ---"
Show-Node 'FINAL'
$svc = (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_05AC&PID_1227' } | Select-Object -First 1).Service
if ($svc -match 'libusb') { Say "RESULT: SUCCESS (service=$svc)"; exit 0 }
Say "RESULT: FAILED - node still on service=$svc. Log: $log"
exit 1
