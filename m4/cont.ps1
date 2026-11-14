function RunFb([string[]]$a) {
    $o = Join-Path $env:TEMP 'fb_out.txt'
    $e = Join-Path $env:TEMP 'fb_err.txt'
    $argList = @('-s', 'LMV350NAWMc386b0d5') + $a
    $p = Start-Process -FilePath 'fastboot' -ArgumentList $argList -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $o -RedirectStandardError $e
    $so = ''; $se = ''
    if (Test-Path $o) { $so = "$(Get-Content $o -Raw)" }
    if (Test-Path $e) { $se = "$(Get-Content $e -Raw)" }
    return [pscustomobject]@{ rc = $p.ExitCode; out = "$so"; err = "$se" }
}
function InFastboot { return [bool]((& fastboot devices 2>$null) -match 'fastboot') }

Write-Host ('[before] fastboot=' + (InFastboot))
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = RunFb @('continue')
Write-Host ('[continue] rc=' + $r.rc + '  out=' + $r.out.Trim() + '  err=' + $r.err.Trim())

$gone = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 500
    $fb = InFastboot
    $el = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if (-not $fb -and -not $gone) { $gone = $true; Write-Host ("    t={0}s  left fastboot" -f $el) }
    if ($fb -and $gone) { Write-Host ("    t={0}s  BACK IN FASTBOOT" -f $el); break }
}
if (-not $gone) { Write-Host '    device never left fastboot' }
elseif (-not (InFastboot)) { Write-Host ('    t={0}s  still not in fastboot -> running?' -f $sw.Elapsed.TotalSeconds) }
Write-Host '[done]'
