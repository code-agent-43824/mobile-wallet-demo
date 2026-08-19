part of 'wallet_flow_screen.dart';

/// The user-facing name of a network. [EvmNetworkConfig.name] is the technical
/// identifier used in diagnostics and logs; the UI shows a translated label so
/// «Тестовая сеть Sepolia» reads as what it is rather than as a chain id.
String _networkLabel(AppLocalizations l10n, EvmNetwork network) =>
    switch (network) {
      EvmNetwork.ethereumMainnet => l10n.networkMainnet,
      EvmNetwork.ethereumSepolia => l10n.networkSepolia,
    };

/// A language's name in that language — deliberately not translated, so the
/// list reads the same whichever language the app is currently showing.
String _languageName(Locale locale) => switch (locale.languageCode) {
  'en' => 'English',
  _ => 'Русский',
};

/// The **Активность** tab: the wallet's recent transactions.
///
/// Reads the shared [ChainDataController] rather than loading its own snapshot,
/// so switching tabs never re-fetches what the Кошелёк tab already has.
class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.chainData});

  final ChainDataController chainData;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            l10n.activityEmpty,
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
                  '${tx.timestampUtc?.toIso8601String() ?? l10n.activityUnknownTime}',
            ),
          ),
      ],
    );
  }
}

/// The **Настройки** tab.
///
/// Holds the wallet-level switches, and is where the redesign parks the
/// technical rows (RPC endpoint, fetch time, data source) behind a
/// «Подробности» sheet instead of showing them on the main screen.
class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.chainData,
    required this.address,
    required this.backendLabel,
    required this.currentBackendId,
    required this.biometricsEnabled,
    required this.isHardwareCustody,
    required this.onLock,
    required this.onRefresh,
    required this.onListWallets,
    required this.onSwitchWallet,
  });

  final ChainDataController chainData;
  final String address;
  final String backendLabel;
  final String currentBackendId;
  final bool biometricsEnabled;
  final bool isHardwareCustody;
  final VoidCallback onLock;
  final Future<void> Function() onRefresh;
  final Future<List<({String id, String label, String? address})>> Function()
  onListWallets;
  final Future<void> Function(String backendId) onSwitchWallet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryTile(label: l10n.settingsActiveAddress, value: address),
        const SizedBox(height: NocturneSpacing.x3),
        _SummaryTile(
          label: l10n.settingsKeyStorage,
          value: isHardwareCustody ? l10n.custodyCard : l10n.custodyPhone,
        ),
        const SizedBox(height: NocturneSpacing.x3),
        _SummaryTile(
          label: l10n.settingsKeyAccess,
          value: l10n.settingsKeyAccessViewOnly,
        ),
        const SizedBox(height: NocturneSpacing.x3),
        _SummaryTile(
          label: l10n.settingsBiometrics,
          value: biometricsEnabled ? l10n.settingsOn : l10n.settingsOff,
        ),
        const SizedBox(height: NocturneSpacing.x6),
        OutlinedButton.icon(
          onPressed: () => _showWalletSwitcher(context),
          icon: const Icon(Icons.swap_horiz),
          label: Text(l10n.settingsSwitchWallet),
        ),
        const SizedBox(height: NocturneSpacing.x3),
        if (AppLocaleScope.maybeOf(context) != null)
          OutlinedButton.icon(
            onPressed: () => _showLanguageSheet(context),
            icon: const Icon(Icons.translate),
            label: Text(l10n.settingsLanguage),
          ),
        const SizedBox(height: NocturneSpacing.x3),
        OutlinedButton(
          onPressed: () => _showDetailsSheet(context),
          child: Text(l10n.settingsDetails),
        ),
        const SizedBox(height: NocturneSpacing.x6),
        Wrap(
          spacing: NocturneSpacing.x4,
          runSpacing: NocturneSpacing.x4,
          children: [
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.settingsRefreshChain),
            ),
            if (!isHardwareCustody)
              OutlinedButton.icon(
                onPressed: onLock,
                icon: const Icon(Icons.lock_outline),
                label: Text(l10n.settingsLockAgain),
              ),
          ],
        ),
      ],
    );
  }

  /// Language picker. Each option is written in its own language, so it stays
  /// readable to someone who opened the app in a language they do not read;
  /// "system" clears the stored choice and follows the device again.
  void _showLanguageSheet(BuildContext context) {
    final scope = AppLocaleScope.maybeOf(context);
    if (scope == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final style = PlatformStyle.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NocturneColors.surface,
      shape: RoundedRectangleBorder(borderRadius: style.sheetBorderRadius),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: NocturneSpacing.x6),
            for (final option in <({Locale? locale, String label})>[
              (locale: null, label: l10n.settingsLanguageSystem),
              for (final locale in selectableLocales)
                (locale: locale, label: _languageName(locale)),
            ])
              ListTile(
                title: Text(option.label),
                trailing:
                    option.locale?.languageCode == scope.locale?.languageCode
                    ? const Icon(Icons.check, color: NocturneColors.accent)
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  scope.onLocaleChanged(option.locale);
                },
              ),
            const SizedBox(height: NocturneSpacing.x4),
          ],
        ),
      ),
    );
  }

  /// Switches between the storage backends that can hold a wallet — the phone
  /// vault and a registered card. Deliberately plain for now:
  /// it exists so a tester can move between wallets without reinstalling.
  void _showWalletSwitcher(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = PlatformStyle.of(context);
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
            child:
                FutureBuilder<
                  List<({String id, String label, String? address})>
                >(
                  future: onListWallets(),
                  builder: (builderContext, snapshot) {
                    final wallets = snapshot.data;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.walletsTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: NocturneSpacing.x4),
                        if (wallets == null)
                          const Padding(
                            padding: EdgeInsets.all(NocturneSpacing.x8),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else
                          for (final wallet in wallets)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(wallet.label),
                              // The address is what tells two wallets apart
                              // once the storage names stop being unique.
                              subtitle: Text(
                                wallet.address ?? l10n.walletsEmptySlot,
                                style: theme.textTheme.bodySmall,
                              ),
                              trailing: wallet.id == currentBackendId
                                  ? const Icon(
                                      Icons.check,
                                      color: NocturneColors.accent,
                                    )
                                  : null,
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                onSwitchWallet(wallet.id);
                              },
                            ),
                        const SizedBox(height: NocturneSpacing.x4),
                        OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(l10n.actionClose),
                        ),
                      ],
                    );
                  },
                ),
          ),
        );
      },
    );
  }

  /// The developer sheet. Everything here used to sit on the main screen; the
  /// redesign moves it out of the way of ordinary use without losing it.
  void _showDetailsSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = PlatformStyle.of(context);
    final snapshot = chainData.snapshot;

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
                  Text(l10n.settingsDetails, style: theme.textTheme.titleLarge),
                  const SizedBox(height: NocturneSpacing.x6),
                  _SummaryTile(
                    label: l10n.settingsKeyStorage,
                    value: backendLabel,
                  ),
                  const SizedBox(height: NocturneSpacing.x3),
                  _SummaryTile(
                    label: l10n.detailsNetwork,
                    value: _networkLabel(l10n, chainData.selectedNetwork),
                  ),
                  if (snapshot != null) ...[
                    const SizedBox(height: NocturneSpacing.x3),
                    _SummaryTile(
                      label: 'RPC endpoint',
                      value: snapshot.providerLabel,
                    ),
                    const SizedBox(height: NocturneSpacing.x3),
                    _SummaryTile(
                      label: l10n.detailsUpdated,
                      value: snapshot.fetchedAtUtc.toIso8601String(),
                    ),
                    const SizedBox(height: NocturneSpacing.x3),
                    _SummaryTile(
                      label: l10n.detailsSource,
                      value: snapshot.loadedFromCache
                          ? l10n.detailsSourceCache
                          : l10n.detailsSourceLive,
                    ),
                  ],
                  const SizedBox(height: NocturneSpacing.x6),
                  OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: Text(l10n.actionClose),
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
    final l10n = AppLocalizations.of(context);
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
              l10n.walletOfflineCache,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// The **Кошелёк** tab: the balance hero, the quick actions and the asset list,
/// with the loading, empty and offline-cache states the design models.
class _WalletTab extends StatefulWidget {
  const _WalletTab({
    required this.chainData,
    required this.address,
    required this.transactionService,
    required this.trackingTransport,
    required this.canUnlockWithBiometrics,
    required this.onAuthorizeAndSubmit,
    required this.onScan,
  });

  final ChainDataController chainData;
  final String address;
  final TransactionService transactionService;
  final JsonRpcTransport trackingTransport;
  final bool canUnlockWithBiometrics;
  final AuthorizeAndSubmitTransfer onAuthorizeAndSubmit;

  /// Opens the surface where scanning happens (the Связи tab), so the design's
  /// third quick action leads somewhere real instead of being a dead button.
  final VoidCallback onScan;

  @override
  State<_WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<_WalletTab> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chainData = widget.chainData;
    final snapshot = chainData.snapshot;
    final config = chainData.networkConfig;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NetworkChip(
          label: _networkLabel(l10n, chainData.selectedNetwork),
          onTap: () => _showNetworkSheet(context),
        ),
        const SizedBox(height: NocturneSpacing.x6),

        if (chainData.isInitialLoad)
          const _BalanceSkeleton()
        else ...[
          if (chainData.isFromCache) ...[
            const _OfflineCacheBanner(),
            const SizedBox(height: NocturneSpacing.x6),
          ],
          if (chainData.errorMessage case final String error) ...[
            _ErrorBanner(message: error),
            const SizedBox(height: NocturneSpacing.x4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: chainData.refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.actionRetry),
              ),
            ),
            const SizedBox(height: NocturneSpacing.x6),
          ],
          if (snapshot != null)
            _BalanceHero(
              amount: snapshot.nativeBalanceFormatted,
              symbol: config.nativeSymbol,
            )
          else if (chainData.errorMessage == null)
            // Never leave the tab blank: with no snapshot, no error and nothing
            // loading there would otherwise be only the chip and the actions.
            _NoDataYet(onRetry: chainData.refresh),
          const SizedBox(height: NocturneSpacing.x8),
          _QuickActions(
            onSend: snapshot == null
                ? null
                : () => _showSendSheet(context, snapshot, config),
            onReceive: () => _showReceiveSheet(context),
            onScan: widget.onScan,
          ),
          if (snapshot != null) ...[
            const SizedBox(height: NocturneSpacing.x8),
            _AssetList(snapshot: snapshot, nativeSymbol: config.nativeSymbol),
          ],
        ],
      ],
    );
  }

  /// The transfer form lives in a sheet rather than on the wallet screen, so
  /// the screen shows balance and assets and the form appears only when asked
  /// for. Scroll-controlled and inset-aware because the form is tall and the
  /// keyboard covers it otherwise.
  void _showSendSheet(
    BuildContext context,
    WalletChainSnapshot snapshot,
    EvmNetworkConfig config,
  ) {
    final l10n = AppLocalizations.of(context);
    final style = PlatformStyle.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NocturneColors.surface,
      shape: RoundedRectangleBorder(borderRadius: style.sheetBorderRadius),
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NocturneSpacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The sheet keeps showing the send result after the operation,
                // so it needs its own way out — the back gesture alone is not
                // an affordance.
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: l10n.actionClose,
                  ),
                ),
                _TransferPreparationSection(
                  snapshot: snapshot,
                  fromAddress: widget.address,
                  networkConfig: config,
                  transactionService: widget.transactionService,
                  trackingTransport: widget.trackingTransport,
                  canUnlockWithBiometrics: widget.canUnlockWithBiometrics,
                  onAuthorizeAndSubmit: widget.onAuthorizeAndSubmit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNetworkSheet(BuildContext context) {
    final style = PlatformStyle.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NocturneColors.surface,
      shape: RoundedRectangleBorder(borderRadius: style.sheetBorderRadius),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: NocturneSpacing.x6),
            for (final network in EvmNetwork.values)
              ListTile(
                title: Text(
                  _networkLabel(AppLocalizations.of(sheetContext), network),
                ),
                trailing: network == widget.chainData.selectedNetwork
                    ? const Icon(Icons.check, color: NocturneColors.accent)
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  widget.chainData.selectNetwork(network);
                },
              ),
            const SizedBox(height: NocturneSpacing.x4),
          ],
        ),
      ),
    );
  }

  void _showReceiveSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = PlatformStyle.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: NocturneColors.surface,
      shape: RoundedRectangleBorder(borderRadius: style.sheetBorderRadius),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(NocturneSpacing.gutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.receiveTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: NocturneSpacing.x6),
                SelectableText(
                  widget.address,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: NocturneSpacing.x8),
                OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(l10n.actionClose),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The network selector chip above the balance.
class _NetworkChip extends StatelessWidget {
  const _NetworkChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: NocturneColors.surface,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            border: Border.all(color: NocturneColors.neutral800),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: NocturneColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: NocturneSpacing.x3),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: NocturneSpacing.x2),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: NocturneColors.textSubtle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The balance figure. Deliberately the largest thing on the screen.
class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.amount, required this.symbol});

  final String amount;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.walletBalance,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: NocturneColors.textSubtle),
        ),
        const SizedBox(height: NocturneSpacing.x2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: NocturneType.family,
                  fontSize: 40,
                  height: 1.05,
                  letterSpacing: -0.8,
                  fontWeight: NocturneType.medium,
                  color: NocturneColors.text,
                ),
              ),
            ),
            const SizedBox(width: NocturneSpacing.x3),
            Text(
              symbol,
              style: const TextStyle(
                fontFamily: NocturneType.family,
                fontSize: 17,
                color: NocturneColors.textSubtle,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Skeleton bars shown while the first snapshot loads — the design calls for a
/// skeleton rather than a spinner so the layout does not jump.
class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: NocturneSpacing.x4),
      decoration: BoxDecoration(
        color: NocturneColors.neutral900,
        borderRadius: NocturneRadius.smAll,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bar(90, 13), bar(210, 40), bar(150, 15), bar(180, 15)],
    );
  }
}

/// Отправить / Получить / Сканировать.
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onSend,
    required this.onReceive,
    required this.onScan,
  });

  final VoidCallback? onSend;
  final VoidCallback onReceive;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.north_east,
            label: l10n.actionSend,
            onTap: onSend,
          ),
        ),
        Expanded(
          child: _QuickAction(
            icon: Icons.south_west,
            label: l10n.actionReceive,
            onTap: onReceive,
          ),
        ),
        Expanded(
          child: _QuickAction(
            icon: Icons.qr_code_scanner,
            label: l10n.actionScan,
            onTap: onScan,
          ),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled
        ? NocturneColors.accent
        : NocturneColors.text.withValues(alpha: 0.45);

    return InkWell(
      onTap: onTap,
      borderRadius: NocturneRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NocturneSpacing.x4),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: NocturneSpacing.x2),
            Text(
              label,
              style: TextStyle(
                fontFamily: NocturneType.family,
                fontSize: 13,
                fontWeight: NocturneType.medium,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The asset list: the native coin first, then any tokens.
class _AssetList extends StatelessWidget {
  const _AssetList({required this.snapshot, required this.nativeSymbol});

  final WalletChainSnapshot snapshot;
  final String nativeSymbol;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (snapshot.nativeBalanceWei == BigInt.zero &&
        snapshot.tokenBalances.isEmpty) {
      return const _EmptyWallet();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: NocturneSpacing.x3),
          child: Text(l10n.walletAssets, style: theme.textTheme.labelSmall),
        ),
        _AssetRow(
          short: nativeSymbol,
          name: nativeSymbol,
          sub: l10n.walletNativeCoin,
          amount: snapshot.nativeBalanceFormatted,
        ),
        for (final token in snapshot.tokenBalances)
          _AssetRow(
            short: token.symbol,
            name: token.name,
            sub: token.symbol,
            amount: token.balanceFormatted,
          ),
      ],
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.short,
    required this.name,
    required this.sub,
    required this.amount,
  });

  final String short;
  final String name;
  final String sub;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NocturneSpacing.x3),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: NocturneColors.neutral900,
              shape: BoxShape.circle,
            ),
            child: Text(
              short.length <= 3 ? short : short.substring(0, 3),
              style: const TextStyle(
                fontFamily: NocturneType.family,
                fontSize: 12,
                fontWeight: NocturneType.semibold,
                color: NocturneColors.neutral300,
              ),
            ),
          ),
          const SizedBox(width: NocturneSpacing.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.bodyMedium),
                Text(
                  sub,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: NocturneColors.textSubtle,
                  ),
                ),
              ],
            ),
          ),
          Text(amount, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// The empty-wallet state: what to do next, not just "nothing here".
class _EmptyWallet extends StatelessWidget {
  const _EmptyWallet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.walletEmptyTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: NocturneSpacing.x2),
        Text(
          l10n.walletEmptyBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: NocturneColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// Shown when the tab has no snapshot to render and no error to explain why —
/// a state that must never render as an empty screen.
class _NoDataYet extends StatelessWidget {
  const _NoDataYet({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.walletNoDataTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: NocturneSpacing.x2),
        Text(
          l10n.walletNoDataBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: NocturneColors.textMuted,
          ),
        ),
        const SizedBox(height: NocturneSpacing.x4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l10n.actionRetry),
          ),
        ),
      ],
    );
  }
}

/// The entered-PIN indicator: one filled dot per digit.
///
/// Shows length only — never the digits — so a shoulder-surfer learns nothing
/// beyond how long the PIN is.
class _PinDots extends StatelessWidget {
  const _PinDots({required this.length});

  final int length;

  /// Dots always drawn, so the row does not jump as the PIN grows.
  static const int _slots = 4;

  @override
  Widget build(BuildContext context) {
    final count = length > _slots ? length : _slots;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: NocturneSpacing.x2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < length ? NocturneColors.accent : Colors.transparent,
              border: Border.all(
                color: i < length
                    ? NocturneColors.accent
                    : NocturneColors.outlineFaint,
              ),
            ),
          ),
      ],
    );
  }
}

/// The numeric keypad. Key shape and fill come from [PlatformStyle]: circular
/// keys on a faint tint for iOS, 16dp rounded keys on the surface for Android.
class _PinKeypad extends StatelessWidget {
  const _PinKeypad({
    required this.style,
    required this.onDigit,
    required this.onBackspace,
  });

  final PlatformStyle style;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'del'],
    ];

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: NocturneSpacing.x3),
            child: Row(
              children: [
                for (final key in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NocturneSpacing.x2,
                      ),
                      child: _PinKey(
                        key: ValueKey<String>('pin-key-$key'),
                        label: key,
                        style: style,
                        onTap: key.isEmpty
                            ? null
                            : key == 'del'
                            ? onBackspace
                            : () => onDigit(key),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({
    super.key,
    required this.label,
    required this.style,
    required this.onTap,
  });

  final String label;
  final PlatformStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) {
      return const SizedBox(height: 56);
    }
    final radius = BorderRadius.circular(style.keypadKeyRadius);
    return Material(
      color: style.keypadKeyFill,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          height: 56,
          child: Center(
            child: label == 'del'
                ? const Icon(Icons.backspace_outlined, size: 20)
                : Text(
                    label,
                    style: const TextStyle(
                      fontFamily: NocturneType.family,
                      fontSize: 24,
                      fontWeight: NocturneType.medium,
                      color: NocturneColors.text,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
