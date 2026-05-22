import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/src/app/app.dart';

void main() {
  testWidgets('App renders HomePage shell', (WidgetTester tester) async {
    await tester.pumpWidget(const StickerApp(loadHomePacks: false));

    expect(find.text('Minhas figurinhas'), findsOneWidget);
  });
}
