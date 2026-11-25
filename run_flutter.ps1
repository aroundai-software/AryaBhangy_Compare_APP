$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:ARYABHANGY_ROOT = $root
$env:PYTHONUNBUFFERED = "1"
Set-Location (Join-Path $root "flutter_app")
flutter pub get
flutter run -d windows
