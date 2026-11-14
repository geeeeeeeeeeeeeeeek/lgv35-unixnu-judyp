$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
$log = 'D:\UniXNU-judyp-bringup\m4\longrun.log'
$img = 'D:\UniXNU-judyp-bringup\m4\boot-uefi-big.img'

function fb {
    $out = & fastboot @args 2>$null
    return (($out | Out-String) -replace '\s+', ' ').Trim()
}

"=== $(Get-Date -Format o) ===" | Out-File $log

$sw = [Diagnostics.Stopwatch]::StartNew()
$ok = $false
while ($sw.Elapsed.TotalSeconds -lt 300) {
    if ((fb devices) -match 'fastboot') { $ok = $true; break }
    Start-Sleep -Milliseconds 800
}
Write-Host ("wait-bootloader: {0} after {1}s" -f $ok, [math]::Round($sw.Elapsed.TotalSeconds, 1))
"wait-bootloader: $ok after $([math]::Round($sw.Elapsed.TotalSeconds,1))s" | Out-File $log -Append
if (-not $ok) { Write-Host 'ABORT: no bootloader'; Get-Content $log; exit 1 }

Write-Host ('set_active: ' + (fb set_active a))
Write-Host ('flash: ' + (fb flash boot_a $img))

$base = @{}
Get-PnpDevice -PresentOnly | ForEach-Object { $base[$_.InstanceId] = 1 }

Write-Host ('reboot: ' + (fb reboot))
Write-Host ('reboot at ' + (Get-Date -Format HH:mm:ss.fff))
"reboot at $(Get-Date -Format HH:mm:ss.fff)" | Out-File $log -Append

$sw2 = [Diagnostics.Stopwatch]::StartNew()
while ($sw2.Elapsed.TotalSeconds -lt 180) {
    $cur = @{}
    Get-PnpDevice -PresentOnly | ForEach-Object { $cur[$_.InstanceId] = $_.FriendlyName }
    foreach ($id in @($cur.Keys)) {
        if (-not $base.ContainsKey($id)) {
            $line = 'NEW  {0}s  {1}  {2}' -f [math]::Round($sw2.Elapsed.TotalSeconds, 2), $id, $cur[$id]
            Write-Host $line; $line | Out-File $log -Append
            $base[$id] = 1
        }
    }
    foreach ($g in @($base.Keys | Where-Object { -not $cur.ContainsKey($_) })) {
        $line = 'GONE {0}s  {1}' -f [math]::Round($sw2.Elapsed.TotalSeconds, 2), $g
        Write-Host $line; $line | Out-File $log -Append
        $base.Remove($g)
    }
    Start-Sleep -Milliseconds 400
}
Write-Host '=== end ==='
