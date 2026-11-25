import 'package:aryabhangy_compare/ui/check_review.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('check rows group by the reason', () {
    expect(
      checkCause('Job-card, vehicle, and bill match, but bill totals differ (Track 1 vs Tally 2).'),
      'Total differs',
    );
    expect(
      checkCause('Job-card and vehicle match, but bill numbers differ. Check manually.'),
      'Bill number differs',
    );
    expect(
      checkCause('This job is in Tally and not on the tracksheet.'),
      'In Tally, not on the Tracksheet',
    );
    expect(
      checkCause('Service bill HO/SS1 was not added to a job.'),
      'Service bill not assigned',
    );
    expect(
      checkCause('This job-card number is used for different vehicles.'),
      'Same job card, two vehicles',
    );
    expect(
      checkCause('This job-card number and vehicle number are on the tracksheet more than once.'),
      'Duplicate on the Tracksheet',
    );
    expect(
      checkCause('Job-card number or vehicle number is missing on the tracksheet, so nothing was changed.'),
      'Job Card incomplete',
    );
    expect(
      checkCause('This Tally bill has no job-card number or no vehicle number, so nothing was changed.'),
      'Tally bill incomplete',
    );
    expect(
      checkCause('Job card and vehicle match, but the totals differ. Tracksheet ₹1. Tally ₹2.'),
      'Total differs',
    );
    expect(
      checkCause(
        'Job Card 006279 is on the Tracksheet for KL07AW0728. '
        'The Tally bill is for KL04AW0728. The vehicle numbers do not match.',
      ),
      'Vehicle number differs',
    );
    expect(
      plainRemark(
        'Job-card and vehicle match. enter Bill # as last 4 digits (5697).\n'
        'Add on Tracksheet: Bill # 5697; Labour 9,639; Spares 14,870.40 '
        'Figures shown are from Tally and were not written to the Tracksheet. '
        'Labour and Spares are before GST. Total includes GST.',
      ),
      'Ready to fill: Bill # 5697, Labour ₹9,639, Spares ₹14,870.40. '
      'Labour and spares are before GST.\n'
      'Nothing is written until you press Write.',
    );
    expect(
      plainRemark(
        'Job-card number or vehicle number is missing on the tracksheet, so nothing was changed.',
        jobCard: '006298',
      ),
      'Job Card 006298 has no vehicle number. Nothing was changed.',
    );
    expect(
      checkCause('Job Card 006298 has no vehicle number. Nothing was changed.'),
      'Job Card incomplete',
    );
    expect(
      plainRemark(
        'Job card and vehicle match. The bill number on the Tracksheet is empty. '
        'Ready to fill: Bill # 5793, Labour ₹930, Spares ₹538.58. '
        'The job card date 09 Oct 2026 differs from bill date 21 Oct 2026. '
        'Labour and spares are before GST. Nothing is written until you press Write.',
      ),
      'Job card and vehicle match.\n'
      'Ready to fill: Bill # 5793, Labour ₹930, Spares ₹538.58.\n'
      'The job card date 09 Oct 2026 differs from bill date 21 Oct 2026. '
      'Labour and spares are before GST.\n'
      'Nothing is written until you press Write.',
    );
    expect(
      checkRowWriteEnabled(
        'This bill is in Tally, but it is not on the Tracksheet. Check it before adding a job card.',
      ),
      isFalse,
    );
    expect(
      checkRowWriteEnabled(
        'Job Card 006279 is on the Tracksheet for KL07AW0728. '
        'The Tally bill is for KL04AW0728. The vehicle numbers do not match.',
      ),
      isTrue,
    );
    expect(
      plainRemark(
        'Service bill HO/SS1516/26-27 on 12 Oct 2026 for KL05BB3192 was not added to a job. '
        'No single Hirise bill on that day for this vehicle. Nothing was written to the Tracksheet.',
      ),
      'Service bill HO/SS1516/26-27 on 12 Oct 2026 for KL05BB3192 could not be joined to one job. '
      'There was no single Hirise bill for this vehicle on that day. Nothing was written.',
    );
  });
}
