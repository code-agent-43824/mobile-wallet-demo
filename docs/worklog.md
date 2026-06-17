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

## 2026-06-16 — Phase 11: auth per operation, not on app open — branch main — done (CI green)
- Trigger: owner noticed the PBKDF2 progress screen on **every** wallet access and asked: is the heavy
  derivation needed just to view? And for a card-based key, should the PIN really be asked to view the
  status screen? Agreed: no. Decisions — open → **read-only dashboard, no auth**; each **private-key op**
  authenticates **every time** (no session reuse), PIN/biometric for the vault, tap+PIN for the device;
  optional "lock app on open" toggle **deferred** (recorded in the plan, Phase 11 "Deferred").
- Plan (Phase 11 in `development-plan.md`): (11.1) `loadInitialState` + onboarding end states → the `unlocked`
  stage repurposed as a read-only dashboard (render from `summary`, no held material); keep `locked`/
  `_LockedStage`/`unlockWallet`/`lockWallet` for the future toggle. (11.2) `_withFreshlyUnlockedMaterial(
  {pin,useBiometrics})` = unlock→op→`lock()` in `finally`, + an `_OperationAuthSheet` (PIN + optional
  biometric) shown before each op. (11.3) rewire send / WC-approve / AirGap-sign to authenticate-on-demand
  (direct `{pin, useBiometrics}` params, not held material); update widget + controller tests.
- Done (v1.32.0+43): `loadInitialState` + onboarding end states → the `unlocked` stage repurposed as the
  read-only dashboard (renders from `summary`, no held material). `_withFreshlyUnlockedMaterial({pin,
  useBiometrics})` unlocks→runs the op→`lock()`+wipes `_material` in a `finally` (key never outlives the op).
  `approvePendingRequest`/`signAirGapRequest`/new `authorizeAndSubmitTransfer` take `{pin, useBiometrics}` and
  run through it; `_pendingRequest` clears only on success. New `_OperationAuthSheet` + `_promptForAuth`
  (PIN + optional biometric) shown by the unlocked/connections widgets before each op, popping the sheet
  with the credential BEFORE the busy op (so `pumpAndSettle` doesn't spin). `locked`/`_LockedStage`/
  `unlockWallet`/`lockWallet` kept for the deferred toggle. Tests reworked (controller + widget + connections).
  Reviewed the security-critical lock-in-`finally`; `dart format` clean (parses).
- Verified: **CI green on all 5 platforms** (run 27701182333). Two stale widget tests were fixed after the
  refactor landed: the external-device test (off-screen taps on the taller dashboard + the old reconnect/
  unlock flow → at rest the demo device is locked, so its PKCS#11 ping/read-address buttons now show a
  graceful "no session" banner; recorded as a deferred follow-up), and the async-tracking test (the
  transient "pending receipt" assertion raced the receipt timer once the auth sheet added a pumpAndSettle →
  bumped the test transport delay to 4s so the pending state is deterministic).
- Next / open: owner verifies on device — open = instant read-only dashboard (no PIN/PBKDF2); PIN/biometric
  (or device tap+PIN) prompt only on send / WC-approve / AirGap-sign. Deferred: the "lock app on open"
  toggle + the external-device session-management UX (both in the plan's Phase 11 "Deferred").
- Refs: this commit; will touch `lib/src/wallet_flow_controller.dart`,
  `lib/src/wallet_flow_screen{,_unlocked,_onboarding,_connections}.dart`, the widget/controller tests.

## 2026-06-16 — Cosmetic: rename to "Wallet Demo" + custom W icon (all platforms) — branch main — done
- Trigger: owner asked for (1) a proper app name + file name "Wallet Demo" on all platforms, (2) a custom
  icon replacing the Flutter default — a round white badge with a big black "W".
- Done (name → **Wallet Demo**): Android `android:label`; iOS `CFBundleDisplayName` + `CFBundleName`; Windows
  window title (`main.cpp`) + `Runner.rc` (FileDescription/ProductName) + `BINARY_NAME`→`WalletDemo` (exe;
  CMake target names can't contain spaces, so the .exe is `WalletDemo.exe`) + `InternalName`/`OriginalFilename`;
  in-app header (`wallet_flow_screen_widgets.dart`) + `MaterialApp.title`; WC peer metadata name
  (`reown_wallet_connect_service.dart`); the iOS artifact `.app` (ci.yml `ditto` + README) → `Wallet Demo.app`;
  `widget_test` assertion updated. **Kept** the Dart package name (`mobile_wallet_demo`) and bundle id
  (`com.example.mobile_wallet_demo`) — those are identifiers, not display names.
- Done (icon): `scripts/gen_app_icon.py` (Pillow, Outfit-Bold "W", 4× supersampled) regenerates all platform
  icons. Android `mipmap-*/ic_launcher.png` + Windows `app_icon.ico` = a white **circle** on a transparent
  background (true round icon). iOS `AppIcon.appiconset/*` = a white **opaque square** (iOS fills alpha with
  black and squircle-masks, so a transparent circle would get black corners) — visually a white rounded icon
  with the W. Verified by rendering a preview.
- **Version bump v1.30.0+41 → v1.31.0+42.**
- Next / open: CI green (Windows build must accept `BINARY_NAME=WalletDemo`; tests with the renamed header
  assertion; all icon files are static assets). Owner sees "Wallet Demo" + the W icon after reinstalling.
- Refs: this commit; `android/.../AndroidManifest.xml` + `mipmap-*`, `ios/Runner/Info.plist` +
  `Assets.xcassets/AppIcon.appiconset/*`, `windows/CMakeLists.txt` + `runner/{main.cpp,Runner.rc,resources/app_icon.ico}`,
  `lib/src/{app.dart,wallet_flow_screen_widgets.dart,walletconnect/reown_wallet_connect_service.dart}`,
  `scripts/gen_app_icon.py`, `.github/workflows/ci.yml`, README, version files.

## 2026-06-16 — On-device UX fixes: biometric activity, create/unlock freeze, progress overlay — branch main — done
- Trigger: owner ran the fixed **release** APK on Android — launches now. Two reported issues + one on-screen
  error: (1) create-wallet (after PIN) **freezes the UI for several seconds**; (2) a (smaller) freeze on PIN
  unlock; (3) screenshot showed `Biometric authentication failed: local_auth plugin requires activity to be a
  FragmentActivity`.
- Root causes: (1)/(2) `PhoneSecureVault._deriveEncryptionKey` runs **PBKDF2 at 600k iterations on the UI
  isolate**, blocking the main thread (same op on create and unlock — hence both freezes). (3) `MainActivity`
  extended `FlutterActivity`; `local_auth`'s BiometricPrompt requires a `FragmentActivity`.
- Fixes (v1.29.0+40 → **v1.30.0+41**):
  - **Biometric:** `MainActivity` → `FlutterFragmentActivity` (`android/app/.../MainActivity.kt`).
  - **Responsiveness:** PBKDF2 moved to a background isolate via `Isolate.run` in `_deriveEncryptionKey`
    (pure compute, sendable args/result, no platform channels) so the UI thread stays free.
  - **Progress UI:** `WalletFlowController` gains `busyMessage` + a `_runBusy(message, action)` wrapper around
    create/import/unlock; `WalletFlowScreen` shows a full-screen `_BusyOverlay` (scrim + spinner + message:
    «Создаём/Импортируем/Разблокируем кошелёк…») — it animates because the work is off-isolate.
  - **Tests:** moving PBKDF2 off the UI isolate frees `pumpAndSettle` to race the overlay's perpetual
    spinner, so widget tests would burn their fake-time budget. Added a test-only
    `PhoneSecureVault.debugIterationsOverride` (null in prod) set to `2` in `setUp`/`tearDown` of
    `widget_test.dart` + `wallet_connect_screen_test.dart`, so the off-isolate derivation is instant. Also
    speeds the suite (was running real 600k per create/unlock).
- Verified: launch-check x86_64/**release** ✅ (production startup fine with `FlutterFragmentActivity` + the
  isolate); `ci.yml` **green on all 5 jobs** (run 27670149548). The first `ci.yml` failed 13 create/unlock
  **widget** tests — moving PBKDF2 off the UI isolate let `pumpAndSettle` exhaust its fake-time budget against
  the overlay's perpetual spinner before the isolate spawn returned; fixed by running derivation **inline**
  when `debugIterationsOverride` is set (commit 2e8ecba; production still uses the isolate).
- Next / open: owner re-tests on device — create/unlock should show a smooth progress overlay (no freeze) and
  biometrics should enable after PIN.
- Refs: 71e0ea8 (fixes) + 2e8ecba (inline-in-tests); `android/app/src/main/kotlin/.../MainActivity.kt`,
  `lib/src/key_storage/phone_secure_vault.dart`, `lib/src/wallet_flow_controller.dart`,
  `lib/src/wallet_flow_screen.dart`, `lib/src/wallet_flow_screen_widgets.dart`, version files, the two test
  files.

## 2026-06-16 — Fix release-only launch crash: JNA stripped by R8 (reown yttrium) — branch main — done (verified on x86_64/release)
- Diagnosis (via the on-demand launch-check agent): the app crashes ~1s after launch **only in release** builds.
  Matrix: x86_64/API34 **debug** → launches fine (20s alive); x86_64/API34 **release** → **crashes**. arm64
  emulator can't run on GitHub CI (macOS Apple-Silicon runners report `HVF HV_UNSUPPORTED`, so no acceleration
  → emulator never boots) — so reproduction came from x86_64 **release**, not arm64. Static `.so` check ruled
  out 16 KB-page alignment for arm64 (all arm64-v8a libs ≥ 16 KB; only the unused 32-bit armeabi-v7a variants
  are 4 KB). Crash buffer:
  `java.lang.UnsatisfiedLinkError: Can't obtain peer field ID for class com.sun.jna.Pointer`
  `at com.sun.jna.Native.initIDs / uniffi.yttrium_wcpay.UniffiRustCallStatus.<init>`.
- Root cause: reown_walletkit's `yttrium`/`walletconnect_pay` bindings use **JNA**; its native
  `libjnidispatch.so` resolves Java fields (e.g. `com.sun.jna.Pointer.peer`) by name via JNI at init. **R8**
  (release only — debug has no R8) renamed/stripped them → the native lookup fails on launch. This also
  reconciles the timeline: the owner's earlier *working* WC dogfood was a **debug** (`flutter run`) build; the
  crashing one is a **release** APK.
- Fix: `android/app/build.gradle.kts` release buildType → `isMinifyEnabled = false` + `isShrinkResources =
  false` (disable R8 shrinking; fine for a demo) and wire `proguard-rules.pro`. New `android/app/proguard-
  rules.pro` keeps JNA (`com.sun.jna.**` + members), uniffi (`uniffi.**`), and reown (`com.reown.**`/
  `com.walletconnect.**`) verbatim so it stays correct if shrinking is ever re-enabled. Build/config only —
  no app code or version bump.
- Verified: x86_64/release now **stays alive 20s, 0 UnsatisfiedLinkError/FATAL** (launch-check CI run
  27652955892), and `ci.yml` is green on the fix commit (run 27652949575 — release build fine with shrinking
  off on all platforms). Before-fix repro: run 27625982920 (x86_64/release, crashed).
- Next / open: owner re-installs the **release** APK on the real phone to confirm (rebuild via
  `scripts/build.sh apk --release`, or grab the `android-apk` artifact from ci.yml run 27652949575), then
  continues the transaction + AirGap dogfood.
- Refs: 7db825d (fix); this commit (verify status). `android/app/build.gradle.kts`,
  `android/app/proguard-rules.pro`.

## 2026-06-16 — On-demand Android launch-check workflow (crash diagnostics) — branch main — done
- Trigger: owner reports the app **crashes ~1s after launch on a real Android phone**. The build chain
  (`ci.yml`) only *builds* the APK and never runs it, so a runtime/startup crash (native init, missing ABI
  `.so`, a plugin throwing at registration) is invisible to it. Owner asked for a **separate, on-demand**
  GitHub agent that installs + launches the app and collects logs — explicitly NOT wired into the normal
  build chain (so it doesn't slow every build).
- Done: (1) `.github/workflows/android-launch-check.yml` — `workflow_dispatch`-only (manual / API trigger;
  inputs: `build-mode` debug|profile|release, `api-level`, `ref`). Builds the APK with
  `--dart-define-from-file=dart_defines.json` (so `WC_PROJECT_ID` is set → the real `ReownWalletConnectService`
  is instantiated on Android, matching the owner's run), boots an emulator via
  `reactivecircus/android-emulator-runner` (x86_64, google_apis, KVM), runs the launch check, and uploads
  `build/launch-logs/**` as an artifact. (2) `scripts/android_launch_check.sh` — installs (`-g`), clears
  logcat, launches via `monkey`, watches the process + crash buffer for `WATCH_SECONDS` (20), then dumps the
  full log + **crash buffer** (`adb logcat -b crash`) and prints the FATAL/AndroidRuntime block; exits non-zero
  if the app never starts or dies. **Also runnable locally against a REAL phone** (the best repro for
  device/ABI-specific crashes): `flutter build apk --debug …` then `bash scripts/android_launch_check.sh`.
- Note: third-party `reactivecircus/android-emulator-runner` added (CI-only, diagnostic; not shipped in the
  app) — flagged like the JitPack decision. No app code or version change (tooling only).
- Prime crash suspects to look for in the logs (don't pre-fix — read first): reown native init
  (`ReownWalletConnectService`/`ReownWalletKit.createInstance`, `yttrium` `.so` for the device ABI), or a
  plugin registration throw. The emulator is x86_64 vs the phone's arm64, so a missing-arm64-`.so` crash may
  NOT reproduce on the emulator — run the script locally on the phone for that case.
- Next / open: on owner's go, trigger the workflow (or owner runs the local script on the phone) → read the
  crash buffer → fix the actual cause. Owner is also checking the iOS simulator.
- Refs: this commit; `.github/workflows/android-launch-check.yml`, `scripts/android_launch_check.sh`.

## 2026-06-16 — Phase 9 / chunk 9.9c: camera polish + Phase-9 doc reconciliation — branch main — done (CI green on all 4 platforms)
- Plan: owner asked to polish the camera and confirm/record that Phase 9 is complete. (1) Add a scan-window
  overlay + torch toggle to the camera scanner. (2) Audit Phase 9 vs. the docs and reconcile plan/checklists/
  CLAUDE.md/worklog. (3) Record the owner's 9.2 dogfood result. (4) Surface any remaining small items.
- Owner dogfood result (2026-06-16): real `reown_walletkit` (9.2) on a device — **connect/disconnect work**,
  and **`personal_sign` works** (approve/reject confirmed against a live dApp). Transaction signing not yet
  tested (wallet had no funds; owner has a seed with test ETH and will verify next). So 9.2 is device-validated
  for pairing + message signing; the tx send is the same sign path (fake tests + `personal_sign` already cover
  the signer), pending funds only.
- Audit: `WalletConnectInboundCoordinator` responds on **every** path (unknown method / unsupported network /
  wrong account / any thrown error → `respondError`), so a dApp never hangs — no correctness gap. Phase 9 is
  **feature-complete**: tx + `personal_sign`/`eth_sign` + EIP-712, over WalletConnect (real reown) + AirGap,
  with file (all platforms) + camera (Android/iOS) QR.
- Done: `qr/camera_qr_scanner.dart` — `_CameraScannerScreen` gains a centred-square **scan window**
  (`ScanWindowOverlay` dims the surround + rounded border; `MobileScanner.scanWindow` limits detection to it)
  and an AppBar **torch** toggle (`_TorchButton`: `ValueListenableBuilder` on the controller's `TorchState` →
  `controller.toggleTorch()`, hidden when unavailable). Reconciled docs: `CLAUDE.md` (Phase 9 overview + the
  WalletConnect/AirGap architecture section + the `WC_PROJECT_ID` note), `docs/development-plan.md` (status
  snapshot ⏳→✅, Current stopping point, Phase 9 Status, Dependencies, Deliverables checkboxes, chunk 9.9 +
  removed the stale duplicate "9.7 — tests" placeholder, changelog v1.28/v1.29). **Version bump v1.28.0+39 →
  v1.29.0+40.** No test change (the polish lives in the un-headless-testable camera widget).
- Next / open: CI green (run 27595359921, v1.29.0+40). The **only** remaining Phase 9 item is the owner's
  **transaction** + **AirGap** dogfood (owner is testing both now and will report separately). The three
  optional follow-ups (`wallet_switchEthereumChain`/`addEthereumChain`; an inbound-request queue; proposal
  chain validation before approve) are deferred by owner decision and now recorded in the plan's Phase 9
  **"Optional follow-ups"** subsection so they aren't lost.
- Refs: 10dfb86 (code+docs); follow-up docs commit (optional-followups backlog + this status flip);
  `lib/src/qr/camera_qr_scanner.dart`, version files, `CLAUDE.md`, `docs/development-plan.md`.

## 2026-06-15 — Phase 9 / chunk 9.9b: live camera QR scan (CameraQrScanner) — branch main — done (CI green on all 4 platforms)
- Plan: with the 9.9a probe green, write the camera integration against the verified `mobile_scanner` 7.2.0
  API (pulled from package source, not guessed): a `CameraQrScanner` that adds the camera source and reuses
  the existing file-decode path; wire it via DI on Android/iOS; add the iOS camera permission. The connections
  UI + controller already call the `scanWithCamera`/`loadFromFile` seam (gated on `isCameraScanAvailable`), so
  this is purely "provide a camera-capable `QrScanner`".
- Done: `qr/camera_qr_scanner.dart` — `CameraQrScanner implements QrScanner`: `isCameraScanAvailable => true`;
  `scanWithCamera({title})` resolves the global `navigatorKey.currentState` (throws `QrScannerException` if
  unmounted) and pushes a full-screen `_CameraScannerScreen` (a `MobileScanner` with
  `MobileScannerController(formats: [BarcodeFormat.qrCode], detectionSpeed: noDuplicates)`, `onDetect` pops
  the first non-empty `barcode.rawValue`; AppBar back = cancel→null; Russian hint using the passed title +
  a Russian `errorBuilder`); `loadFromFile`/`isFileLoadAvailable` **delegate to a composed `FileQrScanner`**
  (no duplication). DI (`app.dart`): a top-level `_appNavigatorKey` installed on `MaterialApp.navigatorKey`;
  `_defaultQrScanner()` returns `CameraQrScanner(navigatorKey: _appNavigatorKey)` on `Platform.isAndroid||isIOS`,
  else `FileQrScanner` (Windows = file-only; the camera class still compiles everywhere — 9.9a proved the
  native side builds/excludes cleanly). iOS `NSCameraUsageDescription` added to `Info.plist` (Russian). Android
  `CAMERA` permission is provided by the plugin's own manifest (merged) — no app-manifest change. New
  `test/camera_qr_scanner_test.dart`: camera-available + file-delegation + the no-navigator error path (the
  live `MobileScanner` widget can't run headless). **Version bump v1.27.0+38 → v1.28.0+39.**
- Next / open: CI green check (analyze must accept the `mobile_scanner` API usage on all platforms). Then it's
  part of the owner's device dogfood: open Connections, tap «Сканировать … камерой», grant the camera
  permission, scan a real `wc:`/`airgap-tx:` QR, confirm it fills the field. **Phase 9 feature work (tx +
  message + typed-data, WalletConnect + AirGap, file + camera QR) is now complete**; the remaining open item
  is real-relay reown dogfooding (9.2).
- Refs: this commit; `lib/src/qr/camera_qr_scanner.dart`, `lib/src/app.dart`, `ios/Runner/Info.plist`,
  `test/camera_qr_scanner_test.dart`, version files, `docs/development-plan.md`.

## 2026-06-15 — Phase 9 / chunk 9.9a: probe — add mobile_scanner dep only — branch main — done (CI green on all 4 platforms)
- Plan: the camera is the remaining QR input source (file-load already ships via `FileQrScanner`; camera is
  declared unavailable today). Before writing the `CameraQrScanner` + scanner-screen widget + NavigatorKey +
  camera permissions + DI wiring, run the same isolation probe that paid off for reown (9.2a): add
  `mobile_scanner: ^7.2.0` to `pubspec.yaml` **alone** (no code — Flutter still compiles a plugin's native
  code from the pubspec), push, and poll CI on all 4 platforms. mobile_scanner declares android/ios/macos/web
  only (NOT windows/linux), and its native iOS pods are the risk (cf. connectivity_plus's too-new SDK symbol).
  This isolates "does it build everywhere?" from the integration code. Build/config only — no version bump.
- Done: **CI run 27581949021 green on all 4 platforms** (Validate + Windows + Android APK + iOS Simulator +
  iOS Device). Pre-analysis from package source held: iOS is **pure-Swift on the Apple Vision API** (no
  GoogleMLKit pod) with `deployment_target = 12.0` ≤ the app's 13.0 — none of the connectivity_plus-style pod
  risk; Android pulls MLKit from **standard Google Maven** (no JitPack) with **no flavor dimension** and
  `minSdk 23` (already satisfied — reown forces ≥23 and builds green) / `compileSdk 36` (Flutter 3.41.7
  default); Windows is excluded cleanly as unsupported. So the dep is safe to keep — no revert needed.
- Next / open: 9.9b (done in the entry above) — the `CameraQrScanner` integration.
- Refs: probe commit b16ef86; `pubspec.yaml`.

## 2026-06-15 — Phase 9 / chunk 9.2b-ii: real ReownWalletConnectService — branch main — done (code-complete; pending device dogfood)
- Plan: with reown building green (9.2b-i), implement the real service over `reown_walletkit` 1.4.0 behind
  the existing `WalletConnectService` interface, mapped from the package source (not guessed), and DI-select
  it on mobile when configured. Fake stays for tests.
- Done: `walletconnect/reown_wallet_connect_service.dart` — `ReownWalletConnectService`:
  `init` → `ReownWalletKit.createInstance(projectId: wcProjectId, metadata)`, subscribes reown's `Event<T>`
  callbacks (`onSessionProposal`/`onSessionRequest`/`onSessionConnect`/`onSessionDelete`) and bridges them to
  our broadcast streams; `pair(uri)`; `approveSession` builds the reown `Map<String,Namespace>` from the
  kept original `ProposalData` (chains/methods/events + our CAIP-10 accounts per namespace) → maps the
  returned `SessionData`; `rejectSession`/`disconnect` via `ReownSignError`; `respondResult`/`respondError`
  via `JsonRpcResponse`/`JsonRpcError`; `activeSessions`/`sessionsChanges` from `getActiveSessions()`. Mapping
  helpers: `ProposalData`/`SessionData`/`SessionRequestEvent` → our `WalletConnectSessionProposal`/`Session`/
  `Request`; `PairingMetadata` → `WalletConnectPeer`. `init` swallows relay/connect failures (stays inert)
  so the controller's `unawaited(init())` can't crash. DI (`app.dart`): `_defaultWalletConnectService()` =
  reown on `Platform.isAndroid||isIOS` when `isWalletConnectConfigured`, else `Unavailable` (so desktop +
  `flutter test` host get `Unavailable` — reown never instantiated; existing tests unaffected; the
  connections widget tests still inject the fake). **Version bump v1.26.0+37 → v1.27.0+38.**
- No reown unit tests — it needs a live relay; the fake + inbound-coordinator tests cover the flows, and
  `flutter analyze` type-checks our usage against reown's real API (the main CI gate here). Real pairing is
  the owner's dogfood (has Android phone + Mac/iPhone).
- Next / open: CI green check (analyze must accept the reown API usage). Then **owner dogfooding**: build,
  install the APK / run the iOS sim, open a test dApp (e.g. on Sepolia), scan the `wc:` pairing QR (load from
  file works today; camera is the remaining `mobile_scanner` chunk), approve the session, sign a tx/message/
  typed-data, confirm the dApp accepts it. Report any runtime mismatch (namespace/respond shape) for a fix.
- Refs: this commit; `lib/src/walletconnect/reown_wallet_connect_service.dart`, `lib/src/app.dart`,
  version files, `docs/development-plan.md`.

## 2026-06-15 — Phase 9 / chunk 9.2b-i: reown toolchain fixes (re-add dep) — branch main — done (CI green on all 4 platforms)
- Plan: owner chose to finish 9.2 carefully (has an Android phone + Mac/iPhone for dogfooding). Apply the
  two toolchain fixes the 9.2a probe identified, re-add `reown_walletkit`, and get CI green on all 4
  platforms before writing any integration (9.2b-ii). Still no behaviour change — the fake/`Unavailable`
  service stays the default; this is build/config only.
- Done: (1) **iOS** — `dependency_overrides: connectivity_plus: 7.0.0`. The probe pinned the failure to
  `connectivity_plus 7.1.1` using `NWPath.isUltraConstrained` (too-new SDK symbol). Verified from source
  that **7.0.0 is clean** of that symbol and sits within `reown_core`'s `connectivity_plus >=6.1.3 <8.0.0`
  (same 7.x Dart API), so the override is safe. (2) **Android** — added `maven { url =
  uri("https://jitpack.io") }` to `android/build.gradle.kts` `allprojects.repositories` so Gradle can fetch
  reown's native `yttrium`/`walletconnect_pay` libs (the `com.github.reown-com.*` JitPack coordinates that
  weren't found). (3) re-added `reown_walletkit: ^1.4.0`. No app-version bump (build/config only).
- Next / open: CI probe again — expect Validate ✅, Windows ✅ (unchanged), and now **iOS + Android green**.
  If green → 9.2b-ii: real `ReownWalletConnectService` behind `WalletConnectService` + `WC_PROJECT_ID` init +
  DI (fake stays for tests), then owner dogfoods on a device. If iOS still red, the fallback is bumping the
  CI Xcode (setup-xcode). No Flutter locally → CI is the verifier.
- Refs: this commit; `pubspec.yaml`, `android/build.gradle.kts`.

## 2026-06-15 — Phase 9 / chunk 9.2a: probe — add reown_walletkit dep only — branch main — probed, reverted (blocked)
- **Probe result (CI run 27568514582):** Validate ✅ (pub get **resolved** reown + 58 transitive deps with
  our pins — web3dart 3 migration paid off; analyze + tests pass). **Windows x64 ✅** — reown is excluded
  cleanly as unsupported, so Windows is NOT a blocker (no need to drop it). **iOS ❌** and **Android ❌**:
  - iOS (device + simulator): `connectivity_plus 7.1.1` (pulled by reown_core/sign) Swift error
    `Value of type 'NWPath' has no member 'isUltraConstrained'` — a very-new iOS SDK symbol the CI
    `macos-latest` Xcode lacks. Fix options: select a newer Xcode on the macOS runner (if one with the
    symbol is available), or `dependency_overrides` `connectivity_plus` to a version that compiles on the
    current Xcode (must stay compatible with reown's usage).
  - Android: `Could not find com.github.reown-com.yttrium:yttrium-wcpay:0.10.14` during
    `mergeReleaseNativeLibs` — reown's native Android libs (`yttrium`, via `walletconnect_pay`) live on a
    non-standard Maven repo. The `com.github.*` group = **JitPack**; fix = add `maven { url
    'https://jitpack.io' }` to `android/` repositories (a supply-chain decision to flag).
- Reverted the dep to keep `main` green (the probe was exactly to learn this without committing to a broken
  state). No code was written against reown.
- Decision needed from owner before 9.2b: (1) OK to add the JitPack Maven repo for Android? (2) iOS — bump
  CI Xcode vs pin `connectivity_plus`? (3) reown only truly validates with **device dogfooding** on a live
  dApp — owner has a phone/Mac? Until then 9.2b would be code-complete-but-unverified.
- Refs: this commit (revert); probe commit d13bbd8; `pubspec.yaml`, `docs/worklog.md`.

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
