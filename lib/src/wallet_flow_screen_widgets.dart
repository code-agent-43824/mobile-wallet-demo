part of 'wallet_flow_screen.dart';

/// Full-screen progress overlay shown while a long operation (key derivation on
/// create/import/unlock) runs, so the screen isn't a frozen blank. Pairs with
/// the off-isolate PBKDF2 in PhoneSecureVault so the spinner actually animates.
class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({
    required this.message,
    required this.onCancel,
    required this.cancellationRequested,
    this.awaitingCard = false,
  });

  final String message;
  final Future<void> Function()? onCancel;
  final bool cancellationRequested;

  /// Waiting for the user to hold the card against the phone. The design gives
  /// this its own affordance — a pulsing target — instead of a generic spinner,
  /// because it asks the user to *do* something rather than just wait.
  final bool awaitingCard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                  if (awaitingCard)
                    const _CardTapPulse()
                  else
                    const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    awaitingCard ? l10n.tapCardBody : l10n.busyTakesSeconds,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (onCancel != null) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: cancellationRequested ? null : onCancel,
                      child: Text(
                        cancellationRequested
                            ? l10n.busyCancelling
                            : l10n.busyCancelNfc,
                      ),
                    ),
                  ],
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
  const _Header();

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
      ],
    );
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

/// The card-tap target: concentric rings expanding and fading on a two-second
/// loop, per the design's NFC animation.
class _CardTapPulse extends StatefulWidget {
  const _CardTapPulse();

  @override
  State<_CardTapPulse> createState() => _CardTapPulseState();
}

class _CardTapPulseState extends State<_CardTapPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Two rings a half-cycle apart, so one is always expanding.
              for (final phase in const <double>[0, 0.5])
                _PulseRing(progress: (_controller.value + phase) % 1),
              const Icon(
                Icons.contactless_outlined,
                size: 44,
                color: NocturneColors.accent,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.progress});

  /// 0 → collapsed and opaque, 1 → fully expanded and transparent.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final size = 60 + 80 * progress;
    return Opacity(
      opacity: (1 - progress).clamp(0.0, 1.0),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: NocturneColors.accent),
        ),
      ),
    );
  }
}
