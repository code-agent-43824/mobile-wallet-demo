# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.57.0] - 2026-10-24

### Added

- Экран «Новая карта»: подключить готовую карту, создать ключ на пустой или записать seed-фразу — в одном
  месте; активный кошелёк не меняется, пока карта не подключена.
- Защита при открытии (по желанию, в «Настройках»): экран блокировки при запуске и после минуты в фоне.
  Телефонный кошелёк открывается PIN или биометрией, карта — PIN и касанием, без подписи.

### Changed

- Каждая подпись и операция с картой проходит в одной шторке: PIN → подпись или касание карты → результат.
  Перевод: форма → проверка → PIN → подпись → результат (ожидание → подтверждение); технические данные —
  в «Подробностях».
- Ошибки доменных слоёв стали кодами и переводятся в интерфейсе: английская версия больше не показывает
  русских сообщений; ошибки карты не называют производителя. Ответы dApp об ошибках — на английском.
- Экран блокировки использует ту же цифровую клавиатуру, что и подписи.

## [1.56.0] - 2026-10-24

### Added

- Влиты v1.54.0+65 и v1.55.0+66: полная RU/EN-локализация с переключателем языка, онбординг
  «Кошелёк за минуту», несколько зарегистрированных карт Рутокен (выбор, «Забыть карту»,
  «Подключить ещё карту», серийный номер карты).
- GitHub Release: по тегу `v*` или ручным запуском CI на `main` с флагом `release` после
  сборки всех платформ публикуется APK с заметками из этого файла (аналог релизного job в GitLab).

### Changed

- Flutter больше не закреплён: CI и `.fvmrc` берут последний стабильный релиз (на момент
  выпуска — 3.47.8); `pubspec.lock` пересобран под него.
- Android: модуль приложения переведён на форму встроенного Kotlin (без `kotlin-android`),
  флаги AGP 9 совпадают с шаблоном `flutter create`; `package_info_plus` поднят до 10.x
  через override, так что Kotlin Gradle Plugin сам применяет только `walletconnect_pay`.
- Убран устаревший override `flutter_secure_storage`: `reown_core` 1.5 принимает 10.x.

### Fixed

- Потеря карты во время операции определяется по присутствию токена, а не по тексту ошибки
  вендора (ждёт физической перепроверки).
- Сборка Android APK на AGP 9.1: `android.newDsl=false` для legacy Kotlin Gradle Plugin.

## [1.0.0] - 2026-10-03

### Added

- Проект перенесён из GitHub (code-agent-43824/mobile-wallet-demo) в группу
  `prototypes` внутреннего GitLab и приведён к стандартам coding-rules.
- Flutter single-account EVM-кошелёк: phone vault (PIN/biometric), read-only
  Mainnet/Sepolia переводы, WalletConnect, EIP-4527/BC-UR AirGap signer,
  Rutoken NFC read-only профиль.
- CI/CD: GitLab пайплайн (анализ/тесты на linux-x64 → сборка Android APK на
  android-раннере → публикация в Package Registry + GitLab Release по тегу).
- GitLab Pages: копия документации (README + docs/).
