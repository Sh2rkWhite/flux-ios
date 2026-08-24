import Foundation
import SwiftUI

// MARK: - Badges

/// Badge type determines how a badge is obtained.
enum BadgeType: String, Codable {
    case system, achievement, premium, shop, event

    var label: String {
        switch self {
        case .system: return "Системный"
        case .achievement: return "Достижение"
        case .premium: return "Премиум"
        case .shop: return "Магазин"
        case .event: return "Событие"
        }
    }
}

/// Badge rarity levels.
enum BadgeRarity: String, Codable, CaseIterable {
    case common, uncommon, rare, epic, legendary, mythic

    var label: String {
        switch self {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "Legendary"
        case .mythic: return "Mythic"
        }
    }

    var color: Color {
        switch self {
        case .common: return Color(hex: 0x9AA1B5)
        case .uncommon: return Color(hex: 0x34C77B)
        case .rare: return Color(hex: 0x3E8BFF)
        case .epic: return Color(hex: 0x8A5CFF)
        case .legendary: return Color(hex: 0xFFB020)
        case .mythic: return Color(hex: 0xFF4D5E)
        }
    }
}

/// A badge that can be awarded to a user.
struct FluxBadge: Identifiable, Equatable, Codable {
    var id: String
    var name: String
    var description: String
    var emoji: String
    var rarity: BadgeRarity
    var badgeType: BadgeType
    var xpPoints: Int
    var cost: Int
    var earnedAtMs: Int?

    init(
        id: String,
        name: String,
        description: String,
        emoji: String,
        rarity: BadgeRarity,
        badgeType: BadgeType = .achievement,
        xpPoints: Int = 0,
        cost: Int = 0,
        earnedAtMs: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.emoji = emoji
        self.rarity = rarity
        self.badgeType = badgeType
        self.xpPoints = xpPoints
        self.cost = cost
        self.earnedAtMs = earnedAtMs
    }

    var isPurchasable: Bool { badgeType == .shop && cost > 0 }

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "name": name,
            "description": description,
            "emoji": emoji,
            "rarity": rarity.rawValue,
            "badgeType": badgeType.rawValue,
            "xpPoints": xpPoints,
            "cost": cost,
        ]
        if let earnedAtMs { json["earnedAtMs"] = earnedAtMs }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> FluxBadge {
        FluxBadge(
            id: json["id"] as? String ?? "",
            name: json["name"] as? String ?? "",
            description: json["description"] as? String ?? "",
            emoji: json["emoji"] as? String ?? "🏅",
            rarity: BadgeRarity(rawValue: json["rarity"] as? String ?? "common") ?? .common,
            badgeType: BadgeType(rawValue: json["badgeType"] as? String ?? "achievement") ?? .achievement,
            xpPoints: (json["xpPoints"] as? NSNumber)?.intValue ?? 0,
            cost: (json["cost"] as? NSNumber)?.intValue ?? 0,
            earnedAtMs: (json["earnedAtMs"] as? NSNumber)?.intValue
        )
    }
}

// MARK: - Levels

struct LevelConfig {
    let level: Int
    let xpRequired: Int
}

/// The full level table — thresholds are configurable by editing this list.
let kLevelTable: [LevelConfig] = [
    LevelConfig(level: 1, xpRequired: 0),
    LevelConfig(level: 2, xpRequired: 10),
    LevelConfig(level: 3, xpRequired: 25),
    LevelConfig(level: 4, xpRequired: 50),
    LevelConfig(level: 5, xpRequired: 100),
    LevelConfig(level: 6, xpRequired: 175),
    LevelConfig(level: 7, xpRequired: 275),
    LevelConfig(level: 8, xpRequired: 400),
    LevelConfig(level: 9, xpRequired: 550),
    LevelConfig(level: 10, xpRequired: 750),
    LevelConfig(level: 11, xpRequired: 1000),
    LevelConfig(level: 12, xpRequired: 1300),
    LevelConfig(level: 13, xpRequired: 1650),
    LevelConfig(level: 14, xpRequired: 2050),
    LevelConfig(level: 15, xpRequired: 2500),
    LevelConfig(level: 16, xpRequired: 3000),
    LevelConfig(level: 17, xpRequired: 3600),
    LevelConfig(level: 18, xpRequired: 4300),
    LevelConfig(level: 19, xpRequired: 5100),
    LevelConfig(level: 20, xpRequired: 6000),
]

/// Compute current level from XP.
func levelFromXp(_ xp: Int) -> Int {
    var level = 1
    for cfg in kLevelTable where xp >= cfg.xpRequired {
        level = cfg.level
    }
    return level
}

/// Compute XP progress within the current level (0.0 … 1.0).
func xpProgressInLevel(_ xp: Int) -> Double {
    let level = levelFromXp(xp)
    guard let current = kLevelTable.first(where: { $0.level == level }) else { return 0 }
    guard let next = kLevelTable.first(where: { $0.level == level + 1 }) else { return 1.0 }
    let range = next.xpRequired - current.xpRequired
    guard range > 0 else { return 1.0 }
    let progress = Double(xp - current.xpRequired) / Double(range)
    return min(max(progress, 0), 1)
}

/// XP needed for the next level (nil at max level).
func xpForNextLevel(_ xp: Int) -> Int? {
    let level = levelFromXp(xp)
    return kLevelTable.first(where: { $0.level == level + 1 })?.xpRequired
}

/// Badge tier based on level.
enum LevelTier {
    case normal, improved, rare, epic

    var gradient: [Color] {
        switch self {
        case .normal: return [Color(hex: 0x9AA1B5), Color(hex: 0x6E7488)]
        case .improved: return [Color(hex: 0x4E9BFF), Color(hex: 0x8A5CFF)]
        case .rare: return [Color(hex: 0xFFB020), Color(hex: 0xFF8C00)]
        case .epic: return [Color(hex: 0xFF4D5E), Color(hex: 0x8A5CFF)]
        }
    }
}

func levelTier(_ level: Int) -> LevelTier {
    if level >= 20 { return .epic }
    if level >= 10 { return .rare }
    if level >= 5 { return .improved }
    return .normal
}

// MARK: - Badge catalog

/// Predefined badge catalog (auto-awarded XP milestones + system badges).
enum BadgeCatalog {
    static let newUser = FluxBadge(
        id: "new_user", name: "Новичок",
        description: "Добро пожаловать в Flux!", emoji: "🌱",
        rarity: .common, badgeType: .system, xpPoints: 0)
    static let active = FluxBadge(
        id: "active", name: "Активный",
        description: "Набрал 10 XP", emoji: "⚡",
        rarity: .uncommon, badgeType: .achievement, xpPoints: 10)
    static let regular = FluxBadge(
        id: "regular", name: "Постоянный участник",
        description: "Набрал 100 XP", emoji: "🔥",
        rarity: .rare, badgeType: .achievement, xpPoints: 100)
    static let experienced = FluxBadge(
        id: "experienced", name: "Опытный",
        description: "Набрал 500 XP", emoji: "💎",
        rarity: .epic, badgeType: .achievement, xpPoints: 500)
    static let veteran = FluxBadge(
        id: "veteran", name: "Veteran",
        description: "Набрал 1000 XP", emoji: "🏆",
        rarity: .legendary, badgeType: .achievement, xpPoints: 1000)
    static let premium = FluxBadge(
        id: "premium", name: "Premium",
        description: "Flux Premium подписчик", emoji: "⭐",
        rarity: .rare, badgeType: .premium, xpPoints: 0)
    static let verified = FluxBadge(
        id: "verified", name: "Verified",
        description: "Верифицированный аккаунт", emoji: "✅",
        rarity: .epic, badgeType: .system, xpPoints: 0)
    static let og = FluxBadge(
        id: "og", name: "OG",
        description: "Один из первых пользователей Flux", emoji: "👑",
        rarity: .mythic, badgeType: .system, xpPoints: 0)

    /// All auto-awarded XP milestone badges in order.
    static let xpMilestones = [newUser, active, regular, experienced, veteran]
}

/// Shop badge catalog — purchasable with Flux Coins.
enum BadgeShopCatalog {
    static let shopBadges: [FluxBadge] = [
        FluxBadge(id: "shop_star", name: "Звёздный", description: "Блистательный бейдж из магазина", emoji: "🌟", rarity: .uncommon, badgeType: .shop, cost: 200),
        FluxBadge(id: "shop_fire", name: "Огненный", description: "Горячий бейдж для активных", emoji: "🔥", rarity: .rare, badgeType: .shop, cost: 500),
        FluxBadge(id: "shop_diamond", name: "Бриллиант", description: "Самый сверкающий бейдж", emoji: "💠", rarity: .epic, badgeType: .shop, cost: 1000),
        FluxBadge(id: "shop_galaxy", name: "Космический", description: "Бейдж из другой галактики", emoji: "🪐", rarity: .legendary, badgeType: .shop, cost: 2500),
        FluxBadge(id: "shop_phoenix", name: "Феникс", description: "Легендарный бейдж возрождения", emoji: "🦅", rarity: .mythic, badgeType: .shop, cost: 5000),
        FluxBadge(id: "shop_ninja", name: "Ниндзя", description: "Тихий и опасный", emoji: "🥷", rarity: .rare, badgeType: .shop, cost: 750),
        FluxBadge(id: "shop_robot", name: "Робот", description: "Технологичный бейдж", emoji: "🤖", rarity: .uncommon, badgeType: .shop, cost: 300),
        FluxBadge(id: "shop_alien", name: "Пришелец", description: "Пришелец из космоса", emoji: "👽", rarity: .epic, badgeType: .shop, cost: 1500),
    ]

    static func findById(_ id: String) -> FluxBadge? {
        shopBadges.first { $0.id == id }
    }
}

// MARK: - Stories

/// A Story item.
struct FluxStory: Identifiable, Equatable, Codable {
    var id: String
    var userId: String
    var mediaPath: String
    var createdAtMs: Int
    var expiresAtMs: Int?
    var caption: String?

    var isExpired: Bool {
        guard let expiresAtMs else { return false }
        return Int(Date().timeIntervalSince1970 * 1000) > expiresAtMs
    }

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "userId": userId,
            "mediaPath": mediaPath,
            "createdAtMs": createdAtMs,
        ]
        if let expiresAtMs { json["expiresAtMs"] = expiresAtMs }
        if let caption { json["caption"] = caption }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> FluxStory {
        FluxStory(
            id: json["id"] as? String ?? UUID().uuidString,
            userId: json["userId"] as? String ?? "",
            mediaPath: json["mediaPath"] as? String ?? "",
            createdAtMs: (json["createdAtMs"] as? NSNumber)?.intValue ?? 0,
            expiresAtMs: (json["expiresAtMs"] as? NSNumber)?.intValue,
            caption: json["caption"] as? String
        )
    }
}

// MARK: - Gifts

/// Gift rarity levels.
enum GiftRarity: String, Codable, CaseIterable {
    case common, uncommon, rare, epic, legendary

    var label: String {
        switch self {
        case .common: return "Обычный"
        case .uncommon: return "Необычный"
        case .rare: return "Редкий"
        case .epic: return "Эпический"
        case .legendary: return "Легендарный"
        }
    }

    var color: Color {
        switch self {
        case .common: return Color(hex: 0x9AA1B5)
        case .uncommon: return Color(hex: 0x34C77B)
        case .rare: return Color(hex: 0x3E8BFF)
        case .epic: return Color(hex: 0x8A5CFF)
        case .legendary: return Color(hex: 0xFFB020)
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .common: return [Color(hex: 0x9AA1B5), Color(hex: 0x6E7488)]
        case .uncommon: return [Color(hex: 0x34C77B), Color(hex: 0x2AA865)]
        case .rare: return [Color(hex: 0x4E9BFF), Color(hex: 0x3E8BFF)]
        case .epic: return [Color(hex: 0x8A5CFF), Color(hex: 0xC05CFF)]
        case .legendary: return [Color(hex: 0xFFB020), Color(hex: 0xFF6B00)]
        }
    }
}

/// A catalog entry — the template for a gift type.
struct GiftCatalogItem: Identifiable, Equatable {
    let id: String
    let emoji: String
    let name: String
    let description: String
    let rarity: GiftRarity
    let cost: Int
}

/// The full gift catalog (identical to the Android implementation).
enum GiftCatalog {
    static let all: [GiftCatalogItem] = [
        // Common
        GiftCatalogItem(id: "heart", emoji: "❤️", name: "Сердце", description: "Простой знак внимания", rarity: .common, cost: 10),
        GiftCatalogItem(id: "flower", emoji: "🌸", name: "Цветок", description: "Нежный цветок сакуры", rarity: .common, cost: 10),
        GiftCatalogItem(id: "star", emoji: "⭐", name: "Звезда", description: "Ты звезда!", rarity: .common, cost: 15),
        GiftCatalogItem(id: "cake", emoji: "🎂", name: "Торт", description: "С праздником!", rarity: .common, cost: 20),
        // Uncommon
        GiftCatalogItem(id: "fire", emoji: "🔥", name: "Огонь", description: "Ты горишь!", rarity: .uncommon, cost: 50),
        GiftCatalogItem(id: "rocket", emoji: "🚀", name: "Ракета", description: "До звёзд!", rarity: .uncommon, cost: 50),
        GiftCatalogItem(id: "rainbow", emoji: "🌈", name: "Радуга", description: "Яркий подарок", rarity: .uncommon, cost: 75),
        GiftCatalogItem(id: "balloon", emoji: "🎈", name: "Шарик", description: "Праздничный шарик", rarity: .uncommon, cost: 60),
        // Rare
        GiftCatalogItem(id: "gem", emoji: "💎", name: "Алмаз", description: "Редкий и ценный", rarity: .rare, cost: 150),
        GiftCatalogItem(id: "crown", emoji: "👑", name: "Корона", description: "Ты король/королева!", rarity: .rare, cost: 200),
        GiftCatalogItem(id: "lightning", emoji: "⚡", name: "Молния", description: "Мощная энергия", rarity: .rare, cost: 175),
        // Epic
        GiftCatalogItem(id: "dragon", emoji: "🐉", name: "Дракон", description: "Легендарный дракон", rarity: .epic, cost: 500),
        GiftCatalogItem(id: "unicorn", emoji: "🦄", name: "Единорог", description: "Волшебный единорог", rarity: .epic, cost: 500),
        GiftCatalogItem(id: "trophy", emoji: "🏆", name: "Кубок", description: "Ты победитель!", rarity: .epic, cost: 400),
        // Legendary
        GiftCatalogItem(id: "galaxy", emoji: "🌌", name: "Галактика", description: "Целая вселенная для тебя", rarity: .legendary, cost: 1000),
        GiftCatalogItem(id: "crystal_ball", emoji: "🔮", name: "Хрустальный шар", description: "Магический артефакт", rarity: .legendary, cost: 1000),
        // Custom
        GiftCatalogItem(id: "cat_nukem", emoji: "🐱", name: "Cat Nukem", description: "Легендарный кот-разрушитель", rarity: .epic, cost: 100),
    ]

    static func findById(_ id: String) -> GiftCatalogItem? {
        all.first { $0.id == id }
    }
}

/// A received gift instance (stored in the recipient's profile).
struct FluxGift: Identifiable, Equatable, Codable {
    var id: String
    var catalogId: String
    var fromUserId: String
    var fromUserName: String
    var toUserId: String
    var emoji: String
    var name: String
    var rarity: GiftRarity
    var sentAtMs: Int
    var message: String?

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "catalogId": catalogId,
            "fromUserId": fromUserId,
            "fromUserName": fromUserName,
            "toUserId": toUserId,
            "emoji": emoji,
            "name": name,
            "rarity": rarity.rawValue,
            "sentAtMs": sentAtMs,
        ]
        if let message { json["message"] = message }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> FluxGift {
        FluxGift(
            id: json["id"] as? String ?? UUID().uuidString,
            catalogId: json["catalogId"] as? String ?? (json["id"] as? String ?? ""),
            fromUserId: json["fromUserId"] as? String ?? "",
            fromUserName: json["fromUserName"] as? String ?? "Пользователь",
            toUserId: json["toUserId"] as? String ?? "",
            emoji: json["emoji"] as? String ?? "🎁",
            name: json["name"] as? String ?? "",
            rarity: GiftRarity(rawValue: json["rarity"] as? String ?? "common") ?? .common,
            sentAtMs: (json["sentAtMs"] as? NSNumber)?.intValue ?? 0,
            message: json["message"] as? String
        )
    }
}

// MARK: - Coin transactions

enum CoinTransactionType: String, Codable, CaseIterable {
    case bonus, giftSent, giftReceived, badgePurchase, usernamePurchase, usernameSale, dailyReward, levelUp
    case coinsTransferSent, coinsTransferReceived, checkCreated, checkRedeemed, checkRefund
    case p2pEscrow, p2pReleased, p2pRefund

    var label: String {
        switch self {
        case .bonus: return "Бонус"
        case .giftSent: return "Отправка подарка"
        case .giftReceived: return "Получение подарка"
        case .badgePurchase: return "Покупка бейджа"
        case .usernamePurchase: return "Покупка username"
        case .usernameSale: return "Продажа username"
        case .dailyReward: return "Ежедневная награда"
        case .levelUp: return "Повышение уровня"
        case .coinsTransferSent: return "Перевод Flux Coins"
        case .coinsTransferReceived: return "Входящий перевод"
        case .checkCreated: return "Чек создан"
        case .checkRedeemed: return "Чек получен"
        case .checkRefund: return "Возврат по чеку"
        case .p2pEscrow: return "P2P: блокировка"
        case .p2pReleased: return "P2P: получение"
        case .p2pRefund: return "P2P: возврат"
        }
    }
}

struct CoinTransaction: Identifiable, Equatable, Codable {
    var id: String
    var userId: String
    var amount: Int
    var type: CoinTransactionType
    var timestampMs: Int
    var description: String
    var relatedObjectId: String?

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "userId": userId,
            "amount": amount,
            "type": type.rawValue,
            "timestampMs": timestampMs,
            "description": description,
        ]
        if let relatedObjectId { json["relatedObjectId"] = relatedObjectId }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> CoinTransaction {
        CoinTransaction(
            id: json["id"] as? String ?? UUID().uuidString,
            userId: json["userId"] as? String ?? "",
            amount: (json["amount"] as? NSNumber)?.intValue ?? 0,
            type: CoinTransactionType(rawValue: json["type"] as? String ?? "bonus") ?? .bonus,
            timestampMs: (json["timestampMs"] as? NSNumber)?.intValue ?? 0,
            description: json["description"] as? String ?? "",
            relatedObjectId: json["relatedObjectId"] as? String
        )
    }
}

// MARK: - Signatures (guestbook)

enum SignatureStatus: String, Codable {
    case pending, approved, rejected
}

struct ProfileSignature: Identifiable, Equatable, Codable {
    var id: String
    var authorId: String
    var authorName: String
    var profileOwnerId: String
    var text: String
    var createdAtMs: Int
    var status: SignatureStatus

    func toJson() -> [String: Any] {
        [
            "id": id,
            "authorId": authorId,
            "authorName": authorName,
            "profileOwnerId": profileOwnerId,
            "text": text,
            "createdAtMs": createdAtMs,
            "status": status.rawValue,
        ]
    }

    static func fromJson(_ json: [String: Any]) -> ProfileSignature {
        ProfileSignature(
            id: json["id"] as? String ?? UUID().uuidString,
            authorId: json["authorId"] as? String ?? "",
            authorName: json["authorName"] as? String ?? "",
            profileOwnerId: json["profileOwnerId"] as? String ?? "",
            text: json["text"] as? String ?? "",
            createdAtMs: (json["createdAtMs"] as? NSNumber)?.intValue ?? 0,
            status: SignatureStatus(rawValue: json["status"] as? String ?? "pending") ?? .pending
        )
    }
}

// MARK: - Additional usernames & Marketplace

struct UsernameEntry: Equatable, Codable {
    var username: String
    var ownerId: String
    var acquiredAtMs: Int

    func toJson() -> [String: Any] {
        ["username": username, "ownerId": ownerId, "acquiredAtMs": acquiredAtMs]
    }

    static func fromJson(_ json: [String: Any]) -> UsernameEntry {
        UsernameEntry(
            username: json["username"] as? String ?? "",
            ownerId: json["ownerId"] as? String ?? "",
            acquiredAtMs: (json["acquiredAtMs"] as? NSNumber)?.intValue ?? 0
        )
    }
}

struct MarketplaceListing: Identifiable, Equatable, Codable {
    var id: String
    var username: String
    var sellerId: String
    var sellerName: String
    var price: Int
    var listedAtMs: Int
    var sold: Bool

    init(id: String, username: String, sellerId: String, sellerName: String, price: Int, listedAtMs: Int, sold: Bool = false) {
        self.id = id
        self.username = username
        self.sellerId = sellerId
        self.sellerName = sellerName
        self.price = price
        self.listedAtMs = listedAtMs
        self.sold = sold
    }

    func toJson() -> [String: Any] {
        [
            "id": id,
            "username": username,
            "sellerId": sellerId,
            "sellerName": sellerName,
            "price": price,
            "listedAtMs": listedAtMs,
            "sold": sold,
        ]
    }

    static func fromJson(_ json: [String: Any]) -> MarketplaceListing {
        MarketplaceListing(
            id: json["id"] as? String ?? UUID().uuidString,
            username: json["username"] as? String ?? "",
            sellerId: json["sellerId"] as? String ?? "",
            sellerName: json["sellerName"] as? String ?? "",
            price: (json["price"] as? NSNumber)?.intValue ?? 0,
            listedAtMs: (json["listedAtMs"] as? NSNumber)?.intValue ?? 0,
            sold: json["sold"] as? Bool ?? false
        )
    }
}

// MARK: - Daily streak

struct DailyStreak: Equatable, Codable {
    var lastLoginDate: String?
    var currentStreak: Int
    var longestStreak: Int

    init(lastLoginDate: String? = nil, currentStreak: Int = 0, longestStreak: Int = 0) {
        self.lastLoginDate = lastLoginDate
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
    }

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "currentStreak": currentStreak,
            "longestStreak": longestStreak,
        ]
        if let lastLoginDate { json["lastLoginDate"] = lastLoginDate }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> DailyStreak {
        DailyStreak(
            lastLoginDate: json["lastLoginDate"] as? String,
            currentStreak: (json["currentStreak"] as? NSNumber)?.intValue ?? 0,
            longestStreak: (json["longestStreak"] as? NSNumber)?.intValue ?? 0
        )
    }
}

// MARK: - Profile visibility

struct ProfileVisibility: Equatable, Codable {
    var showBirthday = true
    var showAge = true
    var showGifts = true
    var showStories = true
    var showBadges = true
    var showAdditionalUsernames = true
    var showSignatures = true
    var allowSignatures = true
    var requireSignatureApproval = true
    var blockedSignatureUserIds: [String] = []

    func toJson() -> [String: Any] {
        [
            "showBirthday": showBirthday,
            "showAge": showAge,
            "showGifts": showGifts,
            "showStories": showStories,
            "showBadges": showBadges,
            "showAdditionalUsernames": showAdditionalUsernames,
            "showSignatures": showSignatures,
            "allowSignatures": allowSignatures,
            "requireSignatureApproval": requireSignatureApproval,
            "blockedSignatureUserIds": blockedSignatureUserIds,
        ]
    }

    static func fromJson(_ json: [String: Any]) -> ProfileVisibility {
        var v = ProfileVisibility()
        v.showBirthday = json["showBirthday"] as? Bool ?? true
        v.showAge = json["showAge"] as? Bool ?? true
        v.showGifts = json["showGifts"] as? Bool ?? true
        v.showStories = json["showStories"] as? Bool ?? true
        v.showBadges = json["showBadges"] as? Bool ?? true
        v.showAdditionalUsernames = json["showAdditionalUsernames"] as? Bool ?? true
        v.showSignatures = json["showSignatures"] as? Bool ?? true
        v.allowSignatures = json["allowSignatures"] as? Bool ?? true
        v.requireSignatureApproval = json["requireSignatureApproval"] as? Bool ?? true
        v.blockedSignatureUserIds = (json["blockedSignatureUserIds"] as? [String]) ?? []
        return v
    }
}

// MARK: - UserProfile

/// Extended profile data (stored alongside FluxUser).
struct UserProfile: Equatable, Codable {
    var bannerPath: String?
    var location: String?
    var website: String?
    var birthday: String?
    var activityPoints: Int
    var badges: [FluxBadge]
    var selectedBadgeIds: [String]
    var stories: [FluxStory]
    var gifts: [FluxGift]
    var fluxCoins: Int
    var coinTransactions: [CoinTransaction]
    var signatures: [ProfileSignature]
    var additionalUsernames: [UsernameEntry]
    var dailyStreak: DailyStreak
    var visibility: ProfileVisibility

    init(
        bannerPath: String? = nil,
        location: String? = nil,
        website: String? = nil,
        birthday: String? = nil,
        activityPoints: Int = 0,
        badges: [FluxBadge] = [],
        selectedBadgeIds: [String] = [],
        stories: [FluxStory] = [],
        gifts: [FluxGift] = [],
        fluxCoins: Int = 0,
        coinTransactions: [CoinTransaction] = [],
        signatures: [ProfileSignature] = [],
        additionalUsernames: [UsernameEntry] = [],
        dailyStreak: DailyStreak = DailyStreak(),
        visibility: ProfileVisibility = ProfileVisibility()
    ) {
        self.bannerPath = bannerPath
        self.location = location
        self.website = website
        self.birthday = birthday
        self.activityPoints = activityPoints
        self.badges = badges
        self.selectedBadgeIds = selectedBadgeIds
        self.stories = stories
        self.gifts = gifts
        self.fluxCoins = fluxCoins
        self.coinTransactions = coinTransactions
        self.signatures = signatures
        self.additionalUsernames = additionalUsernames
        self.dailyStreak = dailyStreak
        self.visibility = visibility
    }

    var level: Int { levelFromXp(activityPoints) }
    var xpProgress: Double { xpProgressInLevel(activityPoints) }
    var nextLevelXp: Int? { xpForNextLevel(activityPoints) }
    var tier: LevelTier { levelTier(level) }

    var displayBadges: [FluxBadge] {
        if selectedBadgeIds.isEmpty {
            return Array(badges.prefix(5))
        }
        return badges.filter { selectedBadgeIds.contains($0.id) }
    }

    var approvedSignatures: [ProfileSignature] {
        signatures.filter { $0.status == .approved }
    }

    var pendingSignatures: [ProfileSignature] {
        signatures.filter { $0.status == .pending }
    }

    static var initial: UserProfile {
        UserProfile(
            activityPoints: 0,
            badges: [BadgeCatalog.newUser.withEarned(atMs: Int(Date().timeIntervalSince1970 * 1000))],
            fluxCoins: 0
        )
    }

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "activityPoints": activityPoints,
            "badges": badges.map { $0.toJson() },
            "selectedBadgeIds": selectedBadgeIds,
            "stories": stories.map { $0.toJson() },
            "gifts": gifts.map { $0.toJson() },
            "fluxCoins": fluxCoins,
            "coinTransactions": coinTransactions.map { $0.toJson() },
            "signatures": signatures.map { $0.toJson() },
            "additionalUsernames": additionalUsernames.map { $0.toJson() },
            "dailyStreak": dailyStreak.toJson(),
            "visibility": visibility.toJson(),
        ]
        if let bannerPath { json["bannerPath"] = bannerPath }
        if let location { json["location"] = location }
        if let website { json["website"] = website }
        if let birthday { json["birthday"] = birthday }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> UserProfile {
        UserProfile(
            bannerPath: json["bannerPath"] as? String,
            location: json["location"] as? String,
            website: json["website"] as? String,
            birthday: json["birthday"] as? String,
            activityPoints: (json["activityPoints"] as? NSNumber)?.intValue ?? 0,
            badges: (json["badges"] as? [[String: Any]])?.map(FluxBadge.fromJson) ?? [],
            selectedBadgeIds: (json["selectedBadgeIds"] as? [String]) ?? [],
            stories: (json["stories"] as? [[String: Any]])?.map(FluxStory.fromJson) ?? [],
            gifts: (json["gifts"] as? [[String: Any]])?.map(FluxGift.fromJson) ?? [],
            fluxCoins: (json["fluxCoins"] as? NSNumber)?.intValue ?? 0,
            coinTransactions: (json["coinTransactions"] as? [[String: Any]])?.map(CoinTransaction.fromJson) ?? [],
            signatures: (json["signatures"] as? [[String: Any]])?.map(ProfileSignature.fromJson) ?? [],
            additionalUsernames: (json["additionalUsernames"] as? [[String: Any]])?.map(UsernameEntry.fromJson) ?? [],
            dailyStreak: (json["dailyStreak"] as? [String: Any]).map(DailyStreak.fromJson) ?? DailyStreak(),
            visibility: (json["visibility"] as? [String: Any]).map(ProfileVisibility.fromJson) ?? ProfileVisibility()
        )
    }
}

extension FluxBadge {
    func withEarned(atMs: Int?) -> FluxBadge {
        var copy = self
        copy.earnedAtMs = atMs ?? earnedAtMs
        return copy
    }
}
