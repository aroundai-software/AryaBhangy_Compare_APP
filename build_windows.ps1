$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:ARYABHANGY_ROOT = $root
Set-Location (Join-Path $root "flutter_app")
flutter pub get
flutter build windows --release
$out = Join-Path $root "flutter_app\build\windows\x64\runner\Release"
Write-Host "Built: $out"
Write-Host "Run with ARYABHANGY_ROOT=$root so the app can find compare\worker.py"
Write-Host "Example:"
Write-Host "  `$env:ARYABHANGY_ROOT='$root'; & '$out\aryabhangy_compare.exe'"
