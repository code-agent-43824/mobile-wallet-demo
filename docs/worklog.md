# Agent worklog

Append-only, **newest first**. One entry per work chunk (even small). Per the working
agreement in `AGENTS.md`: write the **Plan** before coding; fill **Done** and
**Next / open** after. Phase-level status lives in `docs/development-plan.md`; this file
is the granular running log so another agent (possibly working in parallel) can see what
was planned, what shipped, and what's next.

Entry template:

```
## YYYY-MM-DD — <title> — branch <branch> — <planned | in progress | done>
- Plan: …
- Done: …
- Next / open: …
- Refs: <commits / files>
```

---

## 2026-06-04 — Phase 8 / chunk B: external signing session state model — branch claude/wonderful-rubin-eBDKZ — done
- Plan:
  - New module `lib/src/sessions/remote_signing_session.dart` — a protocol-agnostic session/lifecycle
    model that WC (chunk C) and AirGap (chunk D) will implement:
    - `RemoteSigningSessionStatus` (idle → connecting → connected → awaitingSignature →
      disconnected / error) + an immutable `RemoteSigningSession` snapshot.
    - `RemoteSigningSessionController` (implements the chunk-A `RemoteSigningTransport`): owns the
      lifecycle, exposes `state` + a `changes` stream and `connect()` / `disconnect()`, and updates
      its state around `requestSignedTransaction` (awaitingSignature → connected / error).
    - `DemoRemoteSigningSessionController` — in-memory simulation (signing delegated via an injected
      callback), mirroring the Phase 7 external-device demo precedent.
  - Tests: lifecycle transitions + change stream, sign-before-connect guard, error transition, and an
    e2e proving the session composes with chunk A through `submitAuthorizedTransferFlow`.
  - Ticks the Phase 8 deliverable "state model prepared for external signing/session flows".
  - Out of scope: real WC/AirGap protocols (C/D) and UI wiring (E/F).
- Done: added `lib/src/sessions/remote_signing_session.dart` — `RemoteSigningSessionStatus`, immutable
  `RemoteSigningSession` (+ `copyWith`), `RemoteSessionSigner` (the inject point WC/AirGap implement), and
  `RemoteSigningSessionController implements RemoteSigningTransport` with a `DemoRemoteSigningSessionController`
  that walks connect → awaitingSignature → connected / error / disconnected and exposes a `changes` stream.
  The controller is a drop-in transport for `authorizeRemoteSigning`. Tests cover the lifecycle (incl. the
  awaitingSignature transition), the sign-before-connect guard, the error transition, and composition with
  chunk A. Bumped to v1.12.0+23.
- Next / open: chunk C (WalletConnect v2 contract — implement `RemoteSigningSessionController` over a WC
  pairing/request model), then chunk D (AirGap). UI wiring (E/F) still pending; deep signed-tx field
  validation still deferred to C/D.
- Refs: 82de0e5 (plan); this commit.

## 2026-06-04 — Phase 8 / chunk A: async remote signing seam — branch claude/wonderful-rubin-eBDKZ — done
- Plan:
  - Make `WalletTransactionSigner.signPreparedTransfer` async (`Future<SignedTransfer>`);
    the local signers wrap the existing synchronous signing, so the local path is unchanged.
    `submitAuthorizedTransferFlow` / `submitTransferFlow` await it.
  - Add the remote-signer foundation that WC (chunk C) and AirGap (chunk D) will build on:
    `RemoteSigningTransport` (returns a raw signed tx from an external party),
    `RemoteWalletTransactionSigner` (async, holds no key material),
    `WalletOperationAuthorizer.authorizeRemoteSigning(...)`, and `WalletAuthMethod.remoteSession`.
  - Add `TransactionService.assembleSignedTransfer(preparedTransfer, rawSignedTransaction)` so a
    remote signer can build a `SignedTransfer` from externally-provided raw bytes without
    duplicating crypto (impl in `LocalTransactionService`, delegated by the hardened service).
  - Update the `WalletAuthMethod` switch in the unlocked view; add tests for the async local
    path and an end-to-end remote path via a fake transport; bump the version.
  - Out of scope for chunk A: real WC/AirGap protocols and deep signed-tx field validation
    (RLP decode + compare against the prepared tx) — flagged as follow-up for chunks C/D.
- Done: the signer contract is now async (`Future<SignedTransfer>`); local/external-device signers
  wrap the synchronous local signing and the hardened flow awaits it (local path unchanged). Added the
  remote foundation: `RemoteSigningTransport`, `RemoteWalletTransactionSigner`,
  `WalletOperationAuthorizer.authorizeRemoteSigning`, `WalletAuthMethod.remoteSession`, and
  `TransactionService.assembleSignedTransfer` (impl in `LocalTransactionService`, delegated by the hardened
  service). Updated the unlocked-view auth-method switch. Tests: unit (`authorizeRemoteSigning` type +
  auth method) and e2e (async remote signer through `submitAuthorizedTransferFlow` via a local-delegating
  transport). Bumped to v1.11.0+22.
- Next / open: chunk B (session/lifecycle state model for external signing), then C (WalletConnect v2
  contract) and D (AirGap contract). Deep signed-tx field validation (RLP decode + compare against the
  prepared tx) is still deferred to C/D.
- Refs: 4c8a1ee (plan); this commit.

## 2026-06-04 — Cursor/Copilot pointer files — branch claude/wonderful-rubin-eBDKZ — done
- Plan: add thin pointer files for non-Claude tools so they also follow the working
  agreement, without duplicating it (avoid drift).
- Done: added `.github/copilot-instructions.md` and `.cursor/rules/working-agreement.mdc`,
  both pointing at `AGENTS.md` as the canonical source (core rule + docs map + CI/format
  note only). Completes the open item from the previous entry. Docs/config only, no version bump.
- Next / open: **Phase 8** (WalletConnect v2 + AirGap contracts, external signing/session
  state model) — to be started next session, document-first in the plan/worklog.
- Refs: this commit.

## 2026-06-04 — Cross-agent docs + working agreement — branch claude/wonderful-rubin-eBDKZ — done
- Plan: make the repo legible to other agents picking up work; persist the
  "document first, then code, then record" rule; fix doc drift found in analysis.
- Done: added `AGENTS.md` (cross-tool entry + working agreement) and this worklog; added a
  "Multi-agent working agreement" section to `CLAUDE.md`; fixed the stale version
  (`v1.9.0+20` → `v1.10.0+21`) in `README.md` and the development-plan stopping point;
  de-hardcoded the version example in the CLAUDE.md gotcha and listed all sync targets.
- Next / open: optionally add thin `.github/copilot-instructions.md` / `.cursor` pointers
  to `AGENTS.md` if those tools are used; then start **Phase 8**.
- Refs: docs only, no version bump.

## 2026-06-04 — Tame wallet_flow_screen + harden at-rest payload — branch claude/wonderful-rubin-eBDKZ — done
- Plan: split the ~2240-line `wallet_flow_screen.dart`; fix unsafe at-rest payload parsing.
- Done: split the UI orchestrator into `wallet_flow_screen_{widgets,onboarding,unlocked}.dart`
  `part` files (orchestrator now ~560 lines, behaviour unchanged); added vault schema-version
  validation + defensive parsing with typed `CorruptVaultPayloadFailure` /
  `UnsupportedVaultSchemaFailure`; `_loadInitialState` is now resilient to a corrupt/old
  payload; +2 tests; bumped to v1.10.0+21. CI green on `main`.
- Next / open: Phase 8.
- Refs: 9f6fc28 (payload), 75acf88 (refactor), aae5d15 (format fix-forward).

> Earlier history (v0.3 … v1.9) is summarised in `docs/development-plan.md` →
> "Suggested release sequence".
