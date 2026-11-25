import 'package:flutter/material.dart';

import 'state/compare_controller.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = CompareController();
  await controller.start();
  runApp(AryabhangyCompareApp(controller: controller));
}

class AryabhangyCompareApp extends StatefulWidget {
  const AryabhangyCompareApp({super.key, required this.controller});

  final CompareController controller;

  @override
  State<AryabhangyCompareApp> createState() => _AryabhangyCompareAppState();
}

class _AryabhangyCompareAppState extends State<AryabhangyCompareApp> {
  @override
  void dispose() {
    widget.controller.disposeBridge();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aryabhangy Compare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F4D3A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: const Color(0xFFF3F5F4),
      ),
      home: AppShell(controller: widget.controller),
    );
  }
}
