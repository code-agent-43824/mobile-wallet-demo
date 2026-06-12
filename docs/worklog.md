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

## 2026-06-11 — Android + Windows: neutralise org id (same rules as iOS) — branch main — done
- Plan: bring Android + Windows under the iOS rules — replace the org-tied `dev.codeagent43824.*` identifiers
  with neutral `com.example.*` placeholders + document the (simple) local runs.
- Done:
  - Android: `applicationId` + `namespace` → `com.example.mobile_wallet_demo` (`build.gradle.kts`); moved
    `MainActivity.kt` from `.../kotlin/dev/codeagent43824/...` to `.../kotlin/com/example/mobile_wallet_demo/`
    and updated its `package` (the manifest uses relative `.MainActivity`, so it stays aligned with the
    namespace); removed the empty org dirs.
  - Windows: `Runner.rc` `CompanyName` `dev.codeagent43824` → `com.example`; `LegalCopyright` likewise.
  - README: new section listing the placeholder ids (iOS/Android/Windows) + simple local runs
    (`flutter run -d android` with USB-debugging + auto debug-keystore; `flutter run -d windows` with VS C++).
  - No org id left in code (only a historical mention in this worklog). No app/Dart change, no version bump.
- Next / open: none. Phase 9 still paused.
- Refs: this commit.

## 2026-06-11 — iOS: simplify local Xcode device runs (free Apple account) — branch main — done
- Plan: make "open in Xcode → Run on a real iPhone with a free Apple ID" robust + documented; neutralise the
  org-tied bundle id; add the missing Podfile.
- Done:
  - `ios/Runner.xcodeproj/project.pbxproj`: bundle id `dev.codeagent43824.mobileWalletDemo` → neutral
    placeholder `com.example.mobileWalletDemo` (Runner + RunnerTests, 6 configs); added explicit
    `CODE_SIGN_STYLE = Automatic` to the 3 Runner configs (RunnerTests already had it). No `DEVELOPMENT_TEAM`
    hardcoded — the user picks their Personal Team.
  - new `ios/Podfile` — standard Flutter iOS Podfile (the app uses native plugins `flutter_secure_storage` +
    `local_auth`; no Podfile existed → Xcode flow was fragile).
  - new `.fvmrc` pinning Flutter `3.41.7` (matches CI `ci.yml`).
  - README: new **"Run on real iPhone/iPad with free Apple Account"** section (Xcode + Flutter 3.41.7 → clone →
    `flutter pub get` → `flutter build ios --config-only` (runs pod install, wires the workspace) → open
    `Runner.xcworkspace` → Personal Team → replace the placeholder bundle id → device + Developer Mode → Run;
    plus notes on 7-day expiry, RunnerTests not blocking Run, and troubleshooting). Cross-linked from the
    existing "iOS artifacts" device bullet.
  - Checked: Runner = Automatic signing; RunnerTests doesn't block Run (only built on Test). No app/Dart
    change, no version bump.
- Next / open: CI iOS jobs now build with the committed Podfile (validates it). Phase 9 still paused.
- Refs: this commit.

## 2026-06-11 — Refactor: extract Blockscout ExplorerClient (completes blockchain split) — branch main — done
- Plan (finishes docs/repo-review.md #4): pull the explorer-parsing concern out of the provider, completing
  the RPC / explorer / cache split started with `SnapshotCache`.
- Done: new `blockchain/explorer_client.dart` — `JsonApiTransport` + `HttpJsonApiTransport` (moved) +
  `ExplorerData` + `BlockscoutExplorerClient` (`load` + token/tx parsing, bodies **verbatim**; the cache
  fallback is now passed in as `fallbackTokenBalances`/`fallbackTransactions` instead of depending on a cached
  snapshot). `blockchain_provider.dart` is now a **204-line** RPC orchestrator (was 589) that composes the
  explorer + cache and **re-exports both** (`export 'explorer_client.dart';`), so no importer changes. The
  wei→ETH formatter is a small private copy on each side (kept local to avoid a cross-concern import).
  Behaviour unchanged: same explorer URLs + parsing + fallback (the provider test pins it). No version bump.
- Net: `blockchain_provider.dart` 589 → 204; models 72, explorer 252, cache 125. **Blockchain split done.**
- Next / open: pubspec template comments remain (cosmetic, low value). Phase 9 still paused.
- Refs: this commit.

## 2026-06-11 — Refactor: extract SnapshotCache + record audit decisions — branch main — done
- Plan (acts on docs/repo-review.md #3/#4): split the cache concern out of the 589-line
  `blockchain_provider.dart`; record the decided/deferred audit items (single-account, l10n, test fidelity).
- Done: new `blockchain/blockchain_models.dart` (the snapshot models + `BlockchainFailure`, **re-exported**
  from `blockchain_provider.dart` so no importer changes) and `blockchain/snapshot_cache.dart` (`SnapshotCache`:
  cache-key + `read`/`write`, bodies moved **verbatim**). `PublicRpcBlockchainProvider` now composes a
  `SnapshotCache?` built from the unchanged `cacheStore` constructor arg → provider is 412 lines (was 589).
  Behaviour unchanged: same cache key + JSON format (the provider test pins both). Documented
  single-account / l10n / test-fidelity as explicit non-goals in `development-plan.md`. No behaviour change →
  no version bump.
- Next / open: optional follow-up — extract the Blockscout explorer parsing into an `ExplorerClient` (the
  other mixed concern in the provider); pubspec template comments remain (cosmetic). Phase 9 still paused.
- Refs: this commit.

## 2026-06-11 — Refactor: extract WalletFlowController (UI orchestrator) — branch main — done
- Plan (acts on docs/repo-review.md #1): pull the wallet state machine + all domain actions out of the
  ~560-line `WalletFlowScreen` State into a widget-free `WalletFlowController` (`ChangeNotifier`), so the
  logic is unit-testable and the widget becomes a thin listener. No behavior change.
- Done: new `lib/src/wallet_flow_controller.dart` (`part of wallet_flow_screen.dart`, public class) owns the
  vault/external-device/registry collaborators, all stage+session state, and every action (load/create/
  import/unlock/biometrics/lock/external-device ops). `setState` → guarded `notifyListeners`; `if (!mounted)`
  → `if (_disposed)`. `wallet_flow_screen.dart` is now just create+listen+render (identical widget tree and
  callback wiring). Kept it a `part` (not a separate library) so the library's imports stay invariant — zero
  unused-import risk with no local analyzer. Added `test/wallet_flow_controller_test.dart` driving the state
  machine with no widget. Bumped v1.19.0+30.
- Next / open: per the review — `blockchain_provider.dart` split, single-account decision, then Phase 9
  (9.3/9.4 on the fake before the 9.2 native SDK). Phase 9 still paused.
- Refs: this commit.

## 2026-06-11 — Quick repo audit recorded — branch main — done
- Plan: shallow-but-honest review (goals/code/docs/results) to guide further work.
- Done: `docs/repo-review.md` — strengths, ranked weaknesses (UI orchestrator debt, fake-only
  test ceiling, single-account hard-wiring), Phase 9 risks, suggested work order (extract
  `WalletFlowController` first; build 9.3/9.4 on the fake before the 9.2 native SDK).
- Next / open: Phase 9 still paused; next agent should read the review before resuming.
- Refs: this commit.

## 2026-06-09 — CI: fix iOS Simulator artifact packaging + add unsigned Device build — branch main — done
- Plan: the iOS Simulator artifact unzipped to loose bundle contents (`Info.plist`, `Runner`, `Frameworks`,
  …) instead of a `.app`, because `upload-artifact` was pointed straight at `Runner.app` and strips the dir
  it is given. Fix it to yield a single `.app`; add a separate, parallel iOS **device** job (unsigned by
  default, signing only via Secrets); document both scenarios in README. No app code change.
- Done: `ci.yml` —
  - `ios_simulator` (renamed "iOS Simulator build"): after the build, `ditto` the bundle to
    `build/ios/sim-artifact/Mobile Wallet Demo.app` and upload the **parent** dir, so the artifact
    `ios-simulator-app` (→ `ios-simulator-app.zip`) unzips to one `Mobile Wallet Demo.app` — single unzip,
    no double-zip (uploading a self-made `.zip` would double-zip on download).
  - new `ios_device` ("iOS Device build (unsigned)"): `flutter build ios --release --no-codesign` (iphoneos),
    a code-signing-status step that only checks Secret *presence* (never prints values) and logs clearly that
    the build is unsigned, then packages the `.app` the same way and uploads `ios-device-build`. Runs in
    parallel with the simulator job (both `needs: validate`).
  - No Apple credentials in the repo; a real signed export would be gated behind `IOS_CERTIFICATE_BASE64` /
    `IOS_PROVISIONING_PROFILE_BASE64` Secrets.
  - README: updated the CI-artifacts list + added an **"iOS artifacts"** section (Simulator install via
    Finder → Share → Simulator; device run via Xcode Personal Team; honest signing limits).
- Next / open: optional — implement a real signed-IPA export gated on the iOS Secrets if on-device installs
  are needed. Phase 9 still paused.
- Refs: this commit.

## 2026-06-09 — Phase 8/9 docs consolidation + dead-end cleanup — branch main — done
- Plan: after the Phase 8 → 9 role correction, make the docs internally consistent and strip dead-end
  clutter — the **outbound** ("server-side") WC/AirGap remote-signing model, and the conflation of the
  external NFC device with a signing *transport*. No code/logic change.
- Done: rewrote the stale `CLAUDE.md` architecture (dropped `RemoteWalletTransactionSigner` /
  `RemoteSigningTransport` / `RemoteSigningSessionController` / `sessions/…` / `RemoteSignerCatalog` /
  "Подписать через"; documented the surviving codecs + the wallet-side `WalletConnectService` seam; fixed the
  Phase status line). Condensed the development-plan status snapshot, stopping point, Phase 8 section, and the
  v1.11–v1.16 release notes; clarified the external-NFC device as the **custody** axis (Phase 10), explicitly
  *not* a signing transport. Collapsed the six per-chunk Phase 8 worklog entries (A–F) into one historical
  summary (record kept, dead-end detail removed). Reworded the `assembleSignedTransfer` doc comment off the
  outbound framing. Docs + one code comment only — no version bump.
- Next / open: Phase 9 intentionally not started (paused). When resumed: chunk 9.2 (real `reown_walletkit` +
  `WC_PROJECT_ID` + DI) or 9.3/9.4 on the fake first. Workflow note: now developing on `main` directly.
- Refs: this commit.

## 2026-06-08 — Phase 9 / chunk 9.1: WalletConnectService inbound seam — branch claude/wonderful-rubin-eBDKZ — done
- Plan (from the reframe "next"): add the wallet-side WalletConnect service abstraction + a fake for tests/DI,
  pure Dart, no SDK yet. Refined during work: keep the `reown_walletkit` dep + DI wiring for 9.2 (where a real impl
  and a consumer exist) to avoid an injected-but-unused field; ship an `UnavailableWalletConnectService` default
  until then.
- Done: new `lib/src/walletconnect/wallet_connect_service.dart`:
  - inbound models — `WalletConnectPeer`, `WalletConnectSessionProposal`, `WalletConnectSession`,
    `WalletConnectRequest`; `WalletConnectServiceException`.
  - `WalletConnectService` interface (wallet-side): `init`, `isAvailable`, `pair`, `sessionProposals` stream,
    `approveSession` / `rejectSession`, `activeSessions` + `sessionsChanges` stream, `requests` stream,
    `respondResult` / `respondError`, `disconnect`, `dispose`.
  - `UnavailableWalletConnectService` — shippable default (isAvailable=false, refuses pair/approve, empty streams).
  - `FakeWalletConnectService` — in-memory: `pair` auto-emits a proposal; `simulateProposal` / `simulateRequest`
    hooks; records `respondedResults` / `respondedErrors`.
  - tests `test/wallet_connect_service_test.dart`: pair→proposal→approve→active session (+ stream), bad-URI reject,
    incoming request → respondResult/Error, disconnect removes session, Unavailable refuses.
  - Bumped to v1.18.0+29; plan updated (9.1 done; deps/config/DI moved to 9.2), release sequence + snapshot synced.
- Next / open: chunk 9.2 — add `reown_walletkit` + `WC_PROJECT_ID` config + `ReownWalletConnectService` + DI into
  `MobileWalletDemoApp` (init on startup). No local Flutter toolchain — validated via CI (workflow_dispatch).
- Refs: 6639075 (reframe/plan); this commit.

## 2026-06-08 — Phase 9 / chunk 9.0: remove inverted outbound signing — branch claude/wonderful-rubin-eBDKZ — done
- Plan (from the reframe entry's "next"): remove the Phase 8 **outbound** remote-signing direction (this app
  requesting a signature *from* a WC/AirGap signer); keep the reusable codecs + the vault `assembleSignedTransfer`
  seam. No new feature; trim tests to the codecs; bump the version.
- Done:
  - `auth/wallet_operation_auth.dart`: removed `RemoteSigningTransport`, `RemoteWalletTransactionSigner`,
    `WalletOperationAuthorizer.authorizeRemoteSigning`, and `WalletAuthMethod.remoteSession` (+ the `dart:typed_data`
    import). Local/external-device signers and `assembleSignedTransfer` are unchanged.
  - Deleted `lib/src/sessions/remote_signing_session.dart` and `lib/src/sessions/remote_signer_registry.dart`
    (the whole outbound session/registry layer; `sessions/` is now empty).
  - `walletconnect/wallet_connect_v2.dart`: kept `WalletConnectRpcRequest` + `WalletConnectV2RequestCodec`; replaced
    the cross-module `RemoteSigningSessionException` with a local `WalletConnectCodecException`; removed
    `WalletConnectSessionInfo`, `WalletConnectV2Connector`, `DemoWalletConnectV2Connector`.
  - `airgap/airgap_signing.dart`: kept `AirGapPayloadCodec` + request/response models; removed
    `AirGapResponseProvider`, `AirGapOfflineConnector`, `DemoAirGapOfflineConnector`, `_AirGapRoundTripSigner`.
  - UI: removed the "Подписать через" dropdown + the remote-connector branch/disposal in `_signAndSubmit`
    (`wallet_flow_screen_unlocked.dart`), the `remoteSession` auth-method switch arm, and the two `sessions/` imports
    from the orchestrator library.
  - Tests: deleted `remote_signing_session_test.dart` + `remote_signer_registry_test.dart`; rewrote
    `wallet_connect_v2_test.dart` / `airgap_signing_test.dart` to codec-only; pruned the remote cases (and now-unused
    helpers/imports) from `wallet_operation_auth_test.dart`, `hardened_transaction_service_test.dart`, and
    `widget_test.dart`.
  - Bumped to **v1.17.0+28** across pubspec / `app_version.dart` / `widget_test.dart` / development-plan; also fixed
    the stale README version (was `v1.10.0+21`).
- Next / open: chunk **9.1** — deps + `WalletConnectService` abstraction + `FakeWalletConnectService` + DI (no real
  SDK yet). Note: no local Flutter toolchain in this env — validated via CI.
- Refs: 6639075 (reframe/plan); this commit.

## 2026-06-08 — Phase 9 reframed to wallet-side inbound (two axes) + chunk 9.0 planned — branch claude/wonderful-rubin-eBDKZ — done
- Plan: act on the role clarification — the product is **wallet-side** (it *receives* signing requests), so Phase 8's
  **outbound** direction (requesting a signature *from* a WC/AirGap signer) is the wrong role. Two decisions taken:
  (1) **remove** the outbound code, **keep** the reusable codecs; (2) do the **transport axis first** (WalletConnect +
  AirGap inbound + connections screen + request approval), then NFC custody. This commit is docs-only.
- Done: reframed `docs/development-plan.md` — Phase 8 marked **role-corrected/superseded** (codecs +
  `assembleSignedTransfer` kept; outbound transport/session/registry/connectors + "Подписать через" to be removed in
  **chunk 9.0**) with a "what survives" list; **Phase 9 rewritten** to wallet-side inbound signing across **two
  transports** (WC online, AirGap offline) with a connections screen + shared approval sheet, a **two-axis** framing
  (transport here, custody in Phase 10), inbound architecture, the **9.0–9.7** chunk breakdown, deliverables, risks,
  non-goals; added **Phase 10** (custody/NFC second factor); updated the status snapshot + stopping point. No code, no
  version change.
- Next / open: execute **chunk 9.0** (remove the outbound transport/session/registry/connectors + "Подписать через";
  keep `WalletConnectV2RequestCodec` + `AirGapPayloadCodec` + `assembleSignedTransfer`; trim tests to the codecs; bump
  version), then **chunk 9.1** (deps + `WalletConnectService` + `FakeWalletConnectService` + DI).
- Refs: this commit (docs only). Supersedes the 2026-06-06 Phase 9 plan below.

## 2026-06-06 — Phase 9 plan composed (real WalletConnect v2 + connections screen) — branch claude/wonderful-rubin-eBDKZ — done
- Plan: at the user's request, record a plan (no code) for a **real** WalletConnect v2 integration plus a
  dedicated WalletConnect screen showing connection status with disconnect / details / "create new connection".
- Done: added the **Phase 9** section to `docs/development-plan.md` — goal, **role decision (wallet-side, to
  confirm)**, dependencies (`reown_walletkit`, WC Cloud project id, relay reachability, navigation),
  architecture (`WalletConnectService` + fake + DI; request→vault signing; the screen; request sheet), a
  chunk breakdown 9.1–9.6, deliverables checklist, risks/open questions, and non-goals. Noted Phase 9 in the
  status snapshot + stopping point. Docs only — no code, no version change.
- Next / open: **confirm the wallet-side role** (vs dApp-side) and how the WalletConnect Cloud project id is
  supplied; then start **chunk 9.1** (deps + `WalletConnectService` abstraction + `FakeWalletConnectService`
  + DI) by the usual plan → code → record loop.
- Refs: this commit (docs only).

## 2026-06-04 → 06 — Phase 8 (chunks A–F): outbound WC v2 + AirGap remote-signing — branch claude/wonderful-rubin-eBDKZ — superseded
- Summary (condensed; per-chunk Plan/Done detail removed as dead-end clutter). Phase 8 shipped an **outbound**
  remote-signing model (v1.11–v1.16) — this app *requesting* a signature from an external WalletConnect/AirGap
  signer:
  - A (v1.11): async `WalletTransactionSigner` seam + `RemoteSigningTransport` / `RemoteWalletTransactionSigner`
    / `authorizeRemoteSigning` + `TransactionService.assembleSignedTransfer`.
  - B (v1.12): protocol-agnostic `RemoteSigningSessionController` lifecycle (`sessions/remote_signing_session.dart`).
  - C/D (v1.13/v1.14): WC v2 + AirGap contracts — the `WalletConnectV2RequestCodec` / `AirGapPayloadCodec`
    codecs plus outbound demo connectors over the chunk-B controller.
  - E/F (v1.15/v1.16): `RemoteSignerCatalog` (`sessions/remote_signer_registry.dart`) + a "Подписать через"
    send-flow option.
- Outcome: the **outbound role was wrong** — the wallet must *receive* signing requests, not request them.
  Chunk 9.0 (v1.17) removed the transport/session/registry/connectors + the "Подписать через" UI; only the
  codecs (`WalletConnectV2RequestCodec`, `AirGapPayloadCodec`) and `assembleSignedTransfer` were kept. The
  wallet-side inbound rebuild is Phase 9 (see the 9.0 entry above and `docs/development-plan.md`).
- Refs: v1.11–v1.16 (4c8a1ee / 82de0e5 / 7449e67 / ef861e9 / 06cfca5 + per-chunk commits); superseded by 9.0.

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
