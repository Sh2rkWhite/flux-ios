import Foundation

/// Domain models of the FluxCoinsBot (@FluxCoinsBot).
///
/// These documents live in the shared Firestore `coinsBot/` namespace so that
/// both the Android (Flutter) and iOS (Swift) clients operate on a single
/// source of truth. Every coin mutation is executed inside a Firestore
/// transaction; the `transactionId` on each record is the idempotency key of
/// the escrow/transfer that created it. JSON keys mirror the Dart models
/// exactly.

// MARK: - Checks (чеки)

enum CheckStatus: String, Codable, CaseIterable {
    case active, redeemed, cancelled

    var label: String {
        switch self {
        case .active: return "Активен"
        case .redeemed: return "Использован"
        case .cancelled: return "Отменён"
        }
    }
}

/// A one-time Flux Coins voucher. The creator locks `amount` coins at creation
/// (escrow); a recipient redeems it once. A personal check is bound to
/// `recipientFluxId`. After redemption the check is permanently consumed.
struct FluxCheck: Identifiable, Equatable, Codable {
    var id: String
    var amount: Int
    var creatorFluxId: String
    var status: CheckStatus

    /// Idempotency key of the escrow transaction that locked the coins.
    var transactionId: String
    var createdAtMs: Int

    /// When set, only this user may redeem the check (personal check).
    var recipientFluxId: String?

    /// Optional expiry (epoch ms). `nil` = never expires.
    var expiresAtMs: Int?

    var redeemedByFluxId: String?
    var redeemedAtMs: Int?

    func isExpired(_ nowMs: Int) -> Bool {
        if let expiresAtMs { return expiresAtMs <= nowMs }
        return false
    }

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "amount": amount,
            "creatorFluxId": creatorFluxId,
            "status": status.rawValue,
            "transactionId": transactionId,
            "createdAtMs": createdAtMs,
        ]
        if let recipientFluxId { json["recipientFluxId"] = recipientFluxId }
        if let expiresAtMs { json["expiresAtMs"] = expiresAtMs }
        if let redeemedByFluxId { json["redeemedByFluxId"] = redeemedByFluxId }
        if let redeemedAtMs { json["redeemedAtMs"] = redeemedAtMs }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> FluxCheck {
        FluxCheck(
            id: json["id"] as? String ?? "",
            amount: (json["amount"] as? NSNumber)?.intValue ?? 0,
            creatorFluxId: json["creatorFluxId"] as? String ?? "",
            status: CheckStatus(rawValue: json["status"] as? String ?? "") ?? .cancelled,
            transactionId: json["transactionId"] as? String ?? "",
            createdAtMs: (json["createdAtMs"] as? NSNumber)?.intValue ?? 0,
            recipientFluxId: json["recipientFluxId"] as? String,
            expiresAtMs: (json["expiresAtMs"] as? NSNumber)?.intValue,
            redeemedByFluxId: json["redeemedByFluxId"] as? String,
            redeemedAtMs: (json["redeemedAtMs"] as? NSNumber)?.intValue
        )
    }

    func copyWith(
        status: CheckStatus? = nil,
        redeemedByFluxId: String? = nil,
        redeemedAtMs: Int? = nil
    ) -> FluxCheck {
        FluxCheck(
            id: id,
            amount: amount,
            creatorFluxId: creatorFluxId,
            status: status ?? self.status,
            transactionId: transactionId,
            createdAtMs: createdAtMs,
            recipientFluxId: recipientFluxId,
            expiresAtMs: expiresAtMs,
            redeemedByFluxId: redeemedByFluxId ?? self.redeemedByFluxId,
            redeemedAtMs: redeemedAtMs ?? self.redeemedAtMs
        )
    }
}

// MARK: - P2P marketplace

enum P2pSide: String, Codable, CaseIterable {
    case buy, sell
}

enum OfferStatus: String, Codable, CaseIterable {
    case open, matched, cancelled

    var label: String {
        switch self {
        case .open: return "Открыто"
        case .matched: return "В сделке"
        case .cancelled: return "Отменено"
        }
    }
}

/// A P2P listing. For a `.sell` offer the creator escrows `coinAmount` coins
/// when the offer is created; for a `.buy` offer the creator is looking to
/// acquire coins.
struct FluxP2pOffer: Identifiable, Equatable, Codable {
    var id: String
    var side: P2pSide
    var coinAmount: Int
    var creatorFluxId: String
    var status: OfferStatus
    var transactionId: String
    var createdAtMs: Int

    /// Free-form note describing the deal terms / payment method.
    var priceNote: String

    func toJson() -> [String: Any] {
        [
            "id": id,
            "side": side.rawValue,
            "coinAmount": coinAmount,
            "creatorFluxId": creatorFluxId,
            "status": status.rawValue,
            "transactionId": transactionId,
            "createdAtMs": createdAtMs,
            "priceNote": priceNote,
        ]
    }

    static func fromJson(_ json: [String: Any]) -> FluxP2pOffer {
        FluxP2pOffer(
            id: json["id"] as? String ?? "",
            side: (json["side"] as? String) == "buy" ? .buy : .sell,
            coinAmount: (json["coinAmount"] as? NSNumber)?.intValue ?? 0,
            creatorFluxId: json["creatorFluxId"] as? String ?? "",
            status: OfferStatus(rawValue: json["status"] as? String ?? "") ?? .cancelled,
            transactionId: json["transactionId"] as? String ?? "",
            createdAtMs: (json["createdAtMs"] as? NSNumber)?.intValue ?? 0,
            priceNote: json["priceNote"] as? String ?? ""
        )
    }

    func copyWith(status: OfferStatus? = nil) -> FluxP2pOffer {
        FluxP2pOffer(
            id: id,
            side: side,
            coinAmount: coinAmount,
            creatorFluxId: creatorFluxId,
            status: status ?? self.status,
            transactionId: transactionId,
            createdAtMs: createdAtMs,
            priceNote: priceNote
        )
    }
}

enum DealStatus: String, Codable, CaseIterable {
    case escrow, completed, cancelled, disputed

    var label: String {
        switch self {
        case .escrow: return "Ожидает подтверждения"
        case .completed: return "Завершена"
        case .cancelled: return "Отменена"
        case .disputed: return "Спор"
        }
    }
}

/// A matched P2P deal. Coins are held in escrow (`.escrow`) until the seller
/// confirms (`.completed`), the deal is cancelled (refund, `.cancelled`) or
/// disputed (`.disputed`).
struct FluxP2pDeal: Identifiable, Equatable, Codable {
    var id: String
    var offerId: String
    var sellerFluxId: String
    var buyerFluxId: String
    var coinAmount: Int
    var status: DealStatus
    var transactionId: String
    var createdAtMs: Int
    var resolvedAtMs: Int?

    func toJson() -> [String: Any] {
        var json: [String: Any] = [
            "id": id,
            "offerId": offerId,
            "sellerFluxId": sellerFluxId,
            "buyerFluxId": buyerFluxId,
            "coinAmount": coinAmount,
            "status": status.rawValue,
            "transactionId": transactionId,
            "createdAtMs": createdAtMs,
        ]
        if let resolvedAtMs { json["resolvedAtMs"] = resolvedAtMs }
        return json
    }

    static func fromJson(_ json: [String: Any]) -> FluxP2pDeal {
        FluxP2pDeal(
            id: json["id"] as? String ?? "",
            offerId: json["offerId"] as? String ?? "",
            sellerFluxId: json["sellerFluxId"] as? String ?? "",
            buyerFluxId: json["buyerFluxId"] as? String ?? "",
            coinAmount: (json["coinAmount"] as? NSNumber)?.intValue ?? 0,
            status: DealStatus(rawValue: json["status"] as? String ?? "") ?? .cancelled,
            transactionId: json["transactionId"] as? String ?? "",
            createdAtMs: (json["createdAtMs"] as? NSNumber)?.intValue ?? 0,
            resolvedAtMs: (json["resolvedAtMs"] as? NSNumber)?.intValue
        )
    }

    func copyWith(status: DealStatus? = nil, resolvedAtMs: Int? = nil) -> FluxP2pDeal {
        FluxP2pDeal(
            id: id,
            offerId: offerId,
            sellerFluxId: sellerFluxId,
            buyerFluxId: buyerFluxId,
            coinAmount: coinAmount,
            status: status ?? self.status,
            transactionId: transactionId,
            createdAtMs: createdAtMs,
            resolvedAtMs: resolvedAtMs ?? self.resolvedAtMs
        )
    }
}
