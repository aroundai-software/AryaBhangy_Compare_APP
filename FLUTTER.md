# Aryabhangy Compare (Flutter + Python)

Flutter is the Windows UI. Python still reads Tally and the tracksheet and runs the compare.

## Requirements

- Flutter (Windows desktop enabled)
- Python 3 with project dependencies (`pip install -r requirements.txt`)
- TallyPrime open with a company loaded (gateway on `127.0.0.1:9000`)

## Run (development)

From the project root:

```powershell
.\run_flutter.ps1
```

Or:

```powershell
$env:ARYABHANGY_ROOT = (Get-Location).Path
cd flutter_app
flutter run -d windows
```

## Build release

```powershell
.\build_windows.ps1
```

The exe is under `flutter_app\build\windows\x64\runner\Release\`.  
Set `ARYABHANGY_ROOT` to this project folder when launching the exe so it can start `python -m compare.worker`.

Optional:

- `ARYABHANGY_PYTHON` — full path to `python.exe` if it is not on PATH

## Worker protocol

Flutter starts:

```text
python -m compare.worker
```

JSON lines on stdin/stdout. See `compare/worker.py`.

## tkinter

`python app.py` still works. Prefer the Flutter UI going forward.
