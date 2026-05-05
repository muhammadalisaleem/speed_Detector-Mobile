import 'package:flutter_test/flutter_test.dart';
import 'package:speed_app/main.dart';

void main() {
  testWidgets('loads the app shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Speed App'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });
}
