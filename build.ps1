# Build for one device (default fr955) or every device in manifest.xml.
#   ./build.ps1                 fr955 -> bin/Kontrola_fr955.prg
#   ./build.ps1 -Device fr965   another device
#   ./build.ps1 -All            every product in manifest.xml
#   ./build.ps1 -Run            build + run in simulator
param([string]$Device = "fr955", [switch]$All, [switch]$Run)
$sdk = Get-ChildItem (Join-Path $env:APPDATA "Garmin\ConnectIQ\Sdks") -Directory | Sort-Object Name | Select-Object -Last 1
$bin = Join-Path $sdk.FullName "bin"
$key = Join-Path $env:USERPROFILE ".garmin-keys\developer_key.der"

$devices = if ($All) { ([xml](Get-Content manifest.xml)).manifest.application.products.product.id } else { @($Device) }
$fail = @()
foreach ($d in $devices) {
    $out = & (Join-Path $bin "monkeyc.bat") -f monkey.jungle -o "bin/Kontrola_$d.prg" -y $key -d $d -w -l 2 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Host "OK      $d" } else { $fail += $d; Write-Host "FAILED  $d"; $out | ForEach-Object { Write-Host "    $_" } }
}
if ($All) { Write-Host "`n$($devices.Count - $fail.Count)/$($devices.Count) built" }
if ($fail.Count -gt 0) { exit 1 }

if ($Run) {
    if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) { Start-Process (Join-Path $bin "simulator.exe"); Start-Sleep -Seconds 6 }
    & (Join-Path $bin "monkeydo.bat") "bin/Kontrola_$($devices[0]).prg" $devices[0]
}
