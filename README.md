# Flux для iOS (нативное приложение)

Нативная iOS-версия Flux Messenger на **Swift / SwiftUI**. Повторяет
Android-версию (Flutter) по функциям, логике и данным; обе платформы
работают с одним Firestore-проектом и одной схемой документов.

## Сборка IPA через GitHub Actions

Каждый пуш в `main` (а также ручной запуск во вкладке **Actions →
Build iOS IPA**) собирает **неподписанный IPA** на раннере macOS.

Готовый файл: **Actions → Build iOS IPA → успешный запуск → Artifacts →
Flux-unsigned-ipa**.

Неподписанный IPA ставится на iPhone через
[Sideloadly](https://sideloadly.io/) или AltStore — при установке он
подписывается вашим Apple ID (обычная практика для личных сборок без
оплаченного аккаунта разработчика).

## Локальная сборка

Требования: macOS, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
xcodegen generate     # создаст Flux.xcodeproj из project.yml
open Flux.xcodeproj   # цель Flux → Cmd+R
```

Единственная внешняя зависимость — Firebase iOS SDK (FirebaseCore,
FirebaseFirestore) через Swift Package Manager; Xcode разрешит её при
первой сборке. QR-коды, сканирование, запись голоса, биометрия и Keychain
используют только системные фреймворки.

## Firebase (необязательно)

1. В Firebase-консоли откройте **тот же проект, что использует Android**
   (см. `android/app/google-services.json`, не коммитится).
2. Добавьте в нём iOS-приложение с bundle id `com.flux3.ios` и скачайте
   `GoogleService-Info.plist`.
3. Положите файл в `ios-native/Flux/` (рядом с примером).

Без файла приложение работает в локальном режиме (UserDefaults) — так же,
как Android с плейсхолдер-конфигом. С реальным конфигом оба клиента
синхронизируют профили, чаты, сообщения, подарки, подписи и marketplace
через один Firestore (схема описана в корневом README).

## Структура

```
Flux/
├── App/                  FluxApp (точка входа), AppEnvironment, RootView
├── Core/
│   ├── Models/           FluxUser, FluxMessage, FluxChat, UserProfile, …
│   ├── Backend/          LocalBackend (UserDefaults) + FirestoreBackend
│   ├── Services/         PinHash, AccountManager (Keychain), LockController,
│   │                     FluxL10n (ru/en), ThemeController, Haptics
│   ├── DesignSystem/     палитра Flux, компоненты, аватары, баннеры
│   └── Utils/            форматирование дат/файлов, русская плюрализация
├── Features/
│   ├── Onboarding/       онбординг (3 страницы)
│   ├── Auth/             SmartAuth: username → вход | регистрация
│   ├── Lock/             PIN-клавиатура + Face ID
│   ├── Home/             шелл с плавающей навигацией (Чаты/Вызовы/Профиль)
│   ├── Chats/            список чатов, новый чат, контакты
│   ├── Chat/             чат, пузыри сообщений, ввод, голосовые
│   ├── Calls/            история вызовов, экран звонка
│   ├── Profile/          профиль (новая система), редактор, подарки,
│   │                     подписи, stories, бейджи
│   ├── Settings/         настройки, уровень/активность, монеты,
│   │                     магазин бейджей, marketplace, QR
│   ├── Privacy/          приватность, устройства
│   └── Admin/            админ-панель
└── Support/              пикеры (галерея/камера/файлы), QR, аудио
```

## Заметки по платформенным отличиям

- **Блокировка скриншотов.** В iOS нет аналога Android FLAG_SECURE; при
  включённом переключателе приложение фиксирует снимки экрана и
  отправляет предупреждение в чат «Службы безопасности».
- **Медиа.** Вложения (фото, файлы, голосовые) хранятся локально на
  устройстве — как и в Android-версии; в Firestore синхронизируются
  текстовые поля сообщений.
- **Версии.** iOS 16.0+, Swift 5.9, только iPhone (портрет).
