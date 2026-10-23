import 'package:flutter_test/flutter_test.dart';
import 'package:week5_networking/main.dart';

void main() {
  testWidgets('shows app bar title', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Items from an API'), findsOneWidget);
  });
}