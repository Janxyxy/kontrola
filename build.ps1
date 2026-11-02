# Build for fr955. Usage: ./build.ps1 [-Run]   (-Run launches it in the simulator)
param([switch]$Run)
$sdk = Get-ChildItem (Join-Path $env:APPDATA "Garmin\ConnectIQ\Sdks") -Directory | Sort-Object Name | Select-Object -Last 1
$bin = Join-Path $sdk.FullName "bin"
$key = Join-Path $env:USERPROFILE ".garmin-keys\developer_key.der"
$out = "bin/Orienteering_fr955.prg"

& (Join-Path $bin "monkeyc.bat") -f monkey.jungle -o $out -y $key -d fr955 -w -l 2
if ($LASTEXITCODE -ne 0) { exit 1 }

if ($Run) {
    Start-Process (Join-Path $bin "simulator.exe")
    Start-Sleep -Seconds 4
    & (Join-Path $bin "monkeydo.bat") $out fr955
}
