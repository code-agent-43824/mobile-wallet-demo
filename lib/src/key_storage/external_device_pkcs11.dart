enum ExternalDevicePkcs11OperationKind {
  probeSession,
  readPublicAddress,
  signTransactionPreview,
}

class ExternalDevicePkcs11Operation {
  const ExternalDevicePkcs11Operation({required this.kind, this.payload});

  final ExternalDevicePkcs11OperationKind kind;
  final String? payload;
}

class ExternalDevicePkcs11Result {
  const ExternalDevicePkcs11Result({
    required this.sessionId,
    required this.operation,
    required this.ok,
    required this.message,
    required this.respondedAtUtc,
  });

  final String sessionId;
  final ExternalDevicePkcs11Operation operation;
  final bool ok;
  final String message;
  final DateTime respondedAtUtc;
}

class ExternalDevicePkcs11SessionSnapshot {
  const ExternalDevicePkcs11SessionSnapshot({
    required this.sessionId,
    required this.connectedAtUtc,
    required this.operationCount,
    this.lastOperationKind,
    this.lastMessage,
    this.lastOperationAtUtc,
  });

  final String sessionId;
  final DateTime connectedAtUtc;
  final int operationCount;
  final ExternalDevicePkcs11OperationKind? lastOperationKind;
  final String? lastMessage;
  final DateTime? lastOperationAtUtc;
}

abstract interface class ExternalDevicePkcs11Adapter {
  Future<ExternalDevicePkcs11Result> performOperation({
    required ExternalDevicePkcs11SessionSnapshot session,
    required ExternalDevicePkcs11Operation operation,
    required String publicAddress,
  });
}

class DemoExternalDevicePkcs11Adapter implements ExternalDevicePkcs11Adapter {
  const DemoExternalDevicePkcs11Adapter();

  @override
  Future<ExternalDevicePkcs11Result> performOperation({
    required ExternalDevicePkcs11SessionSnapshot session,
    required ExternalDevicePkcs11Operation operation,
    required String publicAddress,
  }) async {
    final now = DateTime.now().toUtc();

    return switch (operation.kind) {
      ExternalDevicePkcs11OperationKind.probeSession =>
        ExternalDevicePkcs11Result(
          sessionId: session.sessionId,
          operation: operation,
          ok: true,
          message: 'PKCS#11 session is alive on demo external device',
          respondedAtUtc: now,
        ),
      ExternalDevicePkcs11OperationKind.readPublicAddress =>
        ExternalDevicePkcs11Result(
          sessionId: session.sessionId,
          operation: operation,
          ok: true,
          message: publicAddress,
          respondedAtUtc: now,
        ),
      ExternalDevicePkcs11OperationKind.signTransactionPreview =>
        ExternalDevicePkcs11Result(
          sessionId: session.sessionId,
          operation: operation,
          ok: true,
          message:
              'Demo PKCS#11 signer accepted transaction preview: ${operation.payload ?? 'no payload'}',
          respondedAtUtc: now,
        ),
    };
  }
}
