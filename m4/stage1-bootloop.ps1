# Measure one reboot of the currently installed boot image. No flashing, no changes.
param([string]$Log = 'D:\UniXNU-judyp-bringup\m4\stage1-bootloop-01.log', [int]$Timeout = 120)
$ErrorActionPreference = 'Continue'
$fb = (Get-Command fastboot).Source

"# Bootloop measurement (installed image, no flash)" | Set-Content -Path $Log
"# date        : $(Get-Date -Format o)"              | Add-Content -Path $Log
"# slot before : $((& $fb getvar current-slot 2>&1 | Out-String).Trim())" | Add-Content -Path $Log
"# product     : $((& $fb getvar product 2>&1 | Out-String).Trim())" | Add-Content -Path $Log

$poll = Start-Job -ScriptBlock {
  param($log, $fb)
  $t0 = Get-Date
  while ($true) {
    $usb = (Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPDeviceID -like 'USB\VID_18D1*' -or $_.PNPDeviceID -like 'USB\VID_05C6*' -or $_.PNPDeviceID -like 'USB\VID_0E8D*' } |
            ForEach-Object { ($_.PNPDeviceID -replace '^USB\\','') + '=' + $_.Name }) -join ' | '
    $fbd = ((& $fb devices 2>&1) | Out-String).Trim() -replace '\s+', ' '
    $adb = ((& adb devices 2>&1) | Out-String).Trim() -replace '\s+', ' ' -replace 'List of devices attached ', ''
    '{0,8:N2}s | fb=[{1}] | adb=[{2}] | usb=[{3}]' -f ((Get-Date) - $t0).TotalSeconds, $fbd, $adb, $usb | Add-Content -Path $log
    Start-Sleep -Milliseconds 400
  }
} -ArgumentList $Log, $fb

Start-Sleep -Milliseconds 600
"# reboot issued at $(Get-Date -Format o)" | Add-Content -Path $Log
& $fb reboot 2>&1 | Out-Null

Start-Sleep -Seconds $Timeout
Stop-Job $poll
Receive-Job $poll | Out-Null
Remove-Job $poll -Force

"# --- after ${Timeout}s ---" | Add-Content -Path $Log
"# slot after : $((& $fb getvar current-slot 2>&1 | Out-String).Trim())" | Add-Content -Path $Log
"# fb now     : $(((& $fb devices 2>&1) | Out-String).Trim())" | Add-Content -Path $Log
"# adb now    : $(((& adb devices 2>&1) | Out-String).Trim())" | Add-Content -Path $Log
Write-Output "log written: $Log"
