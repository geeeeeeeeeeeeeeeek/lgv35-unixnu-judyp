function RunFb([string[]]$a) {
    $o = Join-Path $env:TEMP 'fb_out.txt'
    $e = Join-Path $env:TEMP 'fb_err.txt'
    $argList = @('-s', 'LMV350NAWMc386b0d5') + $a
    $p = Start-Process -FilePath 'fastboot' -ArgumentList $argList -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $o -RedirectStandardError $e
    if (Test-Path $e) { return "$(Get-Content $e -Raw)" }
    return ''
}
$keys = @('current-slot', 'slot-unbootable:a', 'slot-unbootable:b', 'slot-retry-count:a', 'slot-retry-count:b',
          'slot-successful:a', 'slot-successful:b', 'slot-count', 'max-download-size', 'is-userspace',
          'has-slot:boot', 'battery-voltage', 'boot-reason', 'last-boot-reason', 'verity-mode', 'avb-verity')
foreach ($k in $keys) {
    $t = (RunFb @('getvar', $k)) -replace 'Finished\. Total time.*', ''
    Write-Host ("{0,-20} {1}" -f $k, ($t.Trim() -replace "`r`n", ' / '))
}
Write-Host '--- all ---'
$all = RunFb @('getvar', 'all')
($all -split "`r?`n") | Where-Object { $_ -match 'slot|boot|verity|avb|serial|secure|unlock' } |
    Select-Object -First 60 | ForEach-Object { Write-Host ('  ' + $_) }
