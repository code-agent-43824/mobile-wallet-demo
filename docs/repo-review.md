# Repo review — 2026-06-11 (quick audit by Fable, for the next agent)

Scope: a deliberately shallow but honest pass over goals, code quality, docs, and results
at v1.18.0+29 (`main`, CI green). Use this to prioritize work; not a security audit.

## Verdict

Healthy demo project, unusually well-documented, with one architectural debt item (UI layer)
and a known test-fidelity ceiling (fakes, no integration tests). Goals and status are clear
from docs alone — the multi-agent agreement works.

## Strengths (keep doing)

- **Clarity of purpose.** CLAUDE.md / development-plan.md / worklog.md tell one consistent
  story: what's built, what was rolled back (Phase 8 outbound) and why, what's next (9.2+).
- **Layering & DI.** `auth/ blockchain/ key_storage/ transactions/ walletconnect/ airgap/`
  with interface + injected fake + production default everywhere. 12 test files / ~2k lines
  covering every layer; zero TODO/FIXME; lints + format enforced in CI.
- **Sound security decisions for a demo:** DEK + PIN-wrap (PBKDF2 600k), PIN never persisted,
  lockout, biometric secret isolated, 5-min unlock TTL.
- **CI:** validate → 4 platform builds, artifacts verified to unpack correctly (iOS `.app`).

## Weaknesses (ranked, with recommendations)

1. **UI orchestrator is the weak layer.** `wallet_flow_screen*` = ~2 260 lines, a hand-rolled
   state machine in one `StatefulWidget` with `part` files; domain orchestration lives in the
   widget. It carries no unit-testable state object and no navigation. **Recommendation:
   before Phase 9 UI (chunks 9.3/9.4 add a connections screen + approval sheet — the worst
   possible moment to grow this file), extract a plain-Dart `WalletFlowController`
   (ChangeNotifier or similar) owning stage + actions; widgets become thin. Do it as its own
   chunk with no behavior change.**
2. **Test fidelity ceiling.** All tests run against fakes; nothing exercises a real RPC,
   relay, or secure storage. Fine for a demo — but say so. **Recommendation: when 9.2 adds
   `reown_walletkit`, add at least one manual/dogfood checklist doc, since the SDK can't be
   meaningfully faked.**
3. **Single address / single account** is hard-wired (`m/44'/60'/0'/0/0`) across vault, UI,
   and the WC accounts list. Phase 9 WC sessions expose CAIP-10 accounts — multi-account
   would ripple. **Recommendation: explicitly declare single-account as a product decision
   in the plan (or schedule the refactor before 9.3).**
4. **Minor:** `blockchain_provider.dart` (589 lines) mixes RPC fallback, explorer parsing,
   and cache — would split well; Russian UI strings are inlined (no l10n) and tests pin them,
   making any copy change a test change; `pubspec` still carries default template comments.

## Risks for Phase 9 (read before chunk 9.2)

- `reown_walletkit` is the first heavy native dep — pin it, expect platform build breakage
  (the Windows job will need an exclusion strategy since the SDK is mobile-oriented).
- `WC_PROJECT_ID` via `--dart-define`: CI builds will be "unavailable" mode by default —
  the `UnavailableWalletConnectService` default already handles this; keep it.
- Don't conflate axes (the Phase 8 mistake): transport (WC/AirGap inbound) vs custody
  (vault/NFC). The plan's two-axis section is the guard-rail — keep it updated.

## Suggested order of work

1. Chunk "9.1.5": extract `WalletFlowController` (no behavior change, big test win).
2. 9.3/9.4 against `FakeWalletConnectService` (logic + screens, no native risk).
3. 9.2 last among them: real SDK + `WC_PROJECT_ID` + platform-build fallout, isolated.
4. Then 9.5+ (AirGap inbound, QR) per plan.
