param(
    [Parameter(Mandatory=$true)][string]$Img,
    [ValidateSet('boot','flash')][string]$Mode = 'boot',
    [string]$Slot = 'b',
    [int]$Watch = 14
)
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

if (-not (InFastboot)) { Write-Host '[abort] device not in fastboot'; exit 2 }
Write-Host ('[img] ' + (Split-Path $Img -Leaf) + '  ' + (Get-Item $Img).Length + ' bytes  mode=' + $Mode)

# reset retry counter: every failed attempt burns one, and at 0 the slot is
# marked unbootable -> ABL rejects EVERY image with "Load Error".
$r = RunFb @('set_active', $Slot)
Write-Host ('[retry-reset] ' + $r)
for ($i = 0; $i -lt 40; $i++) { if (InFastboot) { break }; Start-Sleep -Milliseconds 300 }
Start-Sleep -Milliseconds 500

$sw = [Diagnostics.Stopwatch]::StartNew()
if ($Mode -eq 'boot') {
    $r = RunFb @('boot', $Img)
} else {
    $r = RunFb @('flash', ('boot_' + $Slot), $Img)
    Write-Host ('[flash] ' + ($r -replace 'Finished\. Total time.*', ''))
    if ($r -notmatch 'OKAY|Finished') { Write-Host '[abort] flash failed'; exit 3 }
    RunFb @('set_active', $Slot) | Out-Null
    for ($i = 0; $i -lt 40; $i++) { if (InFastboot) { break }; Start-Sleep -Milliseconds 300 }
    $r = RunFb @('reboot')
}
Write-Host ('[' + $Mode + '] ' + ($r -replace 'Finished\. Total time.*', ''))

$rejected = $false
if ($r -match 'FAILED') { $rejected = $true }

$gone = $false
$back = $false
for ($i = 0; $i -lt ($Watch * 2.5); $i++) {
    Start-Sleep -Milliseconds 400
    $fb = InFastboot
    $el = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if (-not $fb -and -not $gone) { $gone = $true; Write-Host ("    t={0}s  LEFT fastboot" -f $el) }
    if ($fb -and $gone) { $back = $true; Write-Host ("    t={0}s  back in fastboot" -f $el); break }
}
if ($rejected) { Write-Host '    RESULT: image REJECTED by ABL' }
elseif ($gone -and -not $back) { Write-Host ('    RESULT: ACCEPTED, still away at t={0}s (payload running)' -f [math]::Round($sw.Elapsed.TotalSeconds,1)) }
elseif (-not $gone) { Write-Host '    RESULT: never left fastboot' }
Write-Host ('[retry:b] ' + (RunFb @('getvar','slot-retry-count:b')))
Write-Host '[done]'
