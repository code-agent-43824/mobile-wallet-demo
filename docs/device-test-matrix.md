# Physical-device and live-service test matrix

Automated tests cover deterministic logic with fakes. This checklist is the release evidence for boundaries that
CI cannot reproduce: platform secure storage, biometrics, public RPCs, Reown relay, camera optics, and NFC.
Record the app version, date, OS/device, result, and evidence or issue for every executed row. Never place PINs,
mnemonics, WalletConnect credentials, or private transaction data here.

Result values: `PASS`, `FAIL`, `PARTIAL`, `RETEST`, `BLOCKED`, or `NOT RUN`.

## Current evidence

| Area | Platform | Version / date | Result | Evidence / remaining gap |
| --- | --- | --- | --- | --- |
| WalletConnect pair/disconnect + `personal_sign` | mobile owner device | v1.29 / 2026-06-16 | PASS | Owner dogfood recorded in worklog; exact device/OS not recorded. |
| WalletConnect transaction + per-op auth | iOS Simulator | v1.33 / 2026-06-16 | PASS | Approval/sign flow passed; simulator is not secure-storage hardware evidence. |
| WalletConnect Sepolia broadcast + cold-start vault persistence | Android owner device | v1.36 / 2026-07-21 | PASS | Owner dogfood recorded in worklog; capture device/OS on next repetition. |
| MetaMask EIP-4527 account import/signature return/Sepolia broadcast | Android owner device | v1.38 / 2026-07-22 | PASS | Broadcast appeared successful; transaction hash was not recorded. |
| Dense MetaMask QR live camera after scanner hardening | Nothing Phone 3a / Android 16 | v1.51.0+62 / 2026-08-17 | PASS | Live-camera decode of MetaMask's on-screen request QR succeeded during the EIP-4527 signing run; file/screenshot decode had already passed. |
| Rutoken custody/NFC discovery | Android owner device | v1.43 / 2026-07-22 | PASS | The same phone/card that timed out in v1.41–v1.42 is detected after moving the complete bridge bootstrap to `Application.onCreate`. An empty card then correctly reached the zero-master check. |
| Rutoken public-address/raw-signature probe | Android owner device | v1.46 / 2026-07-23 | PASS | Owner confirms the complete diagnostic succeeds: discovery, PIN/login, public address derivation, raw 64-byte `CKM_ECDSA`, and session teardown. Earlier v1.43–v1.45 failures drove the reference-alignment fixes. |
| Rutoken recoverable create/import provisioning | Android owner device | v1.47 / 2026-07-23 | PASS | Owner confirms existing-seed import returns the expected address and new recoverable creation returns its shown seed phrase/address. No secret test material is recorded here. |
| Rutoken ready-card adoption + biometric Sepolia send | Android owner device | v1.49 / 2026-07-25 | PASS | Owner confirms ready-card adoption, biometric PIN opt-in/release, and one Sepolia send. A second card was unavailable, so physical card-mismatch rejection remains pending. |
| Rutoken × WalletConnect `personal_sign` + EIP-712 + transaction | Nothing Phone 3a / Android 16 | v1.51.0+62 / 2026-08-17 | PASS | `personal_sign` and the transaction ran on `react-app.walletconnect.com`; EIP-712 required a dApp that actually requests typed data (Reown AppKit Lab) because the classic test dApp advertises only `eth_sendTransaction`/`personal_sign`. Sepolia broadcast independently verified on-chain: `0xe22d7a8491bd0d08eb2b7d257b5d1f5400e4e3e99d41f02a31202d56418847e5` — status `0x1`, block 11507550, `type 0x2`, `yParity 0x0`, low-s, `from` = the registered card address. Session disconnect also passed. |
| Rutoken × EIP-4527 AirGap + dense live-camera QR | Nothing Phone 3a / Android 16 | v1.51.0+62 / 2026-08-17 | PASS | MetaMask imported the exported `crypto-hdkey` account and derived exactly the registered card address; the sign request was scanned with the **live camera** (closing the v1.39 dense-QR gap), signed on the card, and MetaMask broadcast the returned signature. Verified on-chain: `0x9ff1e06b73143f83f2a8d68a8e1f4f9999a94e0b2716c7d0227005fbcaaf5a6e` — status `0x1`, block 11507643, `type 0x2`, `yParity 0x0`, low-s, 0.1 ETH, `from` = the registered card address, nonce sequential after the WalletConnect send. |
| Rutoken negative paths: cancel / timeout / NFC loss | Nothing Phone 3a / Android 16 | v1.51.0+62 / 2026-08-17 | PARTIAL | Cancel shows «Ожидание Рутокена отменено.» and timeout shows the 30-second message as specified. Removing the card mid-operation surfaces the generic «Ошибка нативного модуля Рутокена.» instead of the specified «Связь с Рутокеном потеряна. Поднесите карту заново.», so the native layer does not classify that case as `rutoken_nfc_lost`. Teardown is correct: the next operation succeeds. **Fix shipped in v1.55.0+66, not yet re-run:** classification no longer pattern-matches the vendor diagnostic — a failed operation asks the slot-event listener whether the card is still present. RETEST this row on hardware. |
| Rutoken different-card rejection | Nothing Phone 3a / Android 16 | v1.51.0+62 / 2026-08-17 | PASS | A second physical card is now available. Presenting the non-registered card (using that card's own PIN, because PIN login precedes the address check) is rejected with «Поднесён другой Рутокен: адрес карты не совпадает с активным кошельком.»; the registered card still works afterwards. Closes the check deferred since v1.49. |
| Rutoken invalid PIN | Nothing Phone 3a / Android 16 | v1.51.0+62 / 2026-08-17 | PASS | A single deliberate wrong PIN returns «Неверный PIN Рутокена.»; a subsequent correct authorization succeeds and resets the retry counter. Only one attempt was made, to avoid blocking the card. |

## Phone-vault release checks

Run on every supported mobile platform after secure-storage, auth, lifecycle, or platform-plugin changes.

| Check | Android | iOS | Acceptance |
| --- | --- | --- | --- |
| Create wallet, record address, cold restart | NOT RUN | NOT RUN | Same backend/address loads; no onboarding reset. |
| Import known test mnemonic | NOT RUN | NOT RUN | Address matches the reference vector. |
| Wrong PIN and lockout | NOT RUN | NOT RUN | Attempts fail safely; cooldown is visible and later expires. |
| Biometric approve and cancel | NOT RUN | NOT RUN | Approve signs once; cancel signs nothing and returns to a safe state. |
| Per-operation relock | NOT RUN | NOT RUN | Two consecutive private operations each require fresh auth. |
| Network switch during refresh | NOT RUN | NOT RUN | No stale-network balance or asset selection appears. |
| Background/kill/restart during operation | NOT RUN | NOT RUN | No held authorization; wallet reloads read-only. |

## Live transports

| Check | Android | iOS | Acceptance |
| --- | --- | --- | --- |
| Mainnet/Sepolia public RPC refresh and fallback | NOT RUN | NOT RUN | Live or documented cache fallback; network identity stays correct. |
| WalletConnect pair/reconnect/disconnect | PASS v1.36 | PARTIAL v1.33 sim | Session state and namespace match supported accounts/chains/methods. |
| WC transaction preflight and broadcast | PASS v1.36 | PARTIAL v1.33 sim | Simulation/fee preview precedes auth; accepted tx is broadcast once. |
| WC `personal_sign` | PASS v1.29 | PARTIAL v1.33 sim | Exact message/account shown; one fresh auth; valid signature. |
| WC EIP-712 | PASS v1.51 | NOT RUN | Domain/type summary matches request; valid signature after fresh auth. Needs a dApp that requests typed data (Reown AppKit Lab); the classic WalletConnect test dApp does not. |
| AirGap account export + MetaMask import | PASS v1.51 | NOT RUN | First derived MetaMask account equals Wallet Demo address; re-confirmed on the Rutoken-backed account. |
| AirGap dense single/multipart QR by camera | PASS v1.51 | NOT RUN | Reliable decode from live display; progress and cancel are safe. |
| AirGap EIP-1559 sign/return/broadcast | PASS v1.51 | NOT RUN | Preview matches exact request; MetaMask accepts signature and tx hash is recorded (`0x9ff1e06b…5a6e`, verified on-chain). |

`PARTIAL` is historical simulator evidence and must be replaced by physical-device evidence before making a
platform hardware/security claim.

## Phase 10 Rutoken gate

Add exact token model, firmware, SDK version, device/OS, and issue/evidence link when execution starts.

| Check | Android | iOS | Acceptance |
| --- | --- | --- | --- |
| Vendor stack init, token discovery, login, public-key read, teardown | PASS v1.46 | BLOCKED | Complete physical diagnostic passed on Android. |
| Recoverable create + mandatory backup confirmation | PASS v1.47 | BLOCKED | Empty token receives the reference raw master import; owner confirms creation and backup display succeed with the expected address. |
| Existing mnemonic + optional passphrase import | PASS v1.47 | BLOCKED | Owner confirms import succeeds and the address matches the independent source. |
| Address + software-retained account xpub/chain code | PASS v1.47 | BLOCKED | Address matches token derivation; provisioning metadata is produced from the same software reference without a native xpub query. |
| Adopt existing compatible card | PASS v1.49 | BLOCKED | Owner confirms address/path registration without `C_CreateObject`; different-card rejection still needs a second physical card. |
| Biometric PIN release | PASS v1.49 | BLOCKED | Owner confirms opt-in and a later system-biometric PIN release for signing. |
| Own-send | PASS v1.49 | BLOCKED | Owner confirms a biometric-authorized Sepolia send; earlier manual-PIN send also passed. |
| WalletConnect transaction | PASS v1.51 | BLOCKED | Preflight then tap+PIN/biometric; response/broadcast succeeds once. |
| WalletConnect personal/EIP-712 | PASS v1.51 | BLOCKED | Valid signatures; displayed request matches signed payload. |
| EIP-4527 AirGap transaction | PASS v1.51 | BLOCKED | Public account export and request signature require no secret export; descriptor-only adopted cards cannot export xpub. |
| Cancel, wrong PIN, timeout, NFC loss, SDK error | PARTIAL v1.51 | BLOCKED | v1.50 adds cancellation, stable error mapping, presence checks and teardown precedence; physical negative-path evidence remains. |
| Secret-containment review | PARTIAL v1.51 | BLOCKED | Static source/tests confirm public-profile separation, mutable provisioning-buffer clearing, no native secret logging, and fixed generic platform errors that discard raw vendor diagnostics; physical crash/log-output review remains. |

Phase 10 is complete only when the corresponding Definition of Done in `docs/development-plan.md` and every
required row above pass on physical Android; iOS support is complete only after its equivalent column passes.

## Phase 14 two-card gate (14.5)

Needs both cards. Everything below is reachable from Настройки → «Переключить кошелёк»; nothing here requires
re-provisioning, so the existing keys stay as they are.

| Check | Android | Acceptance |
| --- | --- | --- |
| Existing profile survives the upgrade | NOT RUN | After installing over v1.53/v1.54, the already-registered card is still there and still selected; no re-adoption, no NFC tap on startup. |
| Register the second card | NOT RUN | «Подключить ещё карту» → that card's PIN → tap. It is added *alongside* the first (no «уже зарегистрирован» error) and becomes active. |
| Both cards listed with serial and address | NOT RUN | The switcher shows two card rows with different addresses and different serial numbers, exactly one ticked. |
| Switch and sign with each | NOT RUN | Switch to card A, sign one operation with A; switch to card B, sign one with B. The dashboard address follows the switch. |
| **Unselected card cannot sign** | NOT RUN | With card A selected, present card B (using B's own PIN — PIN login precedes the address check). Must be rejected with «Поднесён другой Рутокен…». This is the security property; a PASS here is what re-closes the "different-card rejection" row above. |
| Forget a card | NOT RUN | «Забыть карту» on the inactive card removes only that row; the active card keeps working. Forgetting the active card falls back to the other one. |
| Re-connect a forgotten card | NOT RUN | The forgotten card can be added again with «Подключить ещё карту» and returns with the same address. |

A FAIL on the unselected-card row invalidates the Phase 10 «different-card rejection» evidence recorded for
v1.51.0+62, because that row tested one registered card and this changes what "registered" means.
