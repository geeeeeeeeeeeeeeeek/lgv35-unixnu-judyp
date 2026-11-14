param([string]$Slot = 'b')
# Read-only: dump A/B slot state.  Never run concurrently with another fastboot.
function RunFb([string[]]$a) {
    $o = Join-Path $env:TEMP 'st_out.txt'; $e = Join-Path $env:TEMP 'st_err.txt'
    Remove-Item $o, $e -ErrorAction SilentlyContinue
    Start-Process -FilePath 'fastboot' -ArgumentList $a -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $o -RedirectStandardError $e | Out-Null
    $t = ''
    if (Test-Path $o) { $t += (Get-Content $o -Raw) }
    if (Test-Path $e) { $t += (Get-Content $e -Raw) }
    return ($t -replace '\s+', ' ').Trim()
}
foreach ($v in @('current-slot', 'slot-count', 'slot-retry-count:a', 'slot-retry-count:b',
                 'slot-unbootable:a', 'slot-unbootable:b', 'slot-successful:a',
                 'slot-successful:b', 'version-bootloader', 'product', 'max-download-size')) {
    Write-Host ("{0,-22} = {1}" -f $v, (RunFb @('getvar', $v)))
}
