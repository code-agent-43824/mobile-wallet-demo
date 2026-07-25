import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_wallet_demo/src/auth/biometric_auth.dart';
import 'package:mobile_wallet_demo/src/key_storage/custody_backend.dart';
import 'package:mobile_wallet_demo/src/key_storage/rutoken_method_channel_adapter.dart';
import 'package:mobile_wallet_demo/src/key_storage/secure_key_value_store.dart';
import 'package:mobile_wallet_demo/src/wallet_flow_screen.dart';

void main() {
  test(
    'controller cancels a pending Rutoken NFC wait and clears busy state',
    () async {
      final adapter = _PendingRutokenAdapter();
      final controller = WalletFlowController(
        store: InMemorySecureKeyValueStore(),
        biometricAuthGateway: SimulatedBiometricAuthGateway(),
        rutokenNativeAdapter: adapter,
      );
      addTearDown(controller.dispose);

      final diagnostic = controller.runRutokenTransportDiagnostic('1234');
      await adapter.openStarted.future;

      expect(controller.busyMessage, isNotNull);
      expect(controller.canCancelBusyOperation, isTrue);
      expect(controller.isBusyCancellationRequested, isFalse);

      await controller.cancelBusyOperation();
      await diagnostic;

      expect(adapter.cancelCount, 1);
      expect(controller.busyMessage, isNull);
      expect(controller.canCancelBusyOperation, isFalse);
      expect(controller.isBusyCancellationRequested, isFalse);
      expect(
        controller.errorMessage,
        'Не удалось выполнить операцию: Ожидание Рутокена отменено.',
      );
    },
  );
}

class _PendingRutokenAdapter implements RutokenNativeAdapter {
  final Completer<void> openStarted = Completer<void>();
  final Completer<RutokenNativeSession> _open =
      Completer<RutokenNativeSession>();
  int cancelCount = 0;

  @override
  Future<RutokenNativeSession> openSession({required String pin}) {
    openStarted.complete();
    return _open.future;
  }

  @override
  Future<void> cancelPendingOperation() async {
    cancelCount++;
    if (!_open.isCompleted) {
      _open.completeError(
        const RutokenNativeException(
          'Ожидание Рутокена отменено.',
          code: 'rutoken_cancelled',
        ),
      );
    }
  }

  @override
  Future<void> closeSession(RutokenNativeSession session) async {}

  @override
  Future<WalletAccountDescriptor> importWallet({
    required RutokenNativeSession session,
    required Uint8List masterPrivateKey,
    required Uint8List chainCode,
  }) => throw UnimplementedError();

  @override
  Future<WalletAccountDescriptor?> readAccountDescriptor(
    RutokenNativeSession session,
  ) => throw UnimplementedError();

  @override
  Future<RawEcdsaSignature> signDigest({
    required RutokenNativeSession session,
    required String derivationPath,
    required Uint8List digest,
  }) => throw UnimplementedError();
}
