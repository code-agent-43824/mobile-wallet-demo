# Contributing

## Сборка

```bash
flutter pub get
flutter analyze
flutter test
```

Android APK: `flutter build apk --release --dart-define-from-file=dart_defines.json`.

Требуется свежий Flutter канала `stable` (версия не закреплена; Dart ^3.11.0 как нижняя граница), Java 17 для Android.

## Правила

- Перед коммитом: `dart format .` (CI проверяет форматирование).
- Коммиты — на английском в формате Conventional Commits (`feat: add login screen`).
- Пушим напрямую в `main`; проект должен собираться без ошибок.
- На GitHub выпуск запускается после изменения версии в `main`, если релиза для неё ещё нет;
  CI собирает и проверяет цели, публикует артефакты и создаёт тег. GitLab выпускает релизы по тегам.
- Версия SemVer: патч — правки без новой функциональности, минор — новая
  функциональность. При смене версии обновлять `pubspec.yaml`,
  `lib/src/app_version.dart`, `test/widget_test.dart`.
- Детали работы агентов — в `AGENTS.md`, карта кода — в `CLAUDE.md`,
  направление — в `docs/ROADMAP.md`, текущие задачи — в `docs/PLAN.md`, состояние — в `docs/STATUS.md`.
