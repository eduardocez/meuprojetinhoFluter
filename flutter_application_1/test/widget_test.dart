import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/module/home/home_screen.dart';

void main() {
  testWidgets('Home screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const HomeScreen());

    expect(find.text('Recentes'), findsOneWidget);
  });
}
