# Mobile Wallet Demo — Development Plan

This file is the canonical development plan for the project. Use it as the source of truth while implementing future tasks.

## Status snapshot

Current factual status of the project:
- ✅ CI foundation is in place and stable on Android, iOS Simulator, and Windows x64
- ✅ Phase 0 is effectively completed
- ✅ Phase 1 is implemented as a user-facing flow
- ✅ Phase 2 is implemented, including real biometric integration on Android/iOS and a Windows demo simulation path
- ✅ Phase 3 is implemented
- ✅ Phase 4 is implemented
- ✅ Phase 5 is implemented
- ✅ Phase 6 is implemented end-to-end, including retry/replacement handling and post-submit transaction lifecycle tracking
- ✅ Phase 7 is completed as a foundation layer: backend selection model, backend-compatible signing/auth contracts, demo external-device runtime path, mock device lifecycle, and mock PKCS#11 session/operation contracts are in place; real NFC SDK integration is intentionally still out of scope for this phase
- ✅ Phase 8 — only the WC v2 codec (`WalletConnectV2RequestCodec`) and the vault `TransactionService.assembleSignedTransfer` seam survive. The obsolete custom AirGap codec was removed in Phase 12.5; the **outbound** direction originally shipped by Phase 8 was removed in chunk 9.0
- ✅ Phase 9 (real **wallet-side** inbound signing — WalletConnect v2 + AirGap — plus a connections screen and an incoming-request approval flow) is **feature-complete**. WalletConnect is device-validated on Android through a confirmed Sepolia broadcast; AirGap now uses the MetaMask-compatible EIP-4527 / BC-UR implementation completed in Phase 12
- 🟡 Phase 10 is **in progress**: library-independent custody/EVM assembly and the first real Android vendor
  transport are complete in code; physical Rutoken validation, provisioning, production-backend wiring, and iOS remain
- ✅ Phase 11 is complete: read-only app open plus fresh authentication for every private-key operation
- ✅ Phase 12 is complete: MetaMask-compatible EIP-4527 / BC-UR AirGap signer

## Direction

**North star:** Wallet Demo is a single-account EVM wallet with a production-like phone vault. The next
milestone is an optional Rutoken custody backend for Android/iOS whose signing keys stay non-exporting after
recoverable provisioning and which supports the same own-send, WalletConnect, and EIP-4527 AirGap flows.

- **NOW — v1.46.0+57:** phone-vault custody, Mainnet/Sepolia reads and sends, wallet-side WalletConnect,
  MetaMask-compatible EIP-4527 AirGap, per-operation authentication, hardened QR scanning, and the
  library-independent Rutoken custody/signature foundation plus real Android PC/SC + PKCS#11 transport are built.
- **NEXT — Phase 10 physical validation/provisioning:** validate the read-only transport probe on the owner's
  Rutoken, resolve observed output/lifecycle differences, then implement both recoverable create/import paths,
  register the production backend, and dogfood the signing matrix. iOS follows proven Android behavior.
- **LATER:** optional lock-on-open privacy, broader device/platform integration tests, and only then additional
  chains/accounts if product scope changes. They are not Phase 10 prerequisites.

History is preserved in the phase sections and `docs/worklog.md`; the operational source of truth is the
NOW / NEXT / LATER summary above plus the Phase 10 exit criteria below.

Completed deliverables so far:
- ✅ project module structure started (`auth`, `key_storage`)
- ✅ interfaces for key storage backends
- ✅ placeholder external-device backend contract
- ✅ phone secure vault foundation:
  - BIP-39 seed generation
  - seed import
  - encrypted-at-rest seed storage
  - first EVM address derivation
  - PIN unlock session primitive
- ✅ unit tests for create/import/unlock flow
- ✅ read-only RPC foundation for Ethereum Mainnet and Sepolia
- ✅ read-only wallet experience with token balances, history, and local cache fallback
- ✅ transfer preparation flow with preview-only validation and gas estimation
- ✅ local EIP-1559 signing for native / ERC-20 prepared transfers
- ✅ public-RPC nonce loading for send flow
- ✅ raw transaction submission abstraction with public RPC broadcaster
- ✅ send flow UI states: pending / success / failure

Implemented near-term UX/security items:
- ✅ onboarding UI flow
- ✅ one-time seed phrase display screen
- ✅ biometric enable flow (real platform integration on Android/iOS, simulated path on Windows)
- ✅ locked / uninitialized app shell states

## Core architectural decision

For the phone-based wallet backend we will **not** model the wallet as a literal non-exportable Secure Enclave key, because that conflicts with the product requirement to:
- generate a seed phrase and show it once for backup;
- import a seed phrase.

Instead we use a **Phone Secure Vault** model:
- seed is generated or imported in app logic;
- seed is encrypted at rest;
- encryption keys are protected by platform secure hardware where available;
- PIN is mandatory;
- biometrics may be enabled only after PIN setup and act as a convenience unlock path;
- one PIN prompt per high-level signing operation.

This keeps the UX compatible with future support for an external NFC hardware signer.

## Product scope agreed so far

### Wallet lifecycle
- Create wallet inside the app
- Show seed phrase once for backup
- Import wallet from seed phrase

### Networks for first functional version
- Ethereum Mainnet
- Ethereum Sepolia testnet

### Security model
- Mandatory PIN for wallet usage
- Biometrics can be enabled only after PIN setup
- PIN is required for operations with the private key
- Within one operation, ask for PIN only once
- Biometric unlock is routed through a dedicated biometric secret store (`key_storage/biometric_secret_store.dart`): the seed is encrypted under a random DEK, the PIN is never persisted, no usable key is co-located with the seed ciphertext, PBKDF2 runs at 600k iterations, and repeated wrong PINs trigger a temporary lockout. Full hardware-bound biometric key release (native keystore) remains follow-up hardening.

### Hardware custody path (Phase 10; real device not implemented yet)
- Replace the current simulation with a non-exporting Rutoken backend
- The user chooses one custody backend:
  - phone secure vault;
  - external hardware device
- Both backends expose the same public-account and signing capabilities, but not the same secret-bearing API:
  - phone vault may unlock local material for its internal signer;
  - hardware custody exposes public account metadata and authenticated signing sessions only;
  - a real hardware backend must never return a mnemonic or private key to Dart.
- If the user uses only one backend, they have only one PIN source:
  - phone PIN for phone vault;
  - device PIN for external device

### Blockchain access
- Connect through public caching servers/providers
- Support manual refresh from blockchain
- Show:
  - token balances
  - estimated gas
  - recent transaction history
- Allow sending assets by entering:
  - destination address
  - amount
- Gas should be estimated automatically

### Implemented protocol integrations
- WalletConnect v2 wallet-side pairing and inbound transaction/message/EIP-712 signing
- MetaMask-compatible EIP-4527 / BC-UR AirGap account export and transaction signing

## Implementation principles

1. Start from simple read-safe functionality, then move to signing and sending.
2. Keep code simple and readable.
3. Build around stable interfaces first, especially for key storage backends.
4. Separate UI, domain logic, security/auth, blockchain access, and storage.
5. Every project change should be committed, pushed, and validated via GitHub Actions.

## Recommended architecture

### Main modules
- `auth` — PIN, biometric unlock, operation auth context
- `wallet_core` — wallet domain models and use cases
- `key_storage` — backend contracts and implementations
- `blockchain` — RPC/indexer providers, balances, fees, history
- `transactions` — transaction building, preview, signing, sending
- `ui` — screens, navigation, presentation state

### Key interfaces to design early
- `KeyStorageBackend`
- `AuthGate`
- `WalletRepository`
- `BlockchainProvider`
- `TokenBalanceService`
- `HistoryService`
- `TransactionService`

### As built (reality vs. the recommendation above)
The shipped code deliberately consolidated the recommendation, so a new agent should not expect to find all of the modules/interfaces above:
- Modules under `lib/src/`: `auth/`, `airgap/`, `blockchain/`, `key_storage/`, `qr/`, `transactions/`, and
  `walletconnect/`, plus UI files under `wallet_flow_screen*.dart`. There is no separate `wallet_core/` or
  `ui/` directory.
- Domain state and actions live in the widget-free `WalletFlowController`; `WalletFlowScreen` is a thin
  listener/composition root and the `part` files hold presentation widgets.
- `KeyStorageBackend`, `BlockchainProvider`, and `TransactionService` exist as designed. `AuthGate` / `WalletRepository` / `TokenBalanceService` / `HistoryService` were **not** created as separate interfaces: auth is split across `BiometricAuthGateway` + `WalletOperationAuthorizer`, and token/history reads are folded into `BlockchainProvider.loadSnapshot` (`WalletChainSnapshot`).
- Treat `CLAUDE.md` as the detailed map of the current code; this section distinguishes the original aspiration
  from the present layout.

## Development roadmap

## Phase 0 — architectural skeleton
Goal: create clean module boundaries before feature growth.

Status: ✅ Completed

Deliverables:
- [x] project module structure
- [x] interfaces for key storage backends
- [x] app flow skeleton
- [x] placeholder external-device backend contract

## Phase 1 — onboarding and local auth
Goal: establish secure user entry flow.

Status: ✅ Completed

Deliverables:
- [x] welcome screen
- [x] choice: create wallet / import seed
- [x] mandatory PIN setup and confirmation
- [x] optional biometric enable after PIN setup
- [x] app state for locked/uninitialized wallet

Out of scope:
- blockchain reads
- transfers
- token logic

## Phase 2 — phone secure vault
Goal: implement the first real wallet backend.

Status: ✅ Completed (foundation, create/import UX, seed display, PIN unlock, real mobile biometrics and Windows demo simulation path are implemented)

Deliverables:
- [x] BIP-39 seed generation
- [x] one-time seed phrase display flow
- [x] seed import flow
- [x] encrypted storage of seed
- [x] address derivation for EVM
- [x] unlock flow protected by PIN / biometrics (real biometric auth on Android/iOS, simulated biometric auth on Windows)

## Phase 3 — EVM network foundation
Goal: connect to blockchain in read-only mode.

Status: ✅ Completed

Deliverables:
- [x] Ethereum Mainnet config
- [x] Sepolia config
- [x] public RPC provider layer with fallback strategy
- [x] native balance retrieval
- [x] base fee / gas estimate retrieval
- [x] network metadata handling

## Phase 4 — read-only wallet experience
Goal: first useful user-facing wallet release without send risk.

Status: ✅ Completed

Deliverables:
- [x] wallet home screen
- [x] address display
- [x] current network switch/display
- [x] native and token balances
- [x] manual refresh
- [x] recent transaction history screen
- [x] local cache for last loaded blockchain state

## Phase 5 — transfer preparation
Goal: prepare safe transaction composition before enabling send.

Status: ✅ Completed

Deliverables:
- [x] send screen
- [x] address validation
- [x] amount entry
- [x] asset selection
- [x] automatic gas estimation
- [x] transaction preview screen

## Phase 6 — signing and sending
Goal: enable real blockchain operations.

Status: ✅ Completed (end-to-end send flow with real retry/replacement handling, post-submit transaction tracking, and non-blocking lifecycle UX implemented)

Deliverables:
- [x] one auth prompt per operation (domain-layer signing flow contract)
- [x] transaction signing
- [x] transaction submission
- [x] pending/success/failure status handling
- [x] basic nonce/error handling through public RPC lookup and surfaced failures
- [x] advanced nonce/error hardening with retry logic (replacement tx, stale nonce reconciliation, richer RPC-specific recovery)
- [x] post-submit transaction tracking with TransactionTracker
- [x] gas price increase mechanism for underpriced transaction replacement
- [x] UI integration for transaction status and replacement notifications

## Phase 7 — external NFC device foundation
Goal: keep a clean future path without implementing device SDK now.

Status: ✅ Completed (foundation layer finished without real SDK; this phase now has selection, auth/signing, lifecycle, and mock PKCS#11 session/operation contracts for an external-device path)

Deliverables:
- [x] abstract backend contract for external hardware
- [x] storage-backend selection model
- [x] compatible signing/auth flow contracts
- [x] simulated external-device UX/runtime path without real SDK
- [x] mock device lifecycle: availability, reconnect, session disconnect, error states
- [x] mock PKCS#11 session/operation contracts
- [x] no real NFC implementation yet

## Phase 8 — future extension points (superseded)
Goal: reserve clean extension paths for WalletConnect v2 + AirGap.

Status: ⚠️ **Superseded / role-corrected.** Phase 8 originally shipped (chunks A–F, v1.11–v1.16) in the **outbound** role — this app *requesting* a signature from an external WalletConnect/AirGap signer. That is the wrong role: the wallet must *receive* and approve signing requests. The outbound transport/session/registry/connectors and the "Подписать через" send-flow option were **removed in chunk 9.0 (v1.17)**. The wallet-side integration is **Phase 9**.

What survives Phase 8 for the next agent (kept, still used):
- `WalletConnectV2RequestCodec` (`walletconnect/wallet_connect_v2.dart`) — the WalletConnect wire/field mapping. The custom Phase-8 AirGap payload mapping was superseded and removed by Phase 12.5.
- `TransactionService.assembleSignedTransfer` — build a `SignedTransfer` from raw signed bytes without duplicating crypto.
- The external-device demo (`key_storage/external_device_demo_backend.dart` + `external_device_pkcs11.dart`) is the **custody** precedent for Phase 10 (where the key lives + tap/PIN confirmation) — distinct from this transport axis; it is *not* a signing transport.

## Phase 9 — Wallet-side inbound signing (WalletConnect v2 + AirGap) + connections screen
Goal: make this app a **real wallet** that *receives* signing requests. Two transports bring requests in:
- **WalletConnect v2** (online): external dApps pair with the wallet over the relay, send `eth_sendTransaction` / `eth_signTransaction` / `personal_sign` / `eth_signTypedData_v4`, and the wallet approves and signs with the on-device vault.
- **AirGap** (offline): the wallet scans a request QR from an air-gapped companion (or acts as the offline signer), signs, and returns a response QR.

Both surface through a dedicated **Connections screen** (status, active sessions, inspect/disconnect, new connection) and a shared **incoming-request approval sheet** (request details → Approve/Reject → vault sign → respond).

This corrects the Phase 8 role: Phase 8 modelled the *outbound* direction (the app requesting a signature from an external signer). The product is wallet-side, so **9.0** removes that and **9.1+** build the inbound integration, reusing the Phase 8 codecs.

Status: ✅ **Feature-complete (chunks 9.0–9.9).** 9.0–9.1 done (v1.18); 9.3 done; **9.4 done** (9.4a DI/controller WC seam + screen/request approval, v1.20–v1.21); 9.5–9.8 done (AirGap, QR, EIP-191, EIP-712, v1.22–v1.26); **9.2 done** (real `ReownWalletConnectService`, v1.27); **9.9 done** (live camera QR, v1.28–v1.29). WalletConnect is now **device-validated on Android through a confirmed Sepolia broadcast** (v1.36: connect, transaction approval/sign/broadcast, per-op PIN, request queue, and cold-start vault persistence). v1.37 adds EIP-5792 capability discovery and safe simulated contract previews. The MetaMask-compatible Phase 12 AirGap path was owner-dogfooded end to end in v1.38; v1.39 hardens its intermittent Android camera recognition.

### Owner verification
- **AirGap inbound, end-to-end** (passed on Android, 2026-07-22) — MetaMask imported the EIP-4527 account, Wallet Demo scanned and signed a Sepolia transaction request, and MetaMask accepted the returned signature; the owner reported the transaction appeared to broadcast. The request QR decoded reliably from a saved screenshot but only after several live-camera attempts, motivating the v1.39 camera hardening. The exact transaction hash was not recorded.

### Two axes (do not conflate)
- **Transport axis (this phase):** how a signing request *arrives* — WalletConnect (online relay) or AirGap (offline QR). The wallet still signs with whatever custody backend is active.
- **Custody axis (Phase 10):** *where the key lives and how the user confirms* — phone vault (PIN/biometric) or external NFC device (tap + device PIN). Inbound requests compose with either custody backend.

### Dependencies & prerequisites
- WalletConnect: `reown_walletkit` (official Reown/WalletConnect Flutter wallet SDK; formerly `walletconnect_flutter_v2`). Pin a version; `flutter pub get`.
- A WalletConnect Cloud **project ID** via `--dart-define=WC_PROJECT_ID=…`. This public client id is intentionally
  committed in `dart_defines.json`; builds still show a clear "not configured" state when the define is absent.
- Relay (`wss://relay.walletconnect.org`) reachable — depends on the environment network policy; live pairing is manual/dogfood, automated tests use the fake service.
- QR input: **file load on all platforms** (`file_selector` + `image` + `zxing2`, pure-Dart decode — works on Windows) **+ live camera** on Android/iOS (`mobile_scanner`, with an overlay-only aim guide + torch). v1.39 analyzes the full frame, requests 1920×1080 on Android, and enables Android auto-zoom. No Windows camera — file load is the only path there.
- Navigation: the app is one `WalletFlowScreen` state machine with no routes; this phase introduces a route (or a new stage) for the Connections screen.

### Architecture
- `WalletConnectService` — an abstract interface injected through `MobileWalletDemoApp` like every other dependency (real impl default; `FakeWalletConnectService` for tests/DI). Surface: `init`, `pair(uri)`, `approveSession`/`rejectSession(proposal)`, `disconnect(topic)`, `activeSessions` + a sessions `Stream`, an incoming-requests `Stream`, and `respond(requestId, result|error)`.
- Inbound request models: a session proposal, active-session info (dApp name/url/icon, chains, accounts, connected-at), and an incoming `SigningRequest` (method + params + originating session).
- Request → signing: parse `eth_sendTransaction` / `eth_signTransaction` params, preflight transaction calls,
  then authenticate once for that operation and sign via the summary-bound active custody backend. Phase 11
  supersedes the earlier five-minute-session design: every private-key request gets fresh PIN/biometric or
  device tap+PIN authorization, and the backend is relocked in `finally`. Broadcast `eth_sendTransaction` via
  the existing broadcaster; message and typed-data requests use the same per-operation policy.
- AirGap inbound: export the account via `crypto-hdkey`, scan an EIP-4527 `eth-sign-request`, verify the offline transaction preview, sign through the active backend, and display the `eth-signature` QR.
- Connections screen: a status banner; a list of active sessions (dApp name/url/icon, chains, accounts, connected-at); tap → details; disconnect; "New connection" (paste/scan a `wc:` URI). Navigation entry from the unlocked dashboard.

### Chunk breakdown (each chunk: plan → code → record, per AGENTS.md)
- **9.0** — *cleanup*: remove the inverted Phase 8 **outbound** code (transport/session/registry/connectors + "Подписать через"); keep the codecs (`WalletConnectV2RequestCodec`, `AirGapPayloadCodec`) and `assembleSignedTransfer`. No new feature; tests trimmed to the codecs. ✅ done (v1.17)
- **9.1** — `WalletConnectService` interface + inbound models (`WalletConnectPeer` / `…SessionProposal` / `…Session` / `…Request`) + `FakeWalletConnectService` + `UnavailableWalletConnectService` (shippable default) + unit tests. Pure Dart, no SDK. ✅ done (v1.18). *(The `reown_walletkit` dep + `WC_PROJECT_ID` config + DI wiring moved to 9.2, where the real impl consumes them.)*
- **9.2** — real SDK impl (`ReownWalletConnectService`) behind the interface: init, pair, proposal approve/reject,
  session list + streams, respond, disconnect. ✅ complete and device-validated (v1.27–v1.36): Android owner
  dogfood confirmed pairing, requests, per-operation authorization, and a Sepolia transaction broadcast. The
  original dependency/toolchain probe and integration detail remain in `docs/worklog.md`.
- **9.3** — incoming request → vault signing: WC method parsing (inverse codec), the request→sign→respond flow, broadcast for `eth_sendTransaction`. ✅ done on the fake (`WalletConnectV2RequestCodec.decodeTransactionRequest`, `TransactionService.prepareInboundTransaction`, `WalletConnectInboundCoordinator`); the user-facing approval sheet is folded into 9.4b.
- **9.4a** — DI + controller seam: inject `WalletConnectService` through `MobileWalletDemoApp` → `WalletFlowScreen` → `WalletFlowController` (default `UnavailableWalletConnectService`); the controller subscribes to the proposal/session streams and exposes `isWalletConnectAvailable` / `walletConnectSessions` / `pendingProposal` + actions `pairWalletConnect` / `approvePendingProposal` / `rejectPendingProposal` / `disconnectWalletConnectSession`; controller tests on the fake. ✅ done (no UI yet).
- **9.4b** — Connections screen: `WalletFlowStage.connections` + the screen (status chips, "new connection" `wc:` URI field, the session-proposal approval card, the active-session list with disconnect) + a navigation entry ("Подключения (WalletConnect)") from the unlocked dashboard + widget tests (pair→approve→disconnect, back). ✅ done (v1.20). *The **incoming-request** approval sheet (driving `WalletConnectInboundCoordinator` from the controller on `requests`) is a follow-up — see 9.4c.*
- **9.4c** — incoming-request approval sheet: the controller subscribes to `WalletConnectService.requests` (→
  `pendingRequest`), the Connections screen shows a request card, and approval drives
  `WalletConnectInboundCoordinator`; reject returns `respondError`. ✅ done (v1.21). Phase 11 later replaced
  the original held-material behavior with fresh per-operation authorization.
- **9.5** — AirGap inbound: decode an `airgap-tx:` request → sign with the active backend → encode the `airgap-sig:` response. ✅ done (v1.22): `AirGapInboundCoordinator` (decode → `prepareInboundTransaction` → sign → `encodeResponse`; offline, so no nonce lookup/broadcast) + a Connections-screen "AirGap" section (paste request → «Подписать офлайн» → response payload to copy/show back) + coordinator/controller/widget tests. *Camera scan (`mobile_scanner`) of the request/response QR is deferred to the QR chunk (9.6); this is paste-based.*
- **9.7** — message signing: `personal_sign` / `eth_sign` (EIP-191). ✅ done (v1.25): codec `isMessageSignMethod`/`decodeMessageRequest`, `signPersonalMessage` on `TransactionService` + the signer (web3dart), a `WalletConnectInboundCoordinator` message branch (verify account → sign → respond with the 65-byte signature), and the request card shows the decoded message.
- **9.8** — EIP-712 typed-data signing: `eth_signTypedData_v4` / `_v3`. ✅ done (v1.26): pure-Dart `walletconnect/eip712.dart` (`Eip712Encoder` — domain/struct hashing with nested structs + arrays → the 32-byte digest), `TransactionService.signDigest` + `WalletTransactionSigner.signDigest` (raw secp256k1 via web3dart `sign`, low-s), codec `isTypedDataMethod`/`decodeTypedDataRequest`, a coordinator typed-data branch, and a `primaryType @ domain` summary in the request card. Validated against the canonical EIP-712 "Mail" vector (digest + signature generated with reference `eth-account`).
- **9.6** — QR for WalletConnect pairing + AirGap + incoming-request sheet polish. ✅ done. v1.23: the `QrScanner` seam (`qr/qr_scanner.dart` — interface + `UnavailableQrScanner` + `FakeQrScanner`) injected through `MobileWalletDemoApp` → controller; request-card polish (sender line). v1.24: the seam grows two sources (camera vs file load) and `FileQrScanner` (`qr/file_qr_scanner.dart`) becomes the production default — **real QR load from an image file on every platform** (`file_selector` picker + pure-Dart `image`+`zxing2` decode via `ZxingQrImageDecoder`), the only option on Windows; "Загрузить … из файла" buttons fill the `wc:`/`airgap-tx:` fields. Decode test against a committed PNG fixture + controller/widget tests. *The live **camera** impl (`mobile_scanner`) lands in **9.9** (v1.28); file load + paste are the cross-platform paths and the only ones on Windows.*
- **9.9** — live **camera** QR scan (`mobile_scanner`). ✅ done (v1.28). **9.9a** (probe): added `mobile_scanner: ^7.2.0` dep-only and confirmed CI green on all 4 platforms (iOS = pure-Swift Vision, deployment target 12.0 ≤ app's 13.0, no heavy pod; Android = standard Google Maven MLKit, no flavor dimension, minSdk 23 already satisfied; Windows excluded as unsupported). **9.9b** (integration): `qr/camera_qr_scanner.dart` — `CameraQrScanner` adds `scanWithCamera` (full-screen `MobileScanner`, QR-only + `noDuplicates`, pops the first `rawValue`) and delegates `loadFromFile` to a composed `FileQrScanner`; pushed via a global `navigatorKey` on `MaterialApp` (the seam has no `BuildContext`). DI selects it on Android/iOS (file-only `FileQrScanner` elsewhere). iOS `NSCameraUsageDescription` added; Android `CAMERA` permission comes from the plugin manifest. Unit test covers availability + file delegation + the no-navigator error path (the live widget can't run headless). **9.9c** (polish, v1.29): a scan-window overlay (`ScanWindowOverlay`, centred square — detection initially limited to it) + a torch toggle (`controller.toggleTorch()`, reflecting the live `TorchState`). **v1.39 hardening:** keeps a larger guide only as an overlay, restores full-frame detection, requests 1920×1080 on Android, and enables ML Kit auto-zoom for dense BC-UR QRs.

### Deliverables
- [x] 9.0 cleanup (remove outbound, keep codecs)
- [x] `WalletConnectService` abstraction + `FakeWalletConnectService` (+ `UnavailableWalletConnectService` default; real-impl DI deferred to 9.2)
- [x] real `reown_walletkit` implementation (init / pair / sessions / disconnect) — `ReownWalletConnectService`, v1.27; device-validated for connect/disconnect/`personal_sign`
- [x] incoming-request → vault signing + `respond` (logic on the fake: `WalletConnectInboundCoordinator`; approval-sheet UI wired in 9.4c, v1.21)
- [x] Connections screen (9.4a DI + controller WC seam; 9.4b screen: status / new connection / proposal approval / sessions + disconnect / dashboard entry)
- [x] AirGap inbound (original v1.22 custom format superseded; production path is EIP-4527/BC-UR in Phase 12, v1.38)
- [x] QR-code pairing for WalletConnect (`QrScanner` seam v1.23; all-platform **file load** v1.24 via `FileQrScanner`/`file_selector`/`image`/`zxing2`; live **camera** v1.28–v1.29 via `CameraQrScanner`/`mobile_scanner` on Android/iOS; v1.39 full-frame/high-resolution/auto-zoom hardening + overlay guide + torch)
- [x] message + typed-data signing (`personal_sign`/`eth_sign` v1.25; EIP-712 `eth_signTypedData_v4`/`_v3` v1.26)
- [x] tests + docs (per-chunk unit/widget tests on the fake; docs kept in sync)

### Ongoing validation boundaries
- Live relay reachability and `reown_walletkit` API/toolchain changes remain external risks; keep the dependency
  pinned and repeat pairing dogfood after upgrades.
- Keep approved WalletConnect chains aligned with `blockchain/network_config.dart`.
- Camera permission/focus behavior and live QR recognition remain physical-device checks.
- Deterministic flow tests use fakes; record live coverage in `docs/device-test-matrix.md`.

### Optional follow-ups (deferred — not blockers; Phase 9 is feature-complete)
Owner decision (2026-06-16): finish these later, on demand. Recorded so they aren't lost.
- **`wallet_switchEthereumChain` / `wallet_addEthereumChain`** — `wallet_switchEthereumChain` is done in v1.36
  for the owner's Uniswap dogfood (Mainnet + Sepolia); `wallet_addEthereumChain` remains deferred because the
  wallet exposes only its built-in network catalog.
- **Inbound request queue** — done in v1.36 after live Android dogfood showed timing-dependent request/vault
  failures; requests are queued and approval is serialized, so a later Uniswap/React request cannot overwrite
  the one currently shown or being handled.
- **Proposal namespace validation** — done in v1.37: unsupported required chains/methods reject approval;
  unsupported optional chains/methods are omitted from the approved namespace instead of being advertised.
- **Uniswap / EIP-5792 hardening (done, v1.37)** — auto-answer authorized
  `wallet_getCapabilities` probes without UI/PIN, filter approved namespaces to the methods/chains the wallet
  actually implements, replace fixed inbound gas/fee fallbacks with live RPC estimation, and show a simulated
  contract-call preview before vault authentication.

### Non-goals (this phase)
- non-EVM chains; a full dApp browser; push notifications for background requests; bespoke session persistence beyond what the SDK provides; custody/NFC changes (those are Phase 10).

## Phase 10 — Real Rutoken custody backend
Goal: replace the simulated external-device path with an optional Rutoken backend whose signing keys remain
non-exporting after provisioning and which composes with every existing signing transport while keeping the
phone-vault path unchanged. Provisioning must preserve recoverability using only the demonstrated import primitive:
support importing an existing BIP-39 backup and generating a new mnemonic in software for mandatory one-time
backup confirmation before importing its raw BIP32 master key + chain code. A backup-less mode is deferred.

Status: 🟡 In progress. Phase 10.1–10.2 are complete in v1.40. The Android 10.0/10.3 transport implementation
is present in v1.46 and awaits continued physical validation; provisioning, production-backend wiring, full dogfood, and iOS remain.

> **Reference:** `docs/nfc-pkcs11-integration-notes.md` contains the vendor mechanisms, native-stack setup,
> Ethereum corrections, and physical-device questions. The existing demo adapter is a test double, not an
> interface that the real SDK must preserve.

### Required architecture
- Separate public account data from local secret material. Use an `AccountDescriptor` for the token-derived
  address/path and keep optional account xpub metadata in software from provisioning; keep `WalletMaterial`
  local to the phone vault.
- Have the active backend provide a transient authenticated `WalletTransactionSigner` (or equivalent signer
  session). A real hardware backend never returns mnemonic, seed, or private key to Dart.
- Model account-xpub/`crypto-hdkey` export as an explicit software capability backed by public metadata retained
  during provisioning. The minimal native adapter must not query undocumented derived chain-code/xpub attributes.
- Keep authentication per operation. Open the NFC/device session, verify the device PIN, perform exactly the
  approved operation, and tear the session down on success, error, or cancellation.
- Keep custody independent from transport: own-send, WalletConnect, and AirGap all request a signer from the
  selected backend.

### Chunk breakdown
Small, reviewable steps; each chunk records plan and result in `docs/worklog.md`:
- **10.0 — IMPLEMENTED, PHYSICAL VALIDATION IN PROGRESS (v1.46):** the exact Android v1.1 artifacts are vendored with
  license/checksum and the platform-channel approach is implemented. The welcome-screen diagnostic exercises
  token discovery, session login, public address derivation, raw signing, and teardown without changing the master key.
  Owner dogfood confirms that v1.43 detects the NFC token and reaches key lookup. Public derivation/signing remain
  under physical validation. NFC APDUs remain owned by the vendor PC/SC bridge.
- **10.1 — DONE (v1.40; native boundary corrected v1.46):** secret-free `WalletAccountDescriptor`, account-level public-xpub data,
  `CustodySigningSession`, `WalletCustodyBackend`, and typed `RutokenNativeAdapter` contracts for session,
  public account, raw signing, generation, import, and guaranteed close. For Rutoken, EIP-4527 account export
  consumes public metadata retained by software during provisioning; it is not a native xpub-read operation.
- **10.2 — DONE (v1.40):** `ExternalDigestWalletTransactionSigner` + `EvmSignatureAssembler` validate raw
  64-byte `r‖s`, enforce secp256k1 bounds/EIP-2 low-s, recover y-parity against the expected address, and build
  byte-identical EIP-155/EIP-1559 transactions plus personal/raw-digest/AirGap signatures. Fake native-session
  tests prove local parity and idempotent/error-path teardown.
- **10.3 — IMPLEMENTED, PHYSICAL RETEST PENDING (v1.46):** official rtpcscbridge 1.4.0 + pkcs11wrapper 4.3.1 +
  pkcs11jna 4.2.0 + JNA 5.17.0, ARM64 `libwtpkcs11ecp.so`, serialized Kotlin lifecycle/session/login,
  public-key read, per-operation derived signing keys, raw `CKM_ECDSA`, MethodChannel adapter,
  and success/error/Activity-stop teardown. The first v1.41 device run found that polling `C_GetSlotList` never
  activated NFC discovery even though the official demo worked on the same phone/token; v1.42 now mirrors the
  official concurrent blocking `C_WaitForSlotEvent` listener plus initial slot snapshot, but detection still
  timed out. The remaining startup mismatch was transport attachment from inside Activity creation; v1.43 now
  mirrors `RutokenDemoWalletApplication` and attaches the bridge in `Application.onCreate` before the first
  Activity lifecycle callback; owner dogfood confirms discovery now works. The next v1.43 failure exposed another
  exact reference mismatch: its empty `DerivationPath()` contains a null `LongArray?`, while Wallet Demo passed a
  non-null zero-length array that JNA could not allocate. v1.44 uses the vendor nullable representation, retains
  the `CKK_VENDOR_BIP32` filter so the companion EdDSA key is ignored, and gives a provisioning-specific message
  for an empty token. Owner dogfood on v1.44 passed that boundary and returned `CKA_EC_POINT`, which exposed an
  overly narrow Dart assumption that every token emits an uncompressed 65-byte point. v1.45 now derives the
  official `Pkcs11EcPublicKeyObject`, reads `getEcPointAttributeValue`, and validates/normalizes both compressed
  33-byte and uncompressed 65-byte SEC1 points, either raw or DER OCTET STRING-wrapped. Owner dogfood on v1.45
  then reached `CKR_KEY_TYPE_INCONSISTENT`: the app was querying a derived account chain-code attribute that the
  supplied example never reads. v1.46 removes that operation from the native contract and mirrors the reference
  signing path exactly: derive `Pkcs11EcPrivateKeyObject` with the demonstrated template, sign the software-built
  32-byte digest with plain `CKM_ECDSA`, and destroy the child in `finally`. Retest address + raw signature, then
  refine cancellation, NFC-loss and PIN error mapping.
- **10.4 — recoverable provisioning and public export:** implement both owner-required UX paths through the
  reference example's `C_CreateObject` import only: (a) derive the raw BIP32 master + chain code from an existing
  BIP-39 mnemonic/passphrase in short-lived software buffers, or (b) generate a new mnemonic in software, require
  one-time backup display/confirmation, derive the same raw inputs, and import them. Do not expose backup-less
  creation or invoke undocumented token generation/export behavior. Persist the public account xpub/chain-code
  metadata needed for AirGap at provisioning time; do not query it from the token during normal operation.
- **10.5 — complete signing matrix:** validate own-send; WalletConnect transaction, `personal_sign`, and EIP-712;
  and EIP-4527 AirGap transaction signing through the real device backend.
- **10.6 — UX and iOS:** replace mock device controls with tap/PIN/progress/cooldown/retry UX, then port the
  proven shared contracts to the vendor iOS stack and run the same physical-device matrix.

### Definition of Done
- During normal use and signing, seed/private key never leave the token; logs, errors, persisted platform-channel
  payloads, and long-lived Dart models contain no secret material. Provisioning is the explicit narrow exception:
  both imported and newly generated mnemonic material are handled transiently in software for the explicit
  provisioning flow. Neither path persists plaintext backup material after confirmation.
- Address, derivation path, software-retained account xpub/chain-code metadata, and signatures match independent
  reference vectors.
- Device signatures are byte-compatible with the local EVM assembly rules, including low-s and recovery id.
- Each operation requires one explicit tap/session plus one device-PIN authorization; no authorization leaks
  into the next operation.
- Session teardown is verified for success, rejection, SDK error, timeout, NFC loss, and user cancellation.
- Own-send, WalletConnect transaction/message/typed-data, and AirGap transaction pass on a physical Android
  device; the equivalent iOS matrix passes before iOS support is declared complete.
- Fakes/unit tests remain green, and a maintained manual device matrix covers secure storage, live RPC, Reown
  relay, camera QR, NFC, and platform lifecycle boundaries (`docs/device-test-matrix.md`).

### Non-goals
- Reimplementing vendor NFC/APDU framing in Dart.
- Offering backup-less/non-extractable wallet generation before a separate recovery policy is designed.
- Claiming guaranteed memory zeroization for Dart `String` values. The phone-vault implementation releases
  references and relocks after each operation, but the Dart runtime cannot guarantee immediate zeroization.
- Additional chains, accounts, or hardware vendors before the Rutoken milestone passes its exit criteria.

## Phase 11 — Authenticate per operation, not on app open
Goal: keep viewing the wallet independent from custody authentication: opening the app shows the read-only
dashboard, while every private-key operation gets fresh authorization.

Owner decisions (2026-06-16):
- **Open → read-only dashboard, no auth.** Address + balances + history render from `getWalletSummary()` (public address, stored in plaintext) + the blockchain snapshot — no key derivation, no card.
- **Each private-key operation authenticates EVERY time** (no 5-min session reuse): PIN or biometric for
  `PhoneSecureVault`; "tap + device PIN" for `ExternalDeviceDemoBackend`. The backend is unlocked transiently
  for the operation, references are released, and `lock()` runs immediately afterward. This reduces exposure
  but does not guarantee zeroization of immutable Dart strings.
- The three key ops: send a transaction, approve an inbound WalletConnect request, sign an offline AirGap request. Reject/clear stay auth-free.

Status: ✅ done + **device-validated on iOS sim** (v1.32–v1.33): the per-op PIN prompt works well; a silent-approve gap (the controller swallowed non-`VaultFailure`/WC/AirGap errors) was fixed in v1.33 (`_runGuarded` catch-all).

### Chunks
- **11.1** — state machine: `loadInitialState` (and the post-onboarding end states) land on the read-only dashboard (the `unlocked` stage, repurposed) instead of `locked`; the dashboard renders from `summary` with no held material. The `locked` stage + `_LockedStage` + `unlockWallet`/`lockWallet` are **kept** (unused by default) for the deferred lock-on-open toggle below.
- **11.2** — per-op auth core: `_withFreshlyUnlockedMaterial({pin, useBiometrics})` (unlock → op → `lock()` in a `finally`) + an `_OperationAuthSheet` (PIN + optional biometric) shown by the widget before each key op.
- **11.3** — rewire the three signing paths (send / WC-approve / AirGap-sign) to authenticate-on-demand; drop the held-`material` assumptions; update tests.

### Deferred / future (recorded per owner request)
- **Optional "lock app on open" toggle** — a privacy setting that re-introduces an app-open gate (PIN/biometric to even view), reusing the retained `locked` stage. Off by default. Not built now.
- **External-device session-management UX** — post-Phase-11 the demo device is locked at rest (no PKCS#11 session), so the dashboard's "ping session" / "read address via PKCS#11" buttons surface a "No active device session" banner until a signing op briefly opens one. Demo-path nicety: either hide those controls until a session exists, or have them open a session on demand. (Phase 10 will revisit the real device lifecycle anyway.)

## Phase 12 — AirGap over EIP-4527 / Keystone BC-UR (MetaMask-compatible signer)
Goal: make the AirGap path interoperate with **real online wallets** (MetaMask, OneKey, …) instead of the bespoke `airgap-tx:`/`airgap-sig:` format. The app is **always the offline signer** ("QR-based hardware wallet"): the online wallet is watch-only / has internet, builds the unsigned tx and shows a QR; the app scans it, signs offline (phone vault or external NFC device), and shows a signature QR back; the online wallet broadcasts. No app↔wallet link except QR. Owner decision (2026-06-16): MetaMask-compatible; **no app↔app interop**; signer role only.

Protocol: **ERC/EIP-4527** over **BC-UR** (CBOR + bytewords + multipart fountain QR) — the Keystone standard MetaMask adopted. New deps `cbor` + `bc_ur` (both pure Dart). The old custom-format AirGap (chunk 9.5) is **superseded** and gets removed/rewired by this phase.

CDDL keys (from EIP-4527): `eth-sign-request` map = {1: request-id (UUID, CBOR tag 37), 2: sign-data (bytes), 3: data-type (1 legacy-RLP / 2 EIP-712 / 3 raw-bytes=personal_sign/EIP-191 / 4 EIP-2718 typed-tx incl. EIP-1559), 4: chain-id (int, default 1), 5: derivation-path (crypto-keypath, tag 304), 6: address (20 bytes, opt), 7: origin (text, opt)}. `eth-signature` = {1: request-id, 2: signature (65-byte r‖s‖v), 3: origin?}. `crypto-keypath` (tag 304) = {1: components [index,bool,…], 2: source-fingerprint uint32, 3: depth}. `crypto-hdkey` (UR type; CBOR tag 303 only when nested) for a derived **public** key = {3: key-data (33-byte compressed pubkey), 4: chain-code (32), 5: use-info `#6.305(coininfo {1: type=60 ETH, 2: network=0 mainnet})`, 6: origin (crypto-keypath), 8: parent-fingerprint uint32, 9: name (opt), 10: note (opt)}; is-master(1) / is-private(2) / children(7) are omitted for a public account export.

Two interactions (app = signer):
1. **Pairing**: app shows a **bare `crypto-hdkey`** UR QR (account-level xpub: pubkey + chain code + origin path + master fingerprint) → online wallet adds the account watch-only and derives addresses `M/0/i` (index 0 = the app's own address). Single-account "BIP44 Standard" form; the multi-key `crypto-account` container (Bitcoin / Ledger-Live) is not used.
2. **Signing**: online wallet shows an `eth-sign-request` UR → app decodes, signs by data-type, returns an `eth-signature` UR.

### Chunks
- **12.1 — DONE** — deps probe + pure-Dart `Eip4527Codec`: encode/decode `eth-sign-request` / `eth-signature` (+ `crypto-keypath`) over `cbor`+`bc_ur`, **validated against Keystone test vectors** (recorded in the worklog). CI-only, no device.
- **12.2 — DONE** — sign path: `Eip4527InboundCoordinator` (`lib/src/airgap/eip4527_inbound.dart`) decodes an `eth-sign-request` → branches on data-type → signs via the active backend's `WalletTransactionSigner` → `eth-signature` UR. `signPersonalMessage` for raw-bytes (3), `signDigest` over the `Eip712Encoder` digest for EIP-712 (2), and `signDigest` over `keccak256(signData)` for tx types (1 legacy / 4 typed) — **not** `signPreparedTransfer` (we only have the serialized unsigned tx). The returned **`v` differs by data-type**: personal/EIP-712 keep `recId+27`; typedTransaction → `recId` (EIP-1559 y-parity); legacy → `recId+chainId*2+35` (EIP-155) — per MetaMask's keystone-airgapped-keyring source (see worklog 2026-06-17 for sources). Rejects a request whose pinned `address` ≠ this wallet. Tests recover each sig back to the wallet address. **Legacy (type-1) EIP-155 v flagged for on-device MetaMask verification.** No version bump (not yet wired to UI).
- **12.3 — DONE** — account export (pairing): `Eip4527Codec.encodeHdKey`/`decodeHdKey` + `CryptoHDKey`/`CoinInfo` models, and `AccountExportDeriver` (`lib/src/airgap/account_export.dart`) deriving a **bare `crypto-hdkey`** from a mnemonic at `m/44'/60'/0'` (pubkey + chain code + ETH use-info + origin path w/ master fingerprint + parent fingerprint) via bip32/bip39. The vault already exposes the mnemonic (`WalletMaterial`), so no vault change was needed. Tests: byte-exact fields for the Hardhat seed, a UR regression-pin, encode/decode round-trip, wrong-type rejection, and the decisive correctness check — reconstruct the watch-only node from only the exported pubkey+chaincode, derive `M/0/0`, and confirm it reproduces the `0xf39Fd6…2266` leaf. CI-only, no UI yet, no version bump. **Dogfood lever** if MetaMask rejects the bare hdkey: wrap in `crypto-account` and/or add `note:"account.standard"` (codec already supports both).
- **12.4 — DONE (v1.38)** — static/animated multipart BC-UR QR output, camera sequence assembly with progress, authenticated `crypto-hdkey` account export, transaction request scan/file load, strict Mainnet/Sepolia address/path/chain validation, decoded RLP preview (recipient/value/nonce/gas/max fee/calldata), per-operation sign, and `eth-signature` response QR. Initial UI is deliberately transaction-only: EIP-1559 on both chains and legacy EIP-155 on Mainnet; message/typed-data AirGap UI remains out of scope.
- **12.5 — DONE (v1.38)** — removed the superseded `AirGapPayloadCodec` / `AirGapInboundCoordinator`, paste UI, and their tests; synchronized architecture/docs/version.

### Validation
- Codec + sign path: Keystone/EIP-4527 test vectors in CI (no device).
- End-to-end: owner dogfoods with **MetaMask** (add the app as a QR-based hardware wallet → sign a Mainnet/Sepolia ETH transaction → broadcast).

## Suggested release sequence
- `v0.3` — architecture skeleton + secure vault foundation
- `v0.4` — onboarding/auth shell + create/import UI + one-time seed display flow
- `v0.5` — Ethereum Mainnet + Sepolia read-only balances
- `v0.6` — tokens + history + local cache
- `v0.7` — send form + gas estimation + preview
- `v0.8` — signing foundation + raw transaction submission abstraction
- `v0.9` — visible send flow states + nonce lookup + end-to-end submit wiring
- `v1.0` — complete biometric unlock
- `v1.1` — first transaction tracking and advanced error hardening pass
- `v1.2` — initial Phase 6 completion attempt
- `v1.3` — real replacement flow, gas bump, and non-blocking lifecycle UX
- `v1.4` — backend selection model + backend-compatible signing/auth contracts for future external signer flow
- `v1.5` — simulated external-device runtime path and separate UX branch for Phase 7
- `v1.6` — mock device lifecycle: online/offline, reconnect, session disconnect, and error-state handling
- `v1.7` — mock PKCS#11 session/operation contracts and logical completion of Phase 7 foundation
- `v1.8` — phone-vault security hardening: DEK-based at-rest scheme, PIN never persisted, biometric secret moved to a dedicated gated store
- `v1.9` — PBKDF2 raised to 600k with failed-unlock lockout; transaction-layer cleanup (shared signer base, removed misleading defaults, `LocalTransactionService` rename), base-fee headroom; added send-failure and nonce-reconciliation tests
- `v1.10` — at-rest vault payload schema validation + defensive parsing (resilient startup); `wallet_flow_screen.dart` split into part files; cross-agent docs (`AGENTS.md`, `docs/worklog.md`) and the document-first working agreement
- `v1.11`–`v1.16` — Phase 8 (chunks A–F): an **outbound** WC v2 + AirGap remote-signing model (async signing seam, a remote-signing session/transport, WC/AirGap demo connectors, a "Подписать через" send option) plus the codecs `WalletConnectV2RequestCodec` / `AirGapPayloadCodec` and `assembleSignedTransfer`. The outbound direction was the wrong role and was removed in v1.17; only the codecs + `assembleSignedTransfer` were kept
- `v1.17` — Phase 9 chunk 9.0 (role correction): removed the inverted Phase 8 **outbound** remote-signing code (transport/session/registry/connectors + "Подписать через"); kept the reusable codecs (`WalletConnectV2RequestCodec`, `AirGapPayloadCodec`) and `assembleSignedTransfer`
- `v1.18` — Phase 9 chunk 9.1: wallet-side `WalletConnectService` inbound seam — interface + models + `FakeWalletConnectService` + `UnavailableWalletConnectService` default + unit tests (pure Dart; real SDK + DI deferred to 9.2)
- `v1.19` — refactor (acts on `docs/repo-review.md` #1): extracted a widget-free `WalletFlowController` (`ChangeNotifier`) out of `WalletFlowScreen` — the state machine + all domain actions; the screen is now a thin listener. No behavior change; adds `wallet_flow_controller_test.dart`
- `v1.20` — Phase 9 chunk 9.4 (Connections screen, on the fake): 9.4a wired the `WalletConnectService` seam through `MobileWalletDemoApp` → `WalletFlowScreen` → `WalletFlowController` (proposal/session streams + pair/approve/reject/disconnect actions); 9.4b added the `WalletFlowStage.connections` screen (status chips, `wc:` URI pairing, session-proposal approval card, active sessions + disconnect) and the dashboard entry, plus controller + widget tests. Still on `FakeWalletConnectService` (real `reown_walletkit` is 9.2)
- `v1.21` — Phase 9 chunk 9.4c: incoming-request approval sheet. The controller subscribes to `WalletConnectService.requests` (→ `pendingRequest`) and gains `approvePendingRequest` (builds the active backend's signer → `WalletConnectInboundCoordinator` → sign + broadcast/respond) / `rejectPendingRequest` (`respondError`); the Connections screen renders a request card (method/chain/to/value). Controller + widget tests on the fake
- `v1.22` — Phase 9 chunk 9.5: AirGap inbound. `AirGapInboundCoordinator` (decode `airgap-tx:` → `prepareInboundTransaction` → sign → `encodeResponse` `airgap-sig:`; offline — no nonce lookup/broadcast) + controller `signAirGapRequest`/`clearAirGapResponse` + a Connections-screen AirGap section (paste-based). Coordinator + controller + widget tests. Camera QR scan deferred to 9.6
- `v1.23` — Phase 9 chunk 9.6: the `QrScanner` seam (`qr/qr_scanner.dart`: interface + `UnavailableQrScanner` default + `FakeQrScanner`) injected through `MobileWalletDemoApp` → `WalletFlowController`; gated scan entry points on the Connections screen that fill the `wc:`/`airgap-tx:` paste fields; request-card sender line. Scanner + controller + widget tests
- `v1.24` — Phase 9 chunk 9.6 (real QR file load, all platforms): the seam grows two sources (`isCameraScanAvailable`/`scanWithCamera` vs `isFileLoadAvailable`/`loadFromFile`); `FileQrScanner` (`qr/file_qr_scanner.dart`) is the production default — picks an image via `file_selector` and decodes the QR purely in Dart (`image` + `zxing2` → `ZxingQrImageDecoder`), so it works on **every** platform incl. Windows (the only option there). Live camera stays deferred. "Загрузить из файла" buttons on the Connections screen; decode test against a committed PNG fixture + controller/widget tests
- `v1.25` — Phase 9 chunk 9.7 (message signing): `personal_sign` / `eth_sign` (EIP-191) end-to-end on the fake. `WalletConnectV2RequestCodec` gains `isMessageSignMethod` + `decodeMessageRequest` (handles the `[message,address]` vs `[address,message]` order, hex/utf8 message); `TransactionService.signPersonalMessage` + `WalletTransactionSigner.signPersonalMessage` (web3dart `signPersonalMessageToUint8List`); `WalletConnectInboundCoordinator` gains a message branch; the request card renders the decoded message. Codec + coordinator + controller tests
- `v1.26` — Phase 9 chunk 9.8 (EIP-712 typed-data signing): `eth_signTypedData_v4`/`_v3`. New pure-Dart `walletconnect/eip712.dart` (`Eip712Encoder.encode` → the 32-byte `keccak256(0x1901‖domainSep‖hashStruct)` digest; nested structs + arrays); `TransactionService.signDigest` (raw secp256k1 over a digest via web3dart `sign`, low-s) + `WalletTransactionSigner.signDigest`; codec `isTypedDataMethod`/`decodeTypedDataRequest`; a `WalletConnectInboundCoordinator` typed-data branch; the request card shows a `primaryType @ domain` summary. Validated against the canonical EIP-712 "Mail" vector (digest `0xbe609aee…` + signature, generated with reference `eth-account`)
- `v1.27` — Phase 9 chunk 9.2 (real `reown_walletkit`): toolchain blockers resolved, service integrated and
  DI-selected on configured mobile builds; later Android dogfood through v1.36 validated the real relay and a
  Sepolia transaction broadcast. Fakes and coordinator tests cover deterministic logic; live relay remains a
  manual/device boundary
- `v1.28` — Phase 9 chunk 9.9 (live camera QR scan): 9.9a probe (dep-only `mobile_scanner: ^7.2.0`) → CI green on all 4 platforms (iOS pure-Swift Vision, deployment target 12.0; Android standard-Maven MLKit, no flavor dimension; Windows excluded). 9.9b `qr/camera_qr_scanner.dart` (`CameraQrScanner`: full-screen `MobileScanner` QR-only/`noDuplicates` → first `rawValue`; `loadFromFile` delegates to a composed `FileQrScanner`; pushed via a global `navigatorKey` on `MaterialApp`), DI-selected on Android/iOS (file-only elsewhere), iOS `NSCameraUsageDescription`. Unit test: availability + file delegation + no-navigator error path
- `v1.29` — Phase 9 chunk 9.9c (camera polish): a centred-square scan window (`ScanWindowOverlay` dims the surround + draws a rounded border; detection limited to the window via `MobileScanner.scanWindow`) and an AppBar torch toggle (`controller.toggleTorch()` via a `ValueListenableBuilder` on the controller's `TorchState`, hidden when unavailable). Records the 9.2 owner dogfood (connect/disconnect + `personal_sign` validated on device; tx pending test funds) and reconciles the plan/CLAUDE.md/worklog to Phase 9 = feature-complete
- `v1.38` — Phase 12 completion: MetaMask-compatible EIP-4527/BC-UR AirGap account export, animated multipart QR scanning, Mainnet/Sepolia transaction preview and signing, signature QR, and removal of the custom `airgap-tx:` implementation
- `v1.39` — Android camera QR hardening after AirGap dogfood: analyze the full frame instead of a 70% crop, request a 1920×1080 stream, enable ML Kit auto-zoom, enlarge the overlay-only aim guide, and regression-test the scanner configuration
- `v1.40` — Phase 10.1–10.2 library-independent Rutoken foundation: non-exporting custody/native-adapter
  contracts, public account-xpub export, raw `r‖s` validation/low-s/recovery, and byte-identical legacy,
  EIP-1559, personal/digest, and AirGap signing on a fake native adapter

## Current non-goals and validation limits
- no hardware-device SDK implementation yet
- no additional chains beyond Ethereum Mainnet and Sepolia in the initial AirGap UI
- no multi-chain support beyond Ethereum Mainnet and Sepolia yet
- **single-account by design** (audit decision): one EVM address derived at `m/44'/60'/0'/0/0`; HD-account discovery / multiple accounts are out of scope — Phase 9 WalletConnect sessions expose this one account (`eip155:*:<address>`)
- **localization**: UI strings are intentionally inlined Russian and asserted by widget tests; no ARB/`intl` extraction is planned for the demo
- **test fidelity**: deterministic tests use in-memory fakes; secure storage, public RPC, Reown relay, camera,
  and future NFC behavior cross native/device boundaries and require the maintained manual device matrix in
  addition to CI. WalletConnect and AirGap have owner dogfood evidence, but are not fully automated end-to-end
