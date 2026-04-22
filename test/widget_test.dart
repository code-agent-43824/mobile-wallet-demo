import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';

void main() {
  testWidgets('renders the starter wallet screen and version banner', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MobileWalletDemoApp());

    expect(find.text('Mobile Wallet Demo'), findsOneWidget);
    expect(find.text('v0.2'), findsOneWidget);
    expect(find.textContaining('Минимальный стартовый экран'), findsOneWidget);
  });
}
