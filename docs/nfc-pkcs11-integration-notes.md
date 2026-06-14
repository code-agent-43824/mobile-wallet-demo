# NFC / PKCS#11 hardware-signer integration notes (Phase 10 reference)

> **Audience:** any coding agent (Claude Code or other) who will turn the
> simulated external-NFC device (Phase 7) into a **real** PKCS#11/NFC custody
> signer in Phase 10. Read it together with `docs/development-plan.md`
> (Phase 10) and `AGENTS.md`.
>
> **Status:** research/reference only. **No real PKCS#11 or NFC code exists yet**
> — Phase 7 ships a *simulation* (`ExternalDeviceDemoBackend`). Nothing here is
> wired in. Every constant/recipe below is now cross-checked against the **two
> official Aktiv-Soft / Rutoken demo wallets** (iOS Swift + Android Kotlin) and
> the vendor C headers they ship — see Provenance.

---

## 0. TL;DR for the impatient

The device is a **Rutoken «криптокошелёк»** (hardware token; obtain via
`partners@rutoken.ru`). The host talks to it via **PKCS#11** (`wtpkcs11ecp`) over
an **NFC / PC-SC** transport. For an **Ethereum/EVM** account use the **vendor
BIP32/BIP39 mechanisms** — *not* the generic `CKM_EC_KEY_PAIR_GEN` path:

1. **Open an NFC session** (= the “tap”) and `C_Login(CKU_USER, devicePin)` (=
   the device second factor).
2. **Create** a seed-backed key: `C_GenerateKeyPair(CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN)`
   → a `CKK_VENDOR_BIP32` master key that can be **shown/exported as a BIP-39
   mnemonic** (our product must display the seed — this is the only mechanism
   that allows it). **Import** instead via `C_CreateObject` from a 32-byte master
   private key + 32-byte chain code (recipe §5.2).
3. **Derive** the account key at `m/44'/60'/0'/0/0` (ETH coin type 60):
   `CKM_VENDOR_BIP32_DERIVE_PRIVATE_FROM_PRIVATE` (sign) /
   `…DERIVE_PUBLIC_FROM_PRIVATE` (address).
4. **Address** = `keccak256(X‖Y)[-20:]`, where `X‖Y` come from the derived public
   key’s `CKA_EC_POINT` (DER-encoded ANSI X9.62 — unwrap it).
5. **Sign** an EIP-1559 tx: compute `keccak256(RLP(unsigned tx))` (32 bytes) **on
   the phone**, then `C_SignInit(CKM_ECDSA, derivedPrivKey)` + `C_Sign` → raw
   `r‖s` (64 bytes). **You** then do low-s (EIP-2) + recovery-id, RLP-encode the
   signed tx, and hand the bytes to `TransactionService.assembleSignedTransfer`.

Three Ethereum gotchas the vendor demos **leave to the app** (they sign arbitrary
32-byte data, not EVM tx): the curve must be **secp256k1** (BIP32 is secp256k1 by
definition — good), the digest must be **keccak256** (not `CKM_SHA256`), and you
must build **v / recovery id + low-s** yourself because `CKM_ECDSA` returns only
`r‖s`. Details in §7.

---

## 1. Provenance & sources

| Source | What it gave us | Access |
| --- | --- | --- |
| **`rutoken-demo-wallet` (iOS, Swift/SwiftUI)** — Aktiv-Soft JSC | The authoritative reference: real `Pkcs11/` + `Crypto/` + `Pcsc/` layers, the **`wtpkcs11ecp.xcframework`** with the **vendor C headers** (`wtpkcs11t.h`, lib v2.17.8.1). Source of the confirmed constants (§3) and recipes (§5). | Provided by owner (was the owncloud link). |
| **`rutoken-demo-wallet-android` (Kotlin/Compose)** — Aktiv-Soft JSC, **BSD-2-Clause** | Parity check + the Android native stack (gradle deps, `libwtpkcs11ecp.so`, PC-SC bridge). | Provided by owner (was the owncloud link). |
| **PDF** — *«Механизмы расширения»*, A. Osminina, 2025-10-08 | The vendor **mechanism spec** (the four `CKM_VENDOR_BIP32*` mechanisms + their C param structs), now confirmed verbatim by the headers. | Extracted with `pdftotext`. |
| **github.com/mescheryakov1/wallet-tool** (Python, MIT) | A third-party CLI over `wtpkcs11ecp`. Useful, but its hand-ported constants **disagree with the vendor header on the BIP32 attribute base** — see §3 ⚠️. Trust the header. | Public GitHub. |

**Vendor library:** `wtpkcs11ecp` (Aktiv/Rutoken PKCS#11 provider with crypto-wallet
extensions), shipped as `wtpkcs11ecp.xcframework` (iOS arm64 + sim + macOS) and
`libwtpkcs11ecp.so` (Android **arm64-v8a only**). These native blobs are
**proprietary vendor redistributables** — do **not** vendor them into this repo;
document and depend, don’t copy. A **physical token is required** (no simulator/
emulator).

> The two demo apps **are** the content behind the previously-unreachable
> owncloud links, so §§3–6 are now first-party, not inferred.

---

## 2. Reference implementations at a glance

Both apps implement the same lifecycle; mirror whichever matches the target
platform. They are clean, layered, and worth reading directly when implementing
each chunk.

**iOS (`rutoken-demo-wallet`)**
- `Pkcs11/` — `Pkcs11Actor.swift` (raw `C_*` calls: `C_SignInit`/`C_Sign`/…),
  `Pkcs11Session.swift`, `Pkcs11Token.swift`, `Pkcs11TokenWrapper.swift`
  (generate/import/derive/sign/enumerate), `Pkcs11Template.swift`,
  `Pkcs11Attribute.swift`, `Pkcs11Constants.swift`.
- `Crypto/` — `Bip39WalletCrypto.swift` (seed/master-key), `DerivePathBuilder.swift`,
  `CryptoHelper.swift` (PBKDF2/HMAC/SHA256), `Bip39Wordlist.swift`.
- `Pcsc/PcscHelper.swift` — NFC via the **`RtPcscWrapper`** Swift package
  (`RtReader`, `RtNfcSearchStatus`).
- `Managers/CryptoManager.swift` — the `withToken { … }` orchestration (open NFC →
  wait for token → run → logout → stop NFC).
- Wiring: `wtpkcs11ecp.xcframework` + a **bridging header**
  (`Rutoken_Demo_Wallet-Bridging-Header.h`) importing the vendor C headers; the
  `…entitlements` enables Core NFC.

**Android (`rutoken-demo-wallet-android`)** — Compose + Koin + Room.
- `pkcs11/` — `objects/{create,derive,find,delete}`, `sign/SignExtensions.kt`,
  `Constants.kt`, `WtPkcs11Module.kt`, `Pkcs11Launcher.kt`.
- `crypto/Bip32.kt`, `bip44/{Coin.kt,DerivationPath.kt}`, `bip39/Bip39Provider.kt`.
- `token/slotevent/` — token presence via PC-SC slot events.
- Gradle deps (from `gradle/libs.versions.toml`): `ru.rutoken.pkcs11wrapper:pkcs11wrapper:4.3.1`
  (high-level wrapper), `ru.rutoken:pkcs11jna:4.2.0` (JNA bindings),
  `ru.rutoken.rtpcscbridge:rtpcscbridge:1.4.0` (PC-SC/NFC), `net.java.dev.jna:jna:5.17.0`,
  `org.bouncycastle:bcpkix-jdk18on:1.81`; native `libwtpkcs11ecp.so` bundled under
  `external/pkcs11ecp-wt/android-arm64/`. **Android 9 / API 28+, physical device only.**

> **Flutter implication:** there is no Dart PKCS#11 stack. Phase 10 means
> **FFI/platform-channel down to these native stacks** (iOS `wtpkcs11ecp` +
> `RtPcscWrapper`; Android `pkcs11wrapper`/`pkcs11jna`/`rtpcscbridge` + the `.so`).
> That is the central cost to weigh in chunk 10.0.

---

## 3. Constants (authoritative — from the vendor header `wtpkcs11t.h`)

These are read from `wtpkcs11ecp.xcframework/.../Headers/wtpkcs11t.h` (lib
v2.17.8.1) and corroborated by the Android `Constants.kt`. **Prefer these over
the Python `wallet-tool` values** (see the ⚠️ note).

### Vendor mechanisms — all in the `CKM_VENDOR_DEFINED` (`0x80000000`) range
```
CKM_VENDOR_BIP32_KEY_PAIR_GEN                 = 0x80000006   // VENDOR_DEFINED + 6
CKM_VENDOR_BIP32_DERIVE_PRIVATE_FROM_PRIVATE  = 0x80000007   // + 7
CKM_VENDOR_BIP32_DERIVE_PUBLIC_FROM_PRIVATE   = 0x80000008   // + 8
CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN      = 0x80000009   // + 9
```

### Vendor key type
```
CKK_VENDOR_BIP32  = 0x80000002   // CKK_VENDOR_DEFINED + 2
```

### Vendor attributes — base `BIP32 = (CKA_VENDOR_DEFINED | 0x5000) = 0x80005000`
```
CKA_VENDOR_BIP32_CHAINCODE               = 0x80005000  // 32-byte chain code
CKA_VENDOR_BIP32_ID                      = 0x80005001  // HASH160 of the public key
CKA_VENDOR_BIP32_FINGERPRINT             = 0x80005002  // first 32 bits of *_ID
CKA_VENDOR_BIP39_MNEMONIC_TRACE          = 0x80005003  // master was BIP39-generated
CKA_VENDOR_BIP39_MNEMONIC                = 0x80005004  // the mnemonic words
CKA_VENDOR_BIP39_MNEMONIC_IS_EXTRACTABLE = 0x80005005  // gate before reading ^
```

> ⚠️ **Source discrepancy — trust the header.** The Python `wallet-tool` lists the
> attribute base as `0x85000000` (→ `…_CHAINCODE = 0x85000000`). The vendor
> header defines it as `0x80005000`. The **mechanisms and key type match** both
> sources, but the **attribute IDs differ**. The shipped C header is canonical
> for the real SDK — **always read the vendor `wtpkcs11t.h` of your exact SDK
> version** and do not hardcode attribute IDs from the Python port.

### Standard PKCS#11 used by the recipes
```
CKO_PUBLIC_KEY=0x02  CKO_PRIVATE_KEY=0x03
CKK_EC=0x03  CKK_EC_EDWARDS=0x40
CKA_CLASS=0x00 CKA_TOKEN=0x01 CKA_PRIVATE=0x02 CKA_LABEL=0x03 CKA_VALUE=0x11
CKA_KEY_TYPE=0x100 CKA_ID=0x102 CKA_DERIVE=0x10C CKA_EC_PARAMS=0x180 CKA_EC_POINT=0x181
CKM_EC_KEY_PAIR_GEN=0x1040  CKM_ECDSA=0x1041  CKM_SHA256=0x250
CKU_USER=1  CKF_SERIAL_SESSION=0x02  CKF_RW_SESSION=0x04
```

### EC curve OIDs for `CKA_EC_PARAMS` (DER), from `Pkcs11Constants.swift`
```
secp256k1 (Ethereum) = 06 05 2B 81 04 00 0A        // OID 1.3.132.0.10
Ed25519  (not EVM)   = 06 03 2B 65 70              // OID 1.3.101.112
secp256r1/P-256      = 06 08 2A 86 48 CE 3D 03 01 07  // 1.2.840.10045.3.1.7 — NOT for ETH
```

### Token init/format (only if you ever (re)format a token)
`C_EX_InitToken` takes a `CK_RUTOKEN_WALLET_INIT_PARAM { ulSizeofThisStructure,
UseRepairMode, pNewAdminPin, ulNewAdminPinLen, … }` (extended `C_EX_*` function
via `CK_FUNCTION_LIST_EXTENDED`). Out of scope unless we provision tokens.

---

## 4. The vendor mechanisms (PDF spec, confirmed by the header)

Four mechanisms. C structs below are verbatim from `wtpkcs11t.h` (lines ~404–417),
matching the PDF.

### 4.1 `CKM_VENDOR_BIP32_KEY_PAIR_GEN` (`0x80000006`)
Generate a BIP32 master key (`C_GenerateKeyPair`). **No params.** Result:
`CKK_VENDOR_BIP32` pair. ⚠️ No off-token BIP-39 backup → can’t show a seed; prefer
4.2 for our product.

### 4.2 `CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN` (`0x80000009`) ← **create wallets**
Generate a BIP32 master key **recoverable off-token via a BIP-39 mnemonic**.
```c
typedef struct CK_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN_PARAMS {
    CK_UTF8CHAR_PTR pPassphrase;      // optional BIP-39 passphrase ("25th word")
    CK_ULONG        ulPassphraseLen;  // its length
    CK_ULONG        ulMnemonicLength; // words: one of {12,15,18,21,24}
} CK_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN_PARAMS;
```
Result: `CKK_VENDOR_BIP32` pair; read the words back via `CKA_VENDOR_BIP39_MNEMONIC`
when `CKA_VENDOR_BIP39_MNEMONIC_IS_EXTRACTABLE` is true.

### 4.3 `CKM_VENDOR_BIP32_DERIVE_PRIVATE_FROM_PRIVATE` (`0x80000007`) ← **signing key**
Derive a lower-level **private** key from a private key (`C_DeriveKey`), only on
`CKK_VENDOR_BIP32`.
```c
typedef struct CK_VENDOR_BIP32_DERIVE_PARAMS {
    CK_ULONG_PTR pulDerivationPath;      // path indices, parent → target
    CK_ULONG     ulDerivationPathLength; // count
} CK_VENDOR_BIP32_DERIVE_PARAMS;
```
Hardened levels OR in `0x80000000` (the caller does this — see §5.3). Result:
`CKK_VENDOR_BIP32` private key.

### 4.4 `CKM_VENDOR_BIP32_DERIVE_PUBLIC_FROM_PRIVATE` (`0x80000008`) ← **address**
Derive the **public** key from a private key (`C_DeriveKey`), same
`CK_VENDOR_BIP32_DERIVE_PARAMS`. Result: `CKK_VENDOR_BIP32` public key — read
`CKA_EC_POINT`. **An empty path (`[]`) yields the master public key** (used by the
demos’ key enumeration).

---

## 5. Operation recipes (distilled from the demo code)

### 5.1 Create (seed-backed) — `createWallet`
`C_GenerateKeyPair(CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN, params{ulMnemonicLength=24})`
with token-resident pub/priv templates (`CKA_TOKEN=true`, priv adds
`CKA_PRIVATE=true`, `CKA_DERIVE=true`, `CKA_ID`/`CKA_LABEL`). One-time seed
display: if `CKA_VENDOR_BIP39_MNEMONIC_IS_EXTRACTABLE`, read `CKA_VENDOR_BIP39_MNEMONIC`.

### 5.2 Import existing mnemonic — `importWallet`
Reconstruct the master key **off-token**, then `C_CreateObject`
(`Pkcs11TokenWrapper.importEcdsaKey` + `Bip39WalletCrypto.getMasterKeyAndChainCode`):
```text
seed       = PBKDF2_HMAC_SHA512(mnemonic_utf8, salt="mnemonic"(+passphrase), iters=2048, dkLen=64)
I          = HMAC_SHA512(key="Bitcoin seed", msg=seed)
masterPriv = I[:32];  chainCode = I[32:]
C_CreateObject([
   CKA_CLASS=CKO_PRIVATE_KEY, CKA_KEY_TYPE=CKK_VENDOR_BIP32,
   CKA_TOKEN=true, CKA_PRIVATE=true, CKA_DERIVE=true,
   CKA_VALUE=masterPriv,                     // 32 bytes
   CKA_VENDOR_BIP32_CHAINCODE=chainCode,     // 32 bytes
   CKA_EC_PARAMS=<secp256k1 OID §3>,
   CKA_ID=…, CKA_LABEL=… ])
```
(The demo uses `iters=2048`, salt `"mnemonic"` with no passphrase — standard BIP-39.)

### 5.3 Derive account key + Ethereum address
```text
H = 0x80000000
path = [H|44, H|60, H|0, 0, 0]                 // m/44'/60'/0'/0/0   (ETH coin type 60)
prvAcct = C_DeriveKey(CKM_VENDOR_BIP32_DERIVE_PRIVATE_FROM_PRIVATE{path}, master)
pubAcct = C_DeriveKey(CKM_VENDOR_BIP32_DERIVE_PUBLIC_FROM_PRIVATE{path},  master)
ecPoint = C_GetAttributeValue(pubAcct, CKA_EC_POINT)   // DER OCTET STRING (ANSI X9.62)
XY      = der_unwrap(ecPoint) without 0x04 prefix       // 64 bytes
address = "0x" + keccak256(XY)[-20:]
```

### 5.4 Sign (the device half)
`C_SignInit(CKM_ECDSA, prvAcct)` + `C_Sign(digest32)` → **64-byte `r‖s`**. The
demos sign an arbitrary 32-byte value (`KeyType.ecdsa.signDataLenInBytes == 32`,
`signMechType == CKM_ECDSA`); for Ethereum the 32 bytes are your keccak256 digest
(§7). EdDSA/Ed25519 exists in the demos (`CKM_EDDSA`, no app-side hashing) but is
out of scope for EVM.

---

## 6. NFC / PC-SC transport (the “tap” model)

The token is reached over **PC-SC**, with **NFC** as the reader. This is what
makes “tap + device PIN” a real second factor.

- **Session shape** (iOS `CryptoManager.withToken`): start NFC exchange (shows
  iOS system messages: *wait* → *work* → *stop*) → wait for the token to appear
  on the NFC reader → wrap as a token → run the operation → `logout()` →
  `stopNfc()`. The NFC tap **is** the device-session trigger; `C_Login(CKU_USER,
  devicePin)` is the **device PIN** second factor (distinct from our phone-vault PIN).
- **iOS:** `RtPcscWrapper` Swift package (`RtReader` filtered by `.nfc`,
  `startNfcExchange(...)`, `stopNfc(...)`); Core NFC entitlement required. iOS
  rate-limits NFC — the demo exposes an **NFC cooldown** stream
  (`getNfcCooldown`) you must respect between sessions.
- **Android:** `ru.rutoken.rtpcscbridge` + `pkcs11jna` + `pkcs11wrapper`; token
  presence via **PC-SC slot events** (`token/slotevent/SlotEventProvider`). Native
  `libwtpkcs11ecp.so` is **arm64-v8a only**; **physical device only** (no emulator).
- **Practical:** keep each NFC session short (tap windows are brief and
  rate-limited) — do login + derive + sign within one tap; don’t hold the field
  open waiting on UI.

---

## 7. Ethereum-specific corrections (what the demos leave to us)

The vendor demos are chain-agnostic and sign **arbitrary 32-byte data**, so the
EVM specifics are ours to add on top of the device’s raw `r‖s`:

1. **Curve = secp256k1.** BIP-32 is secp256k1 by definition, so `CKK_VENDOR_BIP32`
   keys are already correct — the demos set `CKA_EC_PARAMS` to the **secp256k1**
   OID (`06 05 2B 81 04 00 0A`). Never use the generic `CKM_EC_KEY_PAIR_GEN`/P-256
   path for the wallet.
2. **Hash = keccak256, signed raw via `CKM_ECDSA`.** Ethereum signs
   `keccak256(RLP(unsigned tx))`; `CKM_SHA256` is SHA-2, a *different* function.
   Compute the 32-byte keccak digest on the phone and pass it to `C_Sign`
   (`CKM_ECDSA` treats its input as the already-computed hash).
3. **Build v / recovery-id + low-s yourself.** `C_Sign` returns 64-byte `r‖s`
   only. Apply low-s (EIP-2: if `s > n/2`, `s = n − s`); compute `yParity ∈ {0,1}`
   by recovering the pubkey and matching the account address; for EIP-1559 the
   signature is `(yParity, r, s)`. RLP-encode the signed tx and pass the bytes to
   `TransactionService.assembleSignedTransfer`. (web3dart already does this for
   local keys; the device just supplies `r‖s`.)
4. **`CKA_EC_POINT` is DER-encoded ANSI X9.62** (per the iOS wrapper comment) —
   unwrap the OCTET STRING to `0x04‖X‖Y` before keccak for the address (§5.3).

---

## 8. How this maps onto the existing code

| Today (simulation) | Phase 10 (real) |
| --- | --- |
| `key_storage/external_device_pkcs11.dart` — `ExternalDevicePkcs11Adapter` + `DemoExternalDevicePkcs11Adapter` (canned `probeSession`/`readPublicAddress`/`signTransactionPreview`). | A **real adapter** with the same interface, backed by FFI/platform-channel to `wtpkcs11ecp` + the PC-SC/NFC bridge. Keep the interface; swap the impl (same DI pattern as the rest of the app). |
| `key_storage/external_device_demo_backend.dart` — wraps a `PhoneSecureVault` delegate + mock lifecycle (`isDeviceAvailable`, `simulateDeviceUnavailable`, `reconnectDevice`, `disconnectSession`, `_beginPkcs11Session`). | Real `ExternalDeviceKeyStorageBackend`: `createWallet`/`importWallet`/`unlock`/sign call the adapter (§5). Lifecycle becomes **NFC presence + `C_OpenSession`/`C_Login`**; `unlock(pin)` → `C_Login(CKU_USER, pin)`. |
| Signing seam `auth/wallet_operation_auth.dart` — `WalletTransactionSigner` (async), today wraps local EIP-1559 signing. | A `Pkcs11TransactionSigner` doing §7.2/§7.3 against the token and returning a `SignedTransfer` via `assembleSignedTransfer`. Contract already async + backend-agnostic — **no interface change**. |
| `ExternalDevicePkcs11OperationKind` (`probeSession`/`readPublicAddress`/`signTransactionPreview`). | Maps to real ops: probe→`C_OpenSession`/find token; readPublicAddress→§5.3; signTransactionPreview→§5.4+§7. Consider adding `createKeyPair`/`importKey`/`readMnemonic`. |

**Rules to keep** (`CLAUDE.md`): `abstract interface class` → nullable ctor arg on
`MobileWalletDemoApp` defaulting to prod → fake for tests. The
`KeyStorageBackend` / `ExternalDeviceKeyStorageBackend` contracts
(create/import/unlock/biometrics/lock + `isDeviceAvailable`) **don’t change** —
Phase 10 is an implementation swap behind them.

---

## 9. Suggested Phase 10 chunking

Small, reviewable steps that keep `main` green (mirrors Phase 9).

- **10.0 — Transport decision & spike.** FFI to `wtpkcs11ecp` vs. a
  platform-channel to the native stacks (iOS `RtPcscWrapper`; Android
  `pkcs11wrapper`/`pkcs11jna`/`rtpcscbridge` + the `.so`). Note: native blobs are
  proprietary, arm64-only, **physical device required**. Record the decision in
  the dev plan.
- **10.1 — Pure-Dart crypto utils** (no device): keccak256 RLP digest, low-s/EIP-2,
  recovery-id, secp256k1 OID, DER `CKA_EC_POINT` → `X‖Y`. Known-vector tests.
- **10.2 — `Pkcs11TransactionSigner` on a fake adapter** that returns a known
  `r‖s`; assert byte-identical output to the local signer for identical inputs.
- **10.3 — Real adapter behind `ExternalDevicePkcs11Adapter`**: init / token
  discovery / NFC session / `C_Login(USER, devicePin)` / teardown, wired into
  `ExternalDeviceDemoBackend`’s lifecycle. Manual/dogfood (no CI token).
- **10.4 — keygen / import / address** (§5.1–5.3) incl. one-time mnemonic display
  via `CKA_VENDOR_BIP39_MNEMONIC`.
- **10.5 — end-to-end device sign** for own-sends **and** Phase 9 inbound WC
  requests (compose with `WalletConnectInboundCoordinator`).
- **10.6 — UX:** real NFC presence/affordances + cooldown handling in the
  external-device branch of `WalletFlowScreen` / `WalletFlowController`.

---

## 10. Open questions to confirm on a real token

(Several earlier questions are now **answered**: mechanism hex values = §3;
attribute base = `0x80005000` = §3 ⚠️; `CKA_EC_POINT` = DER X9.62 = §7.4; hardened
path convention = caller ORs `0x80000000` = §5.3.)

1. **`C_Sign` output format** on this token — raw `r‖s` (64 B) is expected for
   `CKM_ECDSA`; confirm it isn’t DER-wrapped before feeding §7.3.
2. **Mnemonic extractability policy** — is `CKA_VENDOR_BIP39_MNEMONIC` readable
   only once / only right after generation? Affects the one-time-seed-display UX.
3. **Transport reach** under the environment network policy and per platform
   (Android NFC vs. iOS Core NFC entitlement + cooldown) — feeds 10.0.
4. **Passphrase ("25th word")** — expose `pPassphrase` in our UX or not?
5. **SDK/library distribution** — how we obtain `wtpkcs11ecp` for CI-less manual
   builds, and the device-procurement path (`partners@rutoken.ru`).

---

## 11. References

- `rutoken-demo-wallet` (iOS) & `rutoken-demo-wallet-android` (BSD-2-Clause) —
  Aktiv-Soft JSC official demos; vendor headers in `wtpkcs11ecp.xcframework`.
- PDF *«Механизмы расширения»* (vendor BIP32/BIP39 PKCS#11 mechanisms).
- `github.com/mescheryakov1/wallet-tool` (MIT) — Python reference (⚠️ §3).
- BIP-32 (HD, secp256k1), BIP-39 (mnemonics), BIP-44 / SLIP-0044 (ETH = 60).
- EIP-1559 (type-2 tx), EIP-2 (low-s) — already implemented for the local signer;
  the device signer must match its output byte-for-byte.
- This repo: `key_storage/external_device_demo_backend.dart`,
  `key_storage/external_device_pkcs11.dart`, `auth/wallet_operation_auth.dart`,
  `transactions/transaction_service.dart` (`assembleSignedTransfer`),
  `docs/development-plan.md` (Phase 10).
