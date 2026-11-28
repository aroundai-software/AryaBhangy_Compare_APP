import 'dart:isolate';

import 'package:aryabhangy_compare/models/compare_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a parsed compare view can cross an isolate', () async {
    final view = await Isolate.run(() {
      return CompareResultView.fromJson({
        'company': 'Arya',
        'branch': 'Angamaly',
        'from': '2026-09-23',
        'to': '2026-09-30',
        'rows': [
          {
            'mark': statusAdded,
            'category': bothMatch,
            'job_card': '1',
            'vehicle': 'KL',
            'customer': 'A',
            'when': '',
            'adviser': '',
            'branch': 'Angamaly',
            'reason': '',
            'tally_bills': '',
            'track_bill': '',
            'amount': '1',
            'status': '',
            'service': '',
            'phone': '',
            'model': '',
            'booking': '',
            'technician': '',
            'labour': '',
            'spares': '',
            'vas': '',
            'payment': '',
            'items': '',
          },
        ],
      });
    });
    expect(view.company, 'Arya');
    expect(view.rows, hasLength(1));
  });
}
