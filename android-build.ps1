param(
  [string]$JavaHome = '',
  [string]$SdkRoot = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
if (-not $SdkRoot) {
  $SdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
}
if (-not $JavaHome) {
  $java = Get-Command java -ErrorAction SilentlyContinue
  if ($java) { $JavaHome = Split-Path (Split-Path $java.Source -Parent) -Parent }
}
$buildTools = Join-Path $SdkRoot 'build-tools\35.0.0'
$platform = Join-Path $SdkRoot 'platforms\android-35\android.jar'
$out = Join-Path $root 'android\build'
$assets = Join-Path $out 'assets'
$classes = Join-Path $out 'classes'
$required = @(
  (Join-Path $buildTools 'aapt.exe'),
  (Join-Path $buildTools 'd8.bat'),
  (Join-Path $buildTools 'zipalign.exe'),
  (Join-Path $buildTools 'apksigner.bat'),
  $platform,
  (Join-Path $JavaHome 'bin\javac.exe'),
  (Join-Path $JavaHome 'bin\jar.exe'),
  (Join-Path $JavaHome 'bin\keytool.exe')
)
foreach ($path in $required) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Required Android build tool not found: $path" }
}

$env:JAVA_HOME = $JavaHome
$env:Path = (Join-Path $JavaHome 'bin') + ';' + $env:Path
Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $assets, $classes -Force | Out-Null
Copy-Item -Path (Join-Path $root 'public\*') -Destination $assets -Recurse -Force

$javaSources = Get-ChildItem -Path (Join-Path $root 'android') -Filter '*.java' | ForEach-Object { $_.FullName }
& (Join-Path $JavaHome 'bin\javac.exe') -source 8 -target 8 -classpath $platform -d $classes $javaSources
$classFiles = Get-ChildItem -Path $classes -Filter '*.class' -Recurse | ForEach-Object { $_.FullName }
& (Join-Path $buildTools 'd8.bat') --lib $platform --output $out $classFiles
& (Join-Path $buildTools 'aapt.exe') package -f -M (Join-Path $root 'android\AndroidManifest.xml') -S (Join-Path $root 'android\res') -A $assets -I $platform -F (Join-Path $out 'unsigned.apk')
Push-Location $out
& (Join-Path $JavaHome 'bin\jar.exe') uf unsigned.apk classes.dex
Pop-Location

$keystore = Join-Path $root 'android\daily-discipline.keystore'
if (-not (Test-Path -LiteralPath $keystore)) {
  & (Join-Path $JavaHome 'bin\keytool.exe') -genkeypair -v -keystore $keystore -storepass daily123 -keypass daily123 -alias daily-discipline -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Daily Discipline, OU=Personal, O=Daily Discipline, L=Local, ST=Local, C=US'
}
& (Join-Path $buildTools 'zipalign.exe') -f 4 (Join-Path $out 'unsigned.apk') (Join-Path $out 'aligned.apk')
& (Join-Path $buildTools 'apksigner.bat') sign --ks $keystore --ks-pass pass:daily123 --out (Join-Path $root 'DailyDiscipline.apk') (Join-Path $out 'aligned.apk')
& (Join-Path $buildTools 'apksigner.bat') verify --verbose (Join-Path $root 'DailyDiscipline.apk')
Write-Host "APK created: $(Join-Path $root 'DailyDiscipline.apk')"
