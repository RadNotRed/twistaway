import 'package:flutter_test/flutter_test.dart';

import 'package:motoplanner_mobile/main.dart';

void main() {
  testWidgets('MotoPlanner renders the planner shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MotoPlannerApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('MotoPlanner'), findsOneWidget);
    expect(find.text('Set your ride'), findsOneWidget);
    expect(find.text('Plan ride'), findsOneWidget);
  });
}
