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

- Текущая версия: `v0.3` (`0.3.0+3`)
- По договорённости в этом проекте дальше повышаем минорную версию с каждым улучшением или багфиксом

## Что покрывает текущий этап

- генерация новой BIP-39 seed phrase
- импорт существующей seed phrase
- хранение seed в зашифрованном виде
- derivation первого EVM-адреса (`m/44'/60'/0'/0/0`)
- базовая unlock-сессия после PIN

## Артефакты CI

Workflow публикует скачиваемые артефакты:

- Android: `app-release.apk`
- iOS: zip с `Runner.app` для iOS Simulator
- Windows x64: zip с собранным приложением

## Локальный запуск

```bash
flutter pub get
flutter run
```
