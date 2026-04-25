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
  - biometric choice shell
  - locked / unlocked app states
- Контракты для `KeyStorageBackend` и задел под внешний hardware backend
- Реализация `PhoneSecureVault` с шифрованием seed, PIN unlock session и EVM-деривацией первого адреса
- Unit- и widget-тесты для ключевых flow
- GitHub Actions для сборки и публикации артефактов
- Артефакты iOS / Windows без двойной упаковки

## Версионирование

- Текущая версия: `v0.4` (`0.4.0+5`)
- По договорённости в этом проекте дальше повышаем минорную версию с каждым функциональным шагом

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

## Артефакты CI

Workflow публикует скачиваемые артефакты так, чтобы при скачивании с GitHub был нужен только один `unzip`:

- Android: `app-release.apk`
- iOS: один архив GitHub Artifact с `Runner.app` для iOS Simulator внутри
- Windows x64: один архив GitHub Artifact с содержимым `Release/` внутри

## Локальный запуск

```bash
flutter pub get
flutter run
```
