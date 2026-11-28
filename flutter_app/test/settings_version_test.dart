import 'package:aryabhangy_compare/state/compare_controller.dart';
import 'package:aryabhangy_compare/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings page shows the version', (tester) async {
    final controller = CompareController();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SettingsPage(controller: controller))),
    );
    expect(find.text('Version 1.0.4'), findsOneWidget);
  });
}
