import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nursenow_app/patient_hospital/features/organisation/widgets/salary_range_input.dart';
import 'package:vitacare_ui/vitacare_ui.dart';

void main() {
  testWidgets('the active Per day / Per month option is green in the organisation salary range', (tester) async {
    var unit = 'monthly';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SalaryRangeInput(
            unit: unit,
            minController: TextEditingController(),
            maxController: TextEditingController(),
            onUnitChanged: (v) => setState(() => unit = v),
            onChanged: () {},
          ),
        ),
      ),
    ));

    // Colour lives on the button's ink; just assert the selected segment's resolved style.
    final button = tester.widget<SegmentedButton<String>>(find.byKey(const Key('salary-range-unit')));
    final bg = button.style!.backgroundColor!;
    expect(bg.resolve({WidgetState.selected}), AppColors.success);
    expect(bg.resolve({}), isNull);
    expect(unit, 'monthly');
    await tester.tap(find.text('Per day'));
    await tester.pump();
    expect(unit, 'daily');
  });
}
