param(
    [string]$Vbmeta = 'D:\UniXNU-judyp-bringup\los-parts\output\vbmeta.img',
    [string]$Img = 'D:\UniXNU-judyp-bringup\m4\boot-judyp-64.img',
    [int]$Watch = 30
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

if ($Vbmeta) {
    Write-Host ('[vbmeta] flashing ' + (Split-Path $Vbmeta -Leaf) + ' -> vbmeta_b')
    Write-Host ('    ' + ((RunFb @('flash', 'vbmeta_b', $Vbmeta)) -replace 'Finished\. Total time.*', ''))
}

Write-Host ('[boot] ' + (Split-Path $Img -Leaf))
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = RunFb @('boot', $Img)
Write-Host ('    ' + ($r -replace 'Finished\. Total time.*', ''))
if ($r -match 'FAILED') { Write-Host '[abort] boot command rejected'; exit 0 }

$gone = $false
$fb = $true
for ($i = 0; $i -lt ($Watch * 2); $i++) {
    Start-Sleep -Milliseconds 500
    $fb = [bool]((& fastboot devices 2>$null) -match 'fastboot')
    $el = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if (-not $fb -and -not $gone) { $gone = $true; Write-Host ("    t={0}s  left fastboot" -f $el) }
    if ($fb -and $gone) { Write-Host ("    t={0}s  BACK IN FASTBOOT" -f $el); break }
}
if (-not $gone) { Write-Host '    never left fastboot' }
elseif (-not $fb) { Write-Host ('    t={0}s  still away -> payload running' -f $sw.Elapsed.TotalSeconds) }
