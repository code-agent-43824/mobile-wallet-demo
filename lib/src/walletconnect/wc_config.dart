/// WalletConnect (Reown) Cloud project id, injected at build time via
/// `--dart-define-from-file=dart_defines.json` (see README → "WalletConnect
/// project id"). Empty when not provided. The real `reown_walletkit` service
/// consumes it in Phase 9 chunk 9.2; until then the app ships
/// `UnavailableWalletConnectService`.
const String wcProjectId = String.fromEnvironment('WC_PROJECT_ID');

/// Whether a WalletConnect project id was provided at build time.
bool get isWalletConnectConfigured => wcProjectId.isNotEmpty;
