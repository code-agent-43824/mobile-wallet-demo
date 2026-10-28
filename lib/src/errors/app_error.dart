/// Which failure happened, as data rather than as text.
///
/// Domain and infrastructure code (`key_storage/`, `qr/`, `walletconnect/`,
/// `airgap/`, `transactions/`, `auth/`) used to throw Russian sentences, which
/// left the English UI half-translated. It now states *which* failure occurred
/// plus the values its sentence needs; `describeError` at the UI edge turns
/// that into text in the active language through an exhaustive `switch`, so a
/// code without copy fails to compile.
///
/// Protocol parse failures (RLP, BC-UR, EIP-712, WalletConnect parameters) are
/// deliberately few codes with a language-neutral `detail`: the user needs to
/// know the payload was malformed, and the technical reason stays untranslated
/// for whoever debugs it.
enum AppErrorCode {
  // Phone vault.
  walletAlreadyExists,
  walletNotInitialized,
  invalidPin,
  invalidMnemonic,
  biometricUnavailable,
  biometricNotEnabled,
  biometricCancelled,
  biometricLockedOut,
  biometricFailed,

  /// Args: `remaining` ([Duration]).
  vaultLockedOut,
  vaultCorrupt,
  vaultSchemaUnsupported,

  // Card (Rutoken) custody.
  cardPinEmpty,
  cardCancelled,
  cardTimeout,
  cardPinInvalid,
  cardPinLocked,
  cardNfcLost,
  cardNativeFailure,
  cardMasterKeyFailed,
  cardAddressMismatch,
  cardNoCompatibleWallet,
  cardProfileUnsupported,
  cardNotRegistered,
  cardDataCorrupted,
  cardNoAccountXpub,
  cardWrongCard,

  // QR and BC-UR.
  qrCameraUnavailable,
  qrCameraOpenFailed,
  qrImageNotRecognized,
  qrScannerUnavailable,

  /// Args: `detail`.
  urMalformed,

  /// Args: `expected`, `actual`.
  urWrongType,

  // Transfers.
  txRecipientInvalid,
  txAmountEmpty,
  txAmountFormat,
  txAmountDigitsOnly,

  /// Args: `decimals` ([int]).
  txAmountTooManyDecimals,
  txAmountNotPositive,

  /// Args: `symbol`.
  txInsufficientAsset,
  txInsufficientNativeForAmountAndFee,
  txInsufficientNativeForFee,
  txNonceNegative,
  txSenderMismatch,

  /// Shared by WalletConnect and AirGap. Args: `address`.
  requestOtherAccount,

  // WalletConnect.
  wcNotConfigured,
  wcNotInitialized,
  wcInvalidUri,
  wcProposalExpired,
  wcRelayNoSession,

  /// Args: `chains`, `methods`.
  wcUnsupportedNamespaces,

  /// Args: `detail`.
  wcMalformedRequest,

  /// Args: `detail`.
  wcMalformedTypedData,
  wcPreviewMismatch,
  wcPreflightNoFees,

  /// Args: `detail`.
  wcPreflightRpcFailed,

  /// Args: `chainId`.
  wcUnsupportedChain,

  /// Args: `detail`.
  wcInvalidGas,

  // AirGap (EIP-4527).

  /// Args: `detail`.
  airgapMalformedTransaction,

  /// Args: `detail`.
  airgapUnsupportedTransaction,

  /// Args: `requested`, `embedded`.
  airgapChainMismatch,

  /// Args: `detail`.
  airgapSignatureInvalid,

  /// Args: `detail`.
  airgapTypedDataInvalid,
}

/// Implemented by every exception the user may read.
///
/// [errorCode] is null for failures that carry text from outside the app (an
/// RPC node's rejection, a relay error) — [message] is then shown as is.
abstract interface class CodedError {
  AppErrorCode? get errorCode;
  Map<String, Object> get errorArgs;

  /// For coded failures, a developer description (`code {args}`) for logs and
  /// test output — never shown to the user.
  String get message;
}

/// The developer-facing form of a coded failure, used as its [CodedError.message].
String debugDescribeError(AppErrorCode code, Map<String, Object> args) =>
    args.isEmpty ? code.name : '${code.name} $args';
