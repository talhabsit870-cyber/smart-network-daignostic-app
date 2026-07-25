import 'package:flutter_test/flutter_test.dart';

import 'package:smart_network_diagnostic/main.dart';

void main() {
  testWidgets('HomeScreen shows the idle launcher and controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('NetDiagnose'), findsOneWidget);
    expect(find.text('0.0'), findsOneWidget);
    expect(find.text('Mbps down'), findsOneWidget);
    expect(find.text('Ready to test'), findsOneWidget);

    expect(find.text('Start Test'), findsOneWidget);
    expect(find.text('Compare Wi-Fi vs Mobile'), findsOneWidget);
  });
}
