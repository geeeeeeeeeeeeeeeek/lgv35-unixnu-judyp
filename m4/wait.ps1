$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 600) {
    $r = & fastboot devices 2>$null
    if ($r -match 'fastboot') {
        Write-Host ("[found] t={0}s serial={1}" -f [math]::Round($sw.Elapsed.TotalSeconds, 1), (($r -split "`t")[0]))
        exit 0
    }
    Start-Sleep -Seconds 5
}
Write-Host '[timeout] no fastboot in 600s'
