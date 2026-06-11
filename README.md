# mobile-wallet-demo

Минимальный демо-проект Flutter для будущего мобильного криптокошелька.

## Что уже есть

- Flutter-проект с платформами: Android, iOS, Windows x64
- Базовый Secure Vault foundation для phone backend
- Полноценный onboarding/auth shell:
  - welcome screen
  - выбор create / import
  - обязательный PIN setup
  - one-time seed display flow
  - biometric choice flow
  - реальный biometric unlock на Android/iOS
  - имитация biometric unlock на Windows
  - locked / unlocked app states
- Read-only EVM foundation:
  - Ethereum Mainnet + Sepolia
  - публичный RPC provider layer с fallback
  - чтение native balance
  - чтение latest base fee
  - чтение token balances через публичный explorer API
  - чтение recent transaction history
  - локальный кэш последнего успешного snapshot для offline/fallback сценария
  - подготовка перевода: asset selection, address validation, amount entry, gas preview
  - локальная подпись prepared transaction
  - загрузка nonce через публичный RPC
  - RPC broadcaster abstraction для raw transaction submission
  - UI-состояния отправки: pending / success / failure
  - post-submit transaction tracking без блокировки UI
  - retry/replacement flow с автоматическим gas bump для underpriced ошибок
  - ручное обновление данных
- Контракты для `KeyStorageBackend`, модель выбора backend и совместимый signing/auth foundation под будущий внешний hardware backend
- Demo runtime path для внешнего backend: simulated external device, отдельная UX-ветка и отдельный auth/signing путь без реального NFC SDK
- Unit- и widget-тесты для ключевых flow
- GitHub Actions для сборки и публикации артефактов
- Артефакты iOS / Windows без двойной упаковки

## Версионирование

- Текущая версия: `v1.19.0+30`
- По договорённости в этом проекте дальше повышаем minor-версию с каждым функциональным шагом

## Что покрывает текущий этап

- архитектурный skeleton проекта
- secure vault foundation
- onboarding/auth shell
- генерация новой BIP-39 seed phrase
- импорт существующей seed phrase
- one-time показ seed-фразы после создания нового кошелька
- хранение seed в зашифрованном виде
- derivation первого EVM-адреса (`m/44'/60'/0'/0/0`)
- locked / unlocked state для приложения
- biometric unlock после PIN setup: реальный на Android/iOS, имитационный на Windows
- выбор между Ethereum Mainnet и Sepolia
- read-only чтение нативного баланса и base fee из публичных RPC
- fallback между несколькими RPC endpoints
- read-only чтение token balances из публичного explorer layer
- read-only экран recent transaction history
- локальный cache fallback для последнего успешного blockchain snapshot
- send preparation screen с address validation, amount entry, asset selection и preview gas/fee
- локальная EIP-1559 подпись native/ERC-20 transfer после одного auth flow на операцию
- загрузка nonce через public RPC перед подписанием
- raw transaction submission abstraction с публичным RPC broadcaster
- видимые UI-состояния отправки: pending / success / failure
- post-submit transaction tracking без блокировки отправочного UI
- retry/replacement flow с повышением gas price при underpriced reject
- foundation для multi-backend runtime: selection model + backend-compatible signing/auth contracts
- simulated external-device flow: backend selection, device-style lock/unlock UX и отдельный signer runtime path
- mock device lifecycle: online/offline availability, reconnect, session disconnect и error-state handling для external backend
- security hardening: DEK-схема хранения seed (PIN не персистится), биометрия через отдельный gated secret store, PBKDF2 600k + lockout после серии неверных PIN
- transaction-layer cleanup: общий базовый signer, запас по base fee, тесты на failure-отправку и реконсиляцию nonce

## Артефакты CI

Workflow публикует скачиваемые артефакты так, чтобы при скачивании с GitHub был нужен только один `unzip`:

- Android: `app-release.apk`
- iOS Simulator: `ios-simulator-app.zip` — внутри одна папка `Mobile Wallet Demo.app` (см. раздел «iOS artifacts»)
- iOS Device: `ios-device-build.zip` — **неподписанный** device-build (технический артефакт; см. «iOS artifacts»)
- Windows x64: один архив GitHub Artifact с содержимым `Release/` внутри

## iOS artifacts

CI собирает два независимых iOS-артефакта (параллельные job'ы после `validate`):
`ios-simulator-app` и `ios-device-build`.

### 1. Запуск в iOS Simulator (на Mac)

1. Открой нужный запуск в GitHub → вкладка **Actions** → job **iOS Simulator build**.
2. Скачай артефакт **`ios-simulator-app.zip`**.
3. Распакуй — внутри одна папка **`Mobile Wallet Demo.app`** (готовый `.app` bundle, а не набор файлов
   `Info.plist` / `Runner` / `Frameworks` / `Assets.car`).
4. Запусти **Simulator** (Xcode → Open Developer Tool → Simulator) и дождись загрузки симулятора.
5. Установи приложение одним из способов:
   - перетащи `Mobile Wallet Demo.app` на окно запущенного симулятора; **или**
   - в Finder правый клик по `Mobile Wallet Demo.app` → **Share / Поделиться** → **Simulator** → выбери
     запущенный симулятор.

Так приложение можно посмотреть на Mac без Apple-аккаунта и без подписи.

### 2. Запуск на реальном iPhone / iPad

Артефакт **`ios-device-build.zip`** содержит **неподписанный** device-build (`Mobile Wallet Demo.app`) —
это технический артефакт. **Установить его на реальное устройство без подписи нельзя.**

Способы запустить на устройстве:

- **Официальный бесплатный способ (рекомендуется):** открой проект в **Xcode** на Mac, в *Signing &
  Capabilities* выбери свой **Personal Team** (бесплатный Apple ID), подключи iPhone/iPad кабелем и нажми
  **Run**. Xcode сам подпишет сборку development-сертификатом и provisioning profile.
- **Через CI с подписью:** device-артефакт можно подписать в GitHub Actions, **только** если заранее заданы
  signing-credentials в *Settings → Secrets and variables → Actions* (certificate + provisioning profile как
  секреты). Без них job намеренно собирает unsigned-сборку и пишет об этом в лог. Никакие Apple ID, пароли,
  сертификаты или профили в репозиторий не коммитятся — он публичный.

Ограничения (честно):

- Simulator-артефакт запускается только в iOS Simulator на Mac, не на реальном устройстве.
- Для реального iPhone/iPad сборку нужно подписать Apple development certificate + provisioning profile.
- С **бесплатным** Apple Developer account самый надёжный официальный путь — открыть проект в Xcode, выбрать
  Personal Team и нажать **Run**.
- GitHub-hosted runner **не сможет** сам «подключиться» к твоему бесплатному Apple Developer account без
  заранее подготовленных signing-credentials в Secrets. Обычный IPA из GitHub Actions нельзя просто скачать и
  поставить на iPhone без подписи.

## Локальный запуск

```bash
flutter pub get
flutter run
```
