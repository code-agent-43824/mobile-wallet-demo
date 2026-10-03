# Contributing

## Сборка

```bash
flutter pub get
flutter analyze
flutter test
```

Android APK: `flutter build apk --release --dart-define-from-file=dart_defines.json`.

Требуется Flutter 3.41.7 (Dart ^3.11.0), Java 17 для Android.

## Правила

- Перед коммитом: `dart format .` (CI проверяет форматирование).
- Коммиты — на английском, в императиве (`Add login screen`).
- Пушим напрямую в `main`; проект должен собираться без ошибок.
- Релизы — только через CI: пуш тега `vX.Y.Z` → пайплайн собирает, тестирует
  и публикует артефакты (Package Registry + GitLab Release).
- Версия SemVer: патч — правки без новой функциональности, минор — новая
  функциональность. При смене версии обновлять `pubspec.yaml`,
  `lib/src/app_version.dart`, `test/widget_test.dart`.
- Детали работы агентов — в `AGENTS.md`, карта кода — в `CLAUDE.md`,
  роадмап — в `docs/development-plan.md`.
