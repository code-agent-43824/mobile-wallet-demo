# NFC / PKCS#11 hardware-signer integration notes (Phase 10 reference)

> **Audience:** any coding agent (Claude Code or other) who will turn the
> simulated external-NFC device (Phase 7) into a **real** PKCS#11/NFC custody
> signer in Phase 10. This file distills the vendor crypto-wallet PKCS#11
> extension and a working reference tool into a concrete, opinionated plan that
> fits *this* repo's architecture. Read it together with
> `docs/development-plan.md` (Phase 10) and `AGENTS.md`.
>
> **Status:** research/reference only. **No real PKCS#11 or NFC code exists
> yet** — Phase 7 ships a *simulation* (`ExternalDeviceDemoBackend`). Nothing in
> this file has been wired in. Numeric constants marked “confirmed” come from a
> real source (see Provenance); everything else must be checked against the
> vendor SDK headers before you rely on it.

---

## 0. TL;DR for the impatient

For an **Ethereum/EVM** wallet, the right path on these tokens is the **vendor
BIP32/BIP39 mechanisms** — *not* the generic `CKM_EC_KEY_PAIR_GEN` path:

1. **Create** a seed-backed key: `C_GenerateKeyPair(CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN)`
   → a `CKK_VENDOR_BIP32` master key pair that can be **shown/exported as a
   BIP-39 mnemonic** (our product requires showing the seed phrase — this is the
   only mechanism that allows it).
2. **Import** an existing wallet: `C_CreateObject` of a `CKK_VENDOR_BIP32`
   private key from a 32-byte master private key + 32-byte chain code.
3. **Derive** the account key at `m/44'/60'/0'/0/0`:
   `CKM_VENDOR_BIP32_DERIVE_PRIVATE_FROM_PRIVATE` (for signing) and
   `CKM_VENDOR_BIP32_DERIVE_PUBLIC_FROM_PRIVATE` (for the address).
4. **Address** = `keccak256(uncompressed_pubkey_XY)[-20:]` from the derived
   public key’s `CKA_EC_POINT`.
5. **Sign** an EIP-1559 tx: compute `keccak256(RLP(unsigned tx))` **on the
   phone**, then `C_SignInit(CKM_ECDSA, derivedPrivKey)` + `C_Sign(hash)` →
   raw `r‖s` (64 bytes). **You** then do low-s normalization (EIP-2) + recovery
   id, RLP-encode the signed tx, and hand the bytes to
   `TransactionService.assembleSignedTransfer`.

Three Ethereum gotchas that the generic PKCS#11 examples get “wrong” for us
(details in §6): the curve must be **secp256k1** (BIP32 is secp256k1 by
definition — good), the signed digest must be **keccak256** (not `CKM_SHA256` /
SHA-256), and you must derive **v / recovery id + low-s** yourself because
`CKM_ECDSA` returns only `r‖s`.

---

## 1. Provenance & sources

| Source | What it gave us | Access |
| --- | --- | --- |
| **Attached PDF** — *“Механизмы расширения”*, A. Osminina, exported 2025‑10‑08 | The **authoritative vendor mechanism spec**: the four `CKM_VENDOR_BIP32*` mechanisms, their purpose, and their exact C param structs. Quoted verbatim in §4. | Extracted locally with `pdftotext` (Russian-language). |
| **owncloud.aktiv-company.ru** links (×2) provided by the owner | Presumed to be the same vendor wiki the PDF was exported from. | **Could not be fetched** (HTTP 503 from this environment). The attached PDF is treated as the canonical copy of that content. |
| **github.com/mescheryakov1/wallet-tool** (MIT) | A working Python reference CLI that drives these mechanisms over a real `wtpkcs11ecp` library via `ctypes`. Source of the **confirmed numeric constants** (§3) and the operation recipes (§5). | Public GitHub. |

**Vendor library:** `wtpkcs11ecp` (an Aktiv/Rutoken-family PKCS#11 “ecp”
provider with crypto-wallet vendor extensions). The reference tool loads it as
the PKCS#11 module.

> ⚠️ **If you need the owncloud pages’ exact wording** (e.g. error-code tables or
> any mechanism not in the attached PDF), ask the owner to re-share or paste the
> text — those two links were unreachable when this doc was written.

---

## 2. The reference tool (`wallet-tool`) at a glance

A small Python CLI that proves out the full lifecycle against a real token. Use
it as the executable spec for the byte-level details Dart will have to
reproduce.

- **Files:** `main.py` (CLI), `commands.py` (the lifecycle flows + attribute
  templates), `pkcs11.py` (thin wrapper), `pkcs11_definitions.py` (`ctypes`
  `C_*` function signatures), `pkcs11_structs.py` (all the constants — see §3).
- **CLI surface (mirrors the operations we need):**
  `--list-wallets`, `--show-wallet-info`, `--generate-key [curve]`,
  `--import-key`, `--list-keys`, `--delete-key`, `--change-pin`,
  `--get-mnemonic`, with `--wallet-id`, `--pin`, `--key-id`, `--key-label`,
  `--force`.
- **PIN model:** `C_Login(CKU_USER, pin)` — a single user PIN per token. This is
  the natural home for our **device PIN as a true second factor** (distinct from
  the phone-vault PIN; see the Phase 10 goal).

---

## 3. Constants (confirmed from `pkcs11_structs.py`)

These are copied from the reference tool and are safe to rely on. Standard
PKCS#11 values match the OASIS spec; the vendor block is the interesting part.

### Object classes / key types

```
CKO_PUBLIC_KEY                 = 0x00000002
CKO_PRIVATE_KEY                = 0x00000003

CKK_EC                         = 0x00000003   # standard secp256k1/r1 ECDSA keys
CKK_EC_EDWARDS                 = 0x00000040   # Ed25519
CKK_GOSTR3410                  = 0x00000030
CKK_VENDOR_DEFINED             = 0x80000000
CKK_VENDOR_BIP32               = 0x80000002   # ← the wallet key type
```

### Mechanisms

```
CKM_SHA256                     = 0x00000250
CKM_EC_KEY_PAIR_GEN            = 0x00001040   # generic EC keygen (NOT for our wallet)
CKM_ECDSA                      = 0x00001041   # raw ECDSA over a pre-hashed digest
CKM_EC_EDWARDS_KEY_PAIR_GEN    = 0x00001055   # Ed25519 keygen
CKM_GOSTR3410_KEY_PAIR_GEN     = 0x00001200
CKM_GOSTR3410                  = 0x00001201
CKM_GOSTR3411_12_256           = 0x00001225
CKM_VENDOR_DEFINED             = 0x80000000
CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN = 0x80000009   # ← seed-backed keygen
```

### Vendor attributes

```
CKA_VENDOR_DEFINED                       = 0x80000000
CKA_VENDOR_BIP32_CHAINCODE               = 0x85000000   # 32-byte chain code
CKA_VENDOR_BIP32_ID                      = 0x85000001
CKA_VENDOR_BIP32_FINGERPRINT             = 0x85000002
CKA_VENDOR_BIP39_MNEMONIC_TRACE          = 0x85000003
CKA_VENDOR_BIP39_MNEMONIC                = 0x85000004   # the mnemonic words
CKA_VENDOR_BIP39_MNEMONIC_IS_EXTRACTABLE = 0x85000005   # gate before reading ^
```

### Standard attributes used by the templates

```
CKA_CLASS=0x00 CKA_TOKEN=0x01 CKA_PRIVATE=0x02 CKA_LABEL=0x03
CKA_VALUE=0x11 CKA_KEY_TYPE=0x100 CKA_ID=0x102
CKA_DERIVE=0x10C CKA_EC_PARAMS=0x180 CKA_EC_POINT=0x181
```

### Session / misc

```
CKU_USER=1  CKR_OK=0x00  CKF_SERIAL_SESSION=0x02  CKF_RW_SESSION=0x04
```

> **Not present in the reference source** (document by name only — get the hex
> from the vendor `wtpkcs11ecp` headers before use):
> `CKM_VENDOR_BIP32_KEY_PAIR_GEN`,
> `CKM_VENDOR_BIP32_DERIVE_PRIVATE_FROM_PRIVATE`,
> `CKM_VENDOR_BIP32_DERIVE_PUBLIC_FROM_PRIVATE`. They all live in the
> `CKM_VENDOR_DEFINED` (`0x80000000`) range alongside the confirmed
> `…WITH_BIP39…= 0x80000009`. **Do not guess the values.**

---

## 4. The vendor mechanisms (verbatim from the spec PDF)

The PDF documents **four** mechanisms. Reproduced faithfully (Russian source;
English gloss added). These are the contract Phase 10 must honor.

### 4.1 `CKM_VENDOR_BIP32_KEY_PAIR_GEN`
- **Назначение / Purpose:** “Генерация BIP32 мастер-ключа.” Generate a BIP32
  master key. Used with `C_GenerateKeyPair`.
- **Параметры / Params:** none (“Механизм не использует параметров.”).
- **Результат / Result:** a key pair of type `CKK_VENDOR_BIP32`.
- ⚠️ Produces a master key **with no off-token BIP-39 backup** → you cannot show
  a seed phrase. For our product, prefer 4.2 instead (we must display the seed).

### 4.2 `CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN`  ← **use this to create wallets**
- **Purpose:** “Генерация BIP32 мастер-ключа с возможностью восстановления вне
  токена по BIP39.” A BIP32 master key that **can be recovered off-token via a
  BIP-39 mnemonic**.
- **Params** — struct:
  ```c
  typedef struct CK_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN_PARAMS {
      CK_UTF8CHAR_PTR pPassphrase;     // optional BIP-39 passphrase ("25th word")
      CK_ULONG        ulPassphraseLen; // its length
      CK_ULONG        ulMnemonicLength;// words: one of {12, 15, 18, 21, 24}
  } CK_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN_PARAMS;
  ```
- **Result:** a `CKK_VENDOR_BIP32` key pair recoverable via its mnemonic. Read
  the words back with `CKA_VENDOR_BIP39_MNEMONIC` (only when
  `CKA_VENDOR_BIP39_MNEMONIC_IS_EXTRACTABLE` is true).

### 4.3 `CKM_VENDOR_BIP32_DERIVE_PRIVATE_FROM_PRIVATE`  ← **derive signing key**
- **Purpose:** derive a lower-level **private** key from a private key. Only
  valid on `CKK_VENDOR_BIP32` keys (`C_DeriveKey`).
- **Params** — struct:
  ```c
  typedef struct CK_VENDOR_BIP32_DERIVE_PARAMS {
      CK_ULONG_PTR pulDerivationPath;      // array of path indices, parent→…
      CK_ULONG     ulDerivationPathLength; // number of indices
  } CK_VENDOR_BIP32_DERIVE_PARAMS;
  ```
  The path is the set of indices from the parent (the key you call this on) down
  to the target. For `m/44'/60'/0'/0/0` the hardened levels use the BIP-32
  hardened offset `0x80000000` (i.e. `44' = 44 + 0x80000000`).
- **Result:** a `CKK_VENDOR_BIP32` **private** key.

### 4.4 `CKM_VENDOR_BIP32_DERIVE_PUBLIC_FROM_PRIVATE`  ← **derive address**
- **Purpose:** derive the **public** key (same or lower level) from a private
  key. Only `CKK_VENDOR_BIP32` (`C_DeriveKey`).
- **Params:** same `CK_VENDOR_BIP32_DERIVE_PARAMS` as 4.3.
- **Result:** a `CKK_VENDOR_BIP32` **public** key — read `CKA_EC_POINT` to get
  the curve point for the Ethereum address.

---

## 5. Operation recipes (from the reference tool)

Pseudo-code distilled from `commands.py`. Templates are `(CKA_*, value)` lists
passed to `C_GenerateKeyPair` / `C_CreateObject`. Confirm exact templates
against the tool + vendor headers when implementing.

### 5.1 Create (seed-backed) — `createWallet`
```text
session = C_OpenSession(slot, SERIAL|RW); C_Login(USER, devicePin)
params  = CK_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN_PARAMS{
            pPassphrase=passphrase?, ulMnemonicLength=24 }
pub, prv = C_GenerateKeyPair(
   mech   = CKM_VENDOR_BIP32_WITH_BIP39_KEY_PAIR_GEN(params),
   pubTpl = [CKA_TOKEN=true, CKA_LABEL=…, CKA_ID=…],
   prvTpl = [CKA_TOKEN=true, CKA_PRIVATE=true, CKA_DERIVE=true,
             CKA_LABEL=…, CKA_ID=…])
# one-time seed display:
if C_GetAttributeValue(prv, CKA_VENDOR_BIP39_MNEMONIC_IS_EXTRACTABLE):
    mnemonic = C_GetAttributeValue(prv, CKA_VENDOR_BIP39_MNEMONIC)
```

### 5.2 Import existing mnemonic — `importWallet`
The reference tool reconstructs the master key **off-token** and imports it:
```text
seed        = PBKDF2_HMAC_SHA512(mnemonic, "mnemonic"+passphrase, 2048, dkLen=64)
I           = HMAC_SHA512(key="Bitcoin seed", msg=seed)
masterPriv  = I[:32]            # 32-byte master private key
chainCode   = I[32:]           # 32-byte chain code
C_CreateObject([
   CKA_CLASS=CKO_PRIVATE_KEY, CKA_KEY_TYPE=CKK_VENDOR_BIP32,
   CKA_TOKEN=true, CKA_PRIVATE=true, CKA_DERIVE=true,
   CKA_VALUE=masterPriv,                       # 32 bytes
   CKA_VENDOR_BIP32_CHAINCODE=chainCode,       # 32 bytes
   CKA_EC_PARAMS=<secp256k1 OID, see §6>,
   CKA_LABEL=…, CKA_ID=… ])
```
> Note: this import path puts the raw master private key on the token from the
> host. The 4.2 generate path is preferable when the token can generate +
> back-up internally; use import only to migrate an existing phone-vault seed.

### 5.3 Derive account key + address
```text
path = [44|H, 60|H, 0|H, 0, 0]   where H = 0x80000000   # m/44'/60'/0'/0/0
prvAcct = C_DeriveKey(CKM_VENDOR_BIP32_DERIVE_PRIVATE_FROM_PRIVATE(path), master, …)
pubAcct = C_DeriveKey(CKM_VENDOR_BIP32_DERIVE_PUBLIC_FROM_PRIVATE(path),  master, …)
point   = C_GetAttributeValue(pubAcct, CKA_EC_POINT)   # DER OCTET STRING → 65B 0x04||X||Y
address = "0x" + keccak256(point.XY /*64 bytes, drop 0x04*/)[-20:]
```

### 5.4 Sign (generic vs. Ethereum)
The reference tool’s generic flow is `C_SignInit(CKM_SHA256 ⊕ CKM_ECDSA)` then
`C_Sign` (single- or two-stage `C_SignUpdate`/`C_SignFinal`). **For Ethereum,
override the hashing — see §6.2.**

---

## 6. Ethereum-specific corrections (the important part)

The vendor mechanisms and the reference tool are chain-agnostic. Three places
where the “obvious” PKCS#11 usage is wrong for an EVM signer:

### 6.1 Curve = **secp256k1**, not P-256
- BIP-32 is defined **only over secp256k1**, so `CKK_VENDOR_BIP32` keys are
  already secp256k1 — using the vendor BIP32 path gives us the right curve for
  free. **Do not** use the generic `CKM_EC_KEY_PAIR_GEN` path for the wallet.
- The reference tool’s generic `--generate-key` EC example uses the **P-256 /
  prime256v1** OID — fine for its demo, **wrong for Ethereum**. If you ever set
  `CKA_EC_PARAMS` explicitly (e.g. the §5.2 import), use the secp256k1 OID.
- DER OIDs for `CKA_EC_PARAMS`:
  - **secp256k1** (Ethereum): `06 05 2B 81 04 00 0A`  (OID 1.3.132.0.10)
  - secp256r1 / P-256 (the tool’s generic demo): `06 08 2A 86 48 CE 3D 03 01 07`
  - Ed25519 (not used by EVM): `06 03 2B 65 70`

### 6.2 Hash = **keccak256**, signed raw via `CKM_ECDSA` (not `CKM_SHA256`)
- Ethereum signs `keccak256(RLP(unsigned tx))`. PKCS#11 `CKM_SHA256` is SHA-2,
  **not** keccak — they are different functions. Do **not** let the token hash.
- Compute the 32-byte keccak256 digest **on the phone**, then sign it raw:
  `C_SignInit(CKM_ECDSA, prvAcct)` → `C_Sign(digest)`. `CKM_ECDSA` treats its
  input as the already-computed hash, which is exactly what we want.

### 6.3 You must build **v / recovery id** and apply **low-s**
- `CKM_ECDSA` returns a **64-byte `r‖s`** with no recovery id.
- Apply **low-s normalization** (EIP-2): if `s > n/2`, set `s = n − s`.
- Compute the **recovery id** `yParity ∈ {0,1}`: recover the public key for each
  candidate and pick the one matching the account’s known pubkey/address.
- For EIP-1559 (type `0x02`) the signature is `(yParity, r, s)`. RLP-encode the
  full signed tx and pass the bytes to
  `TransactionService.assembleSignedTransfer`. The keccak/RLP/recovery math is
  the **only new crypto** the device signer needs (web3dart already does this
  for local keys; the device just supplies `r‖s`).

---

## 7. How this maps onto the existing code

Phase 7 already shaped the seams so a real backend can drop in. The relevant
files and the exact swap points:

| Today (simulation) | Phase 10 (real) |
| --- | --- |
| `key_storage/external_device_pkcs11.dart` — `ExternalDevicePkcs11Adapter` interface + `DemoExternalDevicePkcs11Adapter` (ops: `probeSession`, `readPublicAddress`, `signTransactionPreview` returning canned strings). | A **real adapter** implementing the same `ExternalDevicePkcs11Adapter` interface, backed by FFI to `wtpkcs11ecp` (or an NFC APDU bridge). Keep the interface; replace the impl — same DI pattern as the rest of the app. |
| `key_storage/external_device_demo_backend.dart` — `ExternalDeviceDemoBackend` wraps a `PhoneSecureVault` delegate + mock device lifecycle (`isDeviceAvailable`, `simulateDeviceUnavailable`, `reconnectDevice`, `disconnectSession`, `_beginPkcs11Session`) and routes ops through the adapter. | A real `ExternalDeviceKeyStorageBackend` whose `createWallet`/`importWallet`/`unlock`/sign call the real adapter (§5). The lifecycle methods become **actual NFC presence + `C_OpenSession`/`C_Login`**, not stored booleans. `unlock(pin)` → `C_Login(CKU_USER, pin)`. |
| Signing seam: `auth/wallet_operation_auth.dart` — `WalletTransactionSigner` (async `Future<SignedTransfer>`), produced by `WalletOperationAuthorizer`; the external-device signer currently wraps **local** EIP-1559 signing of locally-held material. | A `Pkcs11TransactionSigner` that does §6.2/§6.3 against the token and returns a `SignedTransfer` via `assembleSignedTransfer`. The signer contract is already async and backend-agnostic — no interface change needed. |
| `ExternalDevicePkcs11OperationKind` enum (`probeSession`, `readPublicAddress`, `signTransactionPreview`). | Maps cleanly to real ops: `probeSession`→`C_OpenSession`/find token; `readPublicAddress`→ §5.3 derive-public; `signTransactionPreview`→ real §5.4/§6 sign. Consider adding `createKeyPair`/`importKey`/`readMnemonic` kinds. |

**Architectural rules to keep (from `CLAUDE.md`):** define an `abstract interface
class`, inject it as a nullable constructor arg on `MobileWalletDemoApp`
defaulting to the production impl, and provide a fake for tests. The current
`KeyStorageBackend` / `ExternalDeviceKeyStorageBackend` contracts
(create/import/unlock/biometrics/lock + `isDeviceAvailable`) **do not need to
change** — Phase 10 is an implementation swap behind them.

---

## 8. Suggested Phase 10 chunking

Small, reviewable steps that keep `main` green (mirrors how Phase 9 was run).
Each chunk: worklog entry first, then code + tests, then record results.

- **10.0 — Decide the transport.** FFI to `wtpkcs11ecp` (desktop/Android via
  `dart:ffi` + the native lib) vs. an NFC APDU bridge to the token’s PKCS#11
  applet. This gates everything below. Record the decision in the dev plan.
- **10.1 — Constants + curve/OID + recovery-id utilities** (pure Dart, no
  device): keccak256 RLP digest, low-s normalization, recovery-id computation,
  secp256k1 OID. Unit-test against known vectors. Lowest-risk, highest reuse.
- **10.2 — `Pkcs11TransactionSigner`** on a **fake** PKCS#11 adapter that
  returns a known `r‖s` for a test key; assert it produces the same signed tx as
  the local signer for identical inputs. (Test-only; reuses the §6 utilities.)
- **10.3 — Real adapter behind `ExternalDevicePkcs11Adapter`**: `C_Initialize`,
  slot/token discovery, `C_OpenSession`, `C_Login(USER, devicePin)`, session
  teardown — wired into `ExternalDeviceDemoBackend`’s lifecycle methods. Needs a
  real token to validate (mark as manual/dogfood; no CI device).
- **10.4 — Keygen / import / address**: §5.1, §5.2, §5.3 against the token,
  including one-time mnemonic display via `CKA_VENDOR_BIP39_MNEMONIC`.
- **10.5 — End-to-end device sign**: route a prepared transfer (own-send **and**
  a Phase 9 inbound WC request) through the device; “tap + device PIN” becomes a
  genuine confirmation step. Compose with `WalletConnectInboundCoordinator`.
- **10.6 — UX**: real NFC presence/affordances in the external-device branch of
  `WalletFlowScreen` / `WalletFlowController` (replace the simulated
  online/offline toggles).

---

## 9. Open questions to resolve against the vendor SDK / a real token

1. **Numeric values** of `CKM_VENDOR_BIP32_KEY_PAIR_GEN` and the two
   `…DERIVE_*_FROM_PRIVATE` mechanisms (not in the reference source — §3).
2. **`CKA_EC_POINT` encoding** returned by `…DERIVE_PUBLIC_FROM_PRIVATE`:
   DER-wrapped `OCTET STRING` vs. raw `0x04‖X‖Y`? (Unwrap accordingly in §5.3.)
3. **`r‖s` vs. DER** output of `C_Sign(CKM_ECDSA)` on this token (PKCS#11
   `CKM_ECDSA` is specified as raw `r‖s`, but confirm).
4. **Hardened index convention** for `pulDerivationPath` — does the token expect
   the `0x80000000` offset added by the caller (assumed in §5.3) or a separate
   hardened flag?
5. **Mnemonic extractability policy**: is `CKA_VENDOR_BIP39_MNEMONIC` readable
   only once / only right after generation? Affects our one-time-seed-display UX.
6. **Transport reach** under the environment network policy and on each target
   platform (Android NFC vs. desktop USB/PCSC) — see 10.0.
7. **Passphrase ("25th word")** support in our UX — the mechanism accepts one
   (`pPassphrase`); decide whether to expose it.

---

## 10. References

- Attached PDF: *Механизмы расширения* (vendor BIP32/BIP39 PKCS#11 mechanisms).
- `github.com/mescheryakov1/wallet-tool` (MIT) — Python reference CLI over
  `wtpkcs11ecp`.
- BIP-32 (HD wallets, secp256k1), BIP-39 (mnemonics), BIP-44 (`m/44'/60'/0'/0/0`).
- EIP-1559 (type-2 tx), EIP-2 (low-s), EIP-155 (chain id) — already implemented
  for the local signer; the device signer must match its output byte-for-byte.
- This repo: `key_storage/external_device_demo_backend.dart`,
  `key_storage/external_device_pkcs11.dart`, `auth/wallet_operation_auth.dart`,
  `transactions/transaction_service.dart` (`assembleSignedTransfer`),
  `docs/development-plan.md` (Phase 10).
