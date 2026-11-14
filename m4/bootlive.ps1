param([string]$Img, [int]$Watch = 25)
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

Write-Host ('[img] ' + (Split-Path $Img -Leaf) + ' ' + (Get-Item $Img).Length)
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = RunFb @('boot', $Img)
Write-Host ('[boot] ' + ($r -replace 'Finished\. Total time.*', ''))
$gone = $false
for ($i = 0; $i -lt ($Watch * 2); $i++) {
    Start-Sleep -Milliseconds 500
    $fb = [bool]((& fastboot devices 2>$null) -match 'fastboot')
    $el = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if (-not $fb -and -not $gone) { $gone = $true; Write-Host ("    t={0}s  left fastboot" -f $el) }
    if ($fb -and $gone) { Write-Host ("    t={0}s  BACK IN FASTBOOT" -f $el); break }
}
if (-not $gone) { Write-Host '    never left fastboot' }
elseif ($fb -ne $true) { Write-Host ('    t={0}s  still away -> payload running' -f $sw.Elapsed.TotalSeconds) }
Write-Host '[done]'
