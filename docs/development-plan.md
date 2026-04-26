# Mobile Wallet Demo — Development Plan

This file is the canonical development plan for the project. Use it as the source of truth while implementing future tasks.

## Status snapshot

Current factual status of the project:
- ✅ CI foundation is in place and stable on Android, iOS Simulator, and Windows x64
- ✅ Phase 0 is effectively completed
- ✅ Phase 1 is implemented as a user-facing flow
- ◐ Phase 2 is partially implemented; PIN unlock flow is ready, real biometric integration is still pending
- ✅ Phase 3 is implemented
- ✅ Phase 4 is implemented
- ✅ Phase 5 is implemented
- ◐ Phase 6 is largely implemented end-to-end (prepare → nonce → sign → submit + UI submission states); deeper nonce/error hardening and tx lifecycle polling are still pending
- ⏳ Phases 7-8 are not started yet

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

Not implemented yet from the near-term plan:
- ✅ onboarding UI flow
- ✅ one-time seed phrase display screen
- ✅ biometric enable flow (shell state, platform integration later)
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

Status: ◐ Partially completed (foundation, create/import UX and seed display are ready; full production biometrics/integration layers still pending)

Deliverables:
- [x] BIP-39 seed generation
- [x] one-time seed phrase display flow
- [x] seed import flow
- [x] encrypted storage of seed
- [x] address derivation for EVM
- [ ] unlock flow protected by PIN / biometrics (PIN flow implemented; real biometric auth integration still pending)

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

Status: ◐ Partially completed (end-to-end send flow is now wired through preview → nonce → sign → submit with visible UI states; advanced nonce/error hardening and post-submit tracking are still pending)

Deliverables:
- [x] one auth prompt per operation (domain-layer signing flow contract)
- [x] transaction signing
- [x] transaction submission
- [x] pending/success/failure status handling
- [x] basic nonce/error handling through public RPC lookup and surfaced failures
- [ ] advanced nonce/error hardening (replacement tx, stale nonce reconciliation, richer RPC-specific recovery)

## Phase 7 — external NFC device foundation
Goal: keep a clean future path without implementing device SDK now.

Status: ⏳ Not started beyond interface placeholder already created

Deliverables:
- [x] abstract backend contract for external hardware
- [ ] storage-backend selection model
- [ ] compatible signing/auth flow contracts
- [ ] no real NFC implementation yet

## Phase 8 — future extension points
Goal: reserve clean extension paths.

Status: ⏳ Not started

Deliverables:
- [ ] protocol integration contracts for WalletConnect v2
- [ ] protocol integration contracts for AirGap
- [ ] state model prepared for external signing/session flows

## Suggested release sequence
- `v0.3` — architecture skeleton + secure vault foundation
- `v0.4` — onboarding/auth shell + create/import UI + one-time seed display flow
- `v0.5` — Ethereum Mainnet + Sepolia read-only balances
- `v0.6` — tokens + history + local cache
- `v0.7` — send form + gas estimation + preview
- `v0.8` — signing foundation + raw transaction submission abstraction
- `v0.9` — visible send flow states + nonce lookup + end-to-end submit wiring
- `v1.0` — advanced send hardening + groundwork for Phase 7 extension path

## Non-goals for now
- no hardware-device SDK implementation yet
- no WalletConnect v2 implementation yet
- no AirGap implementation yet
- no multi-chain support beyond Ethereum Mainnet and Sepolia yet
