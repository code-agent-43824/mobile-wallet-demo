# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Flutter demo of a mobile EVM crypto wallet targeting Android, iOS, and Windows x64. It supports the full onboarding/auth shell, an encrypted on-device key vault, read-only blockchain access (Ethereum Mainnet + Sepolia), and end-to-end EIP-1559 signing/sending. A simulated "external NFC device" backend exists as a foundation for a future hardware signer — there is no real NFC/SDK integration. UI strings are in Russian; tests assert on those exact strings.

`docs/development-plan.md` is the canonical roadmap and source of truth for scope and phase status. Phases 0–7 are complete (Phase 7 = the simulated external-device **custody** foundation; no real NFC/SDK). Phase 9 makes this a wallet-side WalletConnect receiver and is device-validated on Android through a confirmed Sepolia broadcast; v1.37 adds EIP-5792 capability discovery plus live simulation/gas/fee preflight. Phase 12 is complete in v1.38: the app is a MetaMask-compatible EIP-4527 QR signer for Mainnet/Sepolia transactions, with account export, multipart camera scan, decoded transaction preview, per-operation auth, and signature QR. v1.39 hardens dense live-camera QR recognition with full-frame analysis, high requested Android resolution, and Android auto-zoom. The earlier custom AirGap codec and outbound signer direction are removed.

The current north star is a single-account EVM wallet whose next milestone is a real, non-exporting Rutoken
custody backend for Android/iOS. Phase 10 requires a custody-contract redesign before native integration: a
hardware backend must expose public account metadata and transient authenticated signing, never
`WalletMaterial`/mnemonic/private-key material. v1.40 adds this library-independent seam:
`key_storage/custody_backend.dart` defines public account/xpub/session/`RutokenNativeAdapter` contracts, while
`auth/external_digest_signer.dart` turns raw device `r‖s` into low-s recoverable EVM signatures and byte-exact
legacy/EIP-1559/message/AirGap output. Native Kotlin/Swift implementations are the next step. See the NOW / NEXT
/ LATER section and Phase 10 Definition of Done in `docs/development-plan.md`.

Use `docs/device-test-matrix.md` for physical-device and live-service evidence; do not turn simulator or fake
coverage into hardware/security claims.

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

- **`PhoneSecureVault`** — the real backend. Implements the **"Phone Secure Vault" model** (see development-plan.md "Core architectural decision"): it deliberately does *not* use a non-exportable secure-enclave key, because the product must show/import a seed phrase. Instead the BIP-39 seed is encrypted at rest with AES-GCM-256 under a random data-encryption key (DEK); the DEK is wrapped by a PIN-derived key (PBKDF2, 600k iterations); the PIN is never persisted, and repeated wrong PINs trigger a temporary unlock lockout. A single EVM address is derived at `m/44'/60'/0'/0/0`. Biometric unlock keeps the DEK in a dedicated `BiometricSecretStore` (`key_storage/biometric_secret_store.dart`) gated by `local_auth`, rather than co-locating a key with the seed ciphertext. `PinUnlockSession` remains an internal primitive, but the controller deliberately requests fresh authorization for every private-key operation and calls `lock()` in `finally`. This releases references; immutable Dart strings cannot be claimed to be securely zeroized.
- **`ExternalDeviceDemoBackend`** — implements `ExternalDeviceKeyStorageBackend` (adds `isDeviceAvailable()`). It is a *simulation*: it wraps a `PhoneSecureVault` delegate backed by a `PrefixedSecureKeyValueStore`, and layers on mock device lifecycle (online/offline, reconnect, session disconnect) and mock PKCS#11 session/operation contracts (`external_device_pkcs11.dart`). No real NFC.

### Blockchain: read-only with fallback + cache

`BlockchainProvider.loadSnapshot` returns a `WalletChainSnapshot` (native balance, base fee, token balances, recent transactions). `PublicRpcBlockchainProvider` reads balance/base-fee via JSON-RPC, **falling back across multiple public RPC URLs** per network, and reads token balances + history from a Blockscout-style explorer API. It **caches the last successful snapshot in the secure store** and returns it (with `loadedFromCache: true`) when all live endpoints fail. Network configs (chain IDs, RPC URL lists, explorer base URLs) are in `blockchain/network_config.dart`.

### Transactions: layered, with a retry/replacement flow

`TransactionService` (`transactions/transaction_service.dart`) defines prepare-preview / prepare / sign (local EIP-1559) / submit / track. `LocalTransactionService` implements preparation + signing. `HardenedTransactionServiceImplementation` (the wired-in production service) delegates those to `LocalTransactionService` and adds `submitAuthorizedTransferFlow`: **load nonce → sign → broadcast → track**, retrying on retryable nonce/underpriced RPC errors with a gas bump (×1.15) for replacement. `TransactionTracker` polls `eth_getTransactionReceipt` across RPCs; the UI runs tracking asynchronously so the send screen is not blocked while awaiting a receipt. Signing goes through a `WalletTransactionSigner` (`auth/wallet_operation_auth.dart`) produced by `WalletOperationAuthorizer` — an indirection that keeps signing backend-agnostic. The signer contract is **async** (`Future<SignedTransfer>`); the local and external-device signers wrap the synchronous local EIP-1559 signing. `TransactionService.assembleSignedTransfer` builds a `SignedTransfer` from raw signed bytes without duplicating crypto.

### WalletConnect v2 / EIP-4527 AirGap (wallet-side inbound)

The wallet receives signing requests. WalletConnect uses `WalletConnectV2RequestCodec`, the `WalletConnectService` seam, and the real mobile `ReownWalletConnectService`; requests are queued, capability probes are auto-answered, and transaction calls are simulated/estimated before the summary-bound backend signs and broadcasts. AirGap uses EIP-4527 over BC-UR instead: `Eip4527Codec` + `AccountExportDeriver` export a MetaMask-compatible account xpub, `UrQrEncoder` / `UrQrAssembler` display and scan single/multipart fountain QR, `Eip4527TransactionPreviewDecoder` verifies and displays the exact Mainnet/Sepolia transaction bytes, and `Eip4527InboundCoordinator` returns an `eth-signature` QR after per-operation auth. MetaMask remains responsible for assembling and broadcasting. The obsolete custom `airgap-tx:` codec/coordinator and paste UI were removed in v1.38. The shared UI is the `connections` stage (`wallet_flow_screen_connections.dart`).

### UI: widget-free controller plus thin screen and part files

`WalletFlowController` owns the state machine, custody/backend instances, dependencies, and domain actions.
`WalletFlowScreen` listens to it and composes the current stage; it does not own the vault lifecycle. The
presentational widgets remain library-private in `wallet_flow_screen_widgets.dart`,
`wallet_flow_screen_onboarding.dart`, `wallet_flow_screen_unlocked.dart`, and
`wallet_flow_screen_connections.dart`. Part files share imports from `wallet_flow_screen.dart`; add UI imports
there. New domain collaborators belong in the controller/composition root and should stay injectable for tests.

## Conventions & gotchas

- **The app version is duplicated across several files — keep them in sync.** `pubspec.yaml` (`version:`) is the source; `lib/src/app_version.dart` (`appVersion`/`appVersionLabel`) must match, `test/widget_test.dart` asserts the on-screen `appVersionLabel`, and both `README.md` and the `docs/development-plan.md` NOW snapshot also state it. When bumping, update all of them. Project convention (per README) is to **bump the minor version with each functional step**.
- **Commit messages** follow Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `style:`.
- **UI text and many error messages are Russian.** Widget tests locate elements by Russian strings — keep them consistent when editing UI.
- Keep `docs/development-plan.md` phase status in sync when completing roadmap items (existing `docs:` commits do this).
- **`dart_defines.json`** (repo root) holds the WalletConnect `WC_PROJECT_ID`; builds/runs pass it via `--dart-define-from-file=dart_defines.json` (helpers: `scripts/run.sh` / `scripts/build.sh`) and the app reads it as `wcProjectId` (`walletconnect/wc_config.dart`). It is **intentionally committed** (public client id; the owner accepts quota use) — don't treat it as a leaked secret or remove it. It is consumed by `ReownWalletConnectService` (chunk 9.2, wired).
- **Android vault persistence:** `flutter_secure_storage` 10.x is intentionally forced through an override until `reown_core` widens its 9.x constraint. The API Reown uses remains compatible and CI builds every platform. Our store uses crash-safe v9→v10 migration with `resetOnError:false`; Android Auto Backup is disabled because keystore keys cannot safely restore with encrypted preferences.
