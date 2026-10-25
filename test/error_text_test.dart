import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/l10n/app_localizations.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/error_text.dart';
import 'package:mobile_wallet_demo/src/errors/app_error.dart';
import 'package:mobile_wallet_demo/src/key_storage/key_storage_backend.dart';
import 'package:mobile_wallet_demo/src/transactions/transaction_service.dart';

void main() {
  final ru = lookupAppLocalizations(const Locale('ru'));
  final en = lookupAppLocalizations(const Locale('en'));
  final cyrillic = RegExp('[А-Яа-яЁё]');

  // Every argument any code reads, so no sentence renders with a hole.
  const args = <String, Object>{
    'detail': 'technical detail',
    'remaining': Duration(minutes: 5),
    'expected': 'ur:eth-sign-request',
    'actual': 'ur:crypto-hdkey',
    'decimals': 6,
    'symbol': 'USDC',
    'address': '0x1111111111111111111111111111111111111111',
    'chains': 'eip155:137',
    'methods': 'eth_sign',
    'chainId': 137,
    'requested': 1,
    'embedded': 11155111,
  };

  test('every error code reads in both languages', () {
    for (final code in AppErrorCode.values) {
      final russian = describeAppError(ru, code, args);
      final english = describeAppError(en, code, args);
      expect(russian, isNotEmpty, reason: '$code ru');
      expect(english, isNotEmpty, reason: '$code en');
      expect(russian, contains(cyrillic), reason: '$code is not Russian');
      expect(
        english,
        isNot(contains(cyrillic)),
        reason: '$code is not English',
      );
      for (final text in <String>[russian, english]) {
        expect(text, isNot(contains('{')), reason: '$code left a placeholder');
        expect(text, isNot(contains(code.name)), reason: '$code leaked its id');
      }
    }
  });

  test('arguments reach the sentence', () {
    expect(
      describeAppError(ru, AppErrorCode.txInsufficientAsset, args),
      contains('USDC'),
    );
    expect(
      describeAppError(en, AppErrorCode.urWrongType, args),
      allOf(contains('ur:eth-sign-request'), contains('ur:crypto-hdkey')),
    );
  });

  test('a lockout wait reads in whole minutes, or seconds under one', () {
    expect(formatWait(ru, const Duration(minutes: 5)), '5 мин');
    expect(formatWait(en, const Duration(minutes: 5)), '5 min');
    // Rounded up from the true remainder, never "0 s".
    expect(formatWait(ru, const Duration(seconds: 20)), '21 с');
    expect(formatWait(en, Duration.zero), '1 s');
    expect(
      describeError(ru, VaultLockedOutFailure(const Duration(minutes: 5))),
      'Слишком много неверных попыток. Повторите через 5 мин.',
    );
  });

  test('coded failures read from the bundle, others keep their text', () {
    expect(describeError(ru, const InvalidPinFailure()), 'Неверный PIN.');
    expect(describeError(en, const InvalidPinFailure()), 'Wrong PIN.');
    // Text from outside the app (an RPC node) is shown as is.
    expect(
      describeError(en, const TransactionFailure('nonce too low')),
      'nonce too low',
    );
    // Anything unexpected keeps its cause visible.
    expect(describeError(en, StateError('boom')), contains('boom'));
  });

  test('the biometric dialog speaks the active language', () {
    for (final prompt in BiometricPrompt.values) {
      expect(biometricPromptText(ru, prompt), contains(cyrillic));
      expect(biometricPromptText(en, prompt), isNot(contains(cyrillic)));
    }
  });
}
