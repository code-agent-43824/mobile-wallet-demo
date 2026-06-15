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

## 2026-06-15 — Phase 9 / chunk 9.8: EIP-712 typed-data signing — branch main — done
- Plan: add `eth_signTypedData_v4`/`_v3`. The hard part is the precise EIP-712 hashing; the sign is then raw
  secp256k1 over the digest. To do it safely without a local run, validate the encoder against **reference
  test vectors** generated from a real EIP-712 impl (Python `eth-account`).
- Done: new pure-Dart `walletconnect/eip712.dart` — `Eip712Encoder.encode(typedData)` → the 32-byte
  `keccak256(0x1901 ‖ domainSeparator ‖ hashStruct(message))` digest, with `encodeType` (primary + deps
  sorted), `hashStruct`/`encodeData`, and `encodeValue` covering structs, arrays (v4), string/bytes (keccak),
  bytesN, address, bool, uint/int (two's complement). `TransactionService.signDigest({walletMaterial,
  digest})` signs a raw 32-byte digest via web3dart top-level `sign` (low-s, v=27/28) → 65-byte r‖s‖v hex
  (forwarded by Hardened); `WalletTransactionSigner.signDigest` delegates. Codec: `signTypedDataV4/V3Method`,
  `isTypedDataMethod`, `decodeTypedDataRequest` (`[address, typedData]`, JSON string or Map) →
  `WalletConnectTypedDataRequest`. `WalletConnectInboundCoordinator` gets a typed-data branch (verify
  account → encode → signDigest → respond; chain scoping lives in the typed data's own domain). Request card
  shows `primaryType @ domain`. **Generated ground-truth vectors with `eth-account`** for the canonical
  "Ether Mail" example (cow key): digest `0xbe609aee…30957bd2`, signature `0x4355c47d…915621c` (v=28) —
  asserted exactly in `eip712_test.dart` (web3dart's `sign` canonicalises s, so it matches). Also: codec
  decode tests, coordinator routing tests (valid + wrong-account), controller approve wiring; switched the
  inbound "unsupported method" test to `wallet_switchEthereumChain` (since v4 is now supported). **Version
  bump v1.25.0+36 → v1.26.0+37.** `dart format` clean.
- Result: **wallet-side inbound signing is feature-complete on the fake** — tx + message + typed-data, over
  WalletConnect + AirGap, with file-QR input.
- Next / open: live camera `mobile_scanner` (no Windows) and the real `reown_walletkit` (9.2) — both need
  device/native work. No Flutter locally → CI is the verifier.
- Refs: this commit; `lib/src/walletconnect/eip712.dart`, `wallet_connect_v2.dart`,
  `wallet_connect_inbound.dart`, `transactions/transaction_service.dart`, `hardened_transaction_service.dart`,
  `auth/wallet_operation_auth.dart`, `wallet_flow_screen_connections.dart`, `test/eip712_test.dart`,
  `test/wallet_connect_inbound_test.dart`, `test/wallet_connect_request_decode_test.dart`,
  `test/wallet_connect_controller_test.dart`, version files, `docs/development-plan.md`.

## 2026-06-15 — build(deps): migrate web3dart 2.7 → 3.x (unblocks reown 9.2) — branch main — in progress
- Plan: bump `web3dart: ^2.7.3` → `^3.0.1` (latest is 3.0.2) as an isolated step before adding
  `reown_walletkit` (9.2), which floors `web3dart ^3.0.1`. Doing it alone de-risks: any breakage surfaces
  on its own, not tangled with the SDK.
- Why we were on 2.x: no deliberate reason — `web3dart ^2.7.3` was simply the current stable when the
  crypto/signing foundation was first added (commit 0dcb792, "phone secure vault foundation"). The 2→3 bump
  was *deferred* (not chosen) when reown first surfaced the conflict (worklog 07e5b1a): we picked the older
  reown 1.3.8 over "a risky web3dart 2→3 major bump", then reverted reown entirely for iOS/Windows reasons.
  So 2.x was inertia + stability, never a hard requirement.
- Scope check: all our web3dart usage is **core** API (verified present in 3.0.2 docs): `signTransactionRaw`,
  `prependTransactionType`, `Transaction`/`.copyWith`/`.isEIP1559`, `EthPrivateKey.fromHex`/
  `signPersonalMessageToUint8List`, `EthereumAddress.fromHex`/`.hexEip55`/`.addressBytes`, `EtherAmount`,
  and `crypto.dart` (`bytesToHex`/`hexToBytes`/`keccak256`). 3.0.0 only "cleaned up deprecated
  methods/classes" — none of which we use → expecting a near-no-op code change. Main risk is transitive
  resolution (pointycastle/cryptography vs bip32/bip39). No app-version bump (no user-facing change; the
  existing signing tests are the behavior safety net).
- Done: pubspec bump (run 27565907870). CI's `flutter pub get` surfaced the predicted transitive conflict:
  `bip39 1.0.6` (latest, 5 yrs old) → `pointycastle ^3`, but `web3dart 3` → `pointycastle ^4`. bip39 has no
  newer version, so the fix is `dependency_overrides: pointycastle: ^4.0.0` — bip32/bip39 only use stable
  pointycastle digest/HMAC/EC APIs, and the deterministic derivation test (`phone_secure_vault_test.dart`:
  known mnemonic → `0xf39Fd6…266`) guards that the override doesn't change HD derivation. No app code change.
- Then (run 27566077256) pub get **resolved**, but `flutter analyze` exposed the **real** web3dart 3.0
  breaking changes the changelog hid ("refactor and cleanup deprecated methods/classes"). Downloaded the
  3.0.2 + `wallet` 0.0.18 sources from pub and grepped them for ground truth. The API moves + our fixes:
  • `package:web3dart/crypto.dart` **removed** — the helpers (`bytesToHex`/`hexToBytes`/`keccak256`) are now
    `part`s of the main lib → import `package:web3dart/web3dart.dart` (used `show` for the crypto-only files).
  • `EthereumAddress` / `EtherAmount` **moved to `package:wallet`** (web3dart 3 imports it but no longer
    re-exports) → added `wallet: ^0.0.18` dep + `import 'package:wallet/wallet.dart' show EthereumAddress,
    EtherAmount;` in `transaction_service.dart`. (`fromHex`, `EtherAmount.inWei`/`.zero()` unchanged.)
  • `EthereumAddress.hexEip55` **removed** → `.eip55With0x` (checksummed + 0x; matches our test's `0xf39Fd6…266`).
  • `EthereumAddress.addressBytes` **removed** → `.value` (the base `Address.value` Uint8List).
  6 files touched (4 imports + 2 renames) + pubspec. No logic change.
- Done: web3dart ^3.0.1 + `wallet` ^0.0.18 + `pointycastle` override; API migration above. Status: in
  progress pending CI (resolution ✓ already; expecting analyze + signing/derivation tests to pass now).
- Next / open: confirm CI green (esp. the derivation test under pointycastle 4 and the signing tests under
  web3dart 3), then proceed to reown 9.2. No Flutter locally → CI is the verifier.
- Refs: this commit; `pubspec.yaml`, `transaction_service.dart`, `phone_secure_vault.dart`,
  `airgap_inbound.dart`, `airgap_signing.dart`, `wallet_connect_v2.dart`.

## 2026-06-15 — Phase 9 / chunk 9.7: message signing (personal_sign / eth_sign) — branch main — done
- Plan (user: "следующим шагом делаем personal_sign/typed-data"): add EIP-191 message signing on the fake.
  Scope to `personal_sign` + `eth_sign` (tractable via web3dart); **defer `eth_signTypedData_v4` (EIP-712)**
  — its struct hashing is intricate and high-risk to implement blind (no local run, needs byte-exact
  vectors), so it gets its own focused chunk.
- Done: `WalletConnectV2RequestCodec` — `personalSignMethod`/`ethSignMethod`, `isMessageSignMethod`,
  `decodeMessageRequest(method, params)` → `WalletConnectMessageRequest{address, message bytes, displayText}`
  (handles `personal_sign` `[message,address]` vs `eth_sign` `[address,message]`; message is `0x…` hex or
  utf8; best-effort utf8 display). `TransactionService.signPersonalMessage({walletMaterial, message})` →
  `EthPrivateKey.signPersonalMessageToUint8List` → 0x 65-byte hex (impl in `LocalTransactionService`,
  forwarded by `HardenedTransactionServiceImplementation`); `WalletTransactionSigner.signPersonalMessage`
  (delegates with the signer's material). `WalletConnectInboundCoordinator.handleRequest` gains a message
  branch (chain-agnostic: verify account → sign → respond the signature; no nonce/broadcast). Request card
  renders the decoded «Сообщение». Tests: codec decode (personal_sign hex+utf8 / eth_sign order / missing
  fields), coordinator (personal_sign signs → 132-char sig, eth_sign order, wrong-account → error, and the
  "unsupported method" test switched to `eth_signTypedData_v4`), controller approve personal_sign → signature.
  **Version bump v1.24.0+35 → v1.25.0+36.** `dart format` clean.
- Next / open: `eth_signTypedData`/`_v4` (EIP-712 — needs a verified typed-data hasher), the live camera
  scanner (`mobile_scanner`), and the real `reown_walletkit` (9.2). (No Flutter locally — analyze/tests
  verified via CI.)
- Refs: this commit; `lib/src/walletconnect/wallet_connect_v2.dart`, `lib/src/walletconnect/wallet_connect_inbound.dart`,
  `lib/src/transactions/transaction_service.dart`, `lib/src/transactions/hardened_transaction_service.dart`,
  `lib/src/auth/wallet_operation_auth.dart`, `lib/src/wallet_flow_screen.dart`,
  `lib/src/wallet_flow_screen_connections.dart`, `test/wallet_connect_request_decode_test.dart`,
  `test/wallet_connect_inbound_test.dart`, `test/wallet_connect_controller_test.dart`, version files,
  `docs/development-plan.md`.

## 2026-06-15 — Phase 9 / 9.6 (real QR load from a file, all platforms) — branch main — done
- Plan (user ask): load a QR from a **file** on every platform — the only option on Windows (camera
  plugins/`mobile_scanner` don't support it). Keep the camera deferred. Next chunk = `personal_sign`/typed-data.
- Done: the `QrScanner` seam now has **two sources** — `isCameraScanAvailable`/`scanWithCamera` (deferred)
  vs `isFileLoadAvailable`/`loadFromFile` (all platforms). New `qr/file_qr_scanner.dart`: `ZxingQrImageDecoder`
  (pure Dart — `image` decodes the picked image, `zxing2` reads the QR; runs on Windows) + `FileQrScanner`
  (picks via `file_selector`, injectable `pickImageBytes` for tests) — now the **production default** in
  `MobileWalletDemoApp`. Controller: `isQrCameraAvailable`/`isQrFileLoadAvailable` + `scanQrWithCamera`/
  `loadQrFromFile` (shared `_runQr`). Connections screen: "Загрузить … из файла" buttons (shown on all
  platforms) + camera buttons (gated, hidden for now) that fill the `wc:`/`airgap-tx:` fields. New deps:
  `file_selector ^1`, `image ^4`, `zxing2 ^0.2` (file_selector supports Windows; image/zxing2 are pure
  Dart). Tests: committed PNG fixture `test/fixtures/qr_wc_uri.png` (encodes `wc:9.6demo@2?relay=irn`) →
  `file_qr_scanner_test.dart` exercises the **real** image+zxing2 decode end-to-end + FileQrScanner
  wiring (cancel/no-QR/camera-deferred); updated `qr_scanner_test`, controller `loadQrFromFile`, and the
  widget "load from file fills the wc: field". **Version bump v1.23.0+34 → v1.24.0+35.** `dart format` clean.
- Risk note: 3 new deps + native `file_selector` (incl. Windows) can't be built/`pub get`-verified locally
  (no Flutter SDK here) — relying on CI (validate + all 4 platform builds). `pubspec.lock` is committed but
  CI's `flutter pub get` isn't frozen, so it regenerates the lock with the new deps.
- Next / open: **`personal_sign`/typed-data** (message-signing, on the fake — no new native risk). Then the
  live camera scanner (`mobile_scanner`, needs a Windows fallback) and the real `reown_walletkit` (9.2).
- Refs: this commit; `lib/src/qr/qr_scanner.dart`, `lib/src/qr/file_qr_scanner.dart`, `lib/src/app.dart`,
  `lib/src/wallet_flow_controller.dart`, `lib/src/wallet_flow_screen.dart`,
  `lib/src/wallet_flow_screen_connections.dart`, `pubspec.yaml`, `test/file_qr_scanner_test.dart`,
  `test/fixtures/qr_wc_uri.png`, `test/qr_scanner_test.dart`, `test/wallet_connect_controller_test.dart`,
  `test/wallet_connect_screen_test.dart`, version files, `docs/development-plan.md`.

## 2026-06-15 — Phase 9 / chunk 9.6: QR scanner seam + scan entry points + sheet polish — branch main — done
- Plan: 9.6 = QR scan for WC pairing + AirGap + request-sheet polish. The real camera (`mobile_scanner`)
  can't ship now — it has **no Windows support** (a CI build target) and needs per-platform camera
  permissions, and native builds aren't verifiable locally. So, like the real `reown_walletkit` (9.2):
  build the **seam + fake + unavailable default** (no new dependency), gate the UI on availability, defer
  the camera. No QR *rendering* dep either (kept the AirGap response as selectable text).
- Done: `qr/qr_scanner.dart` — `QrScanner` interface (`isAvailable`, `scan({title})`) +
  `UnavailableQrScanner` (default; `scan` throws `QrScannerException`) + `FakeQrScanner` (returns
  `nextResult`, records titles). Injected through `MobileWalletDemoApp` → `WalletFlowScreen` →
  `WalletFlowController`: `isQrScannerAvailable` + `scanQrCode({title})` (returns the decoded text or null;
  surfaces the unavailable message via `errorMessage`). Connections screen: gated "Сканировать wc: URI" /
  "Сканировать airgap-tx" buttons that fill the existing paste fields (hidden when unavailable, so the
  default build is paste-only — no dead button); request-card polish (added the «Отправитель» line).
  Tests: `qr_scanner_test.dart` (Unavailable throws / Fake returns+records), controller `scanQrCode`
  available+unavailable, widget "scan fills the wc: URI field" (injects `FakeQrScanner`). **Version bump
  v1.22.0+33 → v1.23.0+34** (5 sync points). `dart format` clean.
- Next / open: real `mobile_scanner` camera (when native platforms are tackled — Windows needs a fallback
  or platform-gated dep), `personal_sign`/typed-data (message-signing), and the real `reown_walletkit`
  (9.2). With 9.6, **Phase 9 is feature-complete on the fake** (both inbound transports + scan seam).
  (No Flutter locally — analyze/tests verified via CI.)
- Refs: this commit; `lib/src/qr/qr_scanner.dart`, `lib/src/app.dart`, `lib/src/wallet_flow_screen.dart`,
  `lib/src/wallet_flow_controller.dart`, `lib/src/wallet_flow_screen_connections.dart`,
  `test/qr_scanner_test.dart`, `test/wallet_connect_controller_test.dart`,
  `test/wallet_connect_screen_test.dart`, version files, `docs/development-plan.md`.

## 2026-06-15 — Phase 9 / chunk 9.5: AirGap inbound — branch main — done
- Plan: wallet-side AirGap inbound on the existing `AirGapPayloadCodec`, mirroring the WC inbound shape.
  Decode an `airgap-tx:` request → sign with the active backend → encode the `airgap-sig:` response.
  Paste-based (camera/`mobile_scanner` deferred to the QR chunk).
- Done: `airgap/airgap_inbound.dart` — `AirGapInboundCoordinator.signRequestPayload({requestPayload,
  transactionService, signer})`: `decodeRequest` → guards (unsupported chain / from≠wallet → `AirGapPayloadException`)
  → `prepareInboundTransaction` (reuses the 9.3 seam) → `signer.signPreparedTransfer` (nonce from the request)
  → `encodeResponse`. Offline by definition: no nonce lookup, no broadcast. Controller: `signAirGapRequest`
  (builds the active signer, runs the coordinator, stores `airGapResponsePayload`) + `clearAirGapResponse`;
  `_runGuarded` now also surfaces `AirGapPayloadException`. UI: a Connections-screen "AirGap (офлайн-подпись)"
  section — `airgap-tx:` field + «Подписать офлайн» → `airgap-sig:` response in a `_SummaryTile` + «Очистить
  ответ». Tests: `airgap_inbound_test.dart` (sign happy → `0x02` + requestId; wrong-account / bad chain /
  malformed throw), controller AirGap happy+malformed in `wallet_connect_controller_test.dart`, widget
  malformed-payload error in `wallet_connect_screen_test.dart`. **Version bump v1.21.0+32 → v1.22.0+33** (5
  sync points). `dart format` clean.
- Next / open: camera QR (scan via `mobile_scanner`) for WC pairing + AirGap request/response (9.6), the
  incoming-request-sheet polish, `personal_sign`/typed-data, and the real `reown_walletkit` (9.2, deferred
  behind native-build blockers). (No Flutter locally — analyze/tests verified via CI.)
- Refs: this commit; `lib/src/airgap/airgap_inbound.dart`, `lib/src/wallet_flow_controller.dart`,
  `lib/src/wallet_flow_screen.dart`, `lib/src/wallet_flow_screen_connections.dart`,
  `test/airgap_inbound_test.dart`, `test/wallet_connect_controller_test.dart`,
  `test/wallet_connect_screen_test.dart`, version files, `docs/development-plan.md`.

## 2026-06-15 — Phase 9 / chunk 9.4c: incoming-request approval sheet — branch main — done
- Plan: connect the already-tested 9.3 `WalletConnectInboundCoordinator` to the UI. Controller subscribes
  to `WalletConnectService.requests`, the Connections screen shows a request card, approve drives the
  coordinator (sign → broadcast/respond), reject → respondError. On the fake.
- Done: `WalletFlowController` now takes `transactionService`/`transactionBroadcaster`/`nonceProvider`
  (nullable, default to the prod impls — `HardenedTransactionServiceImplementation` /
  `PublicRpcTransactionBroadcaster` / `PublicRpcNonceProvider`), passed from `WalletFlowScreen` (which
  already has them). Subscribes to `requests` → `pendingRequest`; `approvePendingRequest` builds the active
  backend's `WalletTransactionSigner` via `WalletOperationAuthorizer` (reuses the in-memory unlocked
  material — no per-request prompt) and runs a `WalletConnectInboundCoordinator`; `rejectPendingRequest` →
  `respondError`; requests sub cancelled in `dispose`. UI: `_RequestCard` (method/chain/to/value +
  «Одобрить и подписать»/«Отклонить запрос») on the Connections screen. Tests: controller approve→
  `respondedResults` single = broadcast hash (real local signing of an Anvil-style tx, fake broadcaster/
  nonce) + reject→`respondedErrors`; widget test simulates a request → card → reject → gone +
  `respondedErrors` length 1. **Version bump v1.20.0+31 → v1.21.0+32** (pubspec, `app_version.dart`,
  `widget_test.dart`, README, development-plan stopping point + release sequence). `dart format` clean.
- Next / open: Phase 9 inbound is now end-to-end on the fake (proposals + sessions + requests).
  Remaining: AirGap inbound (9.5), QR pairing (9.6), `personal_sign`/typed-data, and the real
  `reown_walletkit` (9.2, deferred behind native-build blockers). (No Flutter locally — analyze/widget
  tests verified via CI.)
- Refs: this commit; `lib/src/wallet_flow_controller.dart`, `lib/src/wallet_flow_screen.dart`,
  `lib/src/wallet_flow_screen_connections.dart`, `test/wallet_connect_controller_test.dart`,
  `test/wallet_connect_screen_test.dart`, version files, `docs/development-plan.md`.

## 2026-06-15 — Phase 9 / chunk 9.4b: Connections screen — branch main — done
- Plan: build the Connections screen on top of the 9.4a controller seam, on the fake. New
  `WalletFlowStage.connections` + a presentational stage + a dashboard entry. Keep `personal_sign`/
  incoming-request approval sheet out (that's 9.4c).
- Done: new part file `wallet_flow_screen_connections.dart` — `_ConnectionsStage` (status chips
  available/sessions-count, "new connection" `wc:` URI `TextField` + Подключить, the session-proposal
  approval card `_ProposalCard` with Одобрить/Отклонить, active-session list `_SessionCard` with Отключить,
  "Назад к кошельку"). Added `WalletFlowStage.connections` (enum + `_buildStageBody` case + `_Header`
  description), controller `openConnections`/`closeConnections`, and an "Подключения (WalletConnect)" entry
  button in `_UnlockedStage` (new `onOpenConnections`). Tests: controller nav test (open/close) in
  `wallet_connect_controller_test.dart`; widget test `wallet_connect_screen_test.dart` drives the full
  tree on `FakeWalletConnectService` — create→unlock→open connections→pair→proposal→approve→session→
  disconnect, and a back-to-dashboard case. **Version bump v1.19.0+30 → v1.20.0+31** (visible feature):
  pubspec, `app_version.dart`, `widget_test.dart` assertion, README, development-plan stopping point +
  release sequence. `dart format` clean.
- Next / open: **9.4c** — incoming-request approval sheet: subscribe the controller to
  `WalletConnectService.requests`, show a request sheet, drive `WalletConnectInboundCoordinator`
  (sign → broadcast/respond) on approval. Then AirGap inbound (9.5) + QR pairing (9.6). Real
  `reown_walletkit` (9.2) still deferred. (No Flutter locally — analyze/widget tests verified via CI.)
- Refs: this commit; `lib/src/wallet_flow_screen_connections.dart`, `lib/src/wallet_flow_screen.dart`,
  `lib/src/wallet_flow_controller.dart`, `lib/src/wallet_flow_screen_widgets.dart`,
  `lib/src/wallet_flow_screen_unlocked.dart`, `test/wallet_connect_screen_test.dart`,
  `test/wallet_connect_controller_test.dart`, version files, `docs/development-plan.md`.

## 2026-06-15 — Phase 9 / chunk 9.4a: wire WalletConnectService into the controller — branch main — done
- Plan: first sub-step of 9.4 (Connections screen) on the fake. Keep it UI-free and fully unit-tested:
  inject the `WalletConnectService` seam through the DI chain and give `WalletFlowController` the WC state +
  action API the screen (9.4b) will call. Defer the `WalletFlowStage.connections` enum + screen widget to
  9.4b (adding the enum forces a non-exhaustive-switch case, i.e. UI — out of scope here).
- Done: DI — `MobileWalletDemoApp` takes a nullable `walletConnectService` (default
  `const UnavailableWalletConnectService()`), passes it to `WalletFlowScreen` (new required field) →
  `WalletFlowController` (optional, same default, so existing tests/`buildController` still compile). The
  controller now subscribes to `sessionProposals` + `sessionsChanges` in its ctor (seeds from
  `activeSessions`, `unawaited(init())`), cancels both subs in `dispose`, and exposes
  `isWalletConnectAvailable` / `walletConnectSessions` / `pendingProposal` + actions `pairWalletConnect` /
  `approvePendingProposal` (binds CAIP-10 `chain:address` from the unlocked summary) / `rejectPendingProposal`
  / `disconnectWalletConnectSession`. `_runGuarded` now also surfaces `WalletConnectServiceException` as
  `errorMessage`. New `test/wallet_connect_controller_test.dart` drives it on `FakeWalletConnectService`:
  default→unavailable, pair→pending proposal, approve→session w/ bound account + disconnect→empty, reject→
  cleared, invalid URI→error. No version bump (internal seam; UI lands in 9.4b). `dart format` clean.
- Next / open: **9.4b** — `WalletFlowStage.connections` + the Connections screen (status banner, sessions
  list → details → disconnect, "new connection" URI paste, proposal approval sheet) + dashboard entry, and
  wire the incoming-request approval sheet to `WalletConnectInboundCoordinator`. Real `reown_walletkit` (9.2)
  still deferred. (Could not run `flutter analyze`/`flutter test` locally — no Flutter SDK in this env, only
  standalone Dart for `dart format`; relying on CI for analyze/test.)
- Refs: this commit; `lib/src/app.dart`, `lib/src/wallet_flow_screen.dart`, `lib/src/wallet_flow_controller.dart`,
  `test/wallet_connect_controller_test.dart`, `docs/development-plan.md`.

## 2026-06-15 — Phase 10 prep: exact NFC/PC-SC reproduction spec (docs only) — branch main — done
- Plan: owner wants to later reproduce the NFC stack precisely — "what system calls are needed, what is
  not, no errors / no extra steps / no over-complication". Study how the two Rutoken demos actually access
  the NFC reader and write a minimal, reproduction-grade spec.
- Done: rewrote §6 of `docs/nfc-pkcs11-integration-notes.md` into an exact spec. Core finding: **the app
  never calls the OS NFC APIs directly** — it calls only the Rutoken **PC-SC bridge** (start/stop) + standard
  **PKCS#11**; the bridge owns Core NFC (iOS) / `NfcAdapter` (Android) and exposes the token as a PC-SC slot,
  so presence is observed via `C_WaitForSlotEvent`/`CKF_TOKEN_PRESENT`, not OS NFC callbacks. Documented,
  with literal values: iOS = SPM `swift-rtpcsc-wrapper` (branch master) + `wtpkcs11ecp.xcframework`,
  entitlement `com.apple.developer.nfc.readersession.formats=[TAG]`, Info.plist `NFCReaderUsageDescription`
  + `…iso7816.select-identifiers` AIDs (`F0000000005275746F6B656E`="…Rutoken", `A00000039742544659`),
  `RtPcscWrapper.start()` once + `startNfcExchange/stopNfc` per op + `getNfcCooldown`. Android = gradle
  `rtpcscbridge`(transitive→NFC perm)/`pkcs11wrapper`/`pkcs11jna`(both non-transitive)/`jna`(aar), arm64-only
  `libwtpkcs11ecp.so` via jniLibs copy, the two `RtPcscBridge.setAppContext` + `attachToLifecycle(... NFC)`
  lines in `Application.onCreate`, JNA `Native.load("wtpkcs11ecp")`, lifecycle-bound `C_Initialize`/
  `C_Finalize` (`CKF_OS_LOCKING_OK`), blocking `C_WaitForSlotEvent` presence loop. Added explicit **Do NOT**
  lists (iOS: no CoreNFC/`NFCTagReaderSession`/`SCard*`; Android: no `android.permission.NFC`/`uses-feature`
  /`NfcAdapter`/`enableReaderMode`/`enableForegroundDispatch`/NFC intent-filters/tag polling), the one-tap
  operation lifecycle (open→present→OpenSession→Login→crypto→Logout→Close→stop→cooldown), and a Flutter
  mapping (wrap both native stacks behind a platform channel; keep the Ethereum keccak/RLP/recovery math in
  Dart). Updated the dev-plan Phase 10 pointer. Docs-only; no bump.
- Next / open: real-device validation in chunk 10.3 (C_Sign r‖s-vs-DER, mnemonic extractability, cooldown
  timing, SDK delivery). Phase 10 still after Phase 9.
- Refs: this commit; `docs/nfc-pkcs11-integration-notes.md` §6, `docs/development-plan.md`.

## 2026-06-14 — Phase 10 prep: augment NFC/PKCS#11 notes from the Rutoken demo wallets (docs only) — branch main — done
- Plan: the owner supplied the two previously-unreachable owncloud archives — the **official Aktiv-Soft /
  Rutoken demo wallets** (iOS Swift + Android Kotlin). Study them and upgrade `docs/nfc-pkcs11-integration-
  notes.md` from "spec + third-party CLI" to first-party, code-verified guidance.
- Done: rewrote the notes against the demos and the **vendor C headers** shipped in
  `wtpkcs11ecp.xcframework` (lib v2.17.8.1). Now **all four mechanism hex values are confirmed**
  (KEY_PAIR_GEN=0x80000006, DERIVE_PRIVATE=0x80000007, DERIVE_PUBLIC=0x80000008, WITH_BIP39=0x80000009;
  CKK_VENDOR_BIP32=0x80000002) — the three I'd previously only had by name. **Found + flagged a real
  discrepancy:** the vendor header defines the BIP32 attribute base as `CKA_VENDOR_DEFINED|0x5000`
  (→ CKA_VENDOR_BIP32_CHAINCODE=0x80005000 …5005), whereas the Python wallet-tool lists 0x85000000 — doc
  now says trust the header. Verified recipes against real code (import template in `Pkcs11TokenWrapper`,
  PBKDF2(2048,"mnemonic")→HMAC-SHA512("Bitcoin seed") in `Bip39WalletCrypto`, derive at m/44'/60'/0'/0/0
  with hardened 0x80000000, CKM_ECDSA sign of a 32-byte digest, CKA_EC_POINT = DER ANSI X9.62). Added a
  new **NFC/PC-SC transport** section (iOS `RtPcscWrapper`+CoreNFC+cooldown; Android `rtpcscbridge`/
  `pkcs11jna`/`pkcs11wrapper`+`libwtpkcs11ecp.so` arm64, physical-device only) and a per-platform
  native-stack/deps section (the Flutter FFI/channel cost for chunk 10.0). Trimmed the open-questions
  list (4 now answered). Updated the development-plan Phase 10 reference pointer. Docs-only; no bump.
- Note: did **not** vendor the demos' native blobs (`wtpkcs11ecp.xcframework` / `libwtpkcs11ecp.so`) into
  the repo — proprietary vendor redistributables; documented + flagged instead. iOS/Android demos are
  Aktiv-Soft official samples (Android is BSD-2-Clause); a physical Rutoken «криптокошелёк» is required.
- Next / open: Phase 10 still planned (Phase 9 first). Remaining token-only unknowns listed in §10 of the
  notes (C_Sign r‖s-vs-DER, mnemonic extractability policy, transport reach, passphrase UX, SDK delivery).
- Refs: this commit; `docs/nfc-pkcs11-integration-notes.md`, `docs/development-plan.md`.

## 2026-06-14 — Phase 10 prep: NFC / PKCS#11 integration notes (docs only) — branch main — done
- Plan: the owner supplied NFC/PKCS#11 reference material (a vendor mechanism spec PDF + two
  owncloud links + the `mescheryakov1/wallet-tool` repo) and asked to distill the useful bits into
  repo docs so future agents can do Phase 10. Extract → synthesize → cross-link from the roadmap.
- Done: new `docs/nfc-pkcs11-integration-notes.md` — provenance/caveats, the reference tool overview,
  **confirmed** constants from `wallet-tool/pkcs11_structs.py` (CKK_VENDOR_BIP32=0x80000002,
  CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN=0x80000009, the CKA_VENDOR_BIP32/BIP39 attrs, std EC/sign
  consts), the **four vendor mechanisms verbatim from the spec PDF** (KEY_PAIR_GEN, WITH_BIP39, two
  DERIVE_*_FROM_PRIVATE) incl. their C param structs, operation recipes (create/import/derive/sign/
  read-mnemonic), the **Ethereum-specific corrections** (secp256k1 OID not P-256; keccak256 not
  CKM_SHA256; build v/recovery-id + low-s ourselves since CKM_ECDSA returns raw r‖s), a mapping onto
  our existing seams (`external_device_pkcs11.dart` adapter, `external_device_demo_backend.dart`,
  `wallet_operation_auth.dart` signer, `assembleSignedTransfer`), a 10.0–10.6 chunk plan, and open
  questions to confirm against a real token. Fleshed out the `development-plan.md` Phase 10 section
  (reference pointer + chunk breakdown; transport FFI-vs-NFC is the remaining TBD, vendor model no
  longer TBD). Docs-only — no code, no version bump.
- Sources note: the spec **PDF was the canonical content** (extracted via `pdftotext` after
  installing poppler-utils); the two **owncloud links returned HTTP 503** from this environment and
  could not be fetched — the PDF is presumed to be their export. `wallet-tool` (GitHub, MIT) is fully
  accessible and is the source of the confirmed numeric constants + recipes. Three vendor mechanism
  hex values (plain KEY_PAIR_GEN + both DERIVE_*) are **not** in the accessible source — documented by
  name only, flagged to confirm against vendor `wtpkcs11ecp` headers (not guessed).
- Next / open: Phase 10 is still planned (Phase 9 first). If the owncloud pages hold detail beyond the
  PDF (error tables etc.), ask the owner to re-share/paste — links were unreachable here.
- Refs: this commit; `docs/nfc-pkcs11-integration-notes.md`, `docs/development-plan.md`.

## 2026-06-14 — Phase 9 / chunk 9.3b-ii: inbound request coordinator (9.3 done) — branch main — done
- Plan: tie the inbound flow together on the fake — requests → decode → prepare → sign → broadcast/hex →
  respond. Completes 9.3.
- Done: `walletconnect/wallet_connect_inbound.dart` — `WalletConnectInboundCoordinator.handleRequest({request,
  signer})`: guards (unsupported method / unsupported chain / from≠wallet → `respondError`), maps CAIP-2 chain
  → `EvmNetwork`, fills nonce (request or `NonceProvider`) + gas/fee fallbacks, `prepareInboundTransaction` →
  signs via the active `WalletTransactionSigner` → `eth_sendTransaction` broadcasts (returns hash) /
  `eth_signTransaction` returns signed hex → `respond`; every path responds (catch-all → `respondError`).
  Tests `test/wallet_connect_inbound_test.dart` via `FakeWalletConnectService`: send→broadcast hash,
  sign→`0x02` hex, wrong-account→error, unsupported-method→error. No version bump.
- Next / open: **9.4** — connections screen + wire `WalletConnectService` into `MobileWalletDemoApp` /
  `WalletFlowController` (listen to proposals/requests, approve, drive the coordinator on unlock), still on the
  fake / `Unavailable` default. Real `reown_walletkit` (9.2) deferred (iOS Xcode + Windows blockers).
- Refs: this commit.

## 2026-06-14 — Phase 9 / chunk 9.3b-i: prepareInboundTransaction — branch main — done
- Plan: build a `PreparedTransfer` from a decoded inbound WC request's raw tx fields, so the existing
  `signPreparedTransfer` / signer seam signs it (no app snapshot/asset model). Foundation for the 9.3b-ii
  request handler.
- Done: `TransactionService.prepareInboundTransaction({network, fromAddress, toAddress, valueWei, data,
  gasLimit, maxFeePerGasWei, maxPriorityFeePerGasWei})` — added to the interface, implemented in
  `LocalTransactionService` (builds the EIP-1559 web3dart `Transaction` directly + a display-only preview),
  and forwarded by `HardenedTransactionServiceImplementation`. Test `test/transaction_inbound_test.dart`:
  prepare from raw fields → `signPreparedTransfer` → asserts a `0x02` EIP-1559 signed tx. Pure Dart; no bump.
- Next / open: 9.3b-ii — the request coordinator (`WalletConnectService.requests` → decode → prepareInbound →
  sign via the active signer → broadcast (`eth_sendTransaction`) / hex (`eth_signTransaction`) → `respond`),
  tested via `FakeWalletConnectService`.
- Refs: this commit.

## 2026-06-14 — Phase 9 / chunk 9.3a: inbound WC request codec (decode) — branch main — done
- Plan (option A — build on the fake, defer the real SDK after the 9.2 native blockers): 9.3 = inbound request
  → vault sign → respond, in small steps. **9.3a** (this commit): the **inverse** of the WC tx codec — decode
  an incoming `eth_sendTransaction` / `eth_signTransaction` tx object into a typed struct. Pure Dart + tests.
- Done: `walletconnect/wallet_connect_v2.dart` — added `WalletConnectTransactionRequest` + codec
  `decodeTransactionRequest(params)` (+ `sendTransactionMethod` / `isTransactionMethod` + hex parse helpers),
  inverse of `encodeSignTransaction`; optional nonce/gas/fees stay null for the wallet to fill. Tests:
  `test/wallet_connect_request_decode_test.dart` (full tx, minimal tx + defaults, missing-field guards).
  No version bump. (`main` confirmed green at 650f9b0 before starting.)
- Next / open: **9.3b** — add `prepareInboundTransaction` to `TransactionService` (build a `PreparedTransfer`
  from raw fields, reusing the EIP-1559 `Transaction` construction) + a request handler wiring
  `WalletConnectService.requests` → sign via the active `WalletOperationAuthorizer` signer → broadcast
  (`eth_sendTransaction`) / signed-hex (`eth_signTransaction`) → `respond`; tested via `FakeWalletConnectService`.
- Refs: this commit.

## 2026-06-14 — CI: pin Windows runner to windows-2022 (pre-existing local_auth_windows break) — branch main — done
- Finding: the reown revert run (24482e3) was green on Validate/Android/iOS×2 but **Windows STILL failed** →
  the `local_auth_windows` MSVC `<experimental/coroutine>` STL1011 error is **pre-existing**, caused by the
  `windows-latest` image moving to VS 18 / MSVC 14.51 (deprecation became a hard error). NOT a reown issue;
  it would have broken Windows on the next run regardless. (The iOS failure, by contrast, WAS reown's pod and
  went green once reverted.)
- Done: pinned the Windows CI job `runs-on: windows-latest` → `windows-2022` (VS 2022 / MSVC 17.x still
  accepts experimental/coroutine), restoring green.
- Next / open: proper long-term fix = bump `local_auth` to a version whose Windows plugin uses C++20
  `<coroutine>` (or add `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`); windows-2022 is a temporary
  reprieve.
- Refs: this commit.

## 2026-06-14 — Phase 9 / chunk 9.2a: add reown_walletkit dependency (isolated) — branch main — reverted (build blockers)
- Plan: do 9.2 carefully + incrementally. **9.2a** (this commit): add ONLY the `reown_walletkit` dependency and
  let CI prove `pub get` + all 4 platform builds still pass — isolating native-dep risk before any code uses
  it. **9.2b** (next): `ReownWalletConnectService` + DI, behind a **platform (Android/iOS) + config guard**,
  falling back to `UnavailableWalletConnectService` elsewhere.
- Research (pub.dev): `reown_walletkit` latest **1.4.0**; env sdk `>=3.8.0 <4.0.0` (OK with our `^3.11.0`),
  Flutter `>=1.10.0`; **platforms: Android + iOS only** (no Windows/macOS/web → the Windows CI build must not
  break and 9.2b must not construct the real service off-mobile / it'd `MissingPluginException`). Direct deps:
  event / reown_core / reown_sign / walletconnect_pay — none of our crypto deps directly (transitive conflicts,
  if any, surface in CI `pub get`).
- Done (9.2a): pinned `reown_walletkit: 1.3.8` in `pubspec.yaml`, nothing consumes it yet. (First try `1.4.0`
  failed CI `pub get` — run 07e5b1a: `reown_walletkit` 1.3.9+ pull `web3dart ^3.0.1`, clashing with our
  `web3dart ^2.7.3`; 1.3.8 is the last 1.3.x on web3dart 2.x, chosen over a risky web3dart 2→3 major bump.)
  Caveat: `pubspec.lock`
  is committed but there's no local Flutter toolchain to regenerate it — CI `flutter pub get` reconciles it
  (the committed lock lags until a real `pub get` is run + committed). No version bump.
- Outcome (CI run cba54f5): after the web3dart fix, two more blockers — **iOS** (both) fail to compile pods
  (`Value of type 'NWPath' has no member 'isUltraConstrained'` — a reown/transitive pod uses an API newer than
  the `macos-latest` runner's Xcode SDK), and **Windows** fails building `local_auth_windows` (MSVC
  `<experimental/coroutine>` STL1011 hard error, surfaced by the re-resolution). Android + Validate were green.
  With no local Flutter toolchain (each fix = a blind ~15-min CI cycle), **reverted the `reown_walletkit` dep
  to restore green `main`** instead of thrashing. The dart-define plumbing (`wc_config.dart` /
  `dart_defines.json` / `scripts/`) stays — it's inert without the dep.
- Next / open: decide direction — (a) build **9.3/9.4 on `FakeWalletConnectService`** first (no native dep,
  fully buildable + testable), defer the real SDK; or (b) invest in the iOS (pin a newer Xcode on the runner)
  + Windows (`local_auth` bump / coroutine workaround) build fixes for 9.2. **Recommend (a).**
- Refs: this commit.

## 2026-06-13 — WC_PROJECT_ID config plumbing (committed + build-injected) — branch main — done
- Plan: per the owner's explicit call, commit the WalletConnect project id and have builds read it from a
  file and pass it as a dart-define. Plumbing only — the real `reown_walletkit` consumer is chunk 9.2.
- Done: `dart_defines.json` (repo root) holds `WC_PROJECT_ID`, **committed deliberately** (public client id;
  owner accepts quota use). `lib/src/walletconnect/wc_config.dart` reads it via `String.fromEnvironment`
  (`wcProjectId` + `isWalletConnectConfigured`) with a tiny contract test. CI build jobs
  (android / ios×2 / windows) now pass `--dart-define-from-file=dart_defines.json`; local helpers
  `scripts/run.sh` / `scripts/build.sh` inject the same flag. README "WalletConnect project id" section +
  a CLAUDE.md gotcha (so the committed id isn't "fixed" as a leak). Value is unused until 9.2 → no app
  behaviour change, no version bump.
- Next / open: chunk 9.2 — `reown_walletkit` + `ReownWalletConnectService` consuming `wcProjectId` + DI into
  `MobileWalletDemoApp`.
- Refs: this commit.

## 2026-06-11 — iOS: enable "Designed for iPad/iPhone" on Apple Silicon Mac — branch main — done
- Plan: let the existing iOS `Runner` target run on Apple Silicon Macs as "Designed for iPad/iPhone" — no
  `macos/` folder, no `flutter create --platforms=macos`, no separate macOS target, no Mac Catalyst.
- Done: `ios/Runner.xcodeproj/project.pbxproj` — added `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES;` to all 3
  Runner target configs (Debug/Release/Profile). Verified: `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone+iPad) and
  `SDKROOT = iphoneos` already set; `SUPPORTS_MACCATALYST` absent (Catalyst stays off). README: new
  "Run iOS app on Apple Silicon Mac" section (open Runner.xcworkspace → Runner → Personal Team → destination
  "My Mac (Designed for iPad/iPhone)" → Run; Apple-Silicon-only; not Simulator, not a native macOS build).
- Next / open: CI iOS jobs unaffected (they target iphoneos/simulator; the setting is inert there). Phase 9
  still paused.
- Refs: this commit.

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
