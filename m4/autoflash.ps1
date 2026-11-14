param(
    [Parameter(Mandatory = $true)][string]$Img,
    [string]$Slot = 'b',
    [int]$WaitSec = 600,
    [int]$Watch = 90,
    [switch]$NoReboot
)
# Single-process auto-flash: waits for fastboot to appear (device may be in its
# 7-retry boot loop for several minutes), flashes once, then monitors.
# IMPORTANT: never run another fastboot process in parallel (-> "Too many links").

$ErrorActionPreference = 'Continue'

function RunFb([string[]]$a) {
    $o = Join-Path $env:TEMP 'af_out.txt'
    $e = Join-Path $env:TEMP 'af_err.txt'
    Remove-Item $o, $e -ErrorAction SilentlyContinue
    # Windows' USB stack needs a moment to release the previous handle,
    # otherwise back-to-back calls hit "Too many links".
    Start-Sleep -Milliseconds 1500
    Start-Process -FilePath 'fastboot' -ArgumentList $a -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $o -RedirectStandardError $e | Out-Null
    $txt = ''
    if (Test-Path $o) { $txt += (Get-Content $o -Raw) }
    if (Test-Path $e) { $txt += (Get-Content $e -Raw) }
    return ($txt -replace '\s+', ' ').Trim()
}

function InFb {
    $d = & fastboot devices 2>$null
    return [bool]($d -match 'fastboot')
}

Write-Host "[wait] looking for fastboot, up to ${WaitSec}s ..."
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
    if (InFb) { break }
    Start-Sleep -Milliseconds 800
}
if (-not (InFb)) {
    Write-Host ("[abort] no fastboot after {0:N0}s" -f $sw.Elapsed.TotalSeconds)
    exit 2
}
Write-Host ("[found] device in fastboot after {0:N1}s" -f $sw.Elapsed.TotalSeconds)

Write-Host ("[img] {0}  {1} bytes" -f (Split-Path $Img -Leaf), (Get-Item $Img).Length)
Write-Host ("[flash] " + (RunFb @('flash', "boot_$Slot", $Img)))
Write-Host ("[set_active] " + (RunFb @('set_active', $Slot)))
if ($NoReboot) {
    Write-Host "[done] flashed, not rebooting"
    exit 0
}
Write-Host ("[reboot] " + (RunFb @('reboot')))

$sw2 = [Diagnostics.Stopwatch]::StartNew()
$left = $false
while ($sw2.Elapsed.TotalSeconds -lt $Watch) {
    $now = InFb
    if (-not $left -and -not $now) {
        $left = $true
        Write-Host ("    t={0:N1}s  LEFT fastboot" -f $sw2.Elapsed.TotalSeconds)
    }
    elseif ($left -and $now) {
        Write-Host ("    t={0:N1}s  back in fastboot" -f $sw2.Elapsed.TotalSeconds)
        break
    }
    Start-Sleep -Milliseconds 500
}
Write-Host ("[end] left={0} elapsed={1:N1}s" -f $left, $sw2.Elapsed.TotalSeconds)
Write-Host ("[retry:$Slot] " + (RunFb @('getvar', "slot-retry-count:$Slot")))
