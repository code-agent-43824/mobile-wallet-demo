# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

This file contains project-specific commands, code structure, and pitfalls. The imported `AGENTS.md` contains the shared working rules.

## Project map

This is a Flutter EVM wallet for Android and iOS, with desktop builds for Windows (x64, arm64), Linux and macOS. `lib/main.dart` enters `MobileWalletDemoApp` and `WalletFlowScreen`; the architecture map below identifies the domain layers and their testing seams. Product direction is in `docs/ROADMAP.md`, active work in `docs/PLAN.md`, current state and version in `docs/STATUS.md`, and physical-device evidence in `docs/device-test-matrix.md`. `docs/WORKLOG.md` records completed work. Native Rutoken integration details are in `docs/nfc-pkcs11-integration-notes.md`; the complete former plan is archived under `docs/archive/`.

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
flutter build windows --release                  # Windows (the host's architecture)
flutter build linux --release                    # Linux (needs GTK, libsecret: scripts/smoke/install_linux_deps.sh)
flutter build macos --release                    # macOS (universal)
```

CI (`ci.yml`) runs `plan` and `validate` (format check → analyze → test), then one reusable workflow per target (`target-android.yml`, `target-ios.yml`, `target-windows.yml` ×2 arches, `target-linux.yml` ×2, `target-macos.yml`). Each builds on a runner of its own OS/architecture; on a smoke run each build is followed by smoke jobs on the same kind of runner that launch the exact release artifact (`scripts/smoke/`, `scripts/android_launch_check.sh`) and then run `integration_test/smoke_test.dart` from a clean install. **`dart format` is an enforced gate** — unformatted code fails CI. Run `dart format .` before committing.

Releases: bump the version (and the CHANGELOG section) in `main`. The `plan` job sees that `v<version>` has no release, so that run smoke-tests every target and the `release` job publishes every artifact with a smoke table in the notes, creating the tag itself (agents cannot push tags through the proxy). A pushed `v*` tag matching the version also releases. A manual run with `smoke` ticked smoke-tests without publishing. Targets with no same-architecture runner (Android armeabi-v7a, the unsigned iOS device app, Android arm64 when the arm runner has no KVM) are released marked "not smoke-tested". (GitLab releases on its own tags.)

The project's primary home is now the internal GitLab (`prototypes/mobile-wallet-demo`); `.gitlab-ci.yml` runs
blocking SAST (semgrep + osv from `mko/ci-security`), the same format/analyze/test gate, an Android APK build, docs
Pages, and tag releases. The GitHub repository has additional desktop targets and release smoke tests;
do not assume its workflow matches the GitLab pipeline target for target.

## Architecture

Code lives under `lib/src/`, split into layers: `auth/`, `blockchain/`, `key_storage/`, `transactions/`, plus the UI orchestrator `wallet_flow_screen.dart` (its presentational widgets live in `wallet_flow_screen_*.dart` `part` files). `main.dart` → `app.dart` (`MobileWalletDemoApp`) → `WalletFlowScreen`.

### Dependency injection is the testing seam

`MobileWalletDemoApp` (`lib/src/app.dart`) takes every external dependency as an **optional nullable constructor arg, defaulting to the production implementation**. Almost every concrete class has an `abstract interface class` counterpart. Tests inject fakes (`InMemorySecureKeyValueStore`, `_FakeBlockchainProvider`, `_FakeNonceProvider`, `_FakeBroadcaster`, `_FakeTrackingTransport`, `SimulatedBiometricAuthGateway`) through this constructor. Follow this pattern for any new collaborator: define the interface, inject it, default to the real impl.

### Key storage: the central abstraction

`KeyStorageBackend` (`key_storage/key_storage_backend.dart`) is the core contract (create/import/unlock/biometrics/lock). Two backend kinds (`WalletBackendKind.phoneSecureVault` / `externalDevice`), selected at runtime via `WalletBackendRegistry` (persists the choice in the secure store):

- **`PhoneSecureVault`** — the real backend. Implements the **"Phone Secure Vault" model** (historical reasoning: `docs/archive/development-plan-through-v1.60.md`, "Core architectural decision"): it deliberately does *not* use a non-exportable secure-enclave key, because the product must show/import a seed phrase. Instead the BIP-39 seed is encrypted at rest with AES-GCM-256 under a random data-encryption key (DEK); the DEK is wrapped by a PIN-derived key (PBKDF2, 600k iterations); the PIN is never persisted, and repeated wrong PINs trigger a temporary unlock lockout. A single EVM address is derived at `m/44'/60'/0'/0/0`. Biometric unlock keeps the DEK in a dedicated `BiometricSecretStore` (`key_storage/biometric_secret_store.dart`) gated by `local_auth`, rather than co-locating a key with the seed ciphertext. `PinUnlockSession` remains an internal primitive, but the controller deliberately requests fresh authorization for every private-key operation and calls `lock()` in `finally`. This releases references; immutable Dart strings cannot be claimed to be securely zeroized.
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

- **The app version is duplicated in code — keep it in sync.** `pubspec.yaml` (`version:`) is the source; `lib/src/app_version.dart` (`appVersion`/`appVersionLabel`) must match, and `test/widget_test.dart` asserts the on-screen `appVersionLabel`. Update `docs/STATUS.md` when a new release changes the project state. Project convention (per README) is to **bump the minor version with each functional step**.
- **UI text is in ARB; widget tests locate elements by the Russian strings** — keep both ARB files in step.
- **Errors are codes, not sentences.** Domain/infrastructure code (`key_storage/`, `qr/`, `walletconnect/`, `airgap/`, `transactions/`, `auth/`) throws its exception type with `.coded(AppErrorCode.x, {args})` (`lib/src/errors/app_error.dart`); `describeError` (`lib/src/error_text.dart`) is the only place that turns a failure into text. A new failure = a new code + copy in both ARBs + its arm in the exhaustive switch (a missing arm fails to compile; `test/error_text_test.dart` checks both languages). Protocol parse failures use the existing `…Malformed…` codes with an English `detail`. Text sent *to dApps* uses `DappErrorText` (English), never the UI bundle. Uncoded constructors are only for text that comes from outside the app (an RPC node, the relay).
- When a roadmap stage changes, update `docs/STATUS.md`; keep active actions in `docs/PLAN.md` and historical results in `docs/WORKLOG.md`.
- **`dart_defines.json`** (repo root) holds the WalletConnect `WC_PROJECT_ID`; builds/runs pass it via `--dart-define-from-file=dart_defines.json` (helpers: `scripts/run.sh` / `scripts/build.sh`) and the app reads it as `wcProjectId` (`walletconnect/wc_config.dart`). It is **intentionally committed** (public client id; the owner accepts quota use) — don't treat it as a leaked secret or remove it. It is consumed by `ReownWalletConnectService` (chunk 9.2, wired).
- **Android toolchain:** Gradle 9.3.1, AGP 9.1.0, Kotlin 2.4.0. `android/gradle.properties` matches what `flutter create` writes for AGP 9: `android.newDsl=false` is required by the Flutter Gradle plugin itself, and `android.builtInKotlin=false` remains only because `walletconnect_pay` (pulled by `reown_walletkit`, latest 1.1.0) applies `kotlin-android` unconditionally — AGP has no per-module opt-out. The app module is already in built-in-Kotlin form (no `kotlin-android`; Flutter applies KGP to it in this mode). Flip `builtInKotlin` to true once a migrated `walletconnect_pay` ships, and keep KGP `apply false` in `settings.gradle.kts` (it sets the Kotlin version; AGP 9.1 alone embeds 2.2.10, below Flutter's 2.2.20 minimum).
- **`pubspec.lock` follows the latest stable:** it is resolved with the current Flutter stable; after a new Flutter release `flutter pub get` may re-resolve SDK-pinned packages (`meta`, `test_api`, …) — commit that deliberately, together with the Flutter bump it belongs to.
- **`package_info_plus` override:** forced to ^10.2.2 because `reown_core`/`walletconnect_pay` cap it `<10` while 9.x applies KGP itself; 10.0.0 only broke win32/min-platform versions, not the Dart API. Drop it when Reown widens the constraint.
- **Cards need an arm64 process (tech debt, owner is getting the other ABIs).** `libwtpkcs11ecp.so` ships for arm64-v8a only and the PC/SC bridge has no x86_64 build. Kotlin `WalletDemoApplication.isRutokenSupported` (`os.arch`) skips the transport, runtime and channel; Dart `isRutokenSupportedOnThisDevice` (`Abi.current()`) creates no adapter, so the card actions give way to a "not supported on this device" note. Both check the *process* ABI (not `Build.SUPPORTED_ABIS`, which lists arm64 on x86_64 images with ARM translation); keep them in step and drop both once the libraries exist.
- **iOS needs the UIScene manifest.** `Info.plist`'s `UISceneConfigurations` (`$(PRODUCT_MODULE_NAME).SceneDelegate`, storyboard `Main`) is required by the Xcode 27 SDK; without it the app stops with SIGTRAP at launch. An unrelated plist rewrite dropped it once (`a011c2c`), so check it whenever the plist is regenerated.
- **Desktop builds are demos of the phone wallet.** `isDesktopPlatform` (`auth/biometric_auth.dart`) covers Windows, Linux and macOS: biometrics are simulated, `app.dart` gives them no WalletConnect and the file QR scanner, and no card adapter exists there. On macOS the vault uses the login keychain (`MacOsOptions(usesDataProtectionKeychain: false)`): the data-protection keychain needs a team-signed build, and the released app is ad-hoc signed.
- **Android vault persistence:** `flutter_secure_storage` 10.x (the override that once forced it is gone since `reown_core` 1.5 accepts ^10). Our store uses crash-safe v9→v10 migration with `resetOnError:false`; Android Auto Backup is disabled because keystore keys cannot safely restore with encrypted preferences.
