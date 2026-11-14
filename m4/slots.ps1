param()
$sn = 'LMV350NAWMc386b0d5'
function RunFb([string[]]$a) {
    $o = Join-Path $env:TEMP 'fb_out.txt'; $e = Join-Path $env:TEMP 'fb_err.txt'
    $argList = @('-s', $sn) + $a
    Start-Process -FilePath 'fastboot' -ArgumentList $argList -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $o -RedirectStandardError $e | Out-Null
    $so = ''; $se = ''
    if (Test-Path $o) { $so = "$(Get-Content $o -Raw)" }
    if (Test-Path $e) { $se = "$(Get-Content $e -Raw)" }
    return (($so + $se) -replace "`r`n", ' | ').Trim()
}
foreach ($v in @('slot-retry-count:a','slot-retry-count:b','slot-unbootable:a','slot-unbootable:b','slot-successful:a','slot-successful:b','has-slot:vbmeta','is-logical:vbmeta')) {
    Write-Host ($v.PadRight(22) + '= ' + (RunFb @('getvar',$v)))
}
Write-Host '[done]'
