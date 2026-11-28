import 'package:aryabhangy_compare/state/compare_controller.dart';
import 'package:aryabhangy_compare/ui/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _tab(String label) => find.widgetWithText(InkWell, label);

FractionalTranslation _slideOf(WidgetTester tester, String text) {
  final leaf = find.text(text).evaluate().single;
  FractionalTranslation? slide;
  leaf.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is FractionalTranslation) {
      slide = widget;
      return false;
    }
    return true;
  });
  expect(slide, isNotNull);
  return slide!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('page change slides in from the side and then shows that page', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = CompareController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(home: AppShell(controller: controller)));
    await tester.pump();

    expect(find.text('Job Cards compare').hitTestable(), findsOneWidget);
    expect(find.text('Compare history').hitTestable(), findsNothing);

    await tester.tap(_tab('History'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 170));

    expect(_slideOf(tester, 'Compare history').translation.dx, greaterThan(0));
    expect(_slideOf(tester, 'Job Cards compare').translation.dx, lessThan(0));

    await tester.pump(const Duration(milliseconds: 400));
    expect(_slideOf(tester, 'Compare history').translation.dx, 0);
    expect(find.text('Compare history').hitTestable(), findsOneWidget);
    expect(find.text('Job Cards compare').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(_tab('Settings'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Choose the Tally port').hitTestable(), findsOneWidget);
    expect(find.text('Compare history').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
