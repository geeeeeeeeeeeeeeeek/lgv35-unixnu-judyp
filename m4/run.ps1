param(
    [string]$Img = '',
    [string]$Slot = 'b',
    [int]$Watch = 40,
    [switch]$NoFlash,
    [switch]$ActivateA
)
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
function InFastboot { return [bool]((& fastboot devices 2>$null) -match 'fastboot') }

if (-not $NoFlash) {
    if (-not $Img) { Write-Host 'no image given'; exit 1 }
    Write-Host ('[img] ' + (Split-Path $Img -Leaf) + '  ' + (Get-Item $Img).Length + ' bytes')
    Write-Host ('[flash] boot_' + $Slot + ' ...')
    $r = RunFb @('flash', ('boot_' + $Slot), $Img)
    Write-Host ('    ' + ($r -replace 'Finished\. Total time.*', ''))
}

$sw = [Diagnostics.Stopwatch]::StartNew()
if ($ActivateA) {
    Write-Host '[set_active a]'
    Write-Host ('    ' + (RunFb @('set_active', 'a')))
    for ($i = 0; $i -lt 120; $i++) {
        if (InFastboot) { break }
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 2
    Write-Host ('    now fastboot=' + (InFastboot))
}
Write-Host '[reboot]'
$r = RunFb @('reboot')
$gone = $false
$back = $false
for ($i = 0; $i -lt ($Watch * 2); $i++) {
    Start-Sleep -Milliseconds 500
    $fb = InFastboot
    $el = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if (-not $fb -and -not $gone) { $gone = $true; Write-Host ("    t={0}s  left fastboot" -f $el) }
    if ($fb -and $gone) { $back = $true; Write-Host ("    t={0}s  BACK IN FASTBOOT" -f $el); break }
}
if (-not $gone) { Write-Host '    never left fastboot (reboot did not happen?)' }
elseif (-not $back) { Write-Host ('    t={0}s  still away -> payload is running' -f $sw.Elapsed.TotalSeconds) }
if ($back) {
    Write-Host ('    retry:b=' + (RunFb @('getvar', 'slot-retry-count:b')))
    Write-Host ('    unbootable:b=' + (RunFb @('getvar', 'slot-unbootable:b')))
}
Write-Host '[done]'
