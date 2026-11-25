import 'package:aryabhangy_compare/state/compare_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('controller starts with All branches', () {
    final controller = CompareController();
    expect(controller.selectedBranch, allBranches);
    expect(controller.branches, contains(allBranches));
  });
}
