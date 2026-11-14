param([string]$Img = '', [int]$Watch = 8)
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

Write-Host ('[dev] ' + (RunFb @('devices')))
Write-Host ('[dev] now=' + (InFastboot))
Write-Host ('current-slot      = ' + (RunFb @('getvar', 'current-slot')))
Write-Host ('unlocked          = ' + (RunFb @('getvar', 'unlocked')))
Write-Host ('vbmeta_a size     = ' + (RunFb @('getvar', 'partition-size:vbmeta_a')))
Write-Host ('vbmeta_b size     = ' + (RunFb @('getvar', 'partition-size:vbmeta_b')))
Write-Host ('vbmeta   size     = ' + (RunFb @('getvar', 'partition-size:vbmeta')))
Write-Host ('boot_b   size     = ' + (RunFb @('getvar', 'partition-size:boot_b')))

if ($Img) {
    Write-Host ('[img] ' + (Split-Path $Img -Leaf) + ' ' + (Get-Item $Img).Length)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = RunFb @('boot', $Img)
    Write-Host ('[boot] ' + ($r -replace 'Finished\. Total time.*', ''))
    $gone = $false
    for ($i = 0; $i -lt ($Watch * 2); $i++) {
        Start-Sleep -Milliseconds 400
        $fb = InFastboot
        $el = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        if (-not $fb -and -not $gone) { $gone = $true; Write-Host ("    t={0}s  LEFT fastboot" -f $el); break }
    }
    if (-not $gone) { Write-Host '    still in fastboot -> rejected' }
}
Write-Host '[done]'
