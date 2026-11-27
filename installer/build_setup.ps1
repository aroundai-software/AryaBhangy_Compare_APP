# Build AryabhangyCompare-Setup-1.0.2.exe
# The installer carries the Windows app, the compare package, and Python.
$ErrorActionPreference = "Stop"

$installerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $installerDir
$version = "1.0.2"
$pythonVersion = "3.12.10"
$cache = Join-Path $installerDir "cache"
$runtimeCache = Join-Path $cache "runtime"
$stage = Join-Path $root "dist\stage"
$release = Join-Path $root "flutter_app\build\windows\x64\runner\Release"
$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"

New-Item -ItemType Directory -Force -Path $cache | Out-Null

Write-Host "Building the Windows app..."
$env:ARYABHANGY_ROOT = $root
Push-Location (Join-Path $root "flutter_app")
try {
  flutter build windows --release
} finally {
  Pop-Location
}
if (-not (Test-Path (Join-Path $release "aryabhangy_compare.exe"))) {
  throw "The release build did not produce aryabhangy_compare.exe."
}

$openpyxl = Join-Path $runtimeCache "Lib\site-packages\openpyxl\__init__.py"
if (-not (Test-Path $openpyxl)) {
  Write-Host "Preparing Python $pythonVersion..."
  $zip = Join-Path $cache "python-$pythonVersion-embed-amd64.zip"
  $pipScript = Join-Path $cache "get-pip.py"
  if (-not (Test-Path $zip)) {
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-embed-amd64.zip" -OutFile $zip
  }
  if (-not (Test-Path $pipScript)) {
    Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $pipScript
  }
  if (Test-Path $runtimeCache) {
    Remove-Item $runtimeCache -Recurse -Force
  }
  Expand-Archive -Path $zip -DestinationPath $runtimeCache
  $pth = Get-ChildItem $runtimeCache -Filter "python*._pth" | Select-Object -First 1
  if (-not $pth) {
    throw "The Python runtime has no ._pth file."
  }
  $zipLine = @(Get-Content $pth.FullName | Where-Object { $_ -match "^python.*\.zip" }) | Select-Object -First 1
  if (-not $zipLine) {
    $zipLine = "python312.zip"
  }
  @(
    $zipLine
    "."
    ".."
    "Lib\site-packages"
    "import site"
  ) | Set-Content -Path $pth.FullName -Encoding ascii
  & (Join-Path $runtimeCache "python.exe") $pipScript --no-warn-script-location
  if ($LASTEXITCODE -ne 0) {
    throw "get-pip failed."
  }
  & (Join-Path $runtimeCache "python.exe") -m pip install "openpyxl==3.1.5" --no-warn-script-location
  if ($LASTEXITCODE -ne 0) {
    throw "openpyxl install failed."
  }
}

$pth = Get-ChildItem $runtimeCache -Filter "python*._pth" | Select-Object -First 1
if (-not $pth) {
  throw "The Python runtime has no ._pth file."
}
$zipLine = @(Get-Content $pth.FullName | Where-Object { $_ -match "^python.*\.zip" }) | Select-Object -First 1
if (-not $zipLine) {
  $zipLine = "python312.zip"
}
@(
  $zipLine
  "."
  ".."
  "Lib\site-packages"
  "import site"
) | Set-Content -Path $pth.FullName -Encoding ascii

Write-Host "Staging files..."
if (Test-Path $stage) {
  Remove-Item $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item (Join-Path $release "*") $stage -Recurse
Copy-Item $runtimeCache (Join-Path $stage "runtime") -Recurse
$compareStage = Join-Path $stage "compare"
New-Item -ItemType Directory -Force -Path $compareStage | Out-Null
Copy-Item (Join-Path $root "compare\*.py") $compareStage

$python = Join-Path $stage "runtime\python.exe"
Push-Location $stage
try {
  & $python -c "import compare.worker, openpyxl; print('bundle-ok')"
  if ($LASTEXITCODE -ne 0) {
    throw "The staged Python compare did not import."
  }
} finally {
  Pop-Location
}

Write-Host "Compiling the installer..."
& $iscc (Join-Path $installerDir "aryabhangy.iss")
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup failed."
}

$setup = Join-Path $root "dist\AryabhangyCompare-Setup-$version.exe"
if (-not (Test-Path $setup)) {
  throw "Installer was not written."
}
Write-Host "Installer: $setup"
