param(
  [Parameter(Mandatory = $true)]
  [string]$Device,
  [int]$Port = 3000
)

$ErrorActionPreference = 'Stop'
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adbCommand) {
  $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
  $adbPath = Join-Path $sdkRoot 'platform-tools\adb.exe'
  if (-not (Test-Path -LiteralPath $adbPath)) { throw "ADB was not found: $adbPath" }
  $adb = $adbPath
} else {
  $adb = if ($adbCommand.PSObject.Properties['Source']) { $adbCommand.Source } else { $adbCommand.FullName }
}

& $adb connect $Device
& $adb reverse "tcp:$Port" "tcp:$Port"
Write-Host "Wi-Fi bridge ready. Open http://localhost:$Port on the phone."
