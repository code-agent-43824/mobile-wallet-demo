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
      backgroundColor: context.nocturne.surface,
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
      // Scrolls when the content outgrows the window: large Dynamic Type, or a
      // short window on its side.
      child: _SheetSafeArea(
        child: SingleChildScrollView(
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
    this.title,
    this.confirmLabel,
    this.leading,
    this.sideBySide,
    this.keyHeight = _PinKeypad.defaultKeyHeight,
    this.splitAtY,
  });

  /// Free of keys around the window's middle, where a foldable bends. Flutter
  /// on iOS reports no fold (`displayFeatures` is empty on iPhone Duo), so the
  /// panel keeps the band around the window's centre lines clear instead: two
  /// columns sit either side of the vertical one, and on the lock screen of a
  /// tall window the keypad starts below the horizontal one (owner, iPhone Duo,
  /// 2026-11-26: keys landed on the fold).
  static const double middleGap = 64;

  /// Each column's least width when they part around the middle; a narrower
  /// panel keeps its two columns together (a closed iPhone Duo on its side).
  static const double _minHalfWidth = 260;

  final String reason;
  final bool biometricsOffered;
  final ValueChanged<String> onPin;
  final VoidCallback onBiometrics;

  /// Null where there is nowhere to go back to (the lock screen).
  final VoidCallback? onCancel;

  /// Defaults to the confirmation wording; the lock screen names itself.
  final String? title;
  final String? confirmLabel;

  /// Shown above the title, in the prompt's column (the lock screen's wallet).
  final Widget? leading;

  /// Whether the keypad goes beside the prompt rather than under it. Null
  /// decides by the window, which suits a sheet: a sheet scrolls, so the space
  /// it is given says nothing about the space it has.
  final bool? sideBySide;

  final double keyHeight;

  /// Where, from the panel's top, the window's middle falls: the prompt ends
  /// above it and the keypad starts below, [middleGap] apart. Only the lock
  /// screen sets it — a sheet grows from the bottom, so its middle would move
  /// with its own height.
  final double? splitAtY;

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

  /// Hands the PIN over and forgets it, so a failed attempt starts clean.
  void _submit() {
    final pin = _pin;
    setState(() => _pin = '');
    widget.onPin(pin);
  }

  /// A window lower than this cannot stack the keypad under the prompt — a
  /// phone or a closed iPhone Duo on its side — so the two go side by side
  /// when there is the width for it.
  static const double _sideBySideBelowHeight = 600;
  static const double _sideBySideMinWidth = 560;

  /// Wider than this, the keys would stretch into long bars; the column of
  /// prompt, keypad and button keeps a phone's proportions instead.
  static const double _stackedMaxWidth = 400;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = PlatformStyle.of(context);
    final l10n = AppLocalizations.of(context);
    final prompt = <Widget>[
      if (widget.leading case final Widget leading) ...[
        leading,
        const SizedBox(height: NocturneSpacing.x6),
      ],
      Text(
        widget.title ?? l10n.authConfirmTitle,
        style: theme.textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: NocturneSpacing.x3),
      Text(
        widget.reason,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: context.nocturne.textMuted,
        ),
      ),
      const SizedBox(height: NocturneSpacing.x8),
      _PinDots(length: _pin.length, maxLength: _maxPinLength),
      if (widget.biometricsOffered) ...[
        const SizedBox(height: NocturneSpacing.x3),
        TextButton.icon(
          onPressed: widget.onBiometrics,
          icon: const Icon(Icons.fingerprint, size: 20),
          label: Text(l10n.unlockWithBiometrics),
        ),
      ],
    ];
    final keypad = _PinKeypad(
      style: style,
      keyHeight: widget.keyHeight,
      onDigit: _append,
      onBackspace: _backspace,
    );
    final actions = <Widget>[
      OutlinedButton(
        onPressed: _pin.isEmpty ? null : _submit,
        child: Text(widget.confirmLabel ?? l10n.authConfirmAction),
      ),
      if (widget.onCancel case final VoidCallback cancel) ...[
        const SizedBox(height: NocturneSpacing.x3),
        TextButton(onPressed: cancel, child: Text(l10n.actionCancel)),
      ],
    ];

    final window = MediaQuery.sizeOf(context);
    return _WindowMiddle(
      builder: (context, middle) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          const gap = _PinEntryPanel.middleGap;
          const minHalf = _PinEntryPanel._minHalfWidth;
          final parts = width >= 2 * minHalf + gap;
          final sideBySide =
              widget.sideBySide ??
              (parts ||
                  (window.height < _sideBySideBelowHeight &&
                      window.width >= _sideBySideMinWidth));
          if (sideBySide) {
            final promptColumn = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...prompt,
                const SizedBox(height: NocturneSpacing.x6),
                ...actions,
              ],
            );
            final keypadColumn = Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _stackedMaxWidth),
                child: keypad,
              ),
            );
            if (!parts) {
              return Row(
                children: [
                  Expanded(child: promptColumn),
                  const SizedBox(width: NocturneSpacing.x8),
                  Expanded(child: keypadColumn),
                ],
              );
            }
            final split = middle?.dx ?? width / 2;
            final leftWidth = (split - gap / 2).clamp(
              minHalf,
              width - gap - minHalf,
            );
            return Row(
              children: [
                SizedBox(
                  width: leftWidth,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _stackedMaxWidth,
                      ),
                      child: promptColumn,
                    ),
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(child: keypadColumn),
              ],
            );
          }
          final splitAtY = widget.splitAtY;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _stackedMaxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (splitAtY == null) ...[
                    ...prompt,
                    const SizedBox(height: NocturneSpacing.x8),
                  ] else ...[
                    // At least down to the band; a taller prompt pushes the
                    // keypad lower still, never into the band.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (splitAtY - gap / 2).clamp(
                          0,
                          double.infinity,
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: prompt,
                        ),
                      ),
                    ),
                    const SizedBox(height: gap),
                  ],
                  keypad,
                  const SizedBox(height: NocturneSpacing.x6),
                  ...actions,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// [SafeArea] for a bottom sheet with a keypad. A sheet is at most 640 pt
/// wide and centred, so a side inset only reaches it where the window is
/// narrower than that; plain [SafeArea] would pad it anyway — 84 pt on the
/// right of an open iPhone Duo on its side — and push the keypad off-centre,
/// onto the fold.
class _SheetSafeArea extends StatelessWidget {
  const _SheetSafeArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = MediaQuery.sizeOf(context);
        final insets = MediaQuery.paddingOf(context);
        final margin = (window.width - constraints.maxWidth) / 2;
        double overlap(double inset) =>
            (inset - margin).clamp(0.0, double.infinity);
        return SafeArea(
          left: false,
          right: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: overlap(insets.left),
              right: overlap(insets.right),
            ),
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              removeRight: true,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Hands [builder] the point, in this widget's own coordinates, where the
/// middle of the window falls — measured after layout, so null on the first
/// frame. Use it only where this widget's position does not depend on what
/// [builder] returns, or the measurement chases itself.
class _WindowMiddle extends StatefulWidget {
  const _WindowMiddle({required this.builder});

  final Widget Function(BuildContext context, Offset? middle) builder;

  @override
  State<_WindowMiddle> createState() => _WindowMiddleState();
}

class _WindowMiddleState extends State<_WindowMiddle> {
  Offset? _middle;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure(window));
    return widget.builder(context, _middle);
  }

  void _measure(Size window) {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final middle = box.globalToLocal(window.center(Offset.zero));
    final previous = _middle;
    if (previous == null || (middle - previous).distance > 0.5) {
      setState(() => _middle = middle);
    }
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
                color: context.nocturne.textMuted,
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
          color: success ? context.nocturne.success : context.nocturne.danger,
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
            color: context.nocturne.textMuted,
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
