enum ExternalDeviceCommandKind {
  ping,
  readPublicAddress,
  signTransactionPreview,
}

class ExternalDeviceCommand {
  const ExternalDeviceCommand({required this.kind, this.payload});

  final ExternalDeviceCommandKind kind;
  final String? payload;
}

class ExternalDeviceResponse {
  const ExternalDeviceResponse({
    required this.sessionId,
    required this.command,
    required this.ok,
    required this.message,
    required this.respondedAtUtc,
  });

  final String sessionId;
  final ExternalDeviceCommand command;
  final bool ok;
  final String message;
  final DateTime respondedAtUtc;
}

class ExternalDeviceSessionSnapshot {
  const ExternalDeviceSessionSnapshot({
    required this.sessionId,
    required this.connectedAtUtc,
    required this.commandCount,
    this.lastCommandKind,
    this.lastMessage,
    this.lastCommandAtUtc,
  });

  final String sessionId;
  final DateTime connectedAtUtc;
  final int commandCount;
  final ExternalDeviceCommandKind? lastCommandKind;
  final String? lastMessage;
  final DateTime? lastCommandAtUtc;
}

abstract interface class ExternalDeviceProtocolAdapter {
  Future<ExternalDeviceResponse> sendCommand({
    required ExternalDeviceSessionSnapshot session,
    required ExternalDeviceCommand command,
    required String publicAddress,
  });
}

class DemoExternalDeviceProtocolAdapter
    implements ExternalDeviceProtocolAdapter {
  const DemoExternalDeviceProtocolAdapter();

  @override
  Future<ExternalDeviceResponse> sendCommand({
    required ExternalDeviceSessionSnapshot session,
    required ExternalDeviceCommand command,
    required String publicAddress,
  }) async {
    final now = DateTime.now().toUtc();

    return switch (command.kind) {
      ExternalDeviceCommandKind.ping => ExternalDeviceResponse(
        sessionId: session.sessionId,
        command: command,
        ok: true,
        message: 'PONG from demo external device',
        respondedAtUtc: now,
      ),
      ExternalDeviceCommandKind.readPublicAddress => ExternalDeviceResponse(
        sessionId: session.sessionId,
        command: command,
        ok: true,
        message: publicAddress,
        respondedAtUtc: now,
      ),
      ExternalDeviceCommandKind.signTransactionPreview => ExternalDeviceResponse(
        sessionId: session.sessionId,
        command: command,
        ok: true,
        message:
            'Demo device accepted signing preview: ${command.payload ?? 'no payload'}',
        respondedAtUtc: now,
      ),
    };
  }
}
