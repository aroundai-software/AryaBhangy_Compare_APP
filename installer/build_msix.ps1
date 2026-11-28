# Build the Microsoft Store package (MSIX).
# The package contains the Windows app, the compare code, and Python.
$ErrorActionPreference = "Stop"

$installerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $installerDir
$runtime = Join-Path $installerDir "cache\runtime"
$release = Join-Path $root "flutter_app\build\windows\x64\runner\Release"
$python = Join-Path $runtime "python.exe"

if (-not (Test-Path $python)) {
  throw "Python runtime is missing. Run installer\build_setup.ps1 once so the runtime is prepared."
}

Write-Host "Building the Windows app..."
$env:ARYABHANGY_ROOT = $root
Push-Location (Join-Path $root "flutter_app")
try {
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows failed."
  }

  Write-Host "Adding Python and the compare code..."
  $runtimeDest = Join-Path $release "runtime"
  $compareDest = Join-Path $release "compare"
  if (Test-Path $runtimeDest) {
    Remove-Item $runtimeDest -Recurse -Force
  }
  if (Test-Path $compareDest) {
    Remove-Item $compareDest -Recurse -Force
  }
  Copy-Item $runtime $runtimeDest -Recurse
  New-Item -ItemType Directory -Force -Path $compareDest | Out-Null
  Copy-Item (Join-Path $root "compare\*.py") $compareDest

  Push-Location $release
  try {
    & $python -c "import compare.worker, openpyxl; print('bundle-ok')"
    if ($LASTEXITCODE -ne 0) {
      throw "The compare code did not import with the bundled Python."
    }
  } finally {
    Pop-Location
  }

  Write-Host "Packing the MSIX..."
  dart run msix:create --build-windows false
  if ($LASTEXITCODE -ne 0) {
    throw "MSIX packing failed."
  }
} finally {
  Pop-Location
}

$package = Join-Path $root "dist\AryabhangyCompare-1.0.4.msix"
if (-not (Test-Path $package)) {
  throw "The package was not written."
}
Write-Host "Package: $package"
