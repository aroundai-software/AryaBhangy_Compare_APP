import 'dart:io';

import 'package:aryabhangy_compare/bridge/python_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('installed folder uses the Python and compare shipped beside the app', () {
    final root = Directory.systemTemp.createTempSync('aryabhangy-bundle');
    try {
      Directory(p.join(root.path, 'runtime')).createSync();
      Directory(p.join(root.path, 'compare')).createSync();
      File(p.join(root.path, 'runtime', 'python.exe')).writeAsStringSync('');
      File(p.join(root.path, 'compare', 'worker.py')).writeAsStringSync('');

      expect(bundledPythonPath(root.path), p.join(root.path, 'runtime', 'python.exe'));
      expect(bundledProjectRoot(root.path), root.path);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('a development folder without a bundled runtime is left alone', () {
    final root = Directory.systemTemp.createTempSync('aryabhangy-dev');
    try {
      expect(bundledPythonPath(root.path), isNull);
      expect(bundledProjectRoot(root.path), isNull);
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
