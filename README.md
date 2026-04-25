# mobile-wallet-demo

Минимальный демо-проект Flutter для будущего мобильного криптокошелька.

## Что уже есть

- Flutter-проект с платформами: Android, iOS, Windows x64
- Базовый архитектурный фундамент Secure Vault
- Контракты для `KeyStorageBackend` и задел под внешний hardware backend
- Реализация `PhoneSecureVault` с шифрованием seed, PIN unlock session и EVM-деривацией первого адреса
- Unit-тесты на create/import/unlock flow
- Глобальный баннер версии в правом верхнем углу на всех экранах
- GitHub Actions для сборки и публикации артефактов
- Кэширование часто используемых компонентов CI: Flutter SDK, pub cache, Gradle, CocoaPods
- Каждое изменение доводится до push в GitHub и проверки сборки через Actions

## Версионирование

- Текущая версия: `v0.3.1` (`0.3.1+4`)
- Базовый ориентир для проекта — двигаться по понятной последовательности релизов; при необходимости допустим и точечный patch-релиз без изменения продуктового объёма

## Что покрывает текущий этап

- архитектурный skeleton проекта
- базовый Secure Vault foundation
- генерация новой BIP-39 seed phrase
- импорт существующей seed phrase
- хранение seed в зашифрованном виде
- derivation первого EVM-адреса (`m/44'/60'/0'/0/0`)
- базовая unlock-сессия после PIN

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
