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
- ⏳ Phase 8 is not started yet

> **Current stopping point — v1.9.0+20.** Phases 0–7 are complete. On top of the already-complete phases, two hardening passes shipped: **v1.8** (phone-vault security rework — DEK-based at-rest encryption, the PIN is no longer persisted, biometric unlock moved to a dedicated gated secret store) and **v1.9** (PBKDF2 raised to 600k + failed-unlock lockout, transaction-layer cleanup, base-fee headroom, extra send-failure / nonce-reconciliation tests). The next net-new work is **Phase 8** (WalletConnect v2 + AirGap contracts, external signing/session state model).

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

## Phase 8 — future extension points
Goal: reserve clean extension paths.

Status: ⏳ Not started

Deliverables:
- [ ] protocol integration contracts for WalletConnect v2
- [ ] protocol integration contracts for AirGap
- [ ] state model prepared for external signing/session flows

Starting points for the next agent:
- The signing seam already exists: a WalletConnect/AirGap session-driven signer plugs in via `WalletTransactionSigner` / `WalletOperationAuthorizer` (`auth/wallet_operation_auth.dart`), alongside the local and external-device signers.
- The external-device demo (`key_storage/external_device_demo_backend.dart` + `external_device_pkcs11.dart`) is the closest precedent for a session/lifecycle state model to mirror for remote-signing flows.

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

## Non-goals for now
- no hardware-device SDK implementation yet
- no WalletConnect v2 implementation yet
- no AirGap implementation yet
- no multi-chain support beyond Ethereum Mainnet and Sepolia yet
