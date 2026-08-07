import 'package:flutter_test/flutter_test.dart';

import 'package:smart_network_diagnostic/app.dart';

void main() {
  testWidgets('HomeScreen shows the idle launcher and controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('NetDiagnose'), findsOneWidget);
    expect(find.text('0.0'), findsNWidgets(2));
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Ready to test'), findsOneWidget);

    expect(find.textContaining('Start Test'), findsOneWidget);
  });
}
