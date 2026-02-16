import 'package:flutter_test/flutter_test.dart';
import 'package:flyover/app.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const FlyoverApp());
    expect(find.text('Flyover'), findsOneWidget);
  });
}
