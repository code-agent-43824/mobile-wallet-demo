# Mobile Wallet Demo — Development Plan

This file is the canonical development plan for the project. Use it as the source of truth while implementing future tasks.

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

Deliverables:
- project module structure
- interfaces for key storage backends
- app flow skeleton
- placeholder external-device backend contract

## Phase 1 — onboarding and local auth
Goal: establish secure user entry flow.

Deliverables:
- welcome screen
- choice: create wallet / import seed
- mandatory PIN setup and confirmation
- optional biometric enable after PIN setup
- app state for locked/uninitialized wallet

Out of scope:
- blockchain reads
- transfers
- token logic

## Phase 2 — phone secure vault
Goal: implement the first real wallet backend.

Deliverables:
- BIP-39 seed generation
- one-time seed phrase display flow
- seed import flow
- encrypted storage of seed
- address derivation for EVM
- unlock flow protected by PIN / biometrics

## Phase 3 — EVM network foundation
Goal: connect to blockchain in read-only mode.

Deliverables:
- Ethereum Mainnet config
- Sepolia config
- public RPC provider layer with fallback strategy
- native balance retrieval
- base fee / gas estimate retrieval
- network metadata handling

## Phase 4 — read-only wallet experience
Goal: first useful user-facing wallet release without send risk.

Deliverables:
- wallet home screen
- address display
- current network switch/display
- native and token balances
- manual refresh
- recent transaction history screen
- local cache for last loaded blockchain state

## Phase 5 — transfer preparation
Goal: prepare safe transaction composition before enabling send.

Deliverables:
- send screen
- address validation
- amount entry
- asset selection
- automatic gas estimation
- transaction preview screen

## Phase 6 — signing and sending
Goal: enable real blockchain operations.

Deliverables:
- one auth prompt per operation
- transaction signing
- transaction submission
- pending/success/failure status handling
- nonce/error handling

## Phase 7 — external NFC device foundation
Goal: keep a clean future path without implementing device SDK now.

Deliverables:
- abstract backend contract for external hardware
- storage-backend selection model
- compatible signing/auth flow contracts
- no real NFC implementation yet

## Phase 8 — future extension points
Goal: reserve clean extension paths.

Deliverables:
- protocol integration contracts for WalletConnect v2
- protocol integration contracts for AirGap
- state model prepared for external signing/session flows

## Suggested release sequence
- `v0.3` — architecture skeleton + onboarding/auth shell
- `v0.4` — create/import seed + secure phone vault + address derivation
- `v0.5` — Ethereum Mainnet + Sepolia read-only balances
- `v0.6` — tokens + history + local cache
- `v0.7` — send form + gas estimation + preview
- `v0.8` — signing + transaction send
- `v0.9` — hardening + NFC/WalletConnect/AirGap extension groundwork

## Non-goals for now
- no hardware-device SDK implementation yet
- no WalletConnect v2 implementation yet
- no AirGap implementation yet
- no multi-chain support beyond Ethereum Mainnet and Sepolia yet
