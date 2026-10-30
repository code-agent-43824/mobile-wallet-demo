# mobile-wallet-demo

Flutter-демо EVM-кошелька с хранилищем телефона, WalletConnect и
MetaMask-совместимым AirGap. Объём продукта и критерии этапов описаны в дорожной карте.

Текущее состояние и версия — в [STATUS](docs/STATUS.md), ближайшие действия — в
[PLAN](docs/PLAN.md), этапы продукта — в [ROADMAP](docs/ROADMAP.md). Результаты
проверок на устройствах и живых сервисах — в
[матрице проверок](docs/device-test-matrix.md).

## Версионирование

Источник версии приложения — `pubspec.yaml` (`version`). По договорённости с каждым
функциональным шагом повышается минорная версия. История выпусков — в [CHANGELOG](CHANGELOG.md).

## Артефакты CI

Workflow публикует артефакты сборки. Релиз содержит восемь файлов с префиксом
`mobile-wallet-demo-<version>-`:

- Android: `android.apk`;
- iOS Simulator: `ios-simulator.zip` — внутри `Wallet Demo.app`;
- iOS Device: `ios-device-unsigned.zip` — неподписанная сборка;
- Windows: `windows-x64.zip`, `windows-arm64.zip`;
- Linux: `linux-x64.tar.gz`, `linux-arm64.tar.gz`;
- macOS: `macos.zip` — универсальная сборка для arm64 и x64.

На странице запуска Actions артефакты iOS называются `ios-simulator` и `ios-device`;
каждый содержит соответствующий ZIP-файл. Релиз публикуется после проверок запуска
на доступных раннерах; ограничения проверки указаны в заметках к релизу.

## iOS artifacts

CI собирает два независимых iOS-артефакта: `ios-simulator` и `ios-device`.

### 1. Запуск в iOS Simulator (на Mac)

1. Открой нужный запуск в GitHub → вкладка **Actions** → job **iOS / Build simulator app**.
2. Скачай артефакт **`ios-simulator`** и распакуй из него `ios-simulator.zip`.
3. Распакуй ZIP — внутри одна папка **`Wallet Demo.app`** (готовый `.app` bundle, а не набор файлов
   `Info.plist` / `Runner` / `Frameworks` / `Assets.car`).
4. Запусти **Simulator** (Xcode → Open Developer Tool → Simulator) и дождись загрузки симулятора.
5. Установи приложение одним из способов:
   - перетащи `Wallet Demo.app` на окно запущенного симулятора; **или**
   - в Finder правый клик по `Wallet Demo.app` → **Share / Поделиться** → **Simulator** → выбери
     запущенный симулятор.

Так приложение можно посмотреть на Mac без Apple-аккаунта и без подписи.

Для проверки сборки и запуска именно с **Xcode 27** выбери его через `xcode-select`, затем
из корня репозитория запусти `bash scripts/smoke/xcode27_simulator.sh`. Скрипт требует
свежий Flutter stable, создаёт отдельный временный iPhone-симулятор, собирает приложение,
проверяет запуск и сохранность кошелька между двумя процессами. Существующие симуляторы он
не меняет. Версия Xcode, результат и логи сохраняются в `build/smoke/xcode27-*`;
сообщи путь и результат для записи в матрицу проверок.

Тот же сценарий можно запустить без локального Mac через GitHub Actions →
**Xcode 27 simulator smoke** → **Run workflow**. Журнал сохраняется в артефакте
`xcode27-simulator-smoke`.

### 2. Запуск на реальном iPhone / iPad

Артефакт **`ios-device-unsigned.zip`** содержит **неподписанный** device-build (`Wallet Demo.app`) —
это технический артефакт. **Установить его на реальное устройство без подписи нельзя.**

Способы запустить на устройстве:

- **Официальный бесплатный способ (рекомендуется):** открой проект в **Xcode** на Mac, в *Signing &
  Capabilities* выбери свой **Personal Team** (бесплатный Apple ID), подключи iPhone/iPad кабелем и нажми
  **Run**. Xcode сам подпишет сборку development-сертификатом и provisioning profile. Пошаговая
  инструкция — в разделе «Run on real iPhone/iPad with free Apple Account» ниже.
- CI сейчас собирает только неподписанный device-артефакт. Даже если заданы signing-credentials,
  workflow сообщает, что экспорт подписанного IPA пока не реализован. Никакие Apple ID, пароли,
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

**Что понадобится:** Mac с **Xcode** и свежий стабильный **Flutter** — CI всегда берёт последний
релиз канала `stable` (см. `.github/workflows/ci.yml` и `.fvmrc`), версия не закреплена.

1. **Установи Xcode** из Mac App Store и открой его хотя бы раз (доустановит компоненты командной строки).
2. **Установи Flutter (канал `stable`).** Через [fvm](https://fvm.app): `fvm use stable` (канал уже указан в
   `.fvmrc`), либо `flutter channel stable && flutter upgrade`, затем проверь `flutter --version`.
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

На **Apple Silicon Mac** (M1/M2/M3…) iOS-таргет можно запускать как
**«Designed for iPad / iPhone»** без Simulator. Этот режим включён через
`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES` на target `Runner`; Mac Catalyst не используется.
Это отдельный путь от нативной Flutter-сборки macOS в `macos/`.

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
- Для этого режима Flutter macOS-таргет **не нужен**. Часть чисто-iOS возможностей (например, биометрия)
  на Mac может вести себя иначе — это ограничение режима «Designed for iPad», а не проекта.

## Идентификаторы приложения и запуск на Android / Windows

Во всех платформах стоят нейтральные **placeholder-идентификаторы** — для локального запуска их менять не
нужно, но **перед публикацией** замени на свои уникальные:

| Платформа | Где | Текущее значение |
|---|---|---|
| iOS | `ios/Runner.xcodeproj` → Bundle Identifier | `com.example.mobileWalletDemo` |
| Android | `android/app/build.gradle.kts` → `applicationId` (и `namespace`) | `com.example.mobile_wallet_demo` |
| Windows | `windows/runner/Runner.rc` → `CompanyName` | `com.example` |

Локальный запуск (после `flutter pub get`; свежий Flutter `stable`, как в CI / `.fvmrc`):

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
