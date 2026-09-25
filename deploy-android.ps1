param(
  [int]$Port = 3000
)

$ErrorActionPreference = 'Stop'
$adbCommand = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adbCommand) {
  $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
  $candidates = @(
    (Join-Path $sdkRoot 'platform-tools\adb.exe'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe')
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) { $adbCommand = Get-Item -LiteralPath $candidate; break }
  }
}
if (-not $adbCommand) {
  throw 'ADB was not found. Install Android SDK Platform-Tools, then add its platform-tools folder to PATH or set ANDROID_HOME.'
}

$adb = if ($adbCommand.PSObject.Properties['Source']) { $adbCommand.Source } else { $adbCommand.FullName }
& $adb start-server | Out-Null
& $adb wait-for-device
& $adb reverse "tcp:$Port" "tcp:$Port"
Write-Host "USB bridge ready: open http://localhost:$Port in Chrome on the phone."
Write-Host "In Chrome, use menu > Add to home screen, or tap Install app in the tracker."
