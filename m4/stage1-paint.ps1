$ErrorActionPreference = 'Continue'
$log = 'D:\UniXNU-judyp-bringup\m4\stage1-paint.log'
$img = 'D:\UniXNU-judyp-bringup\m4\boot-paint-2m.img'

"=== $(Get-Date -Format o) paint 2MB ===" | Out-File $log -Append
fastboot flash boot_a $img 2>&1 | Out-File $log -Append
"reboot at $(Get-Date -Format HH:mm:ss.fff)" | Out-File $log -Append
fastboot reboot 2>&1 | Out-File $log -Append

$sw = [Diagnostics.Stopwatch]::StartNew()
$state = $null; $transitions = @()
while ($sw.Elapsed.TotalSeconds -lt 60) {
    $present = ((fastboot devices 2>$null) -join '') -match 'fastboot'
    if ($present -ne $state) {
        $transitions += ("{0:N2}s {1}" -f $sw.Elapsed.TotalSeconds, $(if($present){'FASTBOOT'}else{'gone'}))
        $state = $present
    }
    if ($transitions.Count -ge 6) { break }
    Start-Sleep -Milliseconds 100
}
$transitions | Out-File $log -Append
"=== end $(Get-Date -Format o) ===" | Out-File $log -Append
Get-Content $log | Select-Object -Last 14
