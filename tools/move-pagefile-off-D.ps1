<#
  move-pagefile-off-D.ps1 — get the pagefile (and therefore crash-dump writing) off the failing disk.

  WHY
  ---
  The pagefile is at D:\pagefile.sys. D: lives on Disk 2, a Seagate ST1000DM010 (serial ZN1MQS7H)
  that has been "surprise removed" 18 times in 24 hours, with unrecoverable IO errors at specific
  LBAs and a WHEA "fatal hardware error" record.

  Two consequences, both bad:
    1. A dropout during an in-flight paging operation is a bugcheck-class event, not a hiccup.
    2. Windows writes a kernel/small memory dump THROUGH the pagefile on the BOOT volume. With the
       only pagefile on D:, every crash also failed to produce a dump — "volmgr id=161: Dump file
       creation failed" — so no bugcheck code has ever been recorded on this machine.
       There is a 2.81 GB abandoned dump attempt sitting at D:\DUMP1a1f.tmp as evidence.

  WHY C: AND NOT E:
  -----------------
  Master asked that everything move to E:. This one file is the exception, deliberately:
  Windows requires the pagefile used for memory dumps to be on the BOOT volume. Putting it on E:
  would leave dumps broken. C: is also the fastest device here (KINGSTON SNV3S1000G, NVMe).
  Everything else — WSL distros, container storage, project work — goes to E:.

  WHAT IT DOES
    1. records the current setting
    2. sets the pagefile to C:\pagefile.sys with a fixed 4096 MB initial / 16384 MB maximum
    3. keeps CrashDumpEnabled at 3 (small memory dump) — enough for a bugcheck code and stack
    4. removes the abandoned dump artefacts from D:
  REQUIRES A REBOOT to take effect. D:\pagefile.sys is deleted by Windows at that point.

  USAGE (elevated):
    powershell -ExecutionPolicy Bypass -File move-pagefile-off-D.ps1
#>
[CmdletBinding()]
param([switch]$WhatIf)

$ErrorActionPreference = 'Stop'
$log = 'E:\WSL\pagefile-move.log'
function Say($m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line
    Add-Content -Path $log -Value $line -ErrorAction SilentlyContinue
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "This needs an Administrator console." -ForegroundColor Red; exit 5 }

$mm  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$cc  = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'

Say "=== pagefile move ==="
$before = (Get-ItemProperty -Path $mm -Name PagingFiles -ErrorAction SilentlyContinue).PagingFiles
Say ("BEFORE PagingFiles : {0}" -f ($before -join ' | '))
$dumpBefore = (Get-ItemProperty -Path $cc -Name CrashDumpEnabled -ErrorAction SilentlyContinue).CrashDumpEnabled
Say ("BEFORE CrashDumpEnabled : {0}" -f $dumpBefore)
Say ("D: pagefile present : {0}" -f (Test-Path 'D:\pagefile.sys'))

if ($WhatIf) { Say "-WhatIf: nothing changed."; exit 0 }

# 1. pagefile -> C: (boot volume, NVMe). Fixed size so it cannot balloon into C:'s free space.
$newValue = @('C:\pagefile.sys 4096 16384')
Set-ItemProperty -Path $mm -Name PagingFiles -Value $newValue -Type MultiString
$after = (Get-ItemProperty -Path $mm -Name PagingFiles).PagingFiles
Say ("AFTER  PagingFiles : {0}" -f ($after -join ' | '))

# 2. keep minidumps on (3 = small memory dump). AutoReboot is already 0, so a bugcheck will HALT
#    and display its code rather than rebooting straight past it.
Set-ItemProperty -Path $cc -Name CrashDumpEnabled -Value 3 -Type DWord
Set-ItemProperty -Path $cc -Name AutoReboot        -Value 0 -Type DWord
Say ("AFTER  CrashDumpEnabled : {0}  AutoReboot : {1}" -f `
     (Get-ItemProperty -Path $cc -Name CrashDumpEnabled).CrashDumpEnabled, `
     (Get-ItemProperty -Path $cc -Name AutoReboot).AutoReboot)

# 3. clear the abandoned dump attempt and its scratch files off the failing disk
foreach ($f in 'D:\DUMP1a1f.tmp','D:\DumpStack.log','D:\DumpStack.log.tmp') {
    if (Test-Path $f) {
        $sz = (Get-Item $f -Force).Length
        try   { Remove-Item $f -Force -ErrorAction Stop; Say ("deleted {0} ({1:N0} bytes)" -f $f, $sz) }
        catch { Say ("could NOT delete {0}: {1}" -f $f, $_.Exception.Message) }
    }
}

Say "DONE. A REBOOT is required: Windows will switch the pagefile to C: and drop D:\pagefile.sys."
Say "After the reboot, verify with:  Get-CimInstance Win32_PageFileUsage | Select Name,AllocatedBaseSize"
