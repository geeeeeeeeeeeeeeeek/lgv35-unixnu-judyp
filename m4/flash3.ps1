function RunFb([string[]]$a) {
    $o = Join-Path $env:TEMP 'fb_out.txt'
    $e = Join-Path $env:TEMP 'fb_err.txt'
    $argList = @('-s', 'LMV350NAWMc386b0d5') + $a
    $p = Start-Process -FilePath 'fastboot' -ArgumentList $argList -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $o -RedirectStandardError $e
    $so = ''
    $se = ''
    if (Test-Path $o) { $so = "$(Get-Content $o -Raw)" }
    if (Test-Path $e) { $se = "$(Get-Content $e -Raw)" }
    return [pscustomobject]@{ rc = $p.ExitCode; out = $so; err = $se }
}

function InFastboot {
    $r = & fastboot devices 2>$null
    return [bool]($r -match 'fastboot')
}

$img = 'D:\UniXNU-judyp-bringup\m4\boot-judyp-64m.img'
$sw = [Diagnostics.Stopwatch]::StartNew()
Write-Host ('[sha256] ' + (Get-FileHash $img -Algorithm SHA256).Hash)
Write-Host ('[now] fastboot=' + (InFastboot))

Write-Host '[1] flash boot_b'
$r = RunFb @('flash', 'boot_b', $img)
Write-Host ("    rc=" + $r.rc + "  " + ($r.err -replace "`r`n", ' | '))

Write-Host '[2] reboot'
$sw.Restart()
$r = RunFb @('reboot')
Write-Host ("    rc=" + $r.rc)

Write-Host '[3] watch (max 40s, stops at first fastboot re-entry)'
$gone = $false
$result = 'timeout'
for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 500
    $fb = InFastboot
    $el = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if (-not $fb -and -not $gone) { $gone = $true; Write-Host ("    t={0}s  device left fastboot" -f $el) }
    if ($fb -and $gone) {
        $result = 'back-to-fastboot'
        Write-Host ("    t={0}s  BACK IN FASTBOOT" -f $el)
        break
    }
}
if ($result -eq 'timeout') { Write-Host ("    t={0}s  no fastboot for 40s (image still running?)" -f $sw.Elapsed.TotalSeconds) }

if ($result -eq 'back-to-fastboot') {
    $r = RunFb @('getvar', 'slot-retry-count:b')
    Write-Host ('    ' + $r.err.Trim())
}
Write-Host '[done]'
