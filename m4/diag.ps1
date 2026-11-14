function RunFb([string[]]$a) {
    $o = Join-Path $env:TEMP 'fb_out.txt'
    $e = Join-Path $env:TEMP 'fb_err.txt'
    $argList = @('-s', 'LMV350NAWMc386b0d5') + $a
    $p = Start-Process -FilePath 'fastboot' -ArgumentList $argList -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $o -RedirectStandardError $e
    $so = (Get-Content $o -Raw)
    $se = (Get-Content $e -Raw)
    return [pscustomobject]@{ rc = $p.ExitCode; out = $so; err = $se }
}

Write-Host '=== devices ==='
Write-Host ((& fastboot devices 2>&1) -join ' | ')

foreach ($v in @('current-slot', 'slot-retry-count:a', 'slot-retry-count:b', 'slot-successful:b', 'partition-size:boot_b', 'partition-size:boot_a')) {
    $r = RunFb @('getvar', $v)
    Write-Host ("$v  rc=$($r.rc)  out=$($r.out.Trim())  err=$($r.err.Trim())")
}

Write-Host '=== pnp ==='
Get-PnpDevice -PresentOnly | Where-Object { "$($_.InstanceId)" -match 'VID_05C6|VID_1004|VID_18D1' } |
    ForEach-Object { Write-Host ("{0}  {1}  {2}" -f $_.Class, $_.FriendlyName, $_.InstanceId) }
