# Release build helper.
# Usage: powershell -ExecutionPolicy Bypass -File build_release.ps1
# - Increments version in pubspec.yaml (patch + build number)
# - Builds split release APKs
# - Copies them to releases/<versionName>/
# - Writes RELEASE_NOTES.md
$ErrorActionPreference = 'Stop'

$pubspec = Join-Path $PSScriptRoot 'pubspec.yaml'
$content = Get-Content $pubspec -Raw -Encoding UTF8
$match = [regex]::Match($content, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
if (-not $match.Success) { throw 'Cannot parse version in pubspec.yaml' }

$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value + 1
$build = [int]$match.Groups[4].Value + 1
$versionName = "$major.$minor.$patch"
$versionFull = "$versionName+$build"

$content = [regex]::Replace($content, '(?m)^version:.*$', "version: $versionFull")
Set-Content $pubspec $content -Encoding UTF8
Write-Host "Version -> $versionFull" -ForegroundColor Cyan

Push-Location $PSScriptRoot
try {
  flutter build apk --release --split-per-abi -Pforce-version-code-ignoring-abi=true
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

  $outDir = Join-Path $PSScriptRoot "releases/$versionName"
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $apkDir = Join-Path $PSScriptRoot 'build/app/outputs/flutter-apk'
  $abis = @('armeabi-v7a', 'arm64-v8a', 'x86_64')
  foreach ($abi in $abis) {
    $src = Join-Path $apkDir "app-$abi-release.apk"
    if (-not (Test-Path $src)) { throw "Missing APK: $src" }
    Copy-Item $src (Join-Path $outDir "WinzPOSPro-v$versionName-$abi.apk") -Force
  }

  $notes = @"
# Winz POS Pro v$versionName

- Package: com.winz.pos.pro (does not replace older Winz installs)
- Version: $versionFull
- Build: flutter build apk --release --split-per-abi -Pforce-version-code-ignoring-abi=true
- API: https://winz.sreamart.com/api
- Files: WinzPOSPro-v$versionName-<abi>.apk
"@
  Set-Content (Join-Path $outDir 'RELEASE_NOTES.md') $notes -Encoding UTF8
  Write-Host "Release ready: $outDir" -ForegroundColor Green
}
finally {
  Pop-Location
}
