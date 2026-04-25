import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/app.dart';

void main() {
  testWidgets('renders wallet foundation progress on the starter screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MobileWalletDemoApp());

    expect(find.text('Mobile Wallet Demo'), findsOneWidget);
    expect(find.text('v0.3.1'), findsOneWidget);
    expect(find.textContaining('Архитектурный фундамент'), findsOneWidget);
    expect(find.text('Secure Vault'), findsOneWidget);
    expect(find.text('PIN auth'), findsOneWidget);
  });
}
