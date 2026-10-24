part of 'wallet_flow_screen.dart';

/// Runs one private-key operation as a single sheet that walks the design's
/// confirmation pattern — PIN → signing (or the card tap) → result — instead
/// of stacking a PIN sheet under the root busy overlay.
///
/// [run] performs the operation through the controller, which reports a
/// failure via [WalletFlowController.errorMessage]; the sheet shows it in its
/// own result step and clears it, so it is not repeated in the page banner.
/// [successBody] is read after success, so it can quote what the operation
/// produced. Returns true when the operation succeeded.
Future<bool> _confirmOperation(
  BuildContext context, {
  required WalletFlowController controller,
  required String reason,
  required bool biometricsOffered,
  required Future<void> Function(String? pin, bool useBiometrics) run,
  required String Function() successBody,
}) async {
  final style = PlatformStyle.of(context);
  controller.beginInlineConfirmation();
  try {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: NocturneColors.surface,
      shape: RoundedRectangleBorder(borderRadius: style.sheetBorderRadius),
      builder: (sheetContext) => _ConfirmationSheet(
        controller: controller,
        reason: reason,
        biometricsOffered: biometricsOffered,
        run: run,
        successBody: successBody,
      ),
    );
    return result ?? false;
  } finally {
    controller.endInlineConfirmation();
  }
}

enum _ConfirmStep { pin, working, done, failed }

class _ConfirmationSheet extends StatefulWidget {
  const _ConfirmationSheet({
    required this.controller,
    required this.reason,
    required this.biometricsOffered,
    required this.run,
    required this.successBody,
  });

  final WalletFlowController controller;
  final String reason;
  final bool biometricsOffered;
  final Future<void> Function(String? pin, bool useBiometrics) run;
  final String Function() successBody;

  @override
  State<_ConfirmationSheet> createState() => _ConfirmationSheetState();
}

class _ConfirmationSheetState extends State<_ConfirmationSheet> {
  _ConfirmStep _step = _ConfirmStep.pin;
  String? _failure;

  Future<void> _start(String? pin, bool useBiometrics) async {
    setState(() => _step = _ConfirmStep.working);
    await widget.run(pin, useBiometrics);
    if (!mounted) return;
    final failure = widget.controller.errorMessage;
    if (failure != null) {
      widget.controller.clearError();
    }
    setState(() {
      _failure = failure;
      _step = failure == null ? _ConfirmStep.done : _ConfirmStep.failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      // Leaving mid-signature would orphan the operation's progress, so the
      // back gesture waits for the result like the buttons do.
      canPop: _step != _ConfirmStep.working,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: NocturneSpacing.gutter,
            right: NocturneSpacing.gutter,
            top: NocturneSpacing.x8,
            bottom:
                NocturneSpacing.x8 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (_step) {
              _ConfirmStep.pin => _PinEntryPanel(
                key: const ValueKey<String>('confirm-pin'),
                reason: widget.reason,
                biometricsOffered: widget.biometricsOffered,
                onPin: (pin) => _start(pin, false),
                onBiometrics: () => _start(null, true),
                onCancel: () => Navigator.of(context).pop(false),
              ),
              _ConfirmStep.working => _OperationProgress(
                key: const ValueKey<String>('confirm-working'),
                controller: widget.controller,
              ),
              _ConfirmStep.done => _OperationResult(
                key: const ValueKey<String>('confirm-done'),
                success: true,
                title: l10n.confirmSuccessTitle,
                body: widget.successBody(),
                primaryLabel: l10n.actionContinue,
                onPrimary: () => Navigator.of(context).pop(true),
              ),
              _ConfirmStep.failed => _OperationResult(
                key: const ValueKey<String>('confirm-failed'),
                success: false,
                title: l10n.confirmFailureTitle,
                body: _failure ?? '',
                primaryLabel: l10n.actionRetry,
                onPrimary: () => setState(() => _step = _ConfirmStep.pin),
                secondaryLabel: l10n.actionClose,
                onSecondary: () => Navigator.of(context).pop(false),
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// The PIN step: keypad, the biometric fast path when offered, and a way out.
///
/// The keypad keeps the PIN off the system keyboard (and its clipboard,
/// autofill and prediction paths).
class _PinEntryPanel extends StatefulWidget {
  const _PinEntryPanel({
    super.key,
    required this.reason,
    required this.biometricsOffered,
    required this.onPin,
    required this.onBiometrics,
    required this.onCancel,
  });

  final String reason;
  final bool biometricsOffered;
  final ValueChanged<String> onPin;
  final VoidCallback onBiometrics;
  final VoidCallback onCancel;

  @override
  State<_PinEntryPanel> createState() => _PinEntryPanelState();
}

class _PinEntryPanelState extends State<_PinEntryPanel> {
  String _pin = '';

  static const int _maxPinLength = 12;

  void _append(String digit) {
    if (_pin.length >= _maxPinLength) return;
    setState(() => _pin += digit);
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = PlatformStyle.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.authConfirmTitle,
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: NocturneSpacing.x3),
        Text(
          widget.reason,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: NocturneColors.textMuted,
          ),
        ),
        const SizedBox(height: NocturneSpacing.x8),
        _PinDots(length: _pin.length),
        const SizedBox(height: NocturneSpacing.x8),
        _PinKeypad(style: style, onDigit: _append, onBackspace: _backspace),
        const SizedBox(height: NocturneSpacing.x6),
        OutlinedButton(
          onPressed: _pin.isEmpty ? null : () => widget.onPin(_pin),
          child: Text(l10n.authConfirmAction),
        ),
        if (widget.biometricsOffered) ...[
          const SizedBox(height: NocturneSpacing.x3),
          TextButton.icon(
            onPressed: widget.onBiometrics,
            icon: const Icon(Icons.fingerprint, size: 20),
            label: Text(l10n.unlockWithBiometrics),
          ),
        ],
        const SizedBox(height: NocturneSpacing.x3),
        TextButton(onPressed: widget.onCancel, child: Text(l10n.actionCancel)),
      ],
    );
  }
}

/// The signing step, drawn from the controller's busy state: the pulsing card
/// target while the card must be held to the phone (with its cancel action),
/// otherwise a spinner with what is happening.
class _OperationProgress extends StatelessWidget {
  const _OperationProgress({super.key, required this.controller});

  final WalletFlowController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final awaitingCard = controller.isAwaitingCard;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: NocturneSpacing.x6),
            if (awaitingCard)
              const _CardTapPulse()
            else
              const SizedBox(
                height: 64,
                width: 64,
                child: CircularProgressIndicator(),
              ),
            const SizedBox(height: NocturneSpacing.x8),
            Text(
              awaitingCard
                  ? l10n.tapCardTitle
                  : controller.busyMessage ?? l10n.busyUnlockingForSignature,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: NocturneSpacing.x3),
            Text(
              awaitingCard ? l10n.tapCardSignBody : l10n.busyTakesSeconds,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: NocturneColors.textMuted,
              ),
            ),
            if (controller.canCancelBusyOperation) ...[
              const SizedBox(height: NocturneSpacing.x6),
              TextButton(
                onPressed: controller.isBusyCancellationRequested
                    ? null
                    : controller.cancelBusyOperation,
                child: Text(
                  controller.isBusyCancellationRequested
                      ? l10n.busyCancelling
                      : l10n.busyCancelNfc,
                ),
              ),
            ],
            const SizedBox(height: NocturneSpacing.x6),
          ],
        );
      },
    );
  }
}

/// The result step: what happened, in one sentence, and where to go next.
class _OperationResult extends StatelessWidget {
  const _OperationResult({
    super.key,
    required this.success,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.details,
  });

  final bool success;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Extra content between the sentence and the actions (a hash, a status).
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          success ? Icons.check_circle_outline : Icons.error_outline,
          size: 48,
          color: success ? NocturneColors.success : NocturneColors.danger,
        ),
        const SizedBox(height: NocturneSpacing.x4),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: NocturneSpacing.x3),
        Text(
          body,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: NocturneColors.textMuted,
          ),
        ),
        if (details case final Widget extra) ...[
          const SizedBox(height: NocturneSpacing.x6),
          extra,
        ],
        const SizedBox(height: NocturneSpacing.x8),
        OutlinedButton(onPressed: onPrimary, child: Text(primaryLabel)),
        if (secondaryLabel case final String label) ...[
          const SizedBox(height: NocturneSpacing.x3),
          TextButton(onPressed: onSecondary, child: Text(label)),
        ],
      ],
    );
  }
}
