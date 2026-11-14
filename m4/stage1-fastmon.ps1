# Fast USB-presence monitor: poll `fastboot devices` every 50 ms and log only transitions.
param([string]$Log = 'D:\UniXNU-judyp-bringup\m4\stage1-fastmon.log', [int]$Timeout = 45)
$ErrorActionPreference = 'SilentlyContinue'
$fb = (Get-Command fastboot).Source

"# fast usb presence monitor" | Set-Content -Path $Log
"# date: $(Get-Date -Format o)" | Add-Content -Path $Log

$job = Start-Job -ScriptBlock { param($fb) & $fb reboot 2>&1 } -ArgumentList $fb
$t0 = Get-Date

$present = $true
$last = 'present'
"{0,7:N2}s | start present" -f 0 | Add-Content -Path $Log

while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
  $out = ((& $fb devices 2>$null) | Out-String)
  $now = $out -match 'fastboot'
  $cur = if ($now) { 'present' } else { 'absent' }
  if ($cur -ne $last) {
    '{0,7:N2}s | {1} -> {2}' -f ((Get-Date) - $t0).TotalSeconds, $last, $cur | Add-Content -Path $Log
    $last = $cur
  }
  Start-Sleep -Milliseconds 50
}

"{0,7:N2}s | end present={1}" -f (((Get-Date) - $t0).TotalSeconds), $last | Add-Content -Path $Log
"# reboot output: $((Receive-Job $job 2>&1 | Out-String).Trim())" | Add-Content -Path $Log
Remove-Job $job -Force
Write-Output "log written: $Log"
