$ErrorActionPreference = 'SilentlyContinue'
$sn  = 'LMV350NAWMc386b0d5'
$img = 'D:\UniXNU-judyp-bringup\m4\boot-judyp-64m.img'

function Fb([string[]]$a) {
    $o = & fastboot -s $sn @a 2>&1
    ($o | Where-Object { $_ -notmatch 'Finished\. Total' -and $_ -notmatch '^(fastboot\.exe|)\s*:\s*$' })
}

Write-Host '[a] slot:' (Fb @('getvar', 'current-slot'))
Write-Host '[b] flashing boot_b ...'
$r = Fb @('flash', 'boot_b', $img)
$r | ForEach-Object { Write-Host ('    ' + $_) }
Write-Host '[c] reboot'
Fb @('reboot') | ForEach-Object { Write-Host ('    ' + $_) }

$t0 = Get-Date
$prev = 'init'
for ($i = 0; $i -lt 190; $i++) {
    $ids = @(Get-PnpDevice -PresentOnly -Class USB |
             ForEach-Object { ($_.InstanceId -split '\\')[1] } |
             Where-Object { $_ -match 'VID_05C6|VID_18D1|VID_1004|VID_1D57' } |
             Sort-Object -Unique) -join ' '
    if ($ids -ne $prev) {
        $el = [math]::Round(((Get-Date) - $t0).TotalSeconds, 2)
        Write-Host ("t={0,7}s  phone-usb: [{1}]" -f $el, $ids)
        $prev = $ids
    }
    Start-Sleep -Milliseconds 1000
}
Write-Host '[done]'
