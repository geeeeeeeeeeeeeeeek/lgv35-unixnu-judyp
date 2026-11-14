param([int]$Seconds = 30, [switch]$Reboot)

function RunFb([string[]]$a) {
    $o = Join-Path $env:TEMP 'fb_out.txt'
    $e = Join-Path $env:TEMP 'fb_err.txt'
    $argList = @('-s', 'LMV350NAWMc386b0d5') + $a
    $p = Start-Process -FilePath 'fastboot' -ArgumentList $argList -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $o -RedirectStandardError $e
    $so = ''; $se = ''
    if (Test-Path $o) { $so = "$(Get-Content $o -Raw)" }
    if (Test-Path $e) { $se = "$(Get-Content $e -Raw)" }
    return (($so + $se) -replace "`r`n", ' | ').Trim()
}

if ($Reboot) { Write-Host ('[reboot] ' + (RunFb @('reboot'))) }

$t0 = Get-Date
$prev = 'none'
for ($i = 0; $i -lt ($Seconds * 6); $i++) {
    $ids = @(Get-PnpDevice -PresentOnly |
             ForEach-Object { "$($_.InstanceId)" } |
             Where-Object { $_ -match 'VID_05C6|VID_18D1|VID_1004' } |
             ForEach-Object { ($_ -split '\\')[1] } |
             Sort-Object -Unique) -join ','
    if ($ids -ne $prev) {
        $el = [math]::Round(((Get-Date) - $t0).TotalSeconds, 2)
        if ($ids -eq '') { Write-Host ("t={0,6}s  <no phone on usb>" -f $el) }
        else { Write-Host ("t={0,6}s  {1}" -f $el, $ids) }
        $prev = $ids
    }
    Start-Sleep -Milliseconds 150
}
Write-Host '[done]'
