# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
