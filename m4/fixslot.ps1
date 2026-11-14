param([string]$Slot = 'b', [int]$Wait = 40)
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
function InFastboot { return [bool]((& fastboot devices 2>$null) -match 'fastboot') }

Write-Host ('[before] retry:b=' + (RunFb @('getvar','slot-retry-count:b')) + ' unbootable:b=' + (RunFb @('getvar','slot-unbootable:b')))
Write-Host ('[set_active ' + $Slot + '] ' + (RunFb @('set_active', $Slot)))
$sw = [Diagnostics.Stopwatch]::StartNew()
$left = $false
for ($i = 0; $i -lt ($Wait * 2); $i++) {
    Start-Sleep -Milliseconds 500
    $fb = InFastboot
    if (-not $fb -and -not $left) { $left = $true; Write-Host ("    t={0}s left fastboot" -f [math]::Round($sw.Elapsed.TotalSeconds,1)) }
    if ($fb) { if ($left) { Write-Host ("    t={0}s back in fastboot" -f [math]::Round($sw.Elapsed.TotalSeconds,1)) }; break }
}
Write-Host ('[after]  retry:b=' + (RunFb @('getvar','slot-retry-count:b')) + ' unbootable:b=' + (RunFb @('getvar','slot-unbootable:b')))
Write-Host ('[after]  current-slot=' + (RunFb @('getvar','current-slot')))
Write-Host '[done]'
