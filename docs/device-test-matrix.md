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
| Dense MetaMask QR live camera after scanner hardening | Android physical device | v1.39 | NOT RUN | Owner retest pending; file/screenshot decode already passed. |
| Rutoken custody/NFC discovery | Android owner device | v1.43 / 2026-07-22 | PASS | The same phone/card that timed out in v1.41–v1.42 is detected after moving the complete bridge bootstrap to `Application.onCreate`. An empty card then correctly reached the zero-master check. |
| Rutoken public-address/raw-signature probe | Android owner device | v1.46 / 2026-07-23 | PASS | Owner confirms the complete diagnostic succeeds: discovery, PIN/login, public address derivation, raw 64-byte `CKM_ECDSA`, and session teardown. Earlier v1.43–v1.45 failures drove the reference-alignment fixes. |
| Rutoken recoverable create/import provisioning | Android owner device | v1.47 | RETEST | Both empty-token flows are implemented; physical create and import tests are pending. Use only disposable/test backups and never record secrets here. |

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
| WC EIP-712 | NOT RUN | NOT RUN | Domain/type summary matches request; valid signature after fresh auth. |
| AirGap account export + MetaMask import | PASS v1.38 | NOT RUN | First derived MetaMask account equals Wallet Demo address. |
| AirGap dense single/multipart QR by camera | RETEST v1.39 | NOT RUN | Reliable decode from live display; progress and cancel are safe. |
| AirGap EIP-1559 sign/return/broadcast | PASS v1.38 | NOT RUN | Preview matches exact request; MetaMask accepts signature and tx hash is recorded. |

`PARTIAL` is historical simulator evidence and must be replaced by physical-device evidence before making a
platform hardware/security claim.

## Phase 10 Rutoken gate

Add exact token model, firmware, SDK version, device/OS, and issue/evidence link when execution starts.

| Check | Android | iOS | Acceptance |
| --- | --- | --- | --- |
| Vendor stack init, token discovery, login, public-key read, teardown | PASS v1.46 | BLOCKED | Complete physical diagnostic passed on Android. |
| Recoverable create + mandatory backup confirmation | RETEST v1.47 | BLOCKED | Empty token receives the reference raw master import; shown backup restores the same address. |
| Existing mnemonic + optional passphrase import | RETEST v1.47 | BLOCKED | Empty token receives the reference raw master import; address matches an independent vector. |
| Address + software-retained account xpub/chain code | RETEST v1.47 | BLOCKED | Address matches token derivation; provisioning metadata matches independent vectors without a native xpub query. |
| Own-send | BLOCKED | BLOCKED | Device signs; valid low-s/recovery id; broadcast succeeds once. |
| WalletConnect transaction | BLOCKED | BLOCKED | Preflight then tap+PIN; response/broadcast succeeds once. |
| WalletConnect personal/EIP-712 | BLOCKED | BLOCKED | Valid signatures; displayed request matches signed payload. |
| EIP-4527 AirGap transaction | BLOCKED | BLOCKED | Public account export and request signature require no secret export. |
| Cancel, wrong PIN, timeout, NFC loss, SDK error | BLOCKED | BLOCKED | No signature; session always closes; retry starts fresh. |
| Secret-containment review | BLOCKED | BLOCKED | No seed/private key in Dart models, logs, crash output, or errors. |

Phase 10 is complete only when the corresponding Definition of Done in `docs/development-plan.md` and every
required row above pass on physical Android; iOS support is complete only after its equivalent column passes.
