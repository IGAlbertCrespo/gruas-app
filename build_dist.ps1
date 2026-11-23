# build_dist.ps1 - Genera las APK de la version actual en dist\<version>_b<build>\
#   staging : universal (pruebas del cliente, permite cambiar de entorno)
#   prod    : universal + arm32 + arm64
# Uso:  powershell -ExecutionPolicy Bypass -File .\build_dist.ps1 [-SinAnalyze]
param([switch]$SinAnalyze)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$m = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)\+(\d+)' | Select-Object -First 1
if (-not $m) { throw 'No encuentro "version: x.y.z+n" en pubspec.yaml' }
$ver   = $m.Matches[0].Groups[1].Value
$build = $m.Matches[0].Groups[2].Value
$tag   = "$($ver)_b$($build)"
$dest  = Join-Path 'dist' $tag
if (Test-Path $dest) {
    throw "Ya existe $($dest). Sube el build en pubspec.yaml (version: $($ver)+$([int]$build + 1))"
}
$out = 'build\app\outputs\flutter-apk'

function Ejecutar([string[]]$extra) {
    & flutter @extra
    if ($LASTEXITCODE -ne 0) { throw "Fallo: flutter $($extra -join ' ')" }
}

Ejecutar @('pub', 'get')
if (-not $SinAnalyze) { Ejecutar @('analyze', '--no-fatal-infos') }

New-Item -ItemType Directory -Path $dest | Out-Null

# Staging (pruebas): universal
Ejecutar @('build', 'apk', '--release', '-t', 'lib/main_staging.dart')
Copy-Item "$out\app-release.apk" "$dest\gruas_app_$($tag)_staging_universal.apk"

# Produccion: universal
Ejecutar @('build', 'apk', '--release', '-t', 'lib/main_production.dart')
Copy-Item "$out\app-release.apk" "$dest\gruas_app_$($tag)_prod_universal.apk"

# Produccion: una APK por arquitectura (mas ligeras)
Ejecutar @('build', 'apk', '--release', '--split-per-abi', '-t', 'lib/main_production.dart')
Copy-Item "$out\app-armeabi-v7a-release.apk" "$dest\gruas_app_$($tag)_prod_arm32.apk"
Copy-Item "$out\app-arm64-v8a-release.apk"   "$dest\gruas_app_$($tag)_prod_arm64.apk"

Write-Host "`nGenerado en $($dest):" -ForegroundColor Green
Get-ChildItem $dest | Format-Table Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } -AutoSize
