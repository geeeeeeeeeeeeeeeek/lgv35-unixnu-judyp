param([string]$Vbmeta = 'D:\UniXNU-judyp-bringup\los-parts\output\vbmeta.img')
$sn = 'LMV350NAWMc386b0d5'

function RunFb([string[]]$a) {
    $o = Join-Path $env:TEMP 'fb_out.txt'
    $e = Join-Path $env:TEMP 'fb_err.txt'
    $argList = @('-s', $sn) + $a
    $p = Start-Process -FilePath 'fastboot' -ArgumentList $argList -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $o -RedirectStandardError $e
    $so = ''; $se = ''
    if (Test-Path $o) { $so = "$(Get-Content $o -Raw)" }
    if (Test-Path $e) { $se = "$(Get-Content $e -Raw)" }
    return (($so + $se) -replace "`r`n", ' | ').Trim()
}

foreach ($k in @('has-slot:vbmeta', 'partition-size:vbmeta_b', 'partition-type:vbmeta_b', 'current-slot')) {
    Write-Host ("{0,-24} {1}" -f $k, (RunFb @('getvar', $k)))
}

Write-Host ('[vbmeta] ' + (Get-Item $Vbmeta).Length + ' bytes')
Write-Host '[flash] --disable-verity --disable-verification vbmeta_b'
$r = RunFb @('--disable-verity', '--disable-verification', 'flash', 'vbmeta_b', $Vbmeta)
Write-Host ('    ' + ($r -replace 'Finished\. Total time.*', ''))
