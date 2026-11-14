# Stage 1 measurement harness (flash path): flash boot_a, reboot, record the USB timeline.
# Usage: stage1-flash.ps1 -Image <path> -Log <path> [-Timeout 150] [-Slot a]
param(
  [Parameter(Mandatory=$true)][string]$Image,
  [Parameter(Mandatory=$true)][string]$Log,
  [int]$Timeout = 150,
  [string]$Slot = 'a'
)
$ErrorActionPreference = 'Continue'
$fb = (Get-Command fastboot).Source

"# Stage 1 flash attempt"                            | Set-Content -Path $Log
"# date      : $(Get-Date -Format o)"                | Add-Content -Path $Log
"# image     : $Image"                               | Add-Content -Path $Log
"# image size: $((Get-Item $Image).Length)"          | Add-Content -Path $Log
"# image sha : $((Get-FileHash $Image -Algorithm SHA256).Hash)" | Add-Content -Path $Log
"# target    : boot_$Slot"                           | Add-Content -Path $Log
"# slot before: $((& $fb getvar current-slot 2>&1 | Out-String).Trim())" | Add-Content -Path $Log

"# set_active $Slot : $((& $fb set_active $Slot 2>&1 | Out-String).Trim())" | Add-Content -Path $Log
"# slot after : $((& $fb getvar current-slot 2>&1 | Out-String).Trim())" | Add-Content -Path $Log
"# flash      : $((& $fb flash boot_$Slot $Image 2>&1 | Out-String).Trim())" | Add-Content -Path $Log

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
$sw = [System.Diagnostics.Stopwatch]::StartNew()
"# reboot issued at $(Get-Date -Format o)" | Add-Content -Path $Log
& $fb reboot 2>&1 | Out-Null

Start-Sleep -Seconds $Timeout
$sw.Stop()

Stop-Job $poll
Receive-Job $poll | Out-Null
Remove-Job $poll -Force

"# --- final at $([math]::Round($sw.Elapsed.TotalSeconds,2))s ---" | Add-Content -Path $Log
"# usb now : $(((Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.PNPDeviceID -like 'USB\VID_18D1*' -or $_.PNPDeviceID -like 'USB\VID_05C6*' -or $_.PNPDeviceID -like 'USB\VID_0E8D*' } | ForEach-Object { $_.PNPDeviceID + '=' + $_.Name }) -join ' | '))" | Add-Content -Path $Log
"# fb now  : $(((& $fb devices 2>&1) | Out-String).Trim())" | Add-Content -Path $Log
"# adb now : $(((& adb devices 2>&1) | Out-String).Trim())" | Add-Content -Path $Log
Write-Output "log written: $Log"
