part of 'wallet_flow_screen.dart';

/// The Connections screen (Phase 9 chunk 9.4b): WalletConnect status, a
/// "new connection" `wc:` URI field, the incoming session-proposal approval
/// card, and the active-session list with disconnect. Driven by the
/// [WalletFlowController] WC seam (9.4a); works on the fake service until the
/// real `reown_walletkit` impl (9.2) lands.
class _ConnectionsStage extends StatefulWidget {
  const _ConnectionsStage({
    required this.isAvailable,
    required this.sessions,
    required this.pendingProposal,
    required this.pendingRequest,
    required this.walletAddress,
    required this.onPair,
    required this.onApprove,
    required this.onReject,
    required this.onApproveRequest,
    required this.onRejectRequest,
    required this.onDisconnect,
    required this.onBack,
  });

  final bool isAvailable;
  final List<WalletConnectSession> sessions;
  final WalletConnectSessionProposal? pendingProposal;
  final WalletConnectRequest? pendingRequest;
  final String? walletAddress;
  final Future<void> Function({required String uri}) onPair;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final Future<void> Function() onApproveRequest;
  final Future<void> Function() onRejectRequest;
  final Future<void> Function(String topic) onDisconnect;
  final VoidCallback onBack;

  @override
  State<_ConnectionsStage> createState() => _ConnectionsStageState();
}

class _ConnectionsStageState extends State<_ConnectionsStage> {
  final TextEditingController _uriController = TextEditingController();

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final uri = _uriController.text.trim();
    if (uri.isEmpty) {
      return;
    }
    await widget.onPair(uri: uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proposal = widget.pendingProposal;
    final request = widget.pendingRequest;
    final sessions = widget.sessions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Подключения WalletConnect'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(
              label: widget.isAvailable
                  ? 'WalletConnect доступен'
                  : 'WalletConnect не настроен',
            ),
            _StatusChip(label: 'Активных сессий: ${sessions.length}'),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Новое подключение'),
        const SizedBox(height: 8),
        const Text(
          'Вставьте wc: URI из dApp (обычно из QR-кода), чтобы создать пару.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _uriController,
          decoration: const InputDecoration(
            labelText: 'wc: URI',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: widget.isAvailable ? _pair : null,
          icon: const Icon(Icons.link),
          label: const Text('Подключить'),
        ),
        if (proposal != null) ...[
          const SizedBox(height: 24),
          _ProposalCard(
            proposal: proposal,
            onApprove: widget.walletAddress == null ? null : widget.onApprove,
            onReject: widget.onReject,
          ),
        ],
        if (request != null) ...[
          const SizedBox(height: 24),
          _RequestCard(
            request: request,
            onApprove: widget.onApproveRequest,
            onReject: widget.onRejectRequest,
          ),
        ],
        const SizedBox(height: 24),
        const _SectionTitle('Активные сессии'),
        const SizedBox(height: 12),
        if (sessions.isEmpty)
          Text(
            'Нет активных подключений.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...sessions.map(
            (session) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SessionCard(
                session: session,
                onDisconnect: () => widget.onDisconnect(session.topic),
              ),
            ),
          ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Назад к кошельку'),
        ),
      ],
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.onApprove,
    required this.onReject,
  });

  final WalletConnectSessionProposal proposal;
  final Future<void> Function()? onApprove;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Запрос на подключение',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(proposal.peer.name, style: theme.textTheme.bodyLarge),
          if (proposal.peer.url.isNotEmpty)
            Text(
              proposal.peer.url,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          Text('Сети: ${proposal.requiredChains.join(', ')}'),
          Text('Методы: ${proposal.requiredMethods.join(', ')}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: onApprove, child: const Text('Одобрить')),
              OutlinedButton(
                onPressed: onReject,
                child: const Text('Отклонить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final WalletConnectRequest request;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = request.params.isNotEmpty && request.params.first is Map
        ? (request.params.first! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final to = tx['to']?.toString();
    final value = tx['value']?.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Входящий запрос на подпись',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text('Метод: ${request.method}'),
          Text('Сеть: ${request.chainId}'),
          if (to != null) Text('Получатель: $to'),
          if (value != null) Text('Сумма (wei): $value'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: onApprove,
                child: const Text('Одобрить и подписать'),
              ),
              OutlinedButton(
                onPressed: onReject,
                child: const Text('Отклонить запрос'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onDisconnect});

  final WalletConnectSession session;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.peer.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (session.peer.url.isNotEmpty)
            Text(
              session.peer.url,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 6),
          Text('Сети: ${session.chains.join(', ')}'),
          Text('Аккаунты: ${session.accounts.join(', ')}'),
          const SizedBox(height: 4),
          Text(
            'Подключено: ${session.connectedAtUtc.toIso8601String()}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onDisconnect,
            icon: const Icon(Icons.link_off),
            label: const Text('Отключить'),
          ),
        ],
      ),
    );
  }
}
