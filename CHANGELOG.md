# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Влиты v1.54.0+65 и v1.55.0+66: полная RU/EN-локализация с переключателем языка, онбординг
  «Кошелёк за минуту», несколько зарегистрированных карт Рутокен (выбор, «Забыть карту»,
  «Подключить ещё карту», серийный номер карты).

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
