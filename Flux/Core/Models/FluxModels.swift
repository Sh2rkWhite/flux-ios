import Foundation

// MARK: - FluxUser

/// A Flux user — either the local profile or a known contact.
/// JSON field names mirror the Android implementation exactly so both
/// platforms read and write identical Firestore / local-storage shapes.
struct FluxUser: Identifiable, Equatable, Codable {
    var id: String
    /// Public Flux identifier, e.g. `FLX-7K2M9QXR`.
    var fluxId: String
    var name: String
    /// Unique searchable @username chosen at registration (latin, digits, _).
    var username: String?
    var status: String
    var avatarPath: String?
    var isPremium: Bool
    var isOnline: Bool
    var lastSeenMs: Int?
    /// Admin role flag — UI gates the admin panel on it.
    var isAdmin: Bool
    var sessions: [DeviceSession]
    /// Epoch ms when the account was first created.
    var registeredAtMs: Int?
    /// Blue checkmark flag.
    var isVerified: Bool
    /// Salted SHA-256 password hash (`salt:sha256(salt:pwd)`). Local-only.
    var passwordHash: String?
    /// Optional email collected at registration. Local-only.
    var email: String?

    /// Moderation: muted until (epoch ms, 0 = not muted). Muted users
    /// cannot start NEW conversations but keep chatting in existing ones.
    var mutedUntilMs: Int
    /// Moderation: frozen until (epoch ms, 0 = not frozen). Frozen users
    /// are read-only.
    var frozenUntilMs: Int
    var mutedReason: String?
    var frozenReason: String?

    var isMuted: Bool { mutedUntilMs > Int(Date().timeIntervalSince1970 * 1000) }
    var isFrozen: Bool { frozenUntilMs > Int(Date().timeIntervalSince1970 * 1000) }

    static let supportId = "flux-support"
    static let securityBotId = "flux-security"
    /// Sender id used when the security bot posts a system notification.
    static let systemSecurityBotId = "system_security_bot"
    /// Fixed id of the Flux Coins bot (@FluxCoinsBot).
    static let coinsBotId = "flux-coins-bot"

    var isSupport: Bool { id == FluxUser.supportId }
    var isSecurityBot: Bool { id == FluxUser.securityBotId }
    var isCoinsBot: Bool { id == FluxUser.coinsBotId }

    init(
        id: String,
        fluxId: String,
        name: String,
        username: String? = nil,
        status: String = "",
        avatarPath: String? = nil,
        isPremium: Bool = false,
        isOnline: Bool = false,
        lastSeenMs: Int? = nil,
        isAdmin: Bool = false,
        sessions: [DeviceSession] = [],
        registeredAtMs: Int? = nil,
        isVerified: Bool = false,
        passwordHash: String? = nil,
        email: String? = nil,
        mutedUntilMs: Int = 0,
        frozenUntilMs: Int = 0,
        mutedReason: String? = nil,
        frozenReason: String? = nil
    ) {
        self.id = id
        self.fluxId = fluxId
        self.name = name
        self.username = username
        self.status = status
        self.avatarPath = avatarPath
        self.isPremium = isPremium
        self.isOnline = isOnline
        self.lastSeenMs = lastSeenMs
        self.isAdmin = isAdmin
        self.sessions = sessions
        self.registeredAtMs = registeredAtMs
        self.isVerified = isVerified
        self.passwordHash = passwordHash
        self.email = email
        self.mutedUntilMs = mutedUntilMs
        self.frozenUntilMs = frozenUntilMs
        self.mutedReason = mutedReason
        self.frozenReason = frozenReason
    }

    // Custom Codable so documents persisted before the moderation fields
    // existed still decode correctly (missing keys default to 0/nil).
    private enum CodingKeys: String, CodingKey {
        case id, fluxId, name, username, status, avatarPath, isPremium,
             isOnline, lastSeenMs, isAdmin, sessions, registeredAtMs,
             isVerified, passwordHash, email,
             mutedUntilMs, frozenUntilMs, mutedReason, frozenReason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fluxId = try c.decode(String.self, forKey: .fluxId)
        name = try c.decode(String.self, forKey: .name)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        avatarPath = try c.decodeIfPresent(String.self, forKey: .avatarPath)
        isPremium = try c.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        isOnline = try c.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
        lastSeenMs = try c.decodeIfPresent(Int.self, forKey: .lastSeenMs)
        isAdmin = try c.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        sessions = try c.decodeIfPresent([DeviceSession].self, forKey: .sessions) ?? []
        registeredAtMs = try c.decodeIfPresent(Int.self, forKey: .registeredAtMs)
        isVerified = try c.decodeIfPresent(Bool.self, forKey: .isVerified) ?? false
        passwordHash = try c.decodeIfPresent(String.self, forKey: .passwordHash)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        mutedUntilMs = try c.decodeIfPresent(Int.self, forKey: .mutedUntilMs) ?? 0
        frozenUntilMs = try c.decodeIfPresent(Int.self, forKey: .frozenUntilMs) ?? 0
        mutedReason = try c.decodeIfPresent(String.self, forKey: .mutedReason)
        frozenReason = try c.decodeIfPresent(String.self, forKey: .frozenReason)
    }

    // ── JSON (identical keys to the Android implementation) ────────────

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "fluxId": fluxId,
            "name": name,
            "status": status,
            "isPremium": isPremium,
            "isOnline": isOnline,
            "isAdmin": isAdmin,
            "sessions": sessions.map { $0.toJson() },
            "isVerified": isVerified,
            "mutedUntilMs": mutedUntilMs,
            "frozenUntilMs": frozenUntilMs,
        ]
        json["username"] = username
        if let avatarPath { json["avatarPath"] = avatarPath }
        if let lastSeenMs { json["lastSeenMs"] = lastSeenMs }
        if let registeredAtMs { json["registeredAtMs"] = registeredAtMs }
        if let passwordHash { json["passwordHash"] = passwordHash }
        if let email { json["email"] = email }
        if let mutedReason { json["mutedReason"] = mutedReason }
        if let frozenReason { json["frozenReason"] = frozenReason }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> FluxUser {
        FluxUser(
            id: json["id"] as? String ?? "",
            fluxId: json["fluxId"] as? String ?? "",
            name: json["name"] as? String ?? "",
            username: json["username"] as? String,
            status: json["status"] as? String ?? "",
            avatarPath: json["avatarPath"] as? String,
            isPremium: json["isPremium"] as? Bool ?? false,
            isOnline: json["isOnline"] as? Bool ?? false,
            lastSeenMs: (json["lastSeenMs"] as? NSNumber)?.intValue,
            isAdmin: json["isAdmin"] as? Bool ?? false,
            sessions: (json["sessions"] as? [[String: Any]])?.map(DeviceSession.fromJson) ?? [],
            registeredAtMs: (json["registeredAtMs"] as? NSNumber)?.intValue,
            isVerified: json["isVerified"] as? Bool ?? false,
            passwordHash: json["passwordHash"] as? String,
            email: json["email"] as? String,
            mutedUntilMs: (json["mutedUntilMs"] as? NSNumber)?.intValue ?? 0,
            frozenUntilMs: (json["frozenUntilMs"] as? NSNumber)?.intValue ?? 0,
            mutedReason: json["mutedReason"] as? String,
            frozenReason: json["frozenReason"] as? String
        )
    }
}

// MARK: - DeviceSession

/// A single active login session for the local user.
struct DeviceSession: Identifiable, Equatable, Codable {
    var id: String
    var deviceName: String
    var loginAtMs: Int
    var ip: String?
    var platform: String?
    var revoked: Bool

    init(id: String, deviceName: String, loginAtMs: Int, ip: String? = nil, platform: String? = nil, revoked: Bool = false) {
        self.id = id
        self.deviceName = deviceName
        self.loginAtMs = loginAtMs
        self.ip = ip
        self.platform = platform
        self.revoked = revoked
    }

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "deviceName": deviceName,
            "loginAtMs": loginAtMs,
            "revoked": revoked,
        ]
        if let ip { json["ip"] = ip }
        if let platform { json["platform"] = platform }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> DeviceSession {
        DeviceSession(
            id: json["id"] as? String ?? UUID().uuidString,
            deviceName: json["deviceName"] as? String ?? "Unknown",
            loginAtMs: (json["loginAtMs"] as? NSNumber)?.intValue ?? 0,
            ip: json["ip"] as? String,
            platform: json["platform"] as? String,
            revoked: json["revoked"] as? Bool ?? false
        )
    }
}

// MARK: - Messages

enum MessageKind: String, Codable {
    case text, image, voice, file
}

/// A single chat message.
struct FluxMessage: Identifiable, Equatable {
    var id: String
    var chatId: String
    var senderId: String
    var kind: MessageKind
    var text: String
    var mediaPath: String?
    var fileName: String?
    var fileSize: Int?
    var voiceDurationMs: Int
    var sentAtMs: Int
    var deliveredAtMs: Int?
    var readAtMs: Int?
    var editedAtMs: Int?
    var replyToId: String?
    var expiresAtMs: Int?
    /// Posted by a system channel (security bot) — rendered as a shield card.
    var isSystemMessage: Bool
    /// emoji -> user ids
    var reactions: [String: [String]]

    init(
        id: String,
        chatId: String,
        senderId: String,
        kind: MessageKind = .text,
        text: String = "",
        mediaPath: String? = nil,
        fileName: String? = nil,
        fileSize: Int? = nil,
        voiceDurationMs: Int = 0,
        sentAtMs: Int,
        deliveredAtMs: Int? = nil,
        readAtMs: Int? = nil,
        editedAtMs: Int? = nil,
        replyToId: String? = nil,
        expiresAtMs: Int? = nil,
        isSystemMessage: Bool = false,
        reactions: [String: [String]] = [:]
    ) {
        self.id = id
        self.chatId = chatId
        self.senderId = senderId
        self.kind = kind
        self.text = text
        self.mediaPath = mediaPath
        self.fileName = fileName
        self.fileSize = fileSize
        self.voiceDurationMs = voiceDurationMs
        self.sentAtMs = sentAtMs
        self.deliveredAtMs = deliveredAtMs
        self.readAtMs = readAtMs
        self.editedAtMs = editedAtMs
        self.replyToId = replyToId
        self.expiresAtMs = expiresAtMs
        self.isSystemMessage = isSystemMessage
        self.reactions = reactions
    }

    var isRead: Bool { readAtMs != nil }
    var isDelivered: Bool { deliveredAtMs != nil }
    var isEdited: Bool { editedAtMs != nil }

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "chatId": chatId,
            "senderId": senderId,
            "kind": kind.rawValue,
            "text": text,
            "voiceDurationMs": voiceDurationMs,
            "sentAtMs": sentAtMs,
            "reactions": reactions,
            "isSystemMessage": isSystemMessage,
        ]
        if let mediaPath { json["mediaPath"] = mediaPath }
        if let fileName { json["fileName"] = fileName }
        if let fileSize { json["fileSize"] = fileSize }
        if let deliveredAtMs { json["deliveredAtMs"] = deliveredAtMs }
        if let readAtMs { json["readAtMs"] = readAtMs }
        if let editedAtMs { json["editedAtMs"] = editedAtMs }
        if let replyToId { json["replyToId"] = replyToId }
        if let expiresAtMs { json["expiresAtMs"] = expiresAtMs }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> FluxMessage {
        let reactionsRaw = json["reactions"] as? [String: Any] ?? [:]
        var reactions: [String: [String]] = [:]
        for (emoji, value) in reactionsRaw {
            if let ids = value as? [String] {
                reactions[emoji] = ids
            } else if let ids = value as? [Any] {
                reactions[emoji] = ids.compactMap { ($0 as? String) }
            }
        }
        return FluxMessage(
            id: json["id"] as? String ?? UUID().uuidString,
            chatId: json["chatId"] as? String ?? "",
            senderId: json["senderId"] as? String ?? "",
            kind: MessageKind(rawValue: json["kind"] as? String ?? "text") ?? .text,
            text: json["text"] as? String ?? "",
            mediaPath: json["mediaPath"] as? String,
            fileName: json["fileName"] as? String,
            fileSize: (json["fileSize"] as? NSNumber)?.intValue,
            voiceDurationMs: (json["voiceDurationMs"] as? NSNumber)?.intValue ?? 0,
            sentAtMs: (json["sentAtMs"] as? NSNumber)?.intValue ?? 0,
            deliveredAtMs: (json["deliveredAtMs"] as? NSNumber)?.intValue,
            readAtMs: (json["readAtMs"] as? NSNumber)?.intValue,
            editedAtMs: (json["editedAtMs"] as? NSNumber)?.intValue,
            replyToId: json["replyToId"] as? String,
            expiresAtMs: (json["expiresAtMs"] as? NSNumber)?.intValue,
            isSystemMessage: json["isSystemMessage"] as? Bool ?? false,
            reactions: reactions
        )
    }
}

// MARK: - Chats

/// A conversation with a peer.
struct FluxChat: Identifiable, Equatable, Codable {
    var id: String
    var peerId: String
    var createdAtMs: Int
    var lastMessagePreview: String
    var lastMessageAtMs: Int
    var unreadCount: Int
    var pinned: Bool

    init(
        id: String,
        peerId: String,
        createdAtMs: Int,
        lastMessagePreview: String = "",
        lastMessageAtMs: Int = 0,
        unreadCount: Int = 0,
        pinned: Bool = false
    ) {
        self.id = id
        self.peerId = peerId
        self.createdAtMs = createdAtMs
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageAtMs = lastMessageAtMs
        self.unreadCount = unreadCount
        self.pinned = pinned
    }

    func toJson() -> [String: Any] {
        [
            "id": id,
            "peerId": peerId,
            "createdAtMs": createdAtMs,
            "lastMessagePreview": lastMessagePreview,
            "lastMessageAtMs": lastMessageAtMs,
            "unreadCount": unreadCount,
            "pinned": pinned,
        ]
    }

    static func fromJson(_ json: [String: Any]) -> FluxChat {
        FluxChat(
            id: json["id"] as? String ?? UUID().uuidString,
            peerId: json["peerId"] as? String ?? "",
            createdAtMs: (json["createdAtMs"] as? NSNumber)?.intValue ?? 0,
            lastMessagePreview: json["lastMessagePreview"] as? String ?? "",
            lastMessageAtMs: (json["lastMessageAtMs"] as? NSNumber)?.intValue ?? 0,
            unreadCount: (json["unreadCount"] as? NSNumber)?.intValue ?? 0,
            pinned: json["pinned"] as? Bool ?? false
        )
    }
}

// MARK: - Calls

enum CallType: String, Codable {
    case audio, video
}

enum CallDirection: String, Codable {
    case incoming, outgoing, missed
}

/// A record in the calls history.
struct CallRecord: Identifiable, Equatable, Codable {
    var id: String
    var peerId: String
    var type: CallType
    var direction: CallDirection
    var atMs: Int
    var durationSec: Int

    init(id: String, peerId: String, type: CallType, direction: CallDirection, atMs: Int, durationSec: Int = 0) {
        self.id = id
        self.peerId = peerId
        self.type = type
        self.direction = direction
        self.atMs = atMs
        self.durationSec = durationSec
    }

    func toJson() -> [String: Any] {
        [
            "id": id,
            "peerId": peerId,
            "type": type.rawValue,
            "direction": direction.rawValue,
            "atMs": atMs,
            "durationSec": durationSec,
        ]
    }

    static func fromJson(_ json: [String: Any]) -> CallRecord {
        CallRecord(
            id: json["id"] as? String ?? UUID().uuidString,
            peerId: json["peerId"] as? String ?? "",
            type: CallType(rawValue: json["type"] as? String ?? "audio") ?? .audio,
            direction: CallDirection(rawValue: json["direction"] as? String ?? "outgoing") ?? .outgoing,
            atMs: (json["atMs"] as? NSNumber)?.intValue ?? 0,
            durationSec: (json["durationSec"] as? NSNumber)?.intValue ?? 0
        )
    }
}

// MARK: - Auto-delete

/// Auto-delete timer options for messages.
enum AutoDelete: String, Codable, CaseIterable {
    case never, s30, m5, h1, d1, w1

    var durationMs: Int? {
        switch self {
        case .never: return nil
        case .s30: return 30_000
        case .m5: return 300_000
        case .h1: return 3_600_000
        case .d1: return 86_400_000
        case .w1: return 604_800_000
        }
    }

    var labelRu: String {
        switch self {
        case .never: return "Никогда"
        case .s30: return "30 секунд"
        case .m5: return "5 минут"
        case .h1: return "1 час"
        case .d1: return "1 день"
        case .w1: return "1 неделя"
        }
    }
}

// MARK: - Privacy & preferences

/// All privacy controls — every flag is persisted and influences behaviour.
struct PrivacySettings: Equatable, Codable {
    var privacyMode = false
    var showOnline = true
    var showLastSeen = true
    var readReceipts = true
    var hideTyping = false
    var blockScreenshots = false
    var forbidForward = false
    var fatalMessages = false
    var autoDelete: AutoDelete = .never
    var appLockEnabled = false
    /// `salt:sha256(salt:pin)` — the plain PIN is never stored.
    var appLockPinHash: String?
    var appLockBiometrics = false

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "privacyMode": privacyMode,
            "showOnline": showOnline,
            "showLastSeen": showLastSeen,
            "readReceipts": readReceipts,
            "hideTyping": hideTyping,
            "blockScreenshots": blockScreenshots,
            "forbidForward": forbidForward,
            "fatalMessages": fatalMessages,
            "autoDelete": autoDelete.rawValue,
            "appLockEnabled": appLockEnabled,
            "appLockBiometrics": appLockBiometrics,
        ]
        if let appLockPinHash { json["appLockPinHash"] = appLockPinHash }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> PrivacySettings {
        var settings = PrivacySettings()
        settings.privacyMode = json["privacyMode"] as? Bool ?? false
        settings.showOnline = json["showOnline"] as? Bool ?? true
        settings.showLastSeen = json["showLastSeen"] as? Bool ?? true
        settings.readReceipts = json["readReceipts"] as? Bool ?? true
        settings.hideTyping = json["hideTyping"] as? Bool ?? false
        settings.blockScreenshots = json["blockScreenshots"] as? Bool ?? false
        settings.forbidForward = json["forbidForward"] as? Bool ?? false
        settings.fatalMessages = json["fatalMessages"] as? Bool ?? false
        settings.autoDelete = AutoDelete(rawValue: json["autoDelete"] as? String ?? "never") ?? .never
        settings.appLockEnabled = json["appLockEnabled"] as? Bool ?? false
        settings.appLockPinHash = json["appLockPinHash"] as? String
        settings.appLockBiometrics = json["appLockBiometrics"] as? Bool ?? false
        return settings
    }
}

/// App-wide preferences (notifications, language, theme).
struct AppPreferences: Equatable, Codable {
    var notifications = true
    var messagePreview = true
    var sounds = true
    var language = "ru"
    /// light | dark | system
    var themeMode = "light"

    func toJson() -> [String: Any] {
        [
            "notifications": notifications,
            "messagePreview": messagePreview,
            "sounds": sounds,
            "language": language,
            "themeMode": themeMode,
        ]
    }

    static func fromJson(_ json: [String: Any]) -> AppPreferences {
        var prefs = AppPreferences()
        prefs.notifications = json["notifications"] as? Bool ?? true
        prefs.messagePreview = json["messagePreview"] as? Bool ?? true
        prefs.sounds = json["sounds"] as? Bool ?? true
        prefs.language = json["language"] as? String ?? "ru"
        prefs.themeMode = json["themeMode"] as? String ?? "light"
        return prefs
    }
}
