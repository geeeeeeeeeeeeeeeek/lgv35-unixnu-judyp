$ErrorActionPreference = 'SilentlyContinue'
$sn  = 'LMV350NAWMc386b0d5'
$img = 'D:\UniXNU-judyp-bringup\m4\boot-judyp-64m.img'

function fb {
    param([Parameter(ValueFromRemainingArguments = $true)]$args2)
    & fastboot -s $sn @args2 2>$null
}

Write-Host ('[img] ' + (Get-FileHash $img -Algorithm SHA256).Hash)

Write-Host '[1] set_active b'
fb set_active b | Out-Host

$deadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $deadline) {
    $out = fb getvar current-slot
    if ($out -match 'b') { break }
    Start-Sleep -Seconds 2
}
Write-Host ('[2] slot: ' + ((fb getvar current-slot) -join ' '))

Write-Host '[3] flash boot_b'
fb flash boot_b $img | Out-Host

Write-Host '[4] getvar slot-retry-count:b'
fb getvar slot-retry-count:b | Out-Host

Write-Host '[5] reboot'
fb reboot | Out-Host

$t0 = Get-Date
$prev = ''
for ($i = 0; $i -lt 200; $i++) {
    $ids = @(Get-PnpDevice -PresentOnly -Class USB |
             ForEach-Object { ($_.InstanceId -split '\\')[1] } |
             Sort-Object -Unique) -join ' '
    if ($ids -ne $prev) {
        $el = [math]::Round(((Get-Date) - $t0).TotalSeconds, 2)
        Write-Host ("t={0,7}s  usb: {1}" -f $el, $ids)
        $prev = $ids
    }
    Start-Sleep -Milliseconds 1000
}
Write-Host '[done] monitoring finished'
