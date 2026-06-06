# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Flutter demo of a mobile EVM crypto wallet targeting Android, iOS, and Windows x64. It supports the full onboarding/auth shell, an encrypted on-device key vault, read-only blockchain access (Ethereum Mainnet + Sepolia), and end-to-end EIP-1559 signing/sending. A simulated "external NFC device" backend exists as a foundation for a future hardware signer — there is no real NFC/SDK integration. UI strings are in Russian; tests assert on those exact strings.

`docs/development-plan.md` is the canonical roadmap and source of truth for scope and phase status. Phase 7 (external-device foundation) is complete; Phase 8 (WalletConnect v2 + AirGap contracts, external-signing session model) is complete at the contracts/foundation level — real relay/SDK integration is intentionally out of scope.

## Multi-agent working agreement

This repo is worked on by multiple coding agents (Claude Code and others), sometimes in parallel — so **document first, then code, then record**:

1. Before a chunk of work (even a small one), write the plan in `docs/worklog.md` (and update `docs/development-plan.md` if it's roadmap-level).
2. Do the work.
3. Record results **in the same change**: the worklog entry's *Done* + *Next / open*, the plan's status, and any docs that drifted.

The next agent should be able to tell what was planned, what was done, and what's next **from the docs alone** — not the diff. `AGENTS.md` is the full agreement and cross-tool entry point; `docs/development-plan.md` is the source of truth for phase status; `docs/worklog.md` is the granular running log.

## Commands

Toolchain is pinned in `.github/workflows/ci.yml`: **Flutter 3.41.7**, Dart SDK `^3.11.0`, Java 17.

```bash
flutter pub get                                  # install dependencies
flutter run                                      # run the app

flutter test                                     # run all tests
flutter test test/transaction_service_test.dart  # run one test file
flutter test --plain-name 'signs erc20 transfer with transfer selector in calldata'  # run one test by name

flutter analyze                                  # static analysis / lints (flutter_lints)
dart format .                                    # format (REQUIRED — see below)
dart format --output=none --set-exit-if-changed .  # CI's formatting gate

flutter build apk --release                      # Android
flutter build ios --simulator --debug            # iOS simulator
flutter build windows --release                  # Windows x64
```

CI (`ci.yml`) runs `validate` (format check → analyze → test) and only then builds all three platforms. **`dart format` is an enforced gate** — unformatted code fails CI. Run `dart format .` before committing.

## Architecture

Code lives under `lib/src/`, split into layers: `auth/`, `blockchain/`, `key_storage/`, `transactions/`, plus the UI orchestrator `wallet_flow_screen.dart` (its presentational widgets live in `wallet_flow_screen_*.dart` `part` files). `main.dart` → `app.dart` (`MobileWalletDemoApp`) → `WalletFlowScreen`.

### Dependency injection is the testing seam

`MobileWalletDemoApp` (`lib/src/app.dart`) takes every external dependency as an **optional nullable constructor arg, defaulting to the production implementation**. Almost every concrete class has an `abstract interface class` counterpart. Tests inject fakes (`InMemorySecureKeyValueStore`, `_FakeBlockchainProvider`, `_FakeNonceProvider`, `_FakeBroadcaster`, `_FakeTrackingTransport`, `SimulatedBiometricAuthGateway`) through this constructor. Follow this pattern for any new collaborator: define the interface, inject it, default to the real impl.

### Key storage: the central abstraction

`KeyStorageBackend` (`key_storage/key_storage_backend.dart`) is the core contract (create/import/unlock/biometrics/lock). Two implementations, selected at runtime via `WalletBackendRegistry` (persists the choice in the secure store):

- **`PhoneSecureVault`** — the real backend. Implements the **"Phone Secure Vault" model** (see development-plan.md "Core architectural decision"): it deliberately does *not* use a non-exportable secure-enclave key, because the product must show/import a seed phrase. Instead the BIP-39 seed is encrypted at rest with AES-GCM-256 under a random data-encryption key (DEK); the DEK is wrapped by a PIN-derived key (PBKDF2, 600k iterations); the PIN is never persisted, and repeated wrong PINs trigger a temporary unlock lockout. A single EVM address is derived at `m/44'/60'/0'/0/0`. Biometric unlock keeps the DEK in a dedicated `BiometricSecretStore` (`key_storage/biometric_secret_store.dart`) gated by `local_auth`, rather than co-locating a key with the seed ciphertext. `PinUnlockSession` provides a 5-minute unlock TTL so each high-level operation prompts for auth at most once.
- **`ExternalDeviceDemoBackend`** — implements `ExternalDeviceKeyStorageBackend` (adds `isDeviceAvailable()`). It is a *simulation*: it wraps a `PhoneSecureVault` delegate backed by a `PrefixedSecureKeyValueStore`, and layers on mock device lifecycle (online/offline, reconnect, session disconnect) and mock PKCS#11 session/operation contracts (`external_device_pkcs11.dart`). No real NFC.

### Blockchain: read-only with fallback + cache

`BlockchainProvider.loadSnapshot` returns a `WalletChainSnapshot` (native balance, base fee, token balances, recent transactions). `PublicRpcBlockchainProvider` reads balance/base-fee via JSON-RPC, **falling back across multiple public RPC URLs** per network, and reads token balances + history from a Blockscout-style explorer API. It **caches the last successful snapshot in the secure store** and returns it (with `loadedFromCache: true`) when all live endpoints fail. Network configs (chain IDs, RPC URL lists, explorer base URLs) are in `blockchain/network_config.dart`.

### Transactions: layered, with a retry/replacement flow

`TransactionService` (`transactions/transaction_service.dart`) defines prepare-preview / prepare / sign (local EIP-1559) / submit / track. `LocalTransactionService` implements preparation + signing. `HardenedTransactionServiceImplementation` (the wired-in production service) delegates those to `LocalTransactionService` and adds `submitAuthorizedTransferFlow`: **load nonce → sign → broadcast → track**, retrying on retryable nonce/underpriced RPC errors with a gas bump (×1.15) for replacement. `TransactionTracker` polls `eth_getTransactionReceipt` across RPCs; the UI runs tracking asynchronously so the send screen is not blocked while awaiting a receipt. Signing goes through a `WalletTransactionSigner` (`auth/wallet_operation_auth.dart`) produced by `WalletOperationAuthorizer` — an indirection that keeps signing backend-agnostic. The signer contract is **async** (`Future<SignedTransfer>`): local/external-device signers wrap synchronous local signing, while a `RemoteWalletTransactionSigner` (backed by a `RemoteSigningTransport`) lets a WalletConnect/AirGap session sign without holding the key, assembling the result via `TransactionService.assembleSignedTransfer` (Phase 8 foundation). A `RemoteSigningSessionController` (`sessions/remote_signing_session.dart`) wraps that transport with a connect→sign→disconnect lifecycle (`RemoteSigningSession` state + a `changes` stream) for WalletConnect/AirGap sessions. WalletConnect v2 has a contract + demo connector in `walletconnect/wallet_connect_v2.dart` (a request codec mapping a prepared transfer to/from an `eth_signTransaction` request; no relay/SDK). AirGap offline signing has a parallel contract in `airgap/airgap_signing.dart` (export/import QR payloads with request-id validation). A `RemoteSignerCatalog` (`sessions/remote_signer_registry.dart`) surfaces both as a "Подписать через" option in the unlocked send flow (the demo signs with the on-device key).

### UI: one stateful state-machine screen, split across part files

`WalletFlowScreen` (`wallet_flow_screen.dart`, ~560 lines) is the `StatefulWidget` orchestrator driven by the `WalletFlowStage` enum (`loading → welcome → createWallet/importWallet → showSeed → biometricPrompt → locked → unlocked`). It owns the `PhoneSecureVault`, `ExternalDeviceDemoBackend`, and `WalletBackendRegistry` instances and branches its UX when the active backend is the external device. The presentational stage widgets stay library-private but live in `part` files of the same library: `wallet_flow_screen_widgets.dart` (shared leaf widgets + header), `wallet_flow_screen_onboarding.dart` (welcome/pin/import/seed/biometric/locked stages), and `wallet_flow_screen_unlocked.dart` (the unlocked dashboard + send/sign/track section). The `part` files share the orchestrator's imports — add new imports to `wallet_flow_screen.dart`.

## Conventions & gotchas

- **The app version is duplicated across several files — keep them in sync.** `pubspec.yaml` (`version:`) is the source; `lib/src/app_version.dart` (`appVersion`/`appVersionLabel`) must match, `test/widget_test.dart` asserts the on-screen `appVersionLabel`, and both `README.md` and the `docs/development-plan.md` "Current stopping point" also state it. When bumping, update all of them. Project convention (per README) is to **bump the minor version with each functional step**.
- **Commit messages** follow Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `style:`.
- **UI text and many error messages are Russian.** Widget tests locate elements by Russian strings — keep them consistent when editing UI.
- Keep `docs/development-plan.md` phase status in sync when completing roadmap items (existing `docs:` commits do this).
