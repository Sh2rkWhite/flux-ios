import Foundation
import CryptoKit
import UIKit

/// Error type carrying the same message strings as the Android backend so
/// UI mapping behaves identically on both platforms.
struct FluxError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }

    static let userNotFound = FluxError("User not found")
    static let noPasswordSet = FluxError("No password set")
    static let wrongPassword = FluxError("Wrong password")
    static let notLoggedIn = FluxError("Not logged in")
    static func insufficientCoins(_ need: Int, _ have: Int) -> FluxError {
        FluxError("Недостаточно Flux Coins: нужно \(need), есть \(have)")
    }
}

/// Local-first implementation of the Flux backend.
///
/// Everything is persisted to UserDefaults as JSON and survives app
/// restarts — the same storage model as the Android implementation
/// (SharedPreferences), with identical keys and shapes.
///
/// Peers are simulated in local mode: they come online, type and answer,
/// which keeps the whole UX (delivery ticks, read receipts, typing
/// indicator, unread badges) fully functional without a server. The
/// Firestore subclass turns simulation off.
@MainActor
class LocalBackend: ObservableObject {

    // MARK: - Storage keys (identical to Android)

    static let kProfile = "flux.profile"
    static let kContacts = "flux.contacts"
    static let kChats = "flux.chats"
    static let kMessages = "flux.messages"
    static let kCalls = "flux.calls"
    static let kPrivacy = "flux.privacy"
    static let kPrefs = "flux.prefs"
    static let kOnboarded = "flux.onboarded"
    static let kWelcomed = "flux.welcomed"
    static let kCurrentSessionId = "flux.current_session_id"
    static let kBioLoginUsername = "flux.bio_login_username"
    static let kCredentials = "flux.credentials.v1"
    static let kUserProfile = "flux.user_profile"
    static let kUserProfiles = "flux.user_profiles"
    static let kAwardedXpIds = "flux.awarded_xp_ids"
    static let kMarketplace = "flux.marketplace"

    static let placeholderProject = "flux-placeholder"

    // MARK: - Demo directory

    static let seedUsers: [[String: Any]] = [
        ["id": "u-alice", "fluxId": "FLX-7K2M9QXR", "username": "alice", "name": "Алиса Соколова", "status": "Дизайн и кофе ☕️", "isOnline": true, "isPremium": true],
        ["id": "u-mark", "fluxId": "FLX-3TD8VWLN", "username": "mark_orlov", "name": "Марк Орлов", "status": "На связи", "isOnline": false],
        ["id": "u-sofia", "fluxId": "FLX-9QF4HZPY", "username": "sofia_kim", "name": "София Ким", "status": "Путешествую 🌍", "isOnline": true],
        ["id": "u-dan", "fluxId": "FLX-5RB2XCJM", "username": "danvolkov", "name": "Даниил Волков", "status": "", "isOnline": false],
        ["id": "u-lena", "fluxId": "FLX-8NH6KSAE", "username": "lena_music", "name": "Лена Морозова", "status": "Музыка 24/7 🎧", "isOnline": true],
        ["id": "u-team", "fluxId": "FLX-TEAMFLUX", "username": "flux", "name": "Flux Team", "status": "Официальный канал", "isOnline": true, "isPremium": true],
    ]

    static let peerReplies = [
        "Привет! Как дела? 😊",
        "Звучит отлично!",
        "Давай, договорились 👌",
        "Хм, интересно. Расскажи подробнее?",
        "Я как раз об этом думал(а)!",
        "Согласен(на) на все 100%",
        "Может, созвонимся вечером?",
        "Ахаха, ну ты даёшь 😄",
        "Скину детали чуть позже, ок?",
        "Принято ✅",
    ]

    // MARK: - State

    let defaults = UserDefaults.standard
    private(set) var me: FluxUser?
    private(set) var onboardedValue = false

    var contacts: [String: FluxUser] = [:]
    var chatStorage: [String: FluxChat] = [:]
    var messageStorage: [FluxMessage] = []
    var callStorage: [CallRecord] = []
    private(set) var privacy: PrivacySettings = PrivacySettings()
    private(set) var prefs: AppPreferences = AppPreferences()

    /// The FluxID session id of the most recent login on this device.
    private(set) var currentSessionId: String?

    private var typingChatIds: Set<String> = []
    private(set) var credentials: [String: [String: String]] = [:]
    private(set) var userProfileValue = UserProfile.initial
    /// Profiles of other users (keyed by userId) — gifts, badges, signatures.
    var userProfiles: [String: UserProfile] = [:]
    var awardedXpMessageIds: Set<String> = []
    var marketplaceStorage: [MarketplaceListing] = []

    private var bioLoginUsernameValue: String?
    private var pendingTasks: Set<Task<Void, Never>> = []

    /// Whether demo peers simulate delivery/typing/replies. The Firestore
    /// backend disables this — real peers answer instead.
    var simulatePeers: Bool { true }

    // MARK: - Init

    init() {}

    func initBackend() async {
        let p = defaults

        onboardedValue = p.bool(forKey: Self.kOnboarded)
        bioLoginUsernameValue = p.string(forKey: Self.kBioLoginUsername)

        if let profileJson = p.string(forKey: Self.kProfile), let data = profileJson.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            me = FluxUser.fromJson(json)
        }

        for seed in Self.seedUsers {
            let u = FluxUser.fromJson(seed)
            contacts[u.id] = u
        }
        if let contactsJson = p.string(forKey: Self.kContacts), let data = contactsJson.data(using: .utf8),
           let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for json in list {
                let u = FluxUser.fromJson(json)
                contacts[u.id] = u
            }
        }

        if let chatsJson = p.string(forKey: Self.kChats), let data = chatsJson.data(using: .utf8),
           let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for json in list {
                let c = FluxChat.fromJson(json)
                chatStorage[c.id] = c
            }
        }

        if let messagesJson = p.string(forKey: Self.kMessages), let data = messagesJson.data(using: .utf8),
           let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            messageStorage = list.map(FluxMessage.fromJson)
        }

        if let callsJson = p.string(forKey: Self.kCalls), let data = callsJson.data(using: .utf8),
           let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            callStorage = list.map(CallRecord.fromJson)
        }

        if let privacyJson = p.string(forKey: Self.kPrivacy), let data = privacyJson.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            privacy = PrivacySettings.fromJson(json)
        }

        if let prefsJson = p.string(forKey: Self.kPrefs), let data = prefsJson.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            prefs = AppPreferences.fromJson(json)
        }

        // Persistent credential registry — survives logout() so
        // loginSmart can verify passwords after the profile was wiped.
        if let credJson = p.string(forKey: Self.kCredentials), let data = credJson.data(using: .utf8),
           let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: String]] {
            credentials = raw
        }

        if let profileJson = p.string(forKey: Self.kUserProfile), let data = profileJson.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            userProfileValue = UserProfile.fromJson(json)
        }

        if let profilesJson = p.string(forKey: Self.kUserProfiles), let data = profilesJson.data(using: .utf8),
           let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: [String: Any]] {
            for (key, json) in raw {
                userProfiles[key] = UserProfile.fromJson(json)
            }
        }

        if let awardedJson = p.string(forKey: Self.kAwardedXpIds), let data = awardedJson.data(using: .utf8),
           let list = (try? JSONSerialization.jsonObject(with: data)) as? [String] {
            awardedXpMessageIds = Set(list)
        }

        if let marketJson = p.string(forKey: Self.kMarketplace), let data = marketJson.data(using: .utf8),
           let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            marketplaceStorage = list.map(MarketplaceListing.fromJson)
        }

        // Purge messages that already expired while the app was closed.
        let now = Int(Date().timeIntervalSince1970 * 1000)
        messageStorage.removeAll { m in
            if let expiry = m.expiresAtMs, expiry <= now { return true }
            return false
        }
        for m in messageStorage where m.expiresAtMs != nil {
            scheduleExpiry(m)
        }
    }

    // MARK: - Change notification

    func notify() {
        objectWillChange.send()
    }

    private func after(_ ms: Int, _ body: @escaping @MainActor () -> Void) {
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            guard let self, !Task.isCancelled else { return }
            body()
        }
        pendingTasks.insert(task)
    }

    private func cancelAllTasks() {
        pendingTasks.forEach { $0.cancel() }
        pendingTasks.removeAll()
    }

    // MARK: - Persistence helpers

    private func saveString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    private func encodeJson(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    func persistProfile() {
        guard let me else { return }
        saveString(encodeJson(me.toJson()), forKey: Self.kProfile)
    }

    func saveMessages() {
        saveString(encodeJson(messageStorage.map { $0.toJson() }), forKey: Self.kMessages)
    }

    func saveChats() {
        saveString(encodeJson(chatStorage.values.map { $0.toJson() }), forKey: Self.kChats)
    }

    func saveContacts() {
        saveString(encodeJson(contacts.values.map { $0.toJson() }), forKey: Self.kContacts)
    }

    func saveCalls() {
        saveString(encodeJson(callStorage.map { $0.toJson() }), forKey: Self.kCalls)
    }

    func saveCredentials() {
        saveString(encodeJson(credentials), forKey: Self.kCredentials)
    }

    func saveUserProfile() {
        saveString(encodeJson(userProfileValue.toJson()), forKey: Self.kUserProfile)
    }

    func saveUserProfiles() {
        let mapped = userProfiles.mapValues { $0.toJson() }
        saveString(encodeJson(mapped), forKey: Self.kUserProfiles)
    }

    func saveAwardedXpIds() {
        saveString(encodeJson(Array(awardedXpMessageIds)), forKey: Self.kAwardedXpIds)
    }

    func saveMarketplace() {
        saveString(encodeJson(marketplaceStorage.map { $0.toJson() }), forKey: Self.kMarketplace)
    }

    // MARK: - Identity

    var onboarded: Bool { onboardedValue }

    func setOnboarded() {
        onboardedValue = true
        defaults.set(true, forKey: Self.kOnboarded)
        notify()
    }

    var isAdmin: Bool { me?.isAdmin ?? false }

    func generateFluxId() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        var code = ""
        for _ in 0..<8 {
            code.append(alphabet[Int.random(in: 0..<alphabet.count)])
        }
        return "FLX-\(code)"
    }

    func newFluxId() -> String { generateFluxId() }

    func createProfile(_ name: String, username: String?) async -> FluxUser {
        let user = FluxUser(
            id: "me",
            fluxId: "",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username?.trimmingCharacters(in: .whitespacesAndNewlines),
            status: "Привет! Я пользуюсь Flux."
        )
        me = user
        persistProfile()
        notify()
        return user
    }

    func confirmFluxId(_ fluxId: String) async -> FluxUser {
        guard var user = me else { throw FluxError.notLoggedIn }
        user.fluxId = fluxId
        me = user
        persistProfile()
        notify()
        return user
    }

    func updateMe(name: String? = nil, status: String? = nil, avatarPath: String? = nil, isPremium: Bool? = nil) async {
        guard var user = me else { return }
        if let name { user.name = name }
        if let status { user.status = status }
        if let avatarPath { user.avatarPath = avatarPath }
        if let isPremium { user.isPremium = isPremium }
        me = user
        persistProfile()
        notify()
    }

    var myProfile: UserProfile { userProfileValue }

    var fluxCoins: Int { userProfileValue.fluxCoins }

    /// Changes the primary @username after verifying it is free. The old
    /// credential-registry entry moves with it so sign-in keeps working.
    func updateUsername(_ newUsername: String) async throws {
        guard var me else { throw FluxError.notLoggedIn }
        let trimmed = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard trimmed.range(of: "^[a-zA-Z0-9_]{3,20}$", options: .regularExpression) != nil else {
            throw FluxError("Латиница, цифры и «_», от 3 символов")
        }
        if let existing = await lookupUsername(trimmed), existing.id != me.id {
            throw FluxError("Этот username уже занят")
        }
        let oldUsername = me.username?.lowercased()
        me.username = trimmed
        self.me = me
        if let oldUsername, oldUsername != trimmed.lowercased() {
            credentials[trimmed.lowercased()] = credentials[oldUsername]
            credentials[oldUsername] = nil
            saveCredentials()
        }
        persistProfile()
        notify()
    }

    func updateProfile(bannerPath: String? = nil, location: String? = nil, website: String? = nil, birthday: String? = nil) async {
        if let bannerPath { userProfileValue.bannerPath = bannerPath }
        if let location { userProfileValue.location = location }
        if let website { userProfileValue.website = website }
        if let birthday { userProfileValue.birthday = birthday }
        saveUserProfile()
        notify()
    }

    /// Signs the local user out: clears profile, sessions, chats, messages,
    /// calls and preferences. The credential registry and marketplace
    /// listings survive so signing back in and the shared marketplace
    /// keep working.
    func logout() async {
        let p = defaults
        p.removeObject(forKey: Self.kProfile)
        p.removeObject(forKey: Self.kContacts)
        p.removeObject(forKey: Self.kChats)
        p.removeObject(forKey: Self.kMessages)
        p.removeObject(forKey: Self.kCalls)
        p.removeObject(forKey: Self.kPrivacy)
        p.removeObject(forKey: Self.kPrefs)
        p.removeObject(forKey: Self.kOnboarded)
        p.removeObject(forKey: Self.kWelcomed)
        p.removeObject(forKey: Self.kCurrentSessionId)
        p.removeObject(forKey: Self.kAwardedXpIds)
        p.removeObject(forKey: Self.kUserProfiles)
        p.removeObject(forKey: Self.kUserProfile)
        me = nil
        contacts = Self.seedUsers.reduce(into: [:]) { map, seed in
            let u = FluxUser.fromJson(seed)
            map[u.id] = u
        }
        chatStorage = [:]
        messageStorage = []
        callStorage = []
        privacy = PrivacySettings()
        prefs = AppPreferences()
        onboardedValue = false
        currentSessionId = nil
        awardedXpMessageIds = []
        userProfileValue = UserProfile.initial
        userProfiles = [:]
        cancelAllTasks()
        notify()
    }

    // MARK: - Smart Auth

    /// Looks up a user by @username. Returns the profile when taken, nil
    /// when the username is available for registration.
    func lookupUsername(_ username: String) async -> FluxUser? {
        let q = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "@", with: "")
        if q.isEmpty { return nil }

        // 1. Persistent credential registry (survives logout).
        if let cred = credentials[q] {
            if let cur = me, let curName = cur.username, curName.lowercased() == q {
                return cur
            }
            for u in contacts.values where u.username?.lowercased() == q {
                return u
            }
            return FluxUser(
                id: "me",
                fluxId: cred["fluxId"] ?? "",
                name: cred["name"] ?? "",
                username: cred["username"] ?? q,
                passwordHash: cred["passwordHash"],
                email: cred["email"]
            )
        }

        // 2. Current device profile.
        if let cur = me, let curName = cur.username, curName.lowercased() == q {
            return cur
        }

        // 3. Directory (seed + synced contacts).
        for u in contacts.values where u.username?.lowercased() == q {
            return u
        }
        return nil
    }

    /// Registers a brand-new account: mints a FluxID, hashes the password,
    /// persists the profile, sends the security-bot welcome message and
    /// records the initial login session.
    func registerSmart(username: String, email: String, password: String, displayName: String) async throws -> FluxUser {
        let fluxId = generateFluxId()
        let hash = PinHash.hash(password.trimmingCharacters(in: .whitespacesAndNewlines))
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")

        let user = FluxUser(
            id: "me",
            fluxId: fluxId,
            name: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            username: trimmedUsername,
            status: "Привет! Я пользуюсь Flux.",
            passwordHash: hash,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            registeredAtMs: nowMs
        )
        me = user
        persistProfile()

        // Level 1, 0 XP, «Новичок» badge.
        userProfileValue = UserProfile(
            activityPoints: 0,
            badges: [BadgeCatalog.newUser.withEarned(atMs: nowMs)]
        )
        saveUserProfile()

        credentials[trimmedUsername.lowercased()] = [
            "passwordHash": hash,
            "fluxId": fluxId,
            "name": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "username": trimmedUsername,
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        saveCredentials()
        notify()

        try await postSecurityMessage(welcome: true)
        await recordLoginSession()
        _ = await checkAndUpdateDailyStreak()
        return user
    }

    /// Verifies the password against the stored hash for the username and
    /// loads the profile. Throws on unknown user or wrong password.
    func loginSmart(username: String, password: String) async throws -> FluxUser {
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let found = await lookupUsername(username) else {
            throw FluxError.userNotFound
        }
        guard let stored = found.passwordHash else {
            throw FluxError.noPasswordSet
        }
        guard PinHash.verify(trimmedPassword, stored: stored) else {
            throw FluxError.wrongPassword
        }

        me = found
        persistProfile()
        notify()

        try await postSecurityMessage(welcome: false)
        await recordLoginSession()
        _ = await checkAndUpdateDailyStreak()
        return found
    }

    /// Biometric quick-login: restores the session for an enrolled user
    /// without a password. The caller MUST verify biometrics first.
    func loginBiometric(username: String) async throws -> FluxUser {
        guard let found = await lookupUsername(username) else {
            throw FluxError.userNotFound
        }
        me = found
        persistProfile()
        notify()
        try await postSecurityMessage(welcome: false)
        await recordLoginSession()
        _ = await checkAndUpdateDailyStreak()
        return found
    }

    /// Posts a welcome or login notification to the security-bot chat.
    private func postSecurityMessage(welcome: Bool) async throws {
        guard let cur = me, !cur.fluxId.isEmpty else { return }

        let device = await Self.deviceName()
        let ip = await Self.publicIp()
        let platform = "ios"
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)

        let text = welcome
            ? "Здравствуйте! Добро пожаловать в мессенджер! Рады вас видеть."
            : "Здравствуйте! Был осуществлен вход в ваш аккаунт.\nУстройство: \(device)\nIP-адрес: \(ip ?? "—")\nПлатформа: \(platform)"

        let bot = securityBotUser()
        let chat = await openChatWithUser(bot)

        let message = FluxMessage(
            id: UUID().uuidString,
            chatId: chat.id,
            senderId: FluxUser.systemSecurityBotId,
            text: text,
            sentAtMs: nowMs,
            isSystemMessage: true
        )
        messageStorage.append(message)
        updateChatPreview(chat.id, message)
        saveMessages()
        saveChats()
        notify()
    }

    // MARK: - Directory

    var directory: [FluxUser] {
        contacts.values
            .filter { $0.id != FluxUser.supportId && $0.id != FluxUser.securityBotId }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func userById(_ id: String) -> FluxUser? {
        contacts[id]
    }

    func searchUsers(_ query: String) -> [FluxUser] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "@", with: "")
        if q.isEmpty { return directory }
        return directory.filter {
            $0.name.lowercased().contains(q)
                || $0.fluxId.lowercased().contains(q)
                || ($0.username ?? "").lowercased().contains(q)
        }
    }

    func registerExternalUser(_ fluxId: String) -> FluxUser {
        let normalized = fluxId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let existing = contacts.values.first(where: { $0.fluxId.uppercased() == normalized }) {
            return existing
        }
        let idSuffix = normalized.lowercased().filter { $0.isLetter || $0.isNumber }
        let user = FluxUser(
            id: "u-\(idSuffix)",
            fluxId: normalized,
            name: "Пользователь \(normalized)",
            isOnline: Bool.random()
        )
        contacts[user.id] = user
        saveContacts()
        notify()
        return user
    }

    func upsertContact(_ user: FluxUser) {
        contacts[user.id] = user
        saveContacts()
        notify()
    }

    private var supportUserValue: FluxUser {
        if let existing = contacts[FluxUser.supportId] { return existing }
        let support = FluxUser(
            id: FluxUser.supportId,
            fluxId: "FLX-SUPPORT",
            name: "Flux Support",
            status: "Всегда на связи",
            isOnline: true
        )
        contacts[support.id] = support
        return support
    }

    func ensureSupportUser() -> FluxUser { supportUserValue }

    private var securityBotValue: FluxUser {
        if let existing = contacts[FluxUser.securityBotId] { return existing }
        let bot = FluxUser(
            id: FluxUser.securityBotId,
            fluxId: "FLX-SECURITY",
            name: "Служба безопасности",
            status: "Системные уведомления",
            isOnline: true
        )
        contacts[bot.id] = bot
        return bot
    }

    func ensureSecurityBot() -> FluxUser { securityBotValue }

    /// Resolves the FluxID of a known user id (local `me`, remote `r-…`
    /// contacts or seeded demo contacts).
    func fluxIdOfUser(_ userId: String) -> String? {
        if let me, me.id == userId { return me.fluxId }
        if userId.hasPrefix("r-") {
            return String(userId.dropFirst(2)).uppercased()
        }
        return contacts[userId]?.fluxId
    }

    // MARK: - Sessions

    static func deviceName() async -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let mirror = Mirror(reflecting: sysinfo.machine)
        var machine = ""
        for child in mirror.children {
            if let value = child.value as? Int8, value != 0 {
                machine.append(String(UnicodeScalar(UInt8(value))))
            }
        }
        return machine.isEmpty ? UIDevice.current.name : machine
    }

    static func publicIp() async -> String? {
        let endpoints = ["https://api.ipify.org?format=json", "https://api64.ipify.org?format=json"]
        for url in endpoints {
            guard let requestUrl = URL(string: url) else { continue }
            var request = URLRequest(url: requestUrl)
            request.timeoutInterval = 4
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   let ip = json["ip"] as? String, !ip.isEmpty {
                    return ip
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Records a login session; a dedup guard skips the write when the same
    /// device logged in less than 5 minutes ago.
    func recordLoginSession() async {
        guard var cur = me, !cur.fluxId.isEmpty else { return }

        let device = await Self.deviceName()
        let ip = await Self.publicIp()
        let platform = "ios"
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)

        let fingerprint = "\(device)|\(platform)"
        if let last = cur.sessions.first {
            let lastFingerprint = "\(last.deviceName)|\(last.platform ?? "")"
            if fingerprint == lastFingerprint, nowMs - last.loginAtMs < 5 * 60 * 1000 {
                if currentSessionId == nil { currentSessionId = last.id }
                return
            }
        }

        let sessionId = UUID().uuidString
        let session = DeviceSession(
            id: sessionId,
            deviceName: device,
            loginAtMs: nowMs,
            ip: ip,
            platform: platform
        )
        cur.sessions = [session] + cur.sessions.filter { $0.id != sessionId }
        me = cur
        currentSessionId = sessionId
        persistProfile()
        defaults.set(sessionId, forKey: Self.kCurrentSessionId)
        notify()
    }

    func revokeSession(_ sessionId: String) async {
        guard var cur = me else { return }
        cur.sessions = cur.sessions.map { $0.id == sessionId ? DeviceSession(id: $0.id, deviceName: $0.deviceName, loginAtMs: $0.loginAtMs, ip: $0.ip, platform: $0.platform, revoked: true) : $0 }
        me = cur
        persistProfile()
        notify()
    }

    func revokeAllOtherSessions() async {
        guard var cur = me else { return }
        let current = currentSessionId ?? defaults.string(forKey: Self.kCurrentSessionId)
        cur.sessions = cur.sessions.map {
            $0.id == current ? $0 : DeviceSession(id: $0.id, deviceName: $0.deviceName, loginAtMs: $0.loginAtMs, ip: $0.ip, platform: $0.platform, revoked: true)
        }
        me = cur
        persistProfile()
        notify()
    }

    // MARK: - Chats

    var chats: [FluxChat] {
        chatStorage.values.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.lastMessageAtMs > b.lastMessageAtMs
        }
    }

    func chatWithPeer(_ peerId: String) -> FluxChat? {
        chatStorage.values.first { $0.peerId == peerId }
    }

    func openChatWithUser(_ user: FluxUser) async -> FluxChat {
        contacts[user.id] = user
        if let existing = chatWithPeer(user.id) { return existing }
        let chat = FluxChat(
            id: UUID().uuidString,
            peerId: user.id,
            createdAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
        chatStorage[chat.id] = chat
        saveChats()
        notify()
        return chat
    }

    func deleteChat(_ chatId: String) async {
        chatStorage[chatId] = nil
        messageStorage.removeAll { $0.chatId == chatId }
        saveChats()
        saveMessages()
        notify()
    }

    func toggleChatPin(_ chatId: String) async {
        guard let c = chatStorage[chatId] else { return }
        chatStorage[chatId] = FluxChat(
            id: c.id, peerId: c.peerId, createdAtMs: c.createdAtMs,
            lastMessagePreview: c.lastMessagePreview,
            lastMessageAtMs: c.lastMessageAtMs,
            unreadCount: c.unreadCount,
            pinned: !c.pinned
        )
        saveChats()
        notify()
    }

    func markChatRead(_ chatId: String) async {
        guard let c = chatStorage[chatId], c.unreadCount != 0 else { return }
        let meId = me?.id ?? "me"
        for i in messageStorage.indices
        where messageStorage[i].chatId == chatId && messageStorage[i].senderId != meId {
            if messageStorage[i].readAtMs == nil {
                messageStorage[i].readAtMs = Int(Date().timeIntervalSince1970 * 1000)
            }
        }
        chatStorage[chatId] = FluxChat(
            id: c.id, peerId: c.peerId, createdAtMs: c.createdAtMs,
            lastMessagePreview: c.lastMessagePreview,
            lastMessageAtMs: c.lastMessageAtMs,
            unreadCount: 0, pinned: c.pinned
        )
        saveChats()
        saveMessages()
        notify()
    }

    // MARK: - Messages

    func messagesOf(_ chatId: String) -> [FluxMessage] {
        messageStorage.filter { $0.chatId == chatId }.sorted { $0.sentAtMs < $1.sentAtMs }
    }

    func isPeerTyping(_ chatId: String) -> Bool {
        typingChatIds.contains(chatId)
    }

    private var outgoingExpiryMs: Int? {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        var expiry: Int? = nil
        if let auto = privacy.autoDelete.durationMs {
            expiry = now + auto
        }
        if privacy.fatalMessages {
            let fatal = now + 30_000
            expiry = expiry.map { min($0, fatal) } ?? fatal
        }
        return expiry
    }

    @discardableResult
    private func pushOutgoing(
        _ chatId: String, _ kind: MessageKind,
        text: String = "",
        mediaPath: String? = nil,
        fileName: String? = nil,
        fileSize: Int? = nil,
        voiceDurationMs: Int = 0,
        replyToId: String? = nil,
        overrideExpiryMs: Int? = nil
    ) async -> FluxMessage {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let message = FluxMessage(
            id: UUID().uuidString,
            chatId: chatId,
            senderId: me?.id ?? "me",
            kind: kind,
            text: text,
            mediaPath: mediaPath,
            fileName: fileName,
            fileSize: fileSize,
            voiceDurationMs: voiceDurationMs,
            sentAtMs: now,
            replyToId: replyToId,
            expiresAtMs: overrideExpiryMs ?? outgoingExpiryMs
        )
        messageStorage.append(message)
        updateChatPreview(chatId, message)
        saveMessages()
        saveChats()
        if message.expiresAtMs != nil { scheduleExpiry(message) }
        notify()
        if simulatePeers, let peer = chatWithPeer(chatId), peer.id != FluxUser.securityBotId {
            simulatePeerResponse(chatId)
        }
        return message
    }

    @discardableResult
    func sendText(_ chatId: String, _ text: String, replyToId: String? = nil, overrideExpiryMs: Int? = nil) async -> FluxMessage {
        let message = await pushOutgoing(chatId, .text, text: text, replyToId: replyToId, overrideExpiryMs: overrideExpiryMs)
        // +1 XP for sending a text message (skip system/bot chats).
        let chat = chatStorage[chatId]
        let peer = chat.flatMap { contacts[$0.peerId] }
        let isSystemChat = peer?.id == FluxUser.securityBotId || peer?.id == FluxUser.supportId
        if !isSystemChat, me != nil {
            _ = await awardXp(messageId: message.id, xp: 1)
        }
        return message
    }

    @discardableResult
    func sendImage(_ chatId: String, _ path: String, replyToId: String? = nil) async -> FluxMessage {
        await pushOutgoing(chatId, .image, mediaPath: path, text: "Фото", replyToId: replyToId)
    }

    @discardableResult
    func sendVoice(_ chatId: String, _ path: String, _ durationMs: Int, replyToId: String? = nil) async -> FluxMessage {
        await pushOutgoing(chatId, .voice, mediaPath: path, voiceDurationMs: durationMs, text: "Голосовое сообщение", replyToId: replyToId)
    }

    @discardableResult
    func sendFile(_ chatId: String, _ path: String, _ fileName: String, _ fileSize: Int, replyToId: String? = nil) async -> FluxMessage {
        await pushOutgoing(chatId, .file, mediaPath: path, fileName: fileName, fileSize: fileSize, text: fileName, replyToId: replyToId)
    }

    private func updateChatPreview(_ chatId: String, _ message: FluxMessage) {
        guard let chat = chatStorage[chatId] else { return }
        let preview: String
        switch message.kind {
        case .text: preview = message.text
        case .image: preview = "📷 Фото"
        case .voice: preview = "🎤 Голосовое сообщение"
        case .file: preview = "📎 \(message.fileName ?? "Файл")"
        }
        chatStorage[chatId] = FluxChat(
            id: chat.id, peerId: chat.peerId, createdAtMs: chat.createdAtMs,
            lastMessagePreview: preview,
            lastMessageAtMs: message.sentAtMs,
            unreadCount: chat.unreadCount, pinned: chat.pinned
        )
    }

    /// Demo peer lifecycle: delivered → typing → reply (+ read receipt).
    private func simulatePeerResponse(_ chatId: String) {
        guard let chat = chatStorage[chatId] else { return }
        let peerId = chat.peerId

        after(500) { [weak self] in
            guard let self else { return }
            let now = Int(Date().timeIntervalSince1970 * 1000)
            var changed = false
            for i in self.messageStorage.indices
            where self.messageStorage[i].chatId == chatId && self.messageStorage[i].senderId == (self.me?.id ?? "me") {
                if self.messageStorage[i].deliveredAtMs == nil {
                    self.messageStorage[i].deliveredAtMs = now
                    changed = true
                }
            }
            if changed {
                self.saveMessages()
                self.notify()
            }
        }

        if !privacy.hideTyping {
            after(1300) { [weak self] in
                guard let self else { return }
                self.typingChatIds.insert(chatId)
                self.notify()
            }
        }

        let replyDelay = 2600 + Int.random(in: 0..<1200)
        after(replyDelay) { [weak self] in
            guard let self else { return }
            self.typingChatIds.remove(chatId)
            let now = Int(Date().timeIntervalSince1970 * 1000)
            let replyText = Self.peerReplies.randomElement() ?? "Принято ✅"
            let reply = FluxMessage(
                id: UUID().uuidString,
                chatId: chatId,
                senderId: peerId,
                text: replyText,
                sentAtMs: now,
                deliveredAtMs: now,
                readAtMs: now
            )
            self.messageStorage.append(reply)
            self.updateChatPreview(chatId, reply)
            if var c = self.chatStorage[chatId] {
                c.unreadCount += 1
                self.chatStorage[chatId] = c
            }
            if self.privacy.readReceipts {
                for i in self.messageStorage.indices
                where self.messageStorage[i].chatId == chatId && self.messageStorage[i].senderId == (self.me?.id ?? "me") {
                    if self.messageStorage[i].readAtMs == nil {
                        self.messageStorage[i].readAtMs = now
                    }
                }
            }
            self.saveMessages()
            self.saveChats()
            self.notify()
        }
    }

    func editMessage(_ messageId: String, _ newText: String) async {
        guard let idx = messageStorage.firstIndex(where: { $0.id == messageId }) else { return }
        messageStorage[idx].text = newText
        messageStorage[idx].editedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        let chatId = messageStorage[idx].chatId
        if chatStorage[chatId]?.lastMessagePreview != nil {
            updateChatPreview(chatId, messageStorage[idx])
        }
        saveMessages()
        saveChats()
        notify()
    }

    func deleteMessage(_ messageId: String) async {
        guard let idx = messageStorage.firstIndex(where: { $0.id == messageId }) else { return }
        let removed = messageStorage.remove(at: idx)
        if let chat = chatStorage[removed.chatId] {
            let remaining = messagesOf(removed.chatId)
            if let last = remaining.last {
                updateChatPreview(removed.chatId, last)
                chatStorage[removed.chatId]?.lastMessageAtMs = last.sentAtMs
            } else {
                chatStorage[removed.chatId] = FluxChat(
                    id: chat.id, peerId: chat.peerId, createdAtMs: chat.createdAtMs,
                    lastMessagePreview: "", lastMessageAtMs: chat.lastMessageAtMs,
                    unreadCount: chat.unreadCount, pinned: chat.pinned
                )
            }
        }
        saveMessages()
        saveChats()
        notify()
    }

    func toggleReaction(_ messageId: String, _ emoji: String, _ userId: String) async {
        guard let idx = messageStorage.firstIndex(where: { $0.id == messageId }) else { return }
        var users = messageStorage[idx].reactions[emoji] ?? []
        if let existing = users.firstIndex(of: userId) {
            users.remove(at: existing)
        } else {
            users.append(userId)
        }
        if users.isEmpty {
            messageStorage[idx].reactions[emoji] = nil
        } else {
            messageStorage[idx].reactions[emoji] = users
        }
        saveMessages()
        notify()
    }

    private func scheduleExpiry(_ message: FluxMessage) {
        guard let expiresAtMs = message.expiresAtMs else { return }
        let delay = expiresAtMs - Int(Date().timeIntervalSince1970 * 1000)
        if delay <= 0 {
            Task { await deleteMessage(message.id) }
            return
        }
        after(delay) { [weak self] in
            guard let self else { return }
            Task { await self.deleteMessage(message.id) }
        }
    }

    /// Injects a message delivered by the network layer (Firestore
    /// listener). Duplicate ids are ignored.
    func ingestRemoteMessage(_ message: FluxMessage, preview: String? = nil) {
        guard !messageStorage.contains(where: { $0.id == message.id }) else { return }
        messageStorage.append(message)
        if let chat = chatStorage[message.chatId] {
            chatStorage[message.chatId] = FluxChat(
                id: chat.id, peerId: chat.peerId, createdAtMs: chat.createdAtMs,
                lastMessagePreview: preview ?? message.text,
                lastMessageAtMs: message.sentAtMs,
                unreadCount: chat.unreadCount + 1, pinned: chat.pinned
            )
        }
        if message.expiresAtMs != nil { scheduleExpiry(message) }
        saveMessages()
        saveChats()
        notify()
    }

    /// Appends a locally generated system message (screenshot warning,
    /// report confirmation) to an existing chat.
    func ingestScreenshotWarning(_ message: FluxMessage) {
        messageStorage.append(message)
        updateChatPreview(message.chatId, message)
        saveMessages()
        saveChats()
        notify()
    }

    /// Returns (and creates when needed) an empty chat for a peer id.
    @discardableResult
    func ensureChatForPeer(_ peerId: String) -> FluxChat {
        if let existing = chatWithPeer(peerId) { return existing }
        let chat = FluxChat(
            id: UUID().uuidString,
            peerId: peerId,
            createdAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
        chatStorage[chat.id] = chat
        saveChats()
        notify()
        return chat
    }

    // MARK: - Calls

    var calls: [CallRecord] {
        callStorage.sorted { $0.atMs > $1.atMs }
    }

    func logCall(peerId: String, type: CallType, direction: CallDirection, durationSec: Int = 0) async {
        callStorage.append(CallRecord(
            id: UUID().uuidString,
            peerId: peerId,
            type: type,
            direction: direction,
            atMs: Int(Date().timeIntervalSince1970 * 1000),
            durationSec: durationSec
        ))
        saveCalls()
        notify()
    }

    // MARK: - Privacy & prefs

    func updatePrivacy(_ next: PrivacySettings) async {
        privacy = next
        saveString(encodeJson(next.toJson()), forKey: Self.kPrivacy)
        notify()
    }

    func updatePrefs(_ next: AppPreferences) async {
        prefs = next
        saveString(encodeJson(next.toJson()), forKey: Self.kPrefs)
        notify()
    }

    // MARK: - Biometric quick-login

    var biometricLoginUsername: String? { bioLoginUsernameValue }

    func saveBiometricLogin(_ username: String) async {
        bioLoginUsernameValue = username
        defaults.set(username, forKey: Self.kBioLoginUsername)
    }

    func clearBiometricLogin() async {
        bioLoginUsernameValue = nil
        defaults.removeObject(forKey: Self.kBioLoginUsername)
    }

    // MARK: - XP

    /// Awards XP for an action. Protected by messageId deduplication.
    /// Returns (newLevel, newBadges) when a level-up occurred, nil otherwise.
    func awardXp(messageId: String, xp: Int = 1) async -> (level: Int, badges: [FluxBadge])? {
        guard !awardedXpMessageIds.contains(messageId) else { return nil }
        awardedXpMessageIds.insert(messageId)

        let oldLevel = userProfileValue.level
        userProfileValue.activityPoints += xp

        let newBadges = checkAndAwardBadges(userProfileValue)
        if !newBadges.isEmpty {
            userProfileValue.badges.append(contentsOf: newBadges)
        }

        saveUserProfile()
        saveAwardedXpIds()
        notify()

        let newLevel = userProfileValue.level
        if newLevel > oldLevel {
            return (newLevel, newBadges)
        }
        return nil
    }

    /// Checks which XP milestone badges should be awarded.
    private func checkAndAwardBadges(_ profile: UserProfile) -> [FluxBadge] {
        let existingIds = Set(profile.badges.map { $0.id })
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        return BadgeCatalog.xpMilestones.filter {
            !existingIds.contains($0.id) && profile.activityPoints >= $0.xpPoints
        }.map { $0.withEarned(atMs: nowMs) }
    }

    /// Restores XP and badges from a remote source (Firestore).
    func restoreProfileFromRemote(_ xp: Int, _ badges: [FluxBadge]) async {
        userProfileValue.activityPoints = xp
        if !badges.isEmpty { userProfileValue.badges = badges }
        saveUserProfile()
        notify()
    }

    func restoreCoinsFromRemote(_ coins: Int) async {
        userProfileValue.fluxCoins = coins
        saveUserProfile()
        notify()
    }

    /// Replaces the extended profile with a merged local+remote snapshot
    /// prepared by the network layer.
    func mergeRemoteProfile(_ merged: UserProfile) async {
        userProfileValue = merged
        saveUserProfile()
        notify()
    }

    // MARK: - Gifts

    func profileOf(_ userId: String) -> UserProfile? {
        let myId = me?.id ?? "me"
        if userId == myId { return userProfileValue }
        return userProfiles[userId]
    }

    @discardableResult
    func sendGift(toUserId: String, catalogId: String, message: String?) async throws -> FluxGift {
        guard let catalog = GiftCatalog.findById(catalogId) else {
            throw FluxError("Unknown gift catalogId: \(catalogId)")
        }
        guard let sender = me else { throw FluxError.notLoggedIn }
        if userProfileValue.fluxCoins < catalog.cost {
            throw FluxError.insufficientCoins(catalog.cost, userProfileValue.fluxCoins)
        }

        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let gift = FluxGift(
            id: UUID().uuidString,
            catalogId: catalogId,
            fromUserId: sender.id,
            fromUserName: sender.name,
            toUserId: toUserId,
            emoji: catalog.emoji,
            name: catalog.name,
            rarity: catalog.rarity,
            sentAtMs: nowMs,
            message: message
        )

        // Deduct coins with a recorded transaction (balance re-checked).
        try await spendCoinsWithTransaction(
            amount: catalog.cost,
            type: .giftSent,
            description: "Подарок «\(catalog.name)»",
            relatedObjectId: gift.id
        )

        var recipientProfile = userProfiles[toUserId] ?? UserProfile()
        recipientProfile.gifts.insert(gift, at: 0)
        userProfiles[toUserId] = recipientProfile
        saveUserProfiles()

        let myId = me?.id ?? "me"
        if toUserId == myId {
            userProfileValue.gifts.insert(gift, at: 0)
            saveUserProfile()
            _ = await awardXp(messageId: "gift_\(gift.id)", xp: 10)
        }

        notify()
        return gift
    }

    // MARK: - Flux Coins

    func awardCoins(_ amount: Int) async {
        userProfileValue.fluxCoins += amount
        saveUserProfile()
        notify()
    }

    func spendCoins(_ amount: Int) async throws {
        if userProfileValue.fluxCoins < amount {
            throw FluxError.insufficientCoins(amount, userProfileValue.fluxCoins)
        }
        userProfileValue.fluxCoins -= amount
        saveUserProfile()
        notify()
    }

    var coinTransactions: [CoinTransaction] {
        userProfileValue.coinTransactions
    }

    func awardCoinsWithTransaction(amount: Int, type: CoinTransactionType, description: String = "", relatedObjectId: String? = nil) async {
        guard amount != 0 else { return }
        let tx = CoinTransaction(
            id: UUID().uuidString,
            userId: me?.id ?? "me",
            amount: amount,
            type: type,
            timestampMs: Int(Date().timeIntervalSince1970 * 1000),
            description: description,
            relatedObjectId: relatedObjectId
        )
        userProfileValue.fluxCoins += amount
        userProfileValue.coinTransactions.insert(tx, at: 0)
        saveUserProfile()
        notify()
    }

    func spendCoinsWithTransaction(amount: Int, type: CoinTransactionType, description: String = "", relatedObjectId: String? = nil) async throws {
        guard amount != 0 else { return }
        if userProfileValue.fluxCoins < amount {
            throw FluxError.insufficientCoins(amount, userProfileValue.fluxCoins)
        }
        let tx = CoinTransaction(
            id: UUID().uuidString,
            userId: me?.id ?? "me",
            amount: -amount,
            type: type,
            timestampMs: Int(Date().timeIntervalSince1970 * 1000),
            description: description,
            relatedObjectId: relatedObjectId
        )
        userProfileValue.fluxCoins -= amount
        userProfileValue.coinTransactions.insert(tx, at: 0)
        saveUserProfile()
        notify()
    }

    // MARK: - Signatures (guestbook)

    @discardableResult
    func sendSignature(profileOwnerId: String, text: String) async throws -> ProfileSignature {
        guard let sender = me else { throw FluxError.notLoggedIn }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FluxError("Подпись не может быть пустой") }

        let isOwn = profileOwnerId == sender.id
        var target = isOwn ? userProfileValue : (userProfiles[profileOwnerId] ?? UserProfile())

        if !target.visibility.allowSignatures {
            throw FluxError("Владелец профиля запретил подписи")
        }
        if target.visibility.blockedSignatureUserIds.contains(sender.id) {
            throw FluxError("Владелец профиля заблокировал подписи от вас")
        }

        let signature = ProfileSignature(
            id: UUID().uuidString,
            authorId: sender.id,
            authorName: sender.name,
            profileOwnerId: profileOwnerId,
            text: trimmed,
            createdAtMs: Int(Date().timeIntervalSince1970 * 1000),
            status: target.visibility.requireSignatureApproval ? .pending : .approved
        )

        target.signatures.insert(signature, at: 0)
        if isOwn {
            userProfileValue = target
            saveUserProfile()
        } else {
            userProfiles[profileOwnerId] = target
            saveUserProfiles()
        }
        notify()
        return signature
    }

    func updateSignatureStatus(_ signatureId: String, _ status: SignatureStatus) async {
        userProfileValue.signatures = userProfileValue.signatures.map {
            $0.id == signatureId
                ? ProfileSignature(id: $0.id, authorId: $0.authorId, authorName: $0.authorName, profileOwnerId: $0.profileOwnerId, text: $0.text, createdAtMs: $0.createdAtMs, status: status)
                : $0
        }
        saveUserProfile()
        notify()
    }

    func deleteSignature(_ signatureId: String) async {
        userProfileValue.signatures.removeAll { $0.id == signatureId }
        saveUserProfile()
        notify()
    }

    // MARK: - Additional usernames & Marketplace

    var additionalUsernames: [UsernameEntry] {
        userProfileValue.additionalUsernames
    }

    var marketplaceListings: [MarketplaceListing] {
        marketplaceStorage.filter { !$0.sold }
    }

    @discardableResult
    func listUsernameForSale(username: String, price: Int) async throws -> MarketplaceListing {
        guard let cur = me else { throw FluxError.notLoggedIn }
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "").lowercased()
        guard price > 0 else { throw FluxError("Цена должна быть больше нуля") }
        guard normalized != cur.username?.lowercased() else {
            throw FluxError("Основной username аккаунта не продаётся")
        }
        guard userProfileValue.additionalUsernames.contains(where: { $0.username.lowercased() == normalized }) else {
            throw FluxError("Этот username вам не принадлежит")
        }
        guard !marketplaceStorage.contains(where: { !$0.sold && $0.username.lowercased() == normalized }) else {
            throw FluxError("Username уже выставлен на продажу")
        }

        let listing = MarketplaceListing(
            id: UUID().uuidString,
            username: normalized,
            sellerId: cur.id,
            sellerName: cur.name,
            price: price,
            listedAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
        marketplaceStorage.insert(listing, at: 0)
        saveMarketplace()
        notify()
        return listing
    }

    func buyUsername(_ listingId: String) async throws {
        guard let listing = marketplaceStorage.first(where: { $0.id == listingId }) else {
            throw FluxError("Лот не найден")
        }
        guard !listing.sold else { throw FluxError("Этот username уже продан") }
        guard let cur = me else { throw FluxError.notLoggedIn }
        guard listing.sellerId != cur.id else { throw FluxError("Нельзя купить свой собственный лот") }
        guard cur.username?.lowercased() != listing.username else {
            throw FluxError("Этот username уже является вашим основным")
        }
        guard !userProfileValue.additionalUsernames.contains(where: { $0.username.lowercased() == listing.username }) else {
            throw FluxError("Этот username уже принадлежит вам")
        }
        guard userProfileValue.fluxCoins >= listing.price else {
            throw FluxError.insufficientCoins(listing.price, userProfileValue.fluxCoins)
        }

        // Purchase sequence: mark sold → deduct coins → transfer ownership.
        if let idx = marketplaceStorage.firstIndex(where: { $0.id == listingId }) {
            marketplaceStorage[idx].sold = true
        }

        try await spendCoinsWithTransaction(
            amount: listing.price,
            type: .usernamePurchase,
            description: "Покупка username @\(listing.username)",
            relatedObjectId: listing.id
        )

        userProfileValue.additionalUsernames.insert(
            UsernameEntry(
                username: listing.username,
                ownerId: cur.id,
                acquiredAtMs: Int(Date().timeIntervalSince1970 * 1000)
            ),
            at: 0
        )
        saveUserProfile()

        // Credit the seller when their profile is known locally (demo mode).
        if var sellerProfile = userProfiles[listing.sellerId] {
            sellerProfile.additionalUsernames.removeAll { $0.username.lowercased() == listing.username }
            sellerProfile.fluxCoins += listing.price
            sellerProfile.coinTransactions.insert(CoinTransaction(
                id: UUID().uuidString,
                userId: listing.sellerId,
                amount: listing.price,
                type: .usernameSale,
                timestampMs: Int(Date().timeIntervalSince1970 * 1000),
                description: "Продажа username @\(listing.username)",
                relatedObjectId: listing.id
            ), at: 0)
            userProfiles[listing.sellerId] = sellerProfile
            saveUserProfiles()
        }

        saveMarketplace()
        notify()
    }

    func cancelListing(_ listingId: String) async {
        guard let listing = marketplaceStorage.first(where: { $0.id == listingId }),
              !listing.sold, listing.sellerId == me?.id else { return }
        marketplaceStorage.removeAll { $0.id == listingId }
        saveMarketplace()
        notify()
    }

    // MARK: - Daily streak

    var dailyStreak: DailyStreak { userProfileValue.dailyStreak }

    private static func dayKey(_ d: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// Updates the daily streak. Consecutive-day login → +1; a missed day
    /// restarts the streak at 1. Returns true when the streak increased.
    @discardableResult
    func checkAndUpdateDailyStreak() async -> Bool {
        let now = Date()
        let today = Self.dayKey(now)
        let streak = userProfileValue.dailyStreak
        guard streak.lastLoginDate != today else { return false }

        let yesterday = Self.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
        let next = streak.lastLoginDate == yesterday ? streak.currentStreak + 1 : 1

        userProfileValue.dailyStreak = DailyStreak(
            lastLoginDate: today,
            currentStreak: next,
            longestStreak: max(next, streak.longestStreak)
        )
        saveUserProfile()

        // Daily login reward — the regular (non-admin) source of Flux Coins.
        await awardCoinsWithTransaction(
            amount: 25,
            type: .dailyReward,
            description: "Ежедневная награда · день \(next)"
        )
        return true
    }

    // MARK: - Profile visibility

    var profileVisibility: ProfileVisibility { userProfileValue.visibility }

    func updateVisibility(_ visibility: ProfileVisibility) async {
        userProfileValue.visibility = visibility
        saveUserProfile()
        notify()
    }

    // MARK: - Badge shop

    func purchaseBadge(_ badgeId: String) async throws {
        guard let badge = BadgeShopCatalog.findById(badgeId) else {
            throw FluxError("Неизвестный бейдж: \(badgeId)")
        }
        guard !userProfileValue.badges.contains(where: { $0.id == badgeId }) else {
            throw FluxError("Этот бейдж уже получен")
        }
        try await spendCoinsWithTransaction(
            amount: badge.cost,
            type: .badgePurchase,
            description: "Покупка бейджа «\(badge.name)»",
            relatedObjectId: badge.id
        )
        userProfileValue.badges.append(badge.withEarned(atMs: Int(Date().timeIntervalSince1970 * 1000)))
        saveUserProfile()
        notify()
    }

    // MARK: - Reports

    /// Posts a user report into the security-bot chat (a real action for
    /// the profile "Пожаловаться" button).
    func submitReport(against user: FluxUser) async {
        let bot = securityBotUser()
        let chat = await openChatWithUser(bot)
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let text = "⚠️ Жалоба на пользователя \(user.name) (@\(user.username ?? "—"), \(user.fluxId))"
        let message = FluxMessage(
            id: UUID().uuidString,
            chatId: chat.id,
            senderId: FluxUser.systemSecurityBotId,
            text: text,
            sentAtMs: nowMs,
            isSystemMessage: true
        )
        messageStorage.append(message)
        updateChatPreview(chat.id, message)
        saveMessages()
        saveChats()
        notify()
    }

    // MARK: - Remote-profile caching (used by the Firestore backend)

    func cacheRemoteProfile(_ userId: String, _ profile: UserProfile) {
        userProfiles[userId] = profile
        saveUserProfiles()
        notify()
    }

    /// Replaces the local marketplace cache with the remote snapshot.
    func syncMarketplaceListings(_ remote: [MarketplaceListing]) {
        let myId = me?.id
        var merged = Dictionary(uniqueKeysWithValues: marketplaceStorage.map { ($0.id, $0) })
        for listing in remote {
            if let myId, listing.sellerId == myId { continue }
            merged[listing.id] = listing
        }
        marketplaceStorage = merged.values.sorted { $0.listedAtMs > $1.listedAtMs }
        saveMarketplace()
        notify()
    }
}
