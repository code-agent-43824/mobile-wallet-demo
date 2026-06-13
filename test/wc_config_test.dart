import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/walletconnect/wc_config.dart';

void main() {
  test('config flag mirrors whether WC_PROJECT_ID is set', () {
    // Robust whether or not the define is passed to `flutter test`: the getter
    // must mirror `wcProjectId.isNotEmpty`. CI runs without the define, so this
    // is empty/false here; --dart-define-from-file flips both together.
    expect(isWalletConnectConfigured, wcProjectId.isNotEmpty);
  });
}
