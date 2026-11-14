param([int]$Timeout = 180)
$sw = [Diagnostics.Stopwatch]::StartNew()
$last = ''
while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
    $devs = (& fastboot devices 2>$null) -join ' '
    $ads  = (& adb devices 2>$null) -join ' '
    $fb = [bool]($devs -match 'fastboot')
    $ad = [bool]($ads -match "\sdevice\s")
    $state = if ($fb) { 'FASTBOOT' } elseif ($ad) { 'ADB' } else { 'none' }
    if ($state -ne $last) {
        Write-Host ("t={0}s  {1}" -f [math]::Round($sw.Elapsed.TotalSeconds,1), $state)
        $last = $state
    }
    if ($fb) { Write-Host '[ready] fastboot'; exit 0 }
    Start-Sleep -Milliseconds 1000
}
Write-Host ('[timeout] last=' + $last)
exit 1
