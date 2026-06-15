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
- ✅ Phase 8 — only the WC v2 + AirGap **codec/payload mappings** (`WalletConnectV2RequestCodec`, `AirGapPayloadCodec`) and the vault `TransactionService.assembleSignedTransfer` seam survive. The **outbound** direction it originally shipped (this app *requesting* a signature from an external signer) was the **wrong role** and was removed in chunk 9.0 — see the Phase 8 / Phase 9 sections below
- ⏳ Phase 9 (real **wallet-side** inbound signing — WalletConnect v2 + AirGap — plus a connections screen and an incoming-request approval flow) is **in progress, on the fake service** (9.0–9.1 v1.18, 9.3 request→sign coordinator, 9.4 Connections screen v1.20; real `reown_walletkit` 9.2 deferred) — see the "Phase 9" section below
- ⏳ Phase 10 (custody/NFC refinement — tap-to-confirm + device PIN as a real second factor, composed with own-sends and inbound requests) is **planned** — see the "Phase 10" section below

> **Current stopping point — v1.26.0+37.** Phases 0–7 are complete, plus security/maintenance passes v1.8–v1.10 and a UI-orchestrator refactor (v1.19: a widget-free `WalletFlowController`). Phase 8's reusable **codecs** (`WalletConnectV2RequestCodec`, `AirGapPayloadCodec`) and the vault `assembleSignedTransfer` seam are kept; its earlier outbound direction (the app *requesting* a signature from an external signer) was the wrong role and was removed in chunk 9.0 (v1.17). **Phase 9 (wallet-side inbound signing) is in progress, on the fake service** — done: 9.0–9.1 (v1.18: the `WalletConnectService` seam + fake + unavailable default), 9.3 (inbound request decode → `prepareInboundTransaction` → `WalletConnectInboundCoordinator` sign/respond), 9.4 (Connections screen: 9.4a DI/controller WC seam + 9.4b the screen + 9.4c the incoming-request approval sheet wired to `WalletConnectInboundCoordinator`, v1.20–v1.21), 9.5 (AirGap inbound: `AirGapInboundCoordinator` decode→sign→`airgap-sig` response + a Connections-screen section, v1.22), and 9.6 (the `QrScanner` seam + gated entry points + request-sheet polish, v1.23; then v1.24 added **real all-platform QR load from an image file** via `file_selector` + `image` + `zxing2` — the only option on Windows). 9.7 added **message signing** — `personal_sign` / `eth_sign` (EIP-191) end-to-end (codec decode + `signPersonalMessage` on the signer/`TransactionService` + a coordinator branch + the request card), v1.25; and 9.8 added **EIP-712 typed-data signing** — `eth_signTypedData_v4`/`_v3` via a pure-Dart `Eip712Encoder` (validated against the canonical EIP-712 "Mail" vector) + `TransactionService.signDigest` + a coordinator branch, v1.26. **Wallet-side inbound signing is now feature-complete on the fake** (tx + message + typed-data, over WalletConnect + AirGap, with file-QR input). The live **camera** scanner (`mobile_scanner`, no Windows support) and 9.2 (real `reown_walletkit`) remain deferred behind native-platform blockers. **Phase 10** is the custody/NFC second factor. Full plan in the Phase 9 / Phase 10 sections; per-chunk log in `docs/worklog.md`.

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

### Future hardware path (not implemented now)
- Leave an abstraction for a future NFC hardware device SDK
- User will later choose one storage backend:
  - phone secure vault;
  - external hardware device
- Both backends should expose the same logical capabilities:
  - create key/seed
  - import seed
  - derive address
  - sign transaction
  - unlock/auth session
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

### Future protocol extensions (not implemented now)
- WalletConnect v2
- AirGap protocol

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
- Modules under `lib/src/`: `auth/`, `blockchain/`, `key_storage/`, `transactions/` plus a single UI orchestrator `wallet_flow_screen.dart`. There is **no** separate `wallet_core/` or `ui/` module — domain orchestration currently lives inside the UI widget.
- `KeyStorageBackend`, `BlockchainProvider`, and `TransactionService` exist as designed. `AuthGate` / `WalletRepository` / `TokenBalanceService` / `HistoryService` were **not** created as separate interfaces: auth is split across `BiometricAuthGateway` + `WalletOperationAuthorizer`, and token/history reads are folded into `BlockchainProvider.loadSnapshot` (`WalletChainSnapshot`).
- Treat `CLAUDE.md` as the accurate map of the current code; this section is the original aspiration, not the present layout.

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
- `WalletConnectV2RequestCodec` (`walletconnect/wallet_connect_v2.dart`) and `AirGapPayloadCodec` (`airgap/airgap_signing.dart`) — the wire/field mappings (pure serialization, no relay/SDK). Phase 9 adds the inverse direction (decode an incoming `eth_signTransaction` / `eth_sendTransaction` request; encode the signed response).
- `TransactionService.assembleSignedTransfer` — build a `SignedTransfer` from raw signed bytes without duplicating crypto.
- The external-device demo (`key_storage/external_device_demo_backend.dart` + `external_device_pkcs11.dart`) is the **custody** precedent for Phase 10 (where the key lives + tap/PIN confirmation) — distinct from this transport axis; it is *not* a signing transport.

## Phase 9 — Wallet-side inbound signing (WalletConnect v2 + AirGap) + connections screen
Goal: make this app a **real wallet** that *receives* signing requests. Two transports bring requests in:
- **WalletConnect v2** (online): external dApps pair with the wallet over the relay, send `eth_sendTransaction` / `eth_signTransaction` / `personal_sign` / `eth_signTypedData_v4`, and the wallet approves and signs with the on-device vault.
- **AirGap** (offline): the wallet scans a request QR from an air-gapped companion (or acts as the offline signer), signs, and returns a response QR.

Both surface through a dedicated **Connections screen** (status, active sessions, inspect/disconnect, new connection) and a shared **incoming-request approval sheet** (request details → Approve/Reject → vault sign → respond).

This corrects the Phase 8 role: Phase 8 modelled the *outbound* direction (the app requesting a signature from an external signer). The product is wallet-side, so **9.0** removes that and **9.1+** build the inbound integration, reusing the Phase 8 codecs.

Status: ⏳ In progress (option A — build on the fake, defer the real SDK). 9.0–9.1 done (v1.18); 9.3 done on the fake; **9.4 done** (9.4a DI + controller WC seam; 9.4b Connections screen, v1.20; 9.4c incoming-request approval sheet → `WalletConnectInboundCoordinator`, v1.21), 9.5 (AirGap inbound: `AirGapInboundCoordinator` decode→sign→response payload + Connections-screen section, v1.22), and **9.6 done** (the `QrScanner` seam + sheet polish, v1.23; then real **all-platform QR load from an image file** — `FileQrScanner` via `file_selector` + `image` + `zxing2` — v1.24). **9.7 done** (message signing: `personal_sign` / `eth_sign`, EIP-191, v1.25); **9.8 done** (EIP-712 `eth_signTypedData_v4`/`_v3` via a pure-Dart `Eip712Encoder` + `signDigest`, v1.26). Inbound signing is feature-complete on the fake (tx + message + typed-data). The live camera scanner (`mobile_scanner`, no Windows support) and 9.2 (real `reown_walletkit`) are deferred behind native-platform blockers.

### Two axes (do not conflate)
- **Transport axis (this phase):** how a signing request *arrives* — WalletConnect (online relay) or AirGap (offline QR). The wallet still signs with whatever custody backend is active.
- **Custody axis (Phase 10):** *where the key lives and how the user confirms* — phone vault (PIN/biometric) or external NFC device (tap + device PIN). Inbound requests compose with either custody backend.

### Dependencies & prerequisites
- WalletConnect: `reown_walletkit` (official Reown/WalletConnect Flutter wallet SDK; formerly `walletconnect_flutter_v2`). Pin a version; `flutter pub get`.
- A WalletConnect Cloud **project ID** via `--dart-define=WC_PROJECT_ID=…` (never committed); show a clear "not configured" state when absent.
- Relay (`wss://relay.walletconnect.org`) reachable — depends on the environment network policy; live pairing is manual/dogfood, automated tests use the fake service.
- QR input: **file load is implemented on all platforms** (`file_selector` + `image` + `zxing2`, pure-Dart decode — works on Windows). A live **camera** scanner (`mobile_scanner`) is deferred (no Windows support).
- Navigation: the app is one `WalletFlowScreen` state machine with no routes; this phase introduces a route (or a new stage) for the Connections screen.

### Architecture
- `WalletConnectService` — an abstract interface injected through `MobileWalletDemoApp` like every other dependency (real impl default; `FakeWalletConnectService` for tests/DI). Surface: `init`, `pair(uri)`, `approveSession`/`rejectSession(proposal)`, `disconnect(topic)`, `activeSessions` + a sessions `Stream`, an incoming-requests `Stream`, and `respond(requestId, result|error)`.
- Inbound request models: a session proposal, active-session info (dApp name/url/icon, chains, accounts, connected-at), and an incoming `SigningRequest` (method + params + originating session).
- Request → signing: parse `eth_sendTransaction` / `eth_signTransaction` params (the **inverse** of `WalletConnectV2RequestCodec`), sign via the active custody backend through the existing `WalletOperationAuthorizer` / `TransactionService` / `assembleSignedTransfer`, unlock via the existing `PinUnlockSession` (reuse the 5-min TTL so the user isn't prompted per request). Broadcast `eth_sendTransaction` via the existing broadcaster. (`personal_sign` / typed-data are message-signing additions.)
- AirGap inbound: scan a request QR → decode via `AirGapPayloadCodec` → same approval sheet → sign → encode the response QR.
- Connections screen: a status banner; a list of active sessions (dApp name/url/icon, chains, accounts, connected-at); tap → details; disconnect; "New connection" (paste/scan a `wc:` URI). Navigation entry from the unlocked dashboard.

### Chunk breakdown (each chunk: plan → code → record, per AGENTS.md)
- **9.0** — *cleanup*: remove the inverted Phase 8 **outbound** code (transport/session/registry/connectors + "Подписать через"); keep the codecs (`WalletConnectV2RequestCodec`, `AirGapPayloadCodec`) and `assembleSignedTransfer`. No new feature; tests trimmed to the codecs. ✅ done (v1.17)
- **9.1** — `WalletConnectService` interface + inbound models (`WalletConnectPeer` / `…SessionProposal` / `…Session` / `…Request`) + `FakeWalletConnectService` + `UnavailableWalletConnectService` (shippable default) + unit tests. Pure Dart, no SDK. ✅ done (v1.18). *(The `reown_walletkit` dep + `WC_PROJECT_ID` config + DI wiring moved to 9.2, where the real impl consumes them.)*
- **9.2** — real SDK impl (`ReownWalletConnectService`) behind the interface: init, pair, proposal approve/reject, session list + streams, disconnect. Adds the `reown_walletkit` dep + `WC_PROJECT_ID` config + DI wiring into `MobileWalletDemoApp` (init on startup).
- **9.3** — incoming request → vault signing: WC method parsing (inverse codec), the request→sign→respond flow, broadcast for `eth_sendTransaction`. ✅ done on the fake (`WalletConnectV2RequestCodec.decodeTransactionRequest`, `TransactionService.prepareInboundTransaction`, `WalletConnectInboundCoordinator`); the user-facing approval sheet is folded into 9.4b.
- **9.4a** — DI + controller seam: inject `WalletConnectService` through `MobileWalletDemoApp` → `WalletFlowScreen` → `WalletFlowController` (default `UnavailableWalletConnectService`); the controller subscribes to the proposal/session streams and exposes `isWalletConnectAvailable` / `walletConnectSessions` / `pendingProposal` + actions `pairWalletConnect` / `approvePendingProposal` / `rejectPendingProposal` / `disconnectWalletConnectSession`; controller tests on the fake. ✅ done (no UI yet).
- **9.4b** — Connections screen: `WalletFlowStage.connections` + the screen (status chips, "new connection" `wc:` URI field, the session-proposal approval card, the active-session list with disconnect) + a navigation entry ("Подключения (WalletConnect)") from the unlocked dashboard + widget tests (pair→approve→disconnect, back). ✅ done (v1.20). *The **incoming-request** approval sheet (driving `WalletConnectInboundCoordinator` from the controller on `requests`) is a follow-up — see 9.4c.*
- **9.4c** — incoming-request approval sheet: the controller subscribes to `WalletConnectService.requests` (→ `pendingRequest`), the Connections screen shows a request card (method/chain/to/value → approve/reject), and on approval drives `WalletConnectInboundCoordinator` (signs via the active backend's `WalletTransactionSigner` → broadcast/respond); reject → `respondError`. ✅ done (v1.21). *Signing reuses the in-memory unlocked material (no per-request PIN prompt). `personal_sign`/typed-data and AirGap inbound are still later chunks.*
- **9.5** — AirGap inbound: decode an `airgap-tx:` request → sign with the active backend → encode the `airgap-sig:` response. ✅ done (v1.22): `AirGapInboundCoordinator` (decode → `prepareInboundTransaction` → sign → `encodeResponse`; offline, so no nonce lookup/broadcast) + a Connections-screen "AirGap" section (paste request → «Подписать офлайн» → response payload to copy/show back) + coordinator/controller/widget tests. *Camera scan (`mobile_scanner`) of the request/response QR is deferred to the QR chunk (9.6); this is paste-based.*
- **9.7** — message signing: `personal_sign` / `eth_sign` (EIP-191). ✅ done (v1.25): codec `isMessageSignMethod`/`decodeMessageRequest`, `signPersonalMessage` on `TransactionService` + the signer (web3dart), a `WalletConnectInboundCoordinator` message branch (verify account → sign → respond with the 65-byte signature), and the request card shows the decoded message.
- **9.8** — EIP-712 typed-data signing: `eth_signTypedData_v4` / `_v3`. ✅ done (v1.26): pure-Dart `walletconnect/eip712.dart` (`Eip712Encoder` — domain/struct hashing with nested structs + arrays → the 32-byte digest), `TransactionService.signDigest` + `WalletTransactionSigner.signDigest` (raw secp256k1 via web3dart `sign`, low-s), codec `isTypedDataMethod`/`decodeTypedDataRequest`, a coordinator typed-data branch, and a `primaryType @ domain` summary in the request card. Validated against the canonical EIP-712 "Mail" vector (digest + signature generated with reference `eth-account`).
- **9.6** — QR for WalletConnect pairing + AirGap + incoming-request sheet polish. ✅ done. v1.23: the `QrScanner` seam (`qr/qr_scanner.dart` — interface + `UnavailableQrScanner` + `FakeQrScanner`) injected through `MobileWalletDemoApp` → controller; request-card polish (sender line). v1.24: the seam grows two sources (camera vs file load) and `FileQrScanner` (`qr/file_qr_scanner.dart`) becomes the production default — **real QR load from an image file on every platform** (`file_selector` picker + pure-Dart `image`+`zxing2` decode via `ZxingQrImageDecoder`), the only option on Windows; "Загрузить … из файла" buttons fill the `wc:`/`airgap-tx:` fields. Decode test against a committed PNG fixture + controller/widget tests. *The live **camera** impl (`mobile_scanner`) stays deferred — no Windows support + per-platform camera permissions; it lands with the native-platform work. File load + paste are the cross-platform paths.*
- **9.7** — tests (service via the fake, request→sign mapping, screen widget tests) + docs sync + version bumps.

### Deliverables
- [x] 9.0 cleanup (remove outbound, keep codecs)
- [x] `WalletConnectService` abstraction + `FakeWalletConnectService` (+ `UnavailableWalletConnectService` default; real-impl DI deferred to 9.2)
- [ ] real `reown_walletkit` implementation (init / pair / sessions / disconnect)
- [x] incoming-request → vault signing + `respond` (logic on the fake: `WalletConnectInboundCoordinator`; approval-sheet UI wired in 9.4c, v1.21)
- [x] Connections screen (9.4a DI + controller WC seam; 9.4b screen: status / new connection / proposal approval / sessions + disconnect / dashboard entry)
- [x] AirGap inbound (decode `airgap-tx:` → sign → `airgap-sig:` response, paste-based; `AirGapInboundCoordinator` + Connections-screen section, v1.22; camera scan deferred to 9.6)
- [x] QR-code pairing for WalletConnect (`QrScanner` seam v1.23; real all-platform **file load** v1.24 via `FileQrScanner`/`file_selector`/`image`/`zxing2`; live camera `mobile_scanner` deferred)
- [ ] tests + docs

### Risks / open questions
- Relay reachability under the environment network policy; WalletConnect Cloud project-ID provisioning and secret handling.
- Introducing navigation into the single-screen app.
- Per-request auth/unlock UX (reuse the 5-minute `PinUnlockSession` TTL so the user is not prompted per request).
- Chain scoping: WC sessions declare chains (`eip155:1` / `eip155:11155111`) — keep aligned with `blockchain/network_config.dart`.
- `reown_walletkit` API churn — pin the version.
- Camera permissions for QR scanning (WC pairing + AirGap) on each platform.

### Non-goals (this phase)
- non-EVM chains; a full dApp browser; push notifications for background requests; bespoke session persistence beyond what the SDK provides; custody/NFC changes (those are Phase 10).

## Phase 10 — Custody / NFC refinement
Goal: turn the simulated external-NFC device (Phase 7) into a real **custody** second factor and compose it with both own-sends and the Phase 9 inbound requests. The "tap + device PIN" becomes a genuine confirmation step, not a mock.

Status: ⏳ Planned (after Phase 9).

> **Reference:** `docs/nfc-pkcs11-integration-notes.md` is the deep dive for this phase — built from the **official Aktiv-Soft / Rutoken demo wallets** (iOS Swift + Android Kotlin, incl. the vendor `wtpkcs11ecp` C headers), the vendor mechanism spec PDF, and the `mescheryakov1/wallet-tool` CLI. It has the confirmed constants/mechanisms/templates, an **exact NFC/PC-SC reproduction spec** (the app never calls CoreNFC/`NfcAdapter` directly — only the `RtPcsc*` bridge + PKCS#11; iOS entitlement + ISO7816 AIDs; Android `RtPcscBridge` init + jniLibs; the one-tap operation lifecycle), the **Ethereum-specific corrections** (secp256k1 not P-256; keccak256 not `CKM_SHA256`; build v/recovery-id + low-s yourself), per-platform native-stack details (FFI/channel cost), how it maps onto our existing seams, and the open questions to resolve against a real token. Read it before starting any chunk below.

### Scope
- Real (or realistically-simulated) NFC tap as the device-session trigger, with the device PIN as a true second factor distinct from the phone PIN.
- The device signing path actually routes the prepared transaction to the device (vs the Phase 7/8 demo that signs from locally-held material after exercising a mock PKCS#11 op).
- Compose custody with the transport axis: an inbound WalletConnect/AirGap request can be approved and confirmed on the external device just like an own-send.
- One PIN source per backend (phone PIN for the vault, device PIN for the device), per the product security model.

### Non-goals
- The **transport** is still TBD — FFI to the `wtpkcs11ecp` native library vs. an NFC APDU bridge to the token's PKCS#11 applet (decided in chunk 10.0). Until that lands and a real token is validated, this stays a high-fidelity simulation behind the existing `ExternalDeviceKeyStorageBackend` contract. (The *vendor model* is no longer TBD — the BIP32/BIP39 PKCS#11 extension in `docs/nfc-pkcs11-integration-notes.md` is the target.)

### Chunk breakdown
Small, reviewable steps that keep `main` green (full detail + recipes in `docs/nfc-pkcs11-integration-notes.md` §8):
- **10.0** — decide the transport (FFI vs NFC APDU); record the decision here.
- **10.1** — pure-Dart crypto utilities (keccak256 RLP digest, low-s/EIP-2, recovery-id, secp256k1 OID) with known-vector tests. No device.
- **10.2** — `Pkcs11TransactionSigner` on a *fake* PKCS#11 adapter; assert byte-identical output to the local signer for the same inputs.
- **10.3** — real adapter behind `ExternalDevicePkcs11Adapter` (`C_Initialize`/slot discovery/`C_OpenSession`/`C_Login(USER, devicePin)`), wired into `ExternalDeviceDemoBackend`'s lifecycle. Manual/dogfood validation (no CI token).
- **10.4** — keygen (`CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN`) / import (`C_CreateObject`) / address derivation, incl. one-time mnemonic display via `CKA_VENDOR_BIP39_MNEMONIC`.
- **10.5** — end-to-end device sign for own-sends **and** Phase 9 inbound WC requests (compose with `WalletConnectInboundCoordinator`); "tap + device PIN" becomes a real confirmation step.
- **10.6** — UX: real NFC presence/affordances in the external-device branch of `WalletFlowScreen` / `WalletFlowController` (replaces the simulated online/offline toggles).

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

## Non-goals for now
- no hardware-device SDK implementation yet
- no real WalletConnect v2 relay/SDK integration yet (only the codec + the inbound service seam)
- no real AirGap relay/QR integration yet (only the payload codec)
- no multi-chain support beyond Ethereum Mainnet and Sepolia yet
- **single-account by design** (audit decision): one EVM address derived at `m/44'/60'/0'/0/0`; HD-account discovery / multiple accounts are out of scope — Phase 9 WalletConnect sessions expose this one account (`eip155:*:<address>`)
- **localization**: UI strings are intentionally inlined Russian and asserted by widget tests; no ARB/`intl` extraction is planned for the demo
- **test fidelity**: tests run against in-memory fakes; there are no live RPC/relay/secure-storage integration tests — the real `reown_walletkit` path (chunk 9.2) will need manual/dogfood validation
