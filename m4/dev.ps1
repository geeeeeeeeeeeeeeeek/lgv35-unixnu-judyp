Write-Host '--- adb ---'
& adb devices
Write-Host '--- fastboot ---'
& fastboot devices
Write-Host '--- usb ---'
Get-PnpDevice -PresentOnly | ForEach-Object { "$($_.InstanceId)" } |
    Where-Object { $_ -match 'VID_05C6|VID_18D1|VID_1004' }
