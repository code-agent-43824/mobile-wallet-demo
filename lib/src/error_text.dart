import '../l10n/app_localizations.dart';
import 'auth/biometric_auth.dart';
import 'errors/app_error.dart';

/// Turns any caught failure into text for the user, in the active language.
///
/// Coded failures read from the ARB bundle; uncoded ones carry text from
/// outside the app (an RPC node, the relay) and are shown as is; anything else
/// is unexpected and keeps its cause visible for diagnosis.
String describeError(AppLocalizations l10n, Object error) {
  if (error is CodedError) {
    final code = error.errorCode;
    return code == null
        ? error.message
        : describeAppError(l10n, code, error.errorArgs);
  }
  return l10n.errorOperationFailed('$error');
}

/// The sentence for [code]. Exhaustive on purpose: a new code without copy is
/// a compile error rather than a raw identifier on screen.
String describeAppError(
  AppLocalizations l10n,
  AppErrorCode code, [
  Map<String, Object> args = const <String, Object>{},
]) {
  String arg(String name) => '${args[name] ?? ''}';
  return switch (code) {
    AppErrorCode.walletAlreadyExists => l10n.errWalletAlreadyExists,
    AppErrorCode.walletNotInitialized => l10n.errWalletNotInitialized,
    AppErrorCode.invalidPin => l10n.errInvalidPin,
    AppErrorCode.invalidMnemonic => l10n.errInvalidMnemonic,
    AppErrorCode.biometricUnavailable => l10n.errBiometricUnavailable,
    AppErrorCode.biometricNotEnabled => l10n.errBiometricNotEnabled,
    AppErrorCode.biometricCancelled => l10n.errBiometricCancelled,
    AppErrorCode.biometricLockedOut => l10n.errBiometricLockedOut,
    AppErrorCode.biometricFailed => l10n.errBiometricFailed(arg('detail')),
    AppErrorCode.vaultLockedOut => l10n.errVaultLockedOut(
      formatWait(l10n, args['remaining'] as Duration? ?? Duration.zero),
    ),
    AppErrorCode.vaultCorrupt => l10n.errVaultCorrupt,
    AppErrorCode.vaultSchemaUnsupported => l10n.errVaultSchemaUnsupported,
    AppErrorCode.cardPinEmpty => l10n.errCardPinEmpty,
    AppErrorCode.cardCancelled => l10n.errCardCancelled,
    AppErrorCode.cardTimeout => l10n.errCardTimeout,
    AppErrorCode.cardPinInvalid => l10n.errCardPinInvalid,
    AppErrorCode.cardPinLocked => l10n.errCardPinLocked,
    AppErrorCode.cardNfcLost => l10n.errCardNfcLost,
    AppErrorCode.cardNativeFailure => l10n.errCardNativeFailure,
    AppErrorCode.cardMasterKeyFailed => l10n.errCardMasterKeyFailed,
    AppErrorCode.cardAddressMismatch => l10n.errCardAddressMismatch,
    AppErrorCode.cardNoCompatibleWallet => l10n.errCardNoCompatibleWallet,
    AppErrorCode.cardProfileUnsupported => l10n.errCardProfileUnsupported,
    AppErrorCode.cardNotRegistered => l10n.errCardNotRegistered,
    AppErrorCode.cardDataCorrupted => l10n.errCardDataCorrupted,
    AppErrorCode.cardNoAccountXpub => l10n.errCardNoAccountXpub,
    AppErrorCode.cardWrongCard => l10n.errCardWrongCard,
    AppErrorCode.qrCameraUnavailable => l10n.errQrCameraUnavailable,
    AppErrorCode.qrCameraOpenFailed => l10n.errQrCameraOpenFailed,
    AppErrorCode.qrImageNotRecognized => l10n.errQrImageNotRecognized,
    AppErrorCode.qrScannerUnavailable => l10n.errQrScannerUnavailable,
    AppErrorCode.urMalformed => l10n.errUrMalformed(arg('detail')),
    AppErrorCode.urWrongType => l10n.errUrWrongType(
      arg('expected'),
      arg('actual'),
    ),
    AppErrorCode.txRecipientInvalid => l10n.errTxRecipientInvalid,
    AppErrorCode.txAmountEmpty => l10n.errTxAmountEmpty,
    AppErrorCode.txAmountFormat => l10n.errTxAmountFormat,
    AppErrorCode.txAmountDigitsOnly => l10n.errTxAmountDigitsOnly,
    AppErrorCode.txAmountTooManyDecimals => l10n.errTxAmountTooManyDecimals(
      arg('decimals'),
    ),
    AppErrorCode.txAmountNotPositive => l10n.errTxAmountNotPositive,
    AppErrorCode.txInsufficientAsset => l10n.errTxInsufficientAsset(
      arg('symbol'),
    ),
    AppErrorCode.txInsufficientNativeForAmountAndFee =>
      l10n.errTxInsufficientNativeForAmountAndFee,
    AppErrorCode.txInsufficientNativeForFee =>
      l10n.errTxInsufficientNativeForFee,
    AppErrorCode.txNonceNegative => l10n.errTxNonceNegative,
    AppErrorCode.txSenderMismatch => l10n.errTxSenderMismatch,
    AppErrorCode.requestOtherAccount => l10n.errorRequestOtherAccount(
      arg('address'),
    ),
    AppErrorCode.wcNotConfigured => l10n.errWcNotConfigured,
    AppErrorCode.wcNotInitialized => l10n.errWcNotInitialized,
    AppErrorCode.wcInvalidUri => l10n.errWcInvalidUri,
    AppErrorCode.wcProposalExpired => l10n.errWcProposalExpired,
    AppErrorCode.wcRelayNoSession => l10n.errWcRelayNoSession,
    AppErrorCode.wcPairingNoResponse => l10n.errWcPairingNoResponse,
    AppErrorCode.wcApproveNoResponse => l10n.errWcApproveNoResponse,
    AppErrorCode.wcUnsupportedNamespaces => l10n.errWcUnsupportedNamespaces(
      arg('chains'),
      arg('methods'),
    ),
    AppErrorCode.wcMalformedRequest => l10n.errWcMalformedRequest(
      arg('detail'),
    ),
    AppErrorCode.wcMalformedTypedData => l10n.errWcMalformedTypedData(
      arg('detail'),
    ),
    AppErrorCode.wcPreviewMismatch => l10n.errWcPreviewMismatch,
    AppErrorCode.wcPreflightNoFees => l10n.errWcPreflightNoFees,
    AppErrorCode.wcPreflightRpcFailed => l10n.errWcPreflightRpcFailed(
      arg('detail'),
    ),
    AppErrorCode.wcUnsupportedChain => l10n.errWcUnsupportedChain(
      arg('chainId'),
    ),
    AppErrorCode.wcInvalidGas => l10n.errWcInvalidGas(arg('detail')),
    AppErrorCode.airgapMalformedTransaction =>
      l10n.errAirgapMalformedTransaction(arg('detail')),
    AppErrorCode.airgapUnsupportedTransaction =>
      l10n.errAirgapUnsupportedTransaction(arg('detail')),
    AppErrorCode.airgapChainMismatch => l10n.errAirgapChainMismatch(
      arg('requested'),
      arg('embedded'),
    ),
    AppErrorCode.airgapSignatureInvalid => l10n.errAirgapSignatureInvalid(
      arg('detail'),
    ),
    AppErrorCode.airgapTypedDataInvalid => l10n.errAirgapTypedDataInvalid(
      arg('detail'),
    ),
  };
}

/// A wait in readable units: seconds under a minute, whole minutes above.
///
/// Rounds up, so it never reads "0 s", and computes minutes from the true
/// remainder so a fresh five-minute lockout says five and not six.
String formatWait(AppLocalizations l10n, Duration remaining) {
  final seconds = remaining.inSeconds;
  if (seconds < 59) {
    return l10n.durationSeconds(seconds + 1);
  }
  return l10n.durationMinutes((seconds / 60).ceil());
}

/// The system biometric dialog's sentence for [prompt], in the active language.
String biometricPromptText(AppLocalizations l10n, BiometricPrompt prompt) =>
    switch (prompt) {
      BiometricPrompt.enableQuickUnlock =>
        l10n.biometricPromptEnableQuickUnlock,
      BiometricPrompt.unlockWallet => l10n.biometricPromptUnlockWallet,
      BiometricPrompt.saveCardPin => l10n.biometricPromptSaveCardPin,
      BiometricPrompt.releaseCardPin => l10n.biometricPromptReleaseCardPin,
    };
