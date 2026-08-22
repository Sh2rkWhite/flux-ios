import Foundation
import SwiftUI
import UIKit

/// Lightweight localization (Русский / English) backed by the persisted
/// language preference. Strings mirror the Android `FluxL10n`.
@MainActor
final class FluxL10n: ObservableObject {
    @Published private(set) var language: String

    init(_ language: String) {
        self.language = language
    }

    var isRu: Bool { language == "ru" }

    func setLanguage(_ lang: String) {
        guard lang != language else { return }
        language = lang
    }

    private func pick(_ ru: String, _ en: String) -> String { isRu ? ru : en }

    // ── Onboarding ──────────────────────────────────────────────────────
    var obTitle1: String { pick("Общение без границ", "Communication without limits") }
    var obText1: String { pick("Быстрые и безопасные сообщения с людьми по всему миру.", "Fast and secure messaging with people around the world.") }
    var obTitle2: String { pick("Приватность по умолчанию", "Privacy by default") }
    var obText2: String { pick("Гибкие настройки конфиденциальности и анонимный FluxID вместо номера телефона.", "Flexible privacy controls and an anonymous FluxID instead of a phone number.") }
    var obTitle3: String { pick("Всё под контролем", "Everything under control") }
    var obText3: String { pick("Исчезающие сообщения, защита контента и полная свобода общения.", "Disappearing messages, content protection and total freedom to communicate.") }
    var obStart: String { pick("Начать", "Get started") }

    // ── Smart Auth ──────────────────────────────────────────────────────
    var authWelcome: String { pick("Добро пожаловать", "Welcome") }
    var authSubtitle: String { pick("Введите username, чтобы войти или создать аккаунт", "Enter your username to sign in or create an account") }
    var authUsername: String { pick("Username", "Username") }
    var authUsernameHint: String { pick("Латиница, цифры и «_», от 3 символов", "Latin letters, digits and \"_\", 3+ chars") }
    var authCheckUsername: String { pick("Проверить", "Check") }
    var authPassword: String { pick("Пароль", "Password") }
    var authLogin: String { pick("Войти", "Sign in") }
    var authRegister: String { pick("Создать аккаунт", "Create account") }
    var authNewAccount: String { pick("Username свободен — создайте аккаунт", "Username is available — create your account") }
    var authExistingAccount: String { pick("Аккаунт найден — введите пароль", "Account found — enter your password") }
    var authEmail: String { pick("Email", "Email") }
    var authDisplayName: String { pick("Отображаемое имя", "Display name") }
    var authWrongPassword: String { pick("Неверный пароль", "Wrong password") }
    var authUserNotFound: String { pick("Пользователь не найден", "User not found") }
    var authBack: String { pick("Назад", "Back") }
    var authBiometricLogin: String { pick("Войти по биометрии", "Sign in with biometrics") }
    var authRememberMe: String { pick("Запомнить меня", "Remember me") }

    // ── FluxID ──────────────────────────────────────────────────────────
    var idTitle: String { pick("Ваш FluxID", "Your FluxID") }
    var idSubtitle: String { pick("По нему другие пользователи смогут найти вас", "Other users can find you by this ID") }
    var idCopy: String { pick("Скопировать", "Copy") }
    var idCopied: String { pick("FluxID скопирован", "FluxID copied") }

    // ── Tabs / home ─────────────────────────────────────────────────────
    var tabChats: String { pick("Чаты", "Chats") }
    var tabCalls: String { pick("Вызовы", "Calls") }
    var tabProfile: String { pick("Профиль", "Profile") }
    var search: String { pick("Поиск", "Search") }
    var searchChats: String { pick("Поиск чатов и сообщений", "Search chats and messages") }
    var newChat: String { pick("Новый чат", "New chat") }
    var contacts: String { pick("Контакты", "Contacts") }
    var searchById: String { pick("Найти по FluxID", "Find by FluxID") }
    var noResults: String { pick("Ничего не найдено", "Nothing found") }
    var noChatsYet: String { pick("Пока нет чатов", "No chats yet") }
    var noChatsHint: String { pick("Начните новую беседу — нажмите на кнопку выше", "Start a new conversation — tap the button above") }
    var online: String { pick("в сети", "online") }
    var typing: String { pick("печатает…", "typing…") }
    var delete: String { pick("Удалить", "Delete") }
    var pin: String { pick("Закрепить", "Pin") }
    var unpin: String { pick("Открепить", "Unpin") }

    // ── Calls ───────────────────────────────────────────────────────────
    var noCalls: String { pick("Нет вызовов", "No calls") }
    var noCallsHint: String { pick("Здесь будет история ваших звонков", "Your call history will appear here") }
    var incoming: String { pick("Входящий", "Incoming") }
    var outgoing: String { pick("Исходящий", "Outgoing") }
    var missed: String { pick("Пропущенный", "Missed") }
    var audioCall: String { pick("Аудиовызов", "Audio call") }
    var videoCall: String { pick("Видеозвонок", "Video call") }
    var calling: String { pick("Соединение…", "Connecting…") }
    var endCall: String { pick("Завершить", "End") }

    // ── Chat ────────────────────────────────────────────────────────────
    var message: String { pick("Сообщение", "Message") }
    var reply: String { pick("Ответить", "Reply") }
    var edit: String { pick("Редактировать", "Edit") }
    var edited: String { pick("изменено", "edited") }
    var copy: String { pick("Копировать", "Copy") }
    var forward: String { pick("Переслать", "Forward") }
    var photo: String { pick("Фото", "Photo") }
    var file: String { pick("Файл", "File") }
    var camera: String { pick("Камера", "Camera") }
    var gallery: String { pick("Галерея", "Gallery") }
    var voiceMessage: String { pick("Голосовое сообщение", "Voice message") }
    var today: String { pick("Сегодня", "Today") }
    var yesterday: String { pick("Вчера", "Yesterday") }
    var messageDeleted: String { pick("Сообщение удалено", "Message deleted") }
    var forwardDisabled: String { pick("Пересылка отключена в настройках конфиденциальности", "Forwarding is disabled in privacy settings") }
    var fatalHint: String { pick("Исчезнет через 30 секунд", "Disappears in 30 seconds") }

    // ── Profile / settings ──────────────────────────────────────────────
    var premium: String { pick("Premium", "Premium") }
    var premiumHint: String { pick("Расширенные возможности Flux", "Extended Flux capabilities") }
    var settings: String { pick("Настройки", "Settings") }
    var privacy: String { pick("Конфиденциальность", "Privacy") }
    var notifications: String { pick("Уведомления", "Notifications") }
    var languageTitle: String { pick("Язык", "Language") }
    var theme: String { pick("Тема", "Theme") }
    var support: String { pick("Flux Support", "Flux Support") }
    var status: String { pick("Статус", "Status") }
    var name: String { pick("Имя", "Name") }
    var save: String { pick("Сохранить", "Save") }
    var myProfile: String { pick("Мой профиль", "My profile") }
    var registrationDate: String { pick("Дата регистрации", "Registration date") }
    var bio: String { pick("О себе", "Bio") }
    var account: String { pick("Аккаунт", "Account") }
    var general: String { pick("Общие", "General") }
    var messagePreview: String { pick("Показывать текст сообщений", "Show message previews") }
    var sounds: String { pick("Звуки", "Sounds") }
    var themeLight: String { pick("Светлая", "Light") }
    var themeDark: String { pick("Тёмная", "Dark") }
    var themeSystem: String { pick("Системная", "System") }

    // ── Privacy screen ──────────────────────────────────────────────────
    var privacyMode: String { pick("Режим приватности", "Privacy mode") }
    var privacyModeDesc: String { pick("Скройте личную информацию и управляйте тем, кто может вас находить.", "Hide personal information and control who can find you.") }
    var configure: String { pick("Настроить", "Configure") }
    var visibility: String { pick("Видимость", "Visibility") }
    var showOnlineStatus: String { pick("Статус онлайн", "Online status") }
    var lastVisit: String { pick("Последний визит", "Last seen") }
    var readReceipts: String { pick("Отчёты о прочтении", "Read receipts") }
    var hideTypingStatus: String { pick("Скрыть набор текста", "Hide typing status") }
    var contentProtection: String { pick("Защита контента", "Content protection") }
    var blockScreenshots: String { pick("Блокировка скриншотов", "Block screenshots") }
    var forbidForwarding: String { pick("Запрет пересылки", "Forbid forwarding") }
    var fatalMessages: String { pick("Фатальные сообщения", "Fatal messages") }
    var fatalMessagesDesc: String { pick("Сообщения исчезают через 30 секунд после отправки", "Messages disappear 30 seconds after sending") }
    var autoDelete: String { pick("Автоудаление", "Auto-delete") }
    var autoDeleteDesc: String { pick("Сообщения удаляются автоматически", "Messages are removed automatically") }
    var advancedPrivacy: String { pick("Продвинутая конфиденциальность", "Advanced privacy") }

    // ── App lock ────────────────────────────────────────────────────────
    var appLock: String { pick("Блокировка приложения", "App lock") }
    var appLockDesc: String { pick("Вход по PIN-коду или биометрии устройства", "Unlock with a PIN or device biometrics") }
    var appLockBiometrics: String { pick("Биометрия", "Biometrics") }
    var appLockBiometricsDesc: String { pick("Fingerprint / Face ID / Touch ID", "Fingerprint / Face ID / Touch ID") }
    var appLockSetPin: String { pick("Установить код", "Set passcode") }
    var appLockEnterPin: String { pick("Введите код", "Enter passcode") }
    var appLockConfirmPin: String { pick("Повторите код", "Repeat passcode") }
    var appLockMismatch: String { pick("Коды не совпадают", "Passcodes do not match") }
    var appLockWrong: String { pick("Неверный код", "Wrong passcode") }

    // ── Support ─────────────────────────────────────────────────────────
    var supportGreeting: String { pick("Здравствуйте! Команда Flux на связи. Чем могу помочь? 💙", "Hello! The Flux team is here. How can we help? 💙") }

    // ── Logout ──────────────────────────────────────────────────────────
    var logout: String { pick("Выйти из аккаунта", "Log out") }
    var logoutConfirmTitle: String { pick("Выйти из аккаунта?", "Log out?") }
    var logoutConfirmBody: String { pick("Все локальные данные, чаты и настройки будут удалены с этого устройства.", "All local data, chats and settings will be erased from this device.") }

    // ── Admin panel ─────────────────────────────────────────────────────
    var adminPanel: String { pick("Админ-панель", "Admin panel") }
    var adminPanelDesc: String { pick("Управление пользователями и системой", "Manage users and the system") }
    var adminUsers: String { pick("Пользователи", "Users") }
    var adminRole: String { pick("Администратор", "Administrator") }
    var adminStats: String { pick("Статистика", "Statistics") }

    // ── Devices ─────────────────────────────────────────────────────────
    var devices: String { pick("Устройства", "Devices") }
    var devicesDesc: String { pick("Активные сеансы вашего аккаунта", "Active sessions on your account") }
    var thisDevice: String { pick("Это устройство", "This device") }
    var terminate: String { pick("Завершить", "Terminate") }
    var terminateAll: String { pick("Завершить все другие сеансы", "Terminate all other sessions") }
    var terminateAllConfirm: String { pick("Все устройства, кроме текущего, будут отключены от аккаунта.", "All devices except the current one will be signed out.") }
    var terminateTitle: String { pick("Завершить сеанс?", "Terminate session?") }
    var terminateBody: String { pick("Устройство будет отключено от аккаунта.", "The device will be signed out.") }
    var noActiveSessions: String { pick("Нет активных сеансов", "No active sessions") }

    // ── Misc ────────────────────────────────────────────────────────────
    var cancel: String { pick("Отмена", "Cancel") }
    var done: String { pick("Готово", "Done") }
    var ok: String { pick("ОК", "OK") }
    var error: String { pick("Что-то пошло не так", "Something went wrong") }

    func lastSeenAt(_ formatted: String) -> String {
        pick("был(а) в \(formatted)", "last seen \(formatted)")
    }
}

/// Observable theme mode, persisted through the backend preferences.
@MainActor
final class ThemeController: ObservableObject {
    enum Mode: String {
        case light, dark, system

        var colorScheme: ColorScheme? {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .system: return nil
            }
        }
    }

    @Published private(set) var mode: Mode

    init(_ stored: String) {
        switch stored {
        case "dark": mode = .dark
        case "system": mode = .system
        default: mode = .light
        }
    }

    var storedValue: String {
        switch mode {
        case .dark: return "dark"
        case .system: return "system"
        case .light: return "light"
        }
    }

    func setMode(_ mode: Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
    }
}

/// Haptic feedback helpers (the iOS counterpart of the Android Haptics
/// bridge).
enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
