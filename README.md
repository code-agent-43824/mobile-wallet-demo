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

- Текущая версия: `v1.27.0+38`
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
  **Run**. Xcode сам подпишет сборку development-сертификатом и provisioning profile. Пошаговая
  инструкция — в разделе «Run on real iPhone/iPad with free Apple Account» ниже.
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

## Run on real iPhone/iPad with free Apple Account

Пошаговая инструкция, чтобы собрать и запустить приложение на своём iPhone/iPad с **бесплатным**
Apple ID (Personal Team) — через Xcode, без платного Apple Developer Program.

**Что понадобится:** Mac с **Xcode** и **Flutter `3.41.7`** — та же версия, что в CI (см.
`.github/workflows/ci.yml` и файл `.fvmrc`); на других версиях сборка может вести себя иначе.

1. **Установи Xcode** из Mac App Store и открой его хотя бы раз (доустановит компоненты командной строки).
2. **Установи Flutter `3.41.7`.** Через [fvm](https://fvm.app): `fvm install 3.41.7 && fvm use 3.41.7`
   (версия уже зафиксирована в `.fvmrc`), либо вручную поставь этот релиз и проверь `flutter --version`.
3. **Склонируй репозиторий** и зайди в папку проекта:
   ```bash
   git clone <repo-url>
   cd mobile-wallet-demo
   ```
4. **Поставь зависимости и подготовь iOS-проект для Xcode:**
   ```bash
   flutter pub get
   flutter build ios --config-only   # ставит CocoaPods и настраивает workspace; подписи не требует
   ```
   Шаг `--config-only` важен: он выполняет `pod install` (проект использует нативные плагины
   `flutter_secure_storage` и `local_auth`) и дописывает в `Runner.xcworkspace` ссылку на `Pods`.
5. **Открой `ios/Runner.xcworkspace`** в Xcode — именно `.xcworkspace`, не `.xcodeproj` (иначе не
   подхватятся CocoaPods).
6. Выбери проект **Runner** → target **Runner** → вкладку **Signing & Capabilities**:
   - включи **Automatically manage signing** (в проекте уже выставлено `Automatic`);
   - в поле **Team** выбери свой **Personal Team** — твой бесплатный Apple ID (при необходимости добавь
     аккаунт через Xcode → Settings → Accounts).
7. **Замени Bundle Identifier.** В репозитории стоит нейтральный placeholder
   **`com.example.mobileWalletDemo`**; Apple требует **глобально уникальный** id, поэтому поменяй его на
   свой — например `com.<твой-ник>.mobileWalletDemo`. (Подписать `com.example.*` бесплатным аккаунтом не
   получится.)
8. **Подключи iPhone/iPad** кабелем и подтверди на устройстве **Trust This Computer**.
9. **Включи Developer Mode** на устройстве (iOS 16+): *Settings → Privacy & Security → Developer Mode → On*,
   затем перезагрузи устройство и подтверди включение.
10. В Xcode выбери своё устройство в выпадающем списке вверху и нажми **Run** (⌘R).
11. **На первом запуске** разреши свой dev-сертификат на устройстве: *Settings → General → VPN & Device
    Management → <твой Apple ID> → Trust*. После этого приложение запустится.

**Полезно знать:**
- Сборка с бесплатным аккаунтом подписана development-сертификатом и **живёт ~7 дней** — потом просто
  снова нажми **Run**, чтобы переустановить.
- Target **RunnerTests** запуску приложения не мешает: при **Run** он не собирается (только при **Test**).
- Если Xcode жалуется на CocoaPods или `Generated.xcconfig` — повтори `flutter pub get` и
  `flutter build ios --config-only`, затем заново открой `Runner.xcworkspace` (как запасной вариант —
  `cd ios && pod install`).

## Run iOS app on Apple Silicon Mac

На **Apple Silicon Mac** (M1/M2/M3…) этот же iOS-таргет можно запускать прямо на macOS как
**«Designed for iPad / iPhone»** — без отдельной macOS-сборки и без Simulator. В проекте это уже включено
(`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES` на target `Runner`; Mac Catalyst **не** используется,
отдельного Flutter macOS-таргета и папки `macos/` нет).

1. Открой `ios/Runner.xcworkspace` в Xcode (сначала `flutter pub get` и `flutter build ios --config-only`
   для CocoaPods — как в разделе про iPhone выше).
2. Выбери target **Runner**.
3. **Signing & Capabilities** → выбери свой **Personal Team** (бесплатный Apple ID); при необходимости замени
   Bundle Identifier на свой уникальный (см. iOS-раздел выше).
4. В выпадающем списке destination вверху выбери **My Mac (Designed for iPad)** (или **My Mac (Designed for
   iPhone)**).
5. Нажми **Run** (⌘R) — приложение откроется окном на Mac.

Важно:
- Работает **только на Apple Silicon Mac** — на Intel-маках такой destination недоступен.
- Это **не** iOS Simulator и **не** нативная macOS-сборка: запускается тот же iOS-бинарь (`iphoneos`/arm64)
  на macOS как «Designed for iPad/iPhone».
- Отдельный Flutter macOS-таргет для этого **не нужен**. Часть чисто-iOS возможностей (например, биометрия)
  на Mac может вести себя иначе — это ограничение режима «Designed for iPad», а не проекта.

## Идентификаторы приложения и запуск на Android / Windows

Во всех платформах стоят нейтральные **placeholder-идентификаторы** — для локального запуска их менять не
нужно, но **перед публикацией** замени на свои уникальные:

| Платформа | Где | Текущее значение |
|---|---|---|
| iOS | `ios/Runner.xcodeproj` → Bundle Identifier | `com.example.mobileWalletDemo` |
| Android | `android/app/build.gradle.kts` → `applicationId` (и `namespace`) | `com.example.mobile_wallet_demo` |
| Windows | `windows/runner/Runner.rc` → `CompanyName` | `com.example` |

Локальный запуск (после `flutter pub get`; та же Flutter `3.41.7`, что в CI / `.fvmrc`):

- **Android:** включи на устройстве **USB-debugging** (*Settings → Developer options*), подключи кабелем и
  запусти `flutter run -d android`. Debug-сборка подписывается автоматически локальным debug-keystore —
  отдельный аккаунт/сертификат не нужен. `applicationId` важен только для публикации в Google Play.
- **Windows:** установи **Visual Studio** с компонентом *«Desktop development with C++»* и выполни
  `flutter run -d windows`. Подпись не требуется.
- **iOS на реальном устройстве:** см. раздел «Run on real iPhone/iPad with free Apple Account» выше — там
  подпись через Personal Team.

## WalletConnect project id

Project ID для WalletConnect/Reown хранится в **`dart_defines.json`** в репозитории (осознанно — это
публичный client-id; владелец не против использования квоты). Сборки и запуск читают его оттуда нативным
флагом Flutter `--dart-define-from-file`:

```bash
flutter run                     --dart-define-from-file=dart_defines.json   # или scripts/run.sh
flutter build apk     --release --dart-define-from-file=dart_defines.json   # или scripts/build.sh apk --release
flutter build ios     --release --dart-define-from-file=dart_defines.json
flutter build windows --release --dart-define-from-file=dart_defines.json
```

- В коде значение доступно как `wcProjectId` (`lib/src/walletconnect/wc_config.dart`, через
  `String.fromEnvironment('WC_PROJECT_ID')`).
- CI уже передаёт этот флаг во всех build-джобах.
- Реально его **использует** настоящий `reown_walletkit`-сервис в чанке 9.2; пока он не подключён, без id
  приложение работает в режиме «WalletConnect не настроен» (`UnavailableWalletConnectService`).
- Чтобы подставить свой id — поменяй значение в `dart_defines.json`.

## Локальный запуск

```bash
flutter pub get
flutter run
```
