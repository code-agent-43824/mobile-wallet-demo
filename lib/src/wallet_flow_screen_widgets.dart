part of 'wallet_flow_screen.dart';

/// Full-screen progress overlay shown while a long operation (key derivation on
/// create/import/unlock) runs, so the screen isn't a frozen blank. Pairs with
/// the off-isolate PBKDF2 in PhoneSecureVault so the spinner actually animates.
class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Это занимает несколько секунд.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.stage});

  final WalletFlowStage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            Icons.account_balance_wallet_outlined,
            size: 32,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Wallet Demo',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _descriptionFor(stage),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  String _descriptionFor(WalletFlowStage stage) {
    switch (stage) {
      case WalletFlowStage.loading:
        return 'Проверяю текущее состояние кошелька и подготавливаю onboarding shell.';
      case WalletFlowStage.welcome:
        return 'Следующий шаг после foundation: пользовательский onboarding flow с выбором create/import, обязательным PIN и дальнейшим переходом в lock/unlock shell.';
      case WalletFlowStage.createWallet:
        return 'Новый кошелёк начнётся с обязательного PIN, а затем приложение создаст seed-фразу и покажет её один раз.';
      case WalletFlowStage.importWallet:
        return 'Импортируем существующую seed-фразу, задаём PIN и переводим приложение в тот же защищённый shell, что и для нового кошелька.';
      case WalletFlowStage.showSeed:
        return 'Это одноразовый экран резервного сохранения seed-фразы. После закрытия приложения seed больше не должен показываться в открытом виде.';
      case WalletFlowStage.biometricPrompt:
        return 'После PIN можно включить биометрию как удобный путь разблокировки: реальную на мобильных платформах и имитацию на Windows для demo-сценария.';
      case WalletFlowStage.locked:
        return 'Кошелёк инициализирован, но заблокирован. Дальше доступ в приложение идёт через PIN, а при включённой биометрии — ещё и через быстрый biometric unlock.';
      case WalletFlowStage.unlocked:
        return 'Onboarding/auth shell готов. Теперь поверх него строим первый действительно полезный read-only wallet слой: баланс, токены, история и локальный кэш.';
      case WalletFlowStage.connections:
        return 'Подключения WalletConnect: dApp подключается к этому кошельку, присылает запросы на подпись, а кошелёк одобряет их и подписывает локальным vault. Пока работает поверх фейкового сервиса — реальный реле/SDK подключим позже.';
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

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
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}
