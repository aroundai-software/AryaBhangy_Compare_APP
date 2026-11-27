import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef WorkerEventHandler = void Function(Map<String, dynamic> event);

/// Python shipped beside an installed app: `<install>\runtime\python.exe`.
String? bundledPythonPath(String installDir) {
  final candidate = File(p.join(installDir, 'runtime', 'python.exe'));
  if (candidate.existsSync()) {
    return candidate.path;
  }
  return null;
}

/// Compare package shipped beside an installed app.
String? bundledProjectRoot(String installDir) {
  final worker = File(p.join(installDir, 'compare', 'worker.py'));
  if (worker.existsSync()) {
    return installDir;
  }
  return null;
}

class PythonBridge {
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  WorkerEventHandler? onEvent;
  void Function(String message)? onLog;
  bool get isRunning => _process != null;

  Future<void> start() async {
    if (_process != null) {
      return;
    }
    final installDir = p.dirname(Platform.resolvedExecutable);
    final bundledPython = bundledPythonPath(installDir);
    final python = _pythonExecutable(installDir);
    final root = _projectRoot(installDir);
    final environment = <String, String>{
      ...Platform.environment,
      'PYTHONUNBUFFERED': '1',
      'PYTHONIOENCODING': 'utf-8',
    };
    if (bundledPython != null && p.equals(python, bundledPython)) {
      environment['PYTHONNOUSERSITE'] = '1';
    }
    final process = await Process.start(
      python,
      const ['-m', 'compare.worker'],
      workingDirectory: root,
      mode: ProcessStartMode.normal,
      runInShell: false,
      environment: environment,
    );
    _process = process;
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onError: (Object error) {
      onLog?.call('Worker stdout error: $error');
    });
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isNotEmpty) {
        onLog?.call(line);
      }
    });
    unawaited(process.exitCode.then((code) {
      onLog?.call('Python worker exited ($code).');
      _process = null;
    }));
  }

  void send(Map<String, dynamic> command) {
    final process = _process;
    if (process == null) {
      throw StateError('Python worker is not running.');
    }
    process.stdin.writeln(jsonEncode(command));
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) {
      return;
    }
    try {
      send(const {'cmd': 'shutdown'});
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    if (_process != null) {
      _process!.kill();
      _process = null;
    }
  }

  void _onLine(String line) {
    final text = line.trim();
    if (text.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        onEvent?.call(decoded);
      } else if (decoded is Map) {
        onEvent?.call(Map<String, dynamic>.from(decoded));
      }
    } catch (error) {
      onLog?.call('Bad worker line: $text');
    }
  }

  String _pythonExecutable(String installDir) {
    final override = Platform.environment['ARYABHANGY_PYTHON'];
    if (override != null && override.trim().isNotEmpty) {
      return override.trim();
    }
    final bundled = bundledPythonPath(installDir);
    if (bundled != null) {
      return bundled;
    }
    return Platform.isWindows ? 'python' : 'python3';
  }

  String _projectRoot(String installDir) {
    final override = Platform.environment['ARYABHANGY_ROOT'];
    if (override != null && override.trim().isNotEmpty) {
      return override.trim();
    }
    final bundled = bundledProjectRoot(installDir);
    if (bundled != null) {
      return bundled;
    }
    final script = Platform.script.toFilePath();
    var dir = Directory(p.dirname(script));
    for (var i = 0; i < 8; i++) {
      final marker = File(p.join(dir.path, 'compare', 'worker.py'));
      if (marker.existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
    final cwd = Directory.current.path;
    if (File(p.join(cwd, 'compare', 'worker.py')).existsSync()) {
      return cwd;
    }
    final parentCwd = Directory(cwd).parent.path;
    if (File(p.join(parentCwd, 'compare', 'worker.py')).existsSync()) {
      return parentCwd;
    }
    throw StateError(
      'Could not find compare/worker.py. Set ARYABHANGY_ROOT to the project folder.',
    );
  }
}
