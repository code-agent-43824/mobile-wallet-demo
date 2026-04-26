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
  - ручное обновление данных
- Контракты для `KeyStorageBackend` и задел под внешний hardware backend
- Unit- и widget-тесты для ключевых flow
- GitHub Actions для сборки и публикации артефактов
- Артефакты iOS / Windows без двойной упаковки

## Версионирование

- Текущая версия: `v0.9` (`0.9.0+10`)
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
- выбор между Ethereum Mainnet и Sepolia
- read-only чтение нативного баланса и base fee из публичных RPC
- fallback между несколькими RPC endpoints
- read-only чтение token balances из публичного explorer layer
- read-only экран recent transaction history
- локальный cache fallback для последнего успешного blockchain snapshot
- send preparation screen с address validation, amount entry, asset selection и preview gas/fee
- локальная EIP-1559 подпись native/ERC-20 transfer после одного auth flow на операцию
- raw transaction submission abstraction с публичным RPC broadcaster

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
