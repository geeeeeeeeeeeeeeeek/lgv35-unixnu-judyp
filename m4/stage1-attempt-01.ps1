# Stage 1 attempt 01: boot the A1 image and record the timeline.
# Evidence format agreed in PORTING-PLAYBOOK.md: timestamp, USB VID/PID, screen, sha256.
$ErrorActionPreference = 'Continue'
$img  = 'D:\UniXNU-judyp-bringup\m4\boot-a1.img'
$log  = 'D:\UniXNU-judyp-bringup\m4\stage1-attempt-01.log'
$fb   = (Get-Command fastboot).Source

"# Stage 1 attempt 01"                              | Set-Content -Path $log
"# date      : $(Get-Date -Format o)"               | Add-Content -Path $log
"# image     : $img"                                | Add-Content -Path $log
"# image size: $((Get-Item $img).Length)"           | Add-Content -Path $log
"# image sha : $((Get-FileHash $img -Algorithm SHA256).Hash)" | Add-Content -Path $log
"# fastboot  : $(& $fb --version 2>&1 | Select-Object -First 1)" | Add-Content -Path $log
"# slot      : $((& $fb getvar current-slot 2>&1 | Select-String 'current-slot').ToString().Trim())" | Add-Content -Path $log
"# --- timeline: t=seconds since boot command issued ---" | Add-Content -Path $log

# Poll the USB tree and fastboot device list every 200 ms.
$poll = Start-Job -ScriptBlock {
  param($log, $fb)
  $t0 = Get-Date
  while ($true) {
    $usb = (Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPDeviceID -like 'USB\VID_05C6*' } |
            ForEach-Object { $_.PNPDeviceID -replace '^USB\\','' }) -join ','
    $fbd = ((& $fb devices 2>&1) | Out-String).Trim() -replace '\s+', ' '
    $t   = ((Get-Date) - $t0).TotalSeconds
    ('{0,8:N2}s | usb=[{1}] | fb=[{2}]' -f $t, $usb, $fbd) | Add-Content -Path $log
    Start-Sleep -Milliseconds 200
  }
} -ArgumentList $log, $fb

Start-Sleep -Milliseconds 600

# Give slot a one more chance to be the active one.
& $fb set_active a 2>&1 | Out-Null

$sw   = [System.Diagnostics.Stopwatch]::StartNew()
"# boot command issued at $(Get-Date -Format o)" | Add-Content -Path $log
$boot = Start-Job -ScriptBlock { param($fb, $img) & $fb boot $img 2>&1 } -ArgumentList $fb, $img

$done = Wait-Job $boot -Timeout 180
$sw.Stop()

"# --- result ---" | Add-Content -Path $log
"# boot job state : $($boot.State)" | Add-Content -Path $log
"# elapsed        : $([math]::Round($sw.Elapsed.TotalSeconds,2))s" | Add-Content -Path $log
"# boot output    :" | Add-Content -Path $log
(Receive-Job $boot 2>&1 | Out-String) | Add-Content -Path $log

# Keep sampling five more seconds so the "device left/returned" transition is captured.
Start-Sleep -Seconds 5
Stop-Job $poll
Receive-Job $poll | Out-Null
Remove-Job $boot, $poll -Force

"# --- final ---" | Add-Content -Path $log
"# usb now    : $(((Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.PNPDeviceID -like 'USB\VID_05C6*' } | ForEach-Object { $_.PNPDeviceID }) -join ','))" | Add-Content -Path $log
"# fb now     : $(((& $fb devices 2>&1) | Out-String).Trim())" | Add-Content -Path $log
Write-Output "log written: $log"
