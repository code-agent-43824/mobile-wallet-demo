# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Flutter demo of a mobile EVM crypto wallet targeting Android, iOS, and Windows x64. It supports the full onboarding/auth shell, an encrypted on-device key vault, read-only blockchain access (Ethereum Mainnet + Sepolia), and end-to-end EIP-1559 signing/sending. Android v1.51 includes a physically validated Rutoken NFC/PKCS#11 read/sign transport and recoverable provisioning, production backend registration, read-only adoption of an already provisioned compatible card, registered-address binding, biometric-gated PIN convenience, cancellable NFC discovery, stable PIN/timeout/NFC-loss errors, and a fail-closed platform-error boundary that never exposes raw vendor diagnostics to Dart. Startup restores only the software-retained public Rutoken profile without NFC; each private operation opens one fresh card/PIN session. The native transport startup mirrors the official demo: the PC/SC bridge attaches from a custom `Application.onCreate` before any Activity callbacks, then PKCS#11 follows the Activity lifecycle and a blocking `C_WaitForSlotEvent` listener drives token presence. The native crypto boundary is intentionally minimal and follows the supplied example: import one raw BIP32 master private key + chain code with `C_CreateObject`, find it, derive a public address key or per-operation EC private child, call raw `CKM_ECDSA`, destroy transient children, and close the session. Existing-card adoption never calls `C_CreateObject`; it persists only address/path and therefore cannot synthesize EIP-4527 account xpub metadata. The adapter does not query derived chain code or xpub. EC-point intake accepts/validates both compressed and uncompressed SEC1 values with or without the PKCS#11 DER OCTET STRING wrapper. UI copy lives in ARB files (`lib/l10n/app_ru.arb` is primary, `app_en.arb` mirrors it) with an in-app RU/EN switch; widget tests pin `Locale('ru')` and assert on the exact Russian strings.

`docs/development-plan.md` is the canonical roadmap and source of truth for scope and phase status. Phases 0–7 are complete (Phase 7 = the simulated external-device **custody** foundation; the simulation itself was removed in v1.53 once the real Rutoken backend existed). Phase 9 makes this a wallet-side WalletConnect receiver and is device-validated on Android through a confirmed Sepolia broadcast; v1.37 adds EIP-5792 capability discovery plus live simulation/gas/fee preflight. Phase 12 is complete in v1.38: the app is a MetaMask-compatible EIP-4527 QR signer for Mainnet/Sepolia transactions, with account export, multipart camera scan, decoded transaction preview, per-operation auth, and signature QR. v1.39 hardens dense live-camera QR recognition with full-frame analysis, high requested Android resolution, and Android auto-zoom. The earlier custom AirGap codec and outbound signer direction are removed. Phase 13 (v1.52–v1.54) is the Nocturne redesign: dark-only theme, four tabs (Кошелёк / Активность / Связи / Настройки), separate iOS/Android interaction patterns, onboarding variant B («Кошелёк за минуту»), and full RU/EN localization; v1.57 closes it with one confirmation sheet for every key/card operation and coded domain errors. Phase 14 (v1.55) lets the Rutoken backend hold several registered card profiles with one selected; every operation still binds to the selected card's address, v1.57 adds the «Новая карта» screen, and the two-card physical dogfood (14.5) is pending. v1.57 also adds optional lock-on-open.

The current north star is a single-account EVM wallet whose next milestone is a real, non-exporting Rutoken
custody backend for Android/iOS. Phase 10 requires a custody-contract redesign before native integration: a
hardware backend must expose public account metadata and transient authenticated signing, never
`WalletMaterial`/mnemonic/private-key material. v1.40 adds this library-independent seam:
`key_storage/custody_backend.dart` defines public account/session/`RutokenNativeAdapter` contracts plus software-retained xpub metadata, while
`auth/external_digest_signer.dart` turns raw device `r‖s` into low-s recoverable EVM signatures and byte-exact
legacy/EIP-1559/message/AirGap output. v1.41 adds the official Android PC/SC + PKCS#11/JNA stack and Kotlin
platform-channel adapter; v1.42 adds the official blocking slot-event listener, v1.43 moves transport attachment
to `Application.onCreate`, v1.44 passes the vendor-required null pointer for the empty master derivation path, and
v1.45 reads the official EC public-key object type and normalizes compressed/uncompressed `CKA_EC_POINT` values;
v1.46 removes the unsupported derived-chain-code query and mirrors the reference private-child/raw-sign flow;
v1.47 adds recoverable BIP-39/passphrase provisioning through only the reference `C_CreateObject` import and
persists public account-xpub metadata; both paths are physically validated. v1.48 registers the real backend:
provisioning selects it, cold start restores its public summary without NFC, and every signing transport receives
the secret-free transient device signer. v1.49 can instead adopt an existing compatible key as a descriptor-only
profile, rejects a card whose address differs from that profile, and can release its separately stored PIN only
after system biometric authentication. v1.50 makes the Android NFC wait cancellable, maps stable sanitized native
errors, detects a removed token before later operations, and preserves the primary operation failure if teardown
also fails. The Android physical signing matrix passed on v1.51 (2026-08-17), including WalletConnect,
AirGap, invalid PIN, cancellation, timeout, and different-card rejection. Mid-operation NFC loss displayed a
generic error on v1.51; v1.55 classifies it by asking the slot-event listener whether the card is still present,
but that fix has not been re-run on hardware. Physical crash/log-output review and the Swift/iOS implementation
remain open. The exact
`wtpkcs11ecp.xcframework` was received and retained privately, but its archive has no redistribution grant;
do not commit it or expose it through public CI artifacts. See the NOW / NEXT / LATER section and Phase 10
Definition of Done in `docs/development-plan.md`.

Use `docs/device-test-matrix.md` for physical-device and live-service evidence; do not turn simulator or fake
coverage into hardware/security claims.

## Multi-agent working agreement

This repo is worked on by multiple coding agents (Claude Code and others), sometimes in parallel — so **document first, then code, then record**:

1. Before a chunk of work (even a small one), write the plan in `docs/worklog.md` (and update `docs/development-plan.md` if it's roadmap-level).
2. Do the work.
3. Record results **in the same change**: the worklog entry's *Done* + *Next / open*, the plan's status, and any docs that drifted.

The next agent should be able to tell what was planned, what was done, and what's next **from the docs alone** — not the diff. `AGENTS.md` is the full agreement and cross-tool entry point; `docs/development-plan.md` is the source of truth for phase status; `docs/worklog.md` is the granular running log.

## Commands

Toolchain: the **latest Flutter stable**, deliberately unpinned (owner decision 2026-10-24) — `ci.yml` uses `channel: stable` and `.fvmrc` says `stable`; Dart SDK `^3.11.0` is only a floor; Java 17.

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

Releases: bump the version, add the CHANGELOG section, then either push tag `v<version>` or run `ci.yml` manually on `main` with `release` ticked — the `release` job publishes the APK as a GitHub Release (GitLab releases on its own tags).

The project's primary home is now the internal GitLab (`prototypes/mobile-wallet-demo`); `.gitlab-ci.yml` runs
blocking SAST (semgrep + osv from `mko/ci-security`), the same format/analyze/test gate, an Android APK build, docs
Pages, and tag releases. The GitHub repository and its `ci.yml` (Android/iOS/Windows) are kept in sync with it.

## Architecture

Code lives under `lib/src/`, split into layers: `auth/`, `blockchain/`, `key_storage/`, `transactions/`, plus the UI orchestrator `wallet_flow_screen.dart` (its presentational widgets live in `wallet_flow_screen_*.dart` `part` files). `main.dart` → `app.dart` (`MobileWalletDemoApp`) → `WalletFlowScreen`.

### Dependency injection is the testing seam

`MobileWalletDemoApp` (`lib/src/app.dart`) takes every external dependency as an **optional nullable constructor arg, defaulting to the production implementation**. Almost every concrete class has an `abstract interface class` counterpart. Tests inject fakes (`InMemorySecureKeyValueStore`, `_FakeBlockchainProvider`, `_FakeNonceProvider`, `_FakeBroadcaster`, `_FakeTrackingTransport`, `SimulatedBiometricAuthGateway`) through this constructor. Follow this pattern for any new collaborator: define the interface, inject it, default to the real impl.

### Key storage: the central abstraction

`KeyStorageBackend` (`key_storage/key_storage_backend.dart`) is the core contract (create/import/unlock/biometrics/lock). Two backend kinds (`WalletBackendKind.phoneSecureVault` / `externalDevice`), selected at runtime via `WalletBackendRegistry` (persists the choice in the secure store):

- **`PhoneSecureVault`** — the real backend. Implements the **"Phone Secure Vault" model** (see development-plan.md "Core architectural decision"): it deliberately does *not* use a non-exportable secure-enclave key, because the product must show/import a seed phrase. Instead the BIP-39 seed is encrypted at rest with AES-GCM-256 under a random data-encryption key (DEK); the DEK is wrapped by a PIN-derived key (PBKDF2, 600k iterations); the PIN is never persisted, and repeated wrong PINs trigger a temporary unlock lockout. A single EVM address is derived at `m/44'/60'/0'/0/0`. Biometric unlock keeps the DEK in a dedicated `BiometricSecretStore` (`key_storage/biometric_secret_store.dart`) gated by `local_auth`, rather than co-locating a key with the seed ciphertext. `PinUnlockSession` remains an internal primitive, but the controller deliberately requests fresh authorization for every private-key operation and calls `lock()` in `finally`. This releases references; immutable Dart strings cannot be claimed to be securely zeroized.
- **`RutokenCustodyBackend`** (`key_storage/custody_backend.dart`) — the real hardware backend behind `WalletCustodyBackend`. It holds only public account metadata and opens a transient `CustodySigningSession` per operation through `RutokenNativeAdapter` (Android: `rutoken_method_channel_adapter.dart` → Kotlin `RutokenRuntime`); it never sees `WalletMaterial`. `RutokenProvisioningService` (`key_storage/rutoken_provisioning.dart`) handles import/generate/adopt and stores a list of `RutokenCardProfile`s plus a selected id (Phase 14); `RutokenBiometricPinStore` is the opt-in biometric-gated PIN store. The former `ExternalDeviceDemoBackend` simulation was deleted in v1.53.

### Blockchain: read-only with fallback + cache

`BlockchainProvider.loadSnapshot` returns a `WalletChainSnapshot` (native balance, base fee, token balances, recent transactions). `PublicRpcBlockchainProvider` reads balance/base-fee via JSON-RPC, **falling back across multiple public RPC URLs** per network, and reads token balances + history from a Blockscout-style explorer API. It **caches the last successful snapshot in the secure store** and returns it (with `loadedFromCache: true`) when all live endpoints fail. Network configs (chain IDs, RPC URL lists, explorer base URLs) are in `blockchain/network_config.dart`.

### Transactions: layered, with a retry/replacement flow

`TransactionService` (`transactions/transaction_service.dart`) defines prepare-preview / prepare / sign (local EIP-1559) / submit / track. `LocalTransactionService` implements preparation + signing. `HardenedTransactionServiceImplementation` (the wired-in production service) delegates those to `LocalTransactionService` and adds `submitAuthorizedTransferFlow`: **load nonce → sign → broadcast → track**, retrying on retryable nonce/underpriced RPC errors with a gas bump (×1.15) for replacement. `TransactionTracker` polls `eth_getTransactionReceipt` across RPCs; the UI runs tracking asynchronously so the send screen is not blocked while awaiting a receipt. Signing goes through a `WalletTransactionSigner` (`auth/wallet_operation_auth.dart`) produced by `WalletOperationAuthorizer` — an indirection that keeps signing backend-agnostic. The signer contract is **async** (`Future<SignedTransfer>`); the local and external-device signers wrap the synchronous local EIP-1559 signing. `TransactionService.assembleSignedTransfer` builds a `SignedTransfer` from raw signed bytes without duplicating crypto.

### WalletConnect v2 / EIP-4527 AirGap (wallet-side inbound)

The wallet receives signing requests. WalletConnect uses `WalletConnectV2RequestCodec`, the `WalletConnectService` seam, and the real mobile `ReownWalletConnectService`; requests are queued, capability probes are auto-answered, and transaction calls are simulated/estimated before the summary-bound backend signs and broadcasts. AirGap uses EIP-4527 over BC-UR instead: `Eip4527Codec` + `AccountExportDeriver` export a MetaMask-compatible account xpub, `UrQrEncoder` / `UrQrAssembler` display and scan single/multipart fountain QR, `Eip4527TransactionPreviewDecoder` verifies and displays the exact Mainnet/Sepolia transaction bytes, and `Eip4527InboundCoordinator` returns an `eth-signature` QR after per-operation auth. MetaMask remains responsible for assembling and broadcasting. The obsolete custom `airgap-tx:` codec/coordinator and paste UI were removed in v1.38. The shared UI is the `connections` stage (`wallet_flow_screen_connections.dart`).

### UI: widget-free controller plus thin screen and part files

`WalletFlowController` owns the state machine, custody/backend instances, dependencies, and domain actions.
`WalletFlowScreen` listens to it and composes the current stage; it does not own the vault lifecycle.
`ChainDataController` owns network/snapshot/loading state so several tabs can render it. The
presentational widgets remain library-private in `wallet_flow_screen_widgets.dart`,
`wallet_flow_screen_onboarding.dart`, `wallet_flow_screen_unlocked.dart`, `wallet_flow_screen_tabs.dart`, and
`wallet_flow_screen_connections.dart`. Part files share imports from `wallet_flow_screen.dart`; add UI imports
there. New domain collaborators belong in the controller/composition root and should stay injectable for tests.
Every private-key or card operation walks **one sheet**: `_confirmOperation` (`wallet_flow_screen_confirm.dart`)
runs PIN → signing/card tap → result, drawing progress from the controller's busy state; the send sheet
(`wallet_flow_screen_unlocked.dart`) is form → review → PIN → signing → result itself. While such a sheet is open,
`beginInlineConfirmation`/`endInlineConfirmation` keep the root busy overlay and the card-PIN biometric offer out
of its way. Don't stack a PIN sheet under the overlay again. «Новая карта» (`WalletFlowStage.addCard`) is the
only way to add a card from an existing wallet; lock-on-open (`setLockOnOpen`, `appBackgrounded/appResumed`,
one-minute grace) puts `WalletFlowStage.locked` in front, and unlocking keeps no key material.
The Nocturne design system lives in `lib/src/design/` (`nocturne.dart` tokens, `app_theme.dart`,
`platform_style.dart` for the iOS/Android/desktop pattern seam, `app_shell.dart` for the four-tab shell). New
user-visible text goes into both ARB files (`lib/l10n/`), never inline; the persisted language choice is in
`app_locale.dart`.

## Conventions & gotchas

- **The app version is duplicated across several files — keep them in sync.** `pubspec.yaml` (`version:`) is the source; `lib/src/app_version.dart` (`appVersion`/`appVersionLabel`) must match, `test/widget_test.dart` asserts the on-screen `appVersionLabel`, and both `README.md` and the `docs/development-plan.md` NOW snapshot also state it. When bumping, update all of them. Project convention (per README) is to **bump the minor version with each functional step**.
- **Commit messages** follow Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `style:`.
- **UI text is in ARB; widget tests locate elements by the Russian strings** — keep both ARB files in step.
- **Errors are codes, not sentences.** Domain/infrastructure code (`key_storage/`, `qr/`, `walletconnect/`, `airgap/`, `transactions/`, `auth/`) throws its exception type with `.coded(AppErrorCode.x, {args})` (`lib/src/errors/app_error.dart`); `describeError` (`lib/src/error_text.dart`) is the only place that turns a failure into text. A new failure = a new code + copy in both ARBs + its arm in the exhaustive switch (a missing arm fails to compile; `test/error_text_test.dart` checks both languages). Protocol parse failures use the existing `…Malformed…` codes with an English `detail`. Text sent *to dApps* uses `DappErrorText` (English), never the UI bundle. Uncoded constructors are only for text that comes from outside the app (an RPC node, the relay).
- Keep `docs/development-plan.md` phase status in sync when completing roadmap items (existing `docs:` commits do this).
- **`dart_defines.json`** (repo root) holds the WalletConnect `WC_PROJECT_ID`; builds/runs pass it via `--dart-define-from-file=dart_defines.json` (helpers: `scripts/run.sh` / `scripts/build.sh`) and the app reads it as `wcProjectId` (`walletconnect/wc_config.dart`). It is **intentionally committed** (public client id; the owner accepts quota use) — don't treat it as a leaked secret or remove it. It is consumed by `ReownWalletConnectService` (chunk 9.2, wired).
- **Android toolchain:** Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0. `android/gradle.properties` matches what `flutter create` writes for AGP 9: `android.newDsl=false` is required by the Flutter Gradle plugin itself, and `android.builtInKotlin=false` remains only because `walletconnect_pay` (pulled by `reown_walletkit`, latest 1.1.0) applies `kotlin-android` unconditionally — AGP has no per-module opt-out. The app module is already in built-in-Kotlin form (no `kotlin-android`; Flutter applies KGP to it in this mode). Flip `builtInKotlin` to true once a migrated `walletconnect_pay` ships, and keep KGP `apply false` in `settings.gradle.kts` (it sets the Kotlin version; AGP 9.1 alone embeds 2.2.10, below Flutter's 2.2.20 minimum).
- **`pubspec.lock` follows the latest stable:** it is resolved with the current Flutter stable; after a new Flutter release `flutter pub get` may re-resolve SDK-pinned packages (`meta`, `test_api`, …) — commit that deliberately, together with the Flutter bump it belongs to.
- **`package_info_plus` override:** forced to ^10.2.2 because `reown_core`/`walletconnect_pay` cap it `<10` while 9.x applies KGP itself; 10.0.0 only broke win32/min-platform versions, not the Dart API. Drop it when Reown widens the constraint.
- **Android vault persistence:** `flutter_secure_storage` 10.x (the override that once forced it is gone since `reown_core` 1.5 accepts ^10). Our store uses crash-safe v9→v10 migration with `resetOnError:false`; Android Auto Backup is disabled because keystore keys cannot safely restore with encrypted preferences.
