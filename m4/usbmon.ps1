param([int]$Sec = 120, [int]$IntervalMs = 400)
# Objective instrument: track LG USB (VID_1004) presence.
# Reset-loop period tells us *when* the device resets, without anyone watching the screen.
$sw = [Diagnostics.Stopwatch]::StartNew()
$last = $null
$cycles = 0
while ($sw.Elapsed.TotalSeconds -lt $Sec) {
    $out = & pnputil /enum-devices /connected 2>$null | Out-String
    $present = $out -match 'VID_1004'
    if ($present -ne $last) {
        if ($last -ne $null -and $present) { $cycles++ }
        $tag = if ($present) { 'USB PRESENT' } else { '---- gone ----' }
        Write-Host ("{0,7:N1}s  {1}" -f $sw.Elapsed.TotalSeconds, $tag)
        $last = $present
    }
    Start-Sleep -Milliseconds $IntervalMs
}
Write-Host ("[done] {0:N1}s, re-appear count = {1}" -f $sw.Elapsed.TotalSeconds, $cycles)
