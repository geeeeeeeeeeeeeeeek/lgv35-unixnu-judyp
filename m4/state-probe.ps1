$log = 'D:\UniXNU-judyp-bringup\m4\state-probe.log'
"=== $(Get-Date -Format o) ===" | Out-File $log
fastboot reboot 2>&1 | Out-Null
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($t in 3, 5, 8, 12, 16, 20, 25, 30, 40, 50) {
    Start-Sleep -Milliseconds ([math]::Max(0, $t * 1000 - $sw.ElapsedMilliseconds))
    $job = Start-Job { fastboot getvar current-slot 2>&1 }
    $done = Wait-Job $job -Timeout 2
    if ($done) {
        $out = (Receive-Job $job) -join ' '
        $r = if ($out -match 'current-slot') { ($out -replace '\s+', ' ').Trim() } else { 'NO-ANSWER' }
        Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
    } else {
        Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue
        $r = 'TIMEOUT'
    }
    "t=${t}s  $r" | Out-File $log -Append
}
Get-Content $log
