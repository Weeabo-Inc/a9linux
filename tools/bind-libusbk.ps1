<#
  bind-libusbk.ps1 — force the Apple A9 DFU device node onto the libusbK driver.

  WHY THIS EXISTS
  ---------------
  checkm8 performs a host-initiated USB bus reset after every stage attempt, and after the
  PATCH stage that reset is what runs the overwritten bootrom callback. It is the trigger, not a
  cleanup step.

  Windows' WinUSB cannot do that reset. libusb's own backend says so in a comment, and its code
  calls ResetDevice only when the bound sub-API is NOT WinUSB
  (libusb1-sys-0.7.0/libusb/libusb/os/windows_winusb.c:3371-3420). Worse, it returns
  LIBUSB_SUCCESS regardless (:3419), so a no-op reset looks like a successful one.

  libusbK is different, and this was verified from its source rather than assumed:
      UsbK_ResetDevice                      libusbK/src/lusbk_bknd_libusbk.c:856-871
        -> LIBUSB_IOCTL_RESET_DEVICE        libusbK/src/drv_api.h:70-71   (= 0x00222040)
        -> Device_Reset                     libusbK/src/sys/drv_queue_default.c:452-455
        -> WdfUsbTargetDeviceResetPortSynchronously
                                            libusbK/src/sys/drv_device.c:846
        -> IOCTL_INTERNAL_USB_RESET_PORT    (a real port reset; handles stay valid, no VBUS cycle)
  Note: libusbK's *WinUSB* backend has no ResetDevice at all (lusbk_bknd_winusb.c:962-963), so this
  only helps if libusbK.sys is the function driver for the node — which is what this script ensures.

  WHAT IT DOES
  ------------
  Calls newdev!UpdateDriverForPlugAndPlayDevicesW with INSTALLFLAG_FORCE for the specific hardware
  id USB\VID_05AC&PID_1227, then RE-READS the bound driver service and prints a verdict. It does not
  trust the API's return value alone — the lesson of this whole project is that success must be
  measured, not reported.

  It installs nothing: the libusbK package for this device is already staged in the driver store.
  Reversible (see -Restore).

  REQUIRES ELEVATION. It will refuse politely rather than emit a Win32 error dump.

  USAGE
    powershell -ExecutionPolicy Bypass -File bind-libusbk.ps1            # bind libusbK
    powershell -ExecutionPolicy Bypass -File bind-libusbk.ps1 -Restore   # put Apple's driver back
    powershell -ExecutionPolicy Bypass -File bind-libusbk.ps1 -WhatIf
#>
[CmdletBinding()]
param(
    [switch]$Restore,
    [switch]$WhatIf,
    [string]$HardwareId = 'USB\VID_05AC&PID_1227',
    [string]$PreferredInf = ''      # e.g. 'oem46.inf'; auto-detected when empty
)

$ErrorActionPreference = 'Stop'

function Write-Head($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function Write-Ok($t)   { Write-Host "   $t" -ForegroundColor Green }
function Write-Warn($t) { Write-Host "   $t" -ForegroundColor Yellow }
function Write-Bad($t)  { Write-Host "   $t" -ForegroundColor Red }

# --------------------------------------------------------------------------- privilege
$isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Bad "This needs an Administrator terminal. Open one (Win+X -> Terminal (Admin)) and re-run:"
    Write-Host  "   powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -ForegroundColor White
    exit 5
}

# --------------------------------------------------------------------------- P/Invoke
if (-not ('NewDev' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NewDev {
    [DllImport("newdev.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UpdateDriverForPlugAndPlayDevicesW(
        IntPtr hwndParent, string hardwareId, string fullInfPath,
        uint installFlags, out bool needsReboot);
}
'@
}
$INSTALLFLAG_FORCE = 0x00000001

# --------------------------------------------------------------------------- helpers
function Get-DfuNodes {
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_05AC&PID_1227' }
}

function Get-NodeFacts($node) {
    $drvInf  = (Get-PnpDeviceProperty -InstanceId $node.InstanceId -KeyName 'DEVPKEY_Device_DriverInfPath' -ErrorAction SilentlyContinue).Data
    $prov    = (Get-PnpDeviceProperty -InstanceId $node.InstanceId -KeyName 'DEVPKEY_Device_DriverProvider' -ErrorAction SilentlyContinue).Data
    $hwids   = (Get-PnpDeviceProperty -InstanceId $node.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue).Data
    [pscustomobject]@{
        InstanceId = $node.InstanceId
        Service    = "$($node.Service)"
        Inf        = "$drvInf"
        Provider   = "$prov"
        HardwareIds= @($hwids)
    }
}

function Get-LibusbkInfs {
    # libwdi-generated packages publish under C:\Windows\INF\oemNN.inf. Identify them by content:
    # the matching section is  %DeviceName%=LUsbK_Device, USB\VID_05AC&PID_1227
    $found = @()
    Get-ChildItem "$env:SystemRoot\INF\oem*.inf" -ErrorAction SilentlyContinue | ForEach-Object {
        $txt = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
        if ($txt -and $txt -match 'libusbK' -and $txt -match [regex]::Escape($HardwareId)) {
            $ver = if ($txt -match 'DriverVer\s*=\s*([^\r\n]+)') { $Matches[1].Trim() } else { '?' }
            $found += [pscustomobject]@{ Inf = $_.Name; Path = $_.FullName; DriverVer = $ver }
        }
    }
    $found
}

# --------------------------------------------------------------------------- state now
Write-Head "Before"
$nodes = @(Get-DfuNodes)
if ($nodes.Count -eq 0) {
    Write-Bad "No DFU device ($HardwareId) present. Put the phone in DFU mode and re-run."
    exit 2
}
$before = @()
foreach ($n in $nodes) { $before += Get-NodeFacts $n }
$before | ForEach-Object {
    Write-Host ("   {0}" -f $_.InstanceId)
    Write-Host ("     service  : {0}" -f $_.Service)
    Write-Host ("     driver   : {0}  ({1})" -f $_.Inf, $_.Provider)
}

$infs = @(Get-LibusbkInfs)
Write-Head "libusbK packages present in the driver store"
if ($infs.Count -eq 0) { Write-Bad "none found matching $HardwareId" } else { $infs | ForEach-Object { Write-Host ("   {0}   DriverVer={1}" -f $_.Inf, $_.DriverVer) } }

if ($Restore) {
    # Hand the node back to whatever the system ranks highest (in practice Apple's appleusb.inf).
    Write-Head "Restore: re-selecting the system-preferred driver"
    $hwidRev = "$HardwareId&REV_0000"
    $reboot = $false
    $ok = [NewDev]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, $hwidRev, $null, 0, [ref]$reboot)
    if (-not $ok) { $ok = [NewDev]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, $HardwareId, $null, 0, [ref]$reboot) }
    Write-Host ("   api returned : {0}   needsReboot={1}   win32={2}" -f $ok, $reboot, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    Start-Sleep -Seconds 2
    $after = @(Get-DfuNodes | ForEach-Object { Get-NodeFacts $_ })
    $after | ForEach-Object { Write-Host ("   now service : {0}  ({1})" -f $_.Service, $_.Inf) }
    exit 0
}

if ($infs.Count -eq 0) {
    Write-Bad "Cannot bind: no libusbK package matches $HardwareId on this machine."
    Write-Host "   That is a different problem from 'package present but binding refused'." -ForegroundColor DarkGray
    exit 3
}

$target = if ($PreferredInf) { $infs | Where-Object { $_.Inf -eq $PreferredInf } | Select-Object -First 1 }
          else               { $infs | Select-Object -First 1 }
if (-not $target) { Write-Bad "Requested INF '$PreferredInf' not found."; exit 3 }

Write-Head "Plan"
Write-Host ("   bind {0}" -f $HardwareId)
Write-Host ("   to   {0}  ({1})" -f $target.Inf, $target.DriverVer)
Write-Host  "   via  newdev!UpdateDriverForPlugAndPlayDevicesW + INSTALLFLAG_FORCE"
Write-Warn "This changes which driver owns the device node. It is reversible with -Restore."

if ($WhatIf) { Write-Head "-WhatIf: nothing done."; exit 0 }

# --------------------------------------------------------------------------- do it
Write-Head "Binding"
$reboot = $false
$apiOk  = [NewDev]::UpdateDriverForPlugAndPlayDevicesW([IntPtr]::Zero, $HardwareId, $target.Path, $INSTALLFLAG_FORCE, [ref]$reboot)
$win32  = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
Write-Host ("   api returned : {0}   needsReboot={1}   win32={2}" -f $apiOk, $reboot, $win32)

Write-Host "   waiting for the node to settle..." -ForegroundColor DarkGray
Start-Sleep -Seconds 3

# --------------------------------------------------------------------------- verify
Write-Head "After (this is the part that matters — the API's word is not evidence)"
$after = @()
foreach ($n in @(Get-DfuNodes)) { $after += Get-NodeFacts $n }
if ($after.Count -eq 0) {
    Write-Warn "The node disappeared. That usually means it re-enumerated onto the new driver."
    Write-Warn "Unplug and replug, then run: a9ctl --cli"
}
$verdict = 'UNKNOWN'
foreach ($a in $after) {
    Write-Host ("   {0}" -f $a.InstanceId)
    Write-Host ("     service  : {0}" -f $a.Service)
    Write-Host ("     driver   : {0}  ({1})" -f $a.Inf, $a.Provider)
}
if ($after.Count -gt 0) {
    if ($after | Where-Object { $_.Service -match 'libusbK' })     { $verdict = 'LIBUSBK' }
    elseif ($after | Where-Object { $_.Service -match 'WinUSB' })  { $verdict = 'WINUSB'  }
    else                                                            { $verdict = 'OTHER'   }
}

Write-Head "Verdict"
switch ($verdict) {
    'LIBUSBK' {
        Write-Ok "Service is libusbK. A real port reset is now available."
        Write-Host "   next: a9ctl --cli   (expect 'reset capable : YES')" -ForegroundColor White
        Write-Host "   next: a9pwn preflight" -ForegroundColor White
    }
    'WINUSB' {
        Write-Bad "Still WinUSB. Binding did not take."
        Write-Warn "Fallback, in this order:"
        Write-Host "     1) unplug/replug the phone, then re-run this script" -ForegroundColor White
        Write-Host "     2) only if that fails, remove Apple's competing package and rescan:" -ForegroundColor White
        Write-Host "          pnputil /delete-driver oem45.inf /uninstall /force" -ForegroundColor DarkGray
        Write-Host "          pnputil /scan-devices" -ForegroundColor DarkGray
        Write-Host "        NOTE: oem45.inf is Apple's appleusb.inf and also serves Recovery-mode" -ForegroundColor Yellow
        Write-Host "        devices. Deleting it affects the whole Apple USB stack, not just DFU." -ForegroundColor Yellow
    }
    default {
        Write-Warn "Could not read a definitive service. Re-run a9ctl --cli to classify."
    }
}
Write-Host ""
Write-Host "Rollback:  powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Restore" -ForegroundColor DarkGray
