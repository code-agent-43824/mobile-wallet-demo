part of 'wallet_flow_screen.dart';

/// The **Активность** tab: the wallet's recent transactions.
///
/// Reads the shared [ChainDataController] rather than loading its own snapshot,
/// so switching tabs never re-fetches what the Кошелёк tab already has.
class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.chainData});

  final ChainDataController chainData;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = chainData.snapshot;

    if (chainData.isInitialLoad) {
      return const Padding(
        padding: EdgeInsets.only(top: NocturneSpacing.x8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (chainData.errorMessage case final String error) {
      return Padding(
        padding: const EdgeInsets.only(top: NocturneSpacing.x4),
        child: _ErrorBanner(message: error),
      );
    }

    final transactions = snapshot?.recentTransactions ?? const [];
    if (transactions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: NocturneSpacing.x8),
        child: Center(
          child: Text(
            'Операций пока нет',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: NocturneColors.textMuted,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chainData.isFromCache) ...[
          const _OfflineCacheBanner(),
          const SizedBox(height: NocturneSpacing.x4),
        ],
        for (final tx in transactions)
          Padding(
            padding: const EdgeInsets.only(bottom: NocturneSpacing.x3),
            child: _SummaryTile(
              label: '${tx.directionLabel} · ${tx.statusLabel}',
              value:
                  '${tx.valueFormatted}\n${tx.counterparty}\n'
                  '${tx.timestampUtc?.toIso8601String() ?? 'Время неизвестно'}',
            ),
          ),
      ],
    );
  }
}

/// The **Настройки** tab.
///
/// Holds the wallet-level switches, and is where the redesign parks the
/// technical rows (RPC endpoint, fetch time, data source, PKCS#11 session)
/// behind a «Подробности» sheet instead of showing them on the main screen.
class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.chainData,
    required this.address,
    required this.backendLabel,
    required this.biometricsEnabled,
    required this.isHardwareCustody,
    required this.externalRuntimeState,
    required this.onLock,
  });

  final ChainDataController chainData;
  final String address;
  final String backendLabel;
  final bool biometricsEnabled;
  final bool isHardwareCustody;
  final ExternalDeviceDemoRuntimeState? externalRuntimeState;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryTile(label: 'Активный адрес', value: address),
        const SizedBox(height: NocturneSpacing.x3),
        _SummaryTile(
          label: 'Хранилище ключа',
          value: isHardwareCustody ? 'Карта' : 'В этом телефоне',
        ),
        const SizedBox(height: NocturneSpacing.x3),
        _SummaryTile(
          label: 'Биометрия',
          value: biometricsEnabled ? 'Включена' : 'Выключена',
        ),
        const SizedBox(height: NocturneSpacing.x6),
        OutlinedButton(
          onPressed: () => _showDetailsSheet(context),
          child: const Text('Подробности'),
        ),
        const SizedBox(height: NocturneSpacing.x3),
        OutlinedButton(onPressed: onLock, child: const Text('Заблокировать')),
      ],
    );
  }

  /// The developer sheet. Everything here used to sit on the main screen; the
  /// redesign moves it out of the way of ordinary use without losing it.
  void _showDetailsSheet(BuildContext context) {
    final style = PlatformStyle.of(context);
    final snapshot = chainData.snapshot;
    final runtime = externalRuntimeState;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NocturneColors.surface,
      shape: RoundedRectangleBorder(borderRadius: style.sheetBorderRadius),
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(NocturneSpacing.gutter),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Подробности', style: theme.textTheme.titleLarge),
                  const SizedBox(height: NocturneSpacing.x6),
                  _SummaryTile(label: 'Backend', value: backendLabel),
                  const SizedBox(height: NocturneSpacing.x3),
                  _SummaryTile(
                    label: 'Сеть',
                    value: chainData.networkConfig.name,
                  ),
                  if (snapshot != null) ...[
                    const SizedBox(height: NocturneSpacing.x3),
                    _SummaryTile(
                      label: 'RPC endpoint',
                      value: snapshot.providerLabel,
                    ),
                    const SizedBox(height: NocturneSpacing.x3),
                    _SummaryTile(
                      label: 'Обновлено',
                      value: snapshot.fetchedAtUtc.toIso8601String(),
                    ),
                    const SizedBox(height: NocturneSpacing.x3),
                    _SummaryTile(
                      label: 'Источник данных',
                      value: snapshot.loadedFromCache
                          ? 'Локальный кэш'
                          : 'Живой запрос к сети',
                    ),
                  ],
                  if (runtime?.session
                      case final ExternalDevicePkcs11SessionSnapshot
                          session) ...[
                    const SizedBox(height: NocturneSpacing.x3),
                    _SummaryTile(
                      label: 'PKCS#11 session id',
                      value: session.sessionId,
                    ),
                    const SizedBox(height: NocturneSpacing.x3),
                    _SummaryTile(
                      label: 'PKCS#11 operations',
                      value: session.operationCount.toString(),
                    ),
                  ],
                  const SizedBox(height: NocturneSpacing.x6),
                  OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Закрыть'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shown when every live endpoint failed and the snapshot came from the local
/// cache, so the user knows the numbers may be stale.
class _OfflineCacheBanner extends StatelessWidget {
  const _OfflineCacheBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(NocturneSpacing.x4),
      decoration: BoxDecoration(
        color: NocturneColors.warning.withValues(alpha: 0.12),
        borderRadius: NocturneRadius.mdAll,
        border: Border.all(color: NocturneColors.warning),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18, color: NocturneColors.warning),
          const SizedBox(width: NocturneSpacing.x3),
          Expanded(
            child: Text(
              'Данные из локального кэша — сеть недоступна',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
