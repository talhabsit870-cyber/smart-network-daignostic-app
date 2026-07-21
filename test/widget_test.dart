import 'package:flutter_test/flutter_test.dart';

import 'package:smart_network_diagnostic/main.dart';

void main() {
  testWidgets('HomeScreen shows initial diagnostic placeholders and controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('NetDiagnose'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('Ping'), findsOneWidget);
    expect(find.text('Packet Loss'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Not checked'), findsOneWidget);

    expect(find.text('Start Diagnosis'), findsOneWidget);
    expect(find.text('Compare Wi-Fi vs Mobile'), findsOneWidget);
  });
}
