# Stage 1 measurement harness: boot one image, record the USB timeline.
# Usage: stage1-run.ps1 -Image <path> -Log <path> [-Timeout 180]
param(
  [Parameter(Mandatory=$true)][string]$Image,
  [Parameter(Mandatory=$true)][string]$Log,
  [int]$Timeout = 180
)
$ErrorActionPreference = 'Continue'
$fb = (Get-Command fastboot).Source

"# Stage 1 attempt"                                  | Set-Content -Path $Log
"# date      : $(Get-Date -Format o)"                | Add-Content -Path $Log
"# image     : $Image"                               | Add-Content -Path $Log
"# image size: $((Get-Item $Image).Length)"          | Add-Content -Path $Log
"# image sha : $((Get-FileHash $Image -Algorithm SHA256).Hash)" | Add-Content -Path $Log
"# fastboot  : $(& $fb --version 2>&1 | Select-Object -First 1)" | Add-Content -Path $Log
"# slot      : $((& $fb getvar current-slot 2>&1 | Out-String).Trim())" | Add-Content -Path $Log

$poll = Start-Job -ScriptBlock {
  param($log, $fb)
  $t0 = Get-Date
  while ($true) {
    $usb = (Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPDeviceID -like 'USB\VID_18D1*' -or $_.PNPDeviceID -like 'USB\VID_05C6*' } |
            ForEach-Object { ($_.PNPDeviceID -replace '^USB\\','') + '=' + $_.Name }) -join ' | '
    $fbd = ((& $fb devices 2>&1) | Out-String).Trim() -replace '\s+', ' '
    '{0,8:N2}s | usb=[{1}] | fb=[{2}]' -f ((Get-Date) - $t0).TotalSeconds, $usb, $fbd | Add-Content -Path $log
    Start-Sleep -Milliseconds 200
  }
} -ArgumentList $Log, $fb

Start-Sleep -Milliseconds 600
& $fb set_active a 2>&1 | Out-Null

$sw = [System.Diagnostics.Stopwatch]::StartNew()
"# boot command issued at $(Get-Date -Format o)" | Add-Content -Path $Log
$boot = Start-Job -ScriptBlock { param($fb, $img) & $fb boot $img 2>&1 } -ArgumentList $fb, $Image

$done = Wait-Job $boot -Timeout $Timeout
$sw.Stop()

"# --- result ---" | Add-Content -Path $Log
"# boot job state : $($boot.State)" | Add-Content -Path $Log
"# elapsed        : $([math]::Round($sw.Elapsed.TotalSeconds,2))s" | Add-Content -Path $Log
"# boot output    :" | Add-Content -Path $Log
((Receive-Job $boot 2>&1 | Out-String)) | Add-Content -Path $Log

Start-Sleep -Seconds 5
Stop-Job $poll
Receive-Job $poll | Out-Null
Remove-Job $boot, $poll -Force

"# --- final ---" | Add-Content -Path $Log
"# usb now    : $(((Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.PNPDeviceID -like 'USB\VID_18D1*' -or $_.PNPDeviceID -like 'USB\VID_05C6*' } | ForEach-Object { $_.PNPDeviceID }) -join ','))" | Add-Content -Path $Log
"# fb now     : $(((& $fb devices 2>&1) | Out-String).Trim())" | Add-Content -Path $Log
"# adb now    : $(((& adb devices 2>&1) | Out-String).Trim())" | Add-Content -Path $Log
Write-Output "log written: $Log"
