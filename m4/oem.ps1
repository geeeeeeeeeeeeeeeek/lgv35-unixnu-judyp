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
$cmds = @('oem ?', 'oem help', 'oem log', 'oem device-info', 'oem read-log', 'oem lgdump',
          'oem get-log', 'oem dump', 'oem sec-unlock', 'oem show-last-log')
foreach ($c in $cmds) {
    $parts = $c.Split(' ')
    Write-Host ("{0,-18} => {1}" -f $c, (RunFb $parts))
}
