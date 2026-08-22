import Foundation
import FirebaseCore
import FirebaseFirestore

/// Firestore-backed implementation of [LocalBackend].
///
/// Schema (identical to the Android client — both platforms read and write
/// the same documents):
///
/// ```
/// users/{fluxId}
///   fluxId, username, display_name, bio, avatar_url, isPremium,
///   created_at, updatedAt, is_admin, is_verified, is_online, last_seen
///
///   profile/data            — full UserProfile JSON (XP, coins, gifts,
///                              signatures, streak, visibility, …)
///   active_devices/{id}     — DeviceSession
///   chats/{peerFluxId}      — { peerId, updatedAt }
///   chats/{peerFluxId}/messages/{messageId} — message payload
///
/// marketplace/{listingId}   — username marketplace listings
/// ```
@MainActor
final class FirestoreBackend: LocalBackend {

    private var db: Firestore { Firestore.firestore() }

    private var remote = false
    private var chatsListener: ListenerRegistration?
    private var sessionsListener: ListenerRegistration?
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var remoteProfileFetches: Set<String> = []

    override var simulatePeers: Bool { false }

    // MARK: - Init

    override func initBackend() async {
        await super.initBackend()
        remote = FirebaseApp.app() != nil
            && FirebaseApp.app()?.options.projectId != LocalBackend.placeholderProject
            && !(FirebaseApp.app()?.options.projectId ?? "").isEmpty
        guard remote else {
            print("Flux: Firestore disabled — running local-only.")
            return
        }
        print("Flux: Firestore project \"\(FirebaseApp.app()?.options.projectId ?? "")\" connected.")
        await applyRemoteProfile()
        await loadExtendedProfile()
        publishProfile()
        await pullDirectory()
        await pullMarketplace()
        listenSessions()
        listenChats()
    }

    // MARK: - Username lookup

    override func lookupUsername(_ username: String) async -> FluxUser? {
        if let local = await super.lookupUsername(username) { return local }
        guard remote else { return nil }
        let q = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "@", with: "")
        guard !q.isEmpty else { return nil }
        do {
            let snap = try await db.collection("users")
                .whereField("username", isEqualTo: q)
                .limit(to: 1)
                .getDocuments()
            guard let doc = snap.documents.first else { return nil }
            return Self.userFromDoc(doc.documentID, doc.data())
        } catch {
            print("Flux: lookupUsername failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func userFromDoc(_ docId: String, _ data: [String: Any]) -> FluxUser {
        let fluxId = data["fluxId"] as? String ?? docId
        var registeredAtMs: Int?
        if let ts = data["created_at"] as? Timestamp {
            registeredAtMs = Int(ts.dateValue().timeIntervalSince1970 * 1000)
        }
        return FluxUser(
            id: "r-\(fluxId.lowercased())",
            fluxId: fluxId,
            name: (data["display_name"] as? String) ?? (data["name"] as? String) ?? "Flux user",
            username: data["username"] as? String,
            status: (data["bio"] as? String) ?? (data["status"] as? String) ?? "",
            isPremium: data["isPremium"] as? Bool ?? false,
            isVerified: data["is_verified"] as? Bool ?? false,
            isOnline: data["is_online"] as? Bool ?? false,
            isAdmin: data["is_admin"] as? Bool ?? false,
            avatarPath: data["avatar_url"] as? String,
            registeredAtMs: registeredAtMs
        )
    }

    // MARK: - Registration / login hooks

    override func registerSmart(username: String, email: String, password: String, displayName: String) async throws -> FluxUser {
        let user = try await super.registerSmart(username: username, email: email, password: password, displayName: displayName)
        if remote {
            publishProfile()
            listenSessions()
            listenChats()
        }
        return user
    }

    // MARK: - Remote profile sync

    /// Pulls the remote Firestore document for the current user and applies
    /// server-side flags (`is_admin`, `is_verified`) the client cannot set.
    private func applyRemoteProfile() async {
        guard let cur = me, !cur.fluxId.isEmpty else { return }
        do {
            let doc = try await db.collection("users").document(cur.fluxId).getDocument()
            guard let data = doc.data() else { return }
            let remoteAdmin = data["is_admin"] as? Bool ?? false
            let remoteVerified = data["is_verified"] as? Bool ?? false
            guard remoteAdmin != cur.isAdmin || remoteVerified != cur.isVerified else { return }
            var updated = cur
            updated.isAdmin = remoteAdmin
            updated.isVerified = remoteVerified
            me = updated
            persistProfile()
            notify()
        } catch {
            print("Flux: remote profile fetch failed: \(error.localizedDescription)")
        }
    }

    /// Publishes the full local profile to Firestore. Server-controlled
    /// flags are written only on first creation (merge) and never
    /// overwritten by the client afterwards.
    func publishProfile() {
        guard let me, !me.fluxId.isEmpty else { return }
        let docRef = db.collection("users").document(me.fluxId)
        let firstWrite: [String: Any] = [
            "created_at": FieldValue.serverTimestamp(),
            "is_admin": false,
            "is_verified": false,
        ]
        let data: [String: Any] = [
            "fluxId": me.fluxId,
            "username": me.username?.lowercased() ?? NSNull(),
            "display_name": me.name,
            "bio": me.status,
            "avatar_url": me.avatarPath ?? NSNull(),
            "isPremium": me.isPremium,
            "is_online": me.isOnline,
            "last_seen": me.isOnline ? NSNull() : FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        let batch = db.batch()
        batch.setData(firstWrite, forDocument: docRef, merge: true)
        batch.setData(data, forDocument: docRef, merge: true)
        batch.commit { error in
            if let error {
                print("Flux: profile publish FAILED: \(error.localizedDescription)")
            }
        }
    }

    override func updateMe(name: String? = nil, status: String? = nil, avatarPath: String? = nil, isPremium: Bool? = nil) async {
        await super.updateMe(name: name, status: status, avatarPath: avatarPath, isPremium: isPremium)
        if remote { publishProfile() }
    }

    override func updateUsername(_ newUsername: String) async throws {
        try await super.updateUsername(newUsername)
        if remote { publishProfile() }
    }

    // MARK: - Extended profile

    override func updateProfile(bannerPath: String? = nil, location: String? = nil, website: String? = nil, birthday: String? = nil) async {
        await super.updateProfile(bannerPath: bannerPath, location: location, website: website, birthday: birthday)
        if remote { publishExtendedProfile() }
    }

    /// Publishes the whole extended profile doc — mirrors UserProfile JSON
    /// so the Android client reads exactly the same shape.
    func publishExtendedProfile() {
        guard let myFluxId = me?.fluxId, !myFluxId.isEmpty else { return }
        var data = myProfile.toJson()
        data["level"] = myProfile.level
        data["updatedAt"] = FieldValue.serverTimestamp()
        db.collection("users").document(myFluxId)
            .collection("profile").document("data")
            .setData(data, merge: true) { error in
                if let error {
                    print("Flux: extended profile publish failed: \(error.localizedDescription)")
                }
            }
    }

    /// Merges a remote extended-profile snapshot into the local one.
    static func mergeRemoteSnapshot(_ local: UserProfile, _ remote: UserProfile) -> UserProfile {
        var merged = local
        merged.bannerPath = remote.bannerPath ?? local.bannerPath
        merged.location = remote.location ?? local.location
        merged.website = remote.website ?? local.website
        merged.birthday = remote.birthday ?? local.birthday
        merged.activityPoints = max(local.activityPoints, remote.activityPoints)

        // Union lists by id (remote wins on clash), newest first.
        merged.badges = unionById(local.badges, remote.badges, { $0.id }, { $0.earnedAtMs ?? 0 })
        merged.stories = unionById(local.stories, remote.stories, { $0.id }, { $0.createdAtMs })
        merged.gifts = unionById(local.gifts, remote.gifts, { $0.id }, { $0.sentAtMs })
        merged.coinTransactions = unionById(local.coinTransactions, remote.coinTransactions, { $0.id }, { $0.timestampMs })
        merged.signatures = unionById(local.signatures, remote.signatures, { $0.id }, { $0.createdAtMs })

        merged.selectedBadgeIds = remote.selectedBadgeIds.isEmpty ? local.selectedBadgeIds : remote.selectedBadgeIds
        merged.fluxCoins = max(local.fluxCoins, remote.fluxCoins)

        var byName: [String: UsernameEntry] = [:]
        for entry in local.additionalUsernames + remote.additionalUsernames {
            byName[entry.username.lowercased()] = byName[entry.username.lowercased()] ?? entry
        }
        merged.additionalUsernames = byName.values.sorted { $0.acquiredAtMs > $1.acquiredAtMs }

        let remoteStreakWins = (remote.dailyStreak.lastLoginDate ?? "")
            .compare(local.dailyStreak.lastLoginDate ?? "") != .orderedAscending
        merged.dailyStreak = remoteStreakWins ? remote.dailyStreak : local.dailyStreak
        merged.visibility = remote.visibility
        return merged
    }

    private static func unionById<T>(_ a: [T], _ b: [T], _ idOf: (T) -> String, _ newest: (T) -> Int) -> [T] {
        var byId: [String: T] = [:]
        for item in a { byId[idOf(item)] = item }
        for item in b { byId[idOf(item)] = item }
        return byId.values.sorted { newest($0) > newest($1) }
    }

    private func loadExtendedProfile() async {
        guard let myFluxId = me?.fluxId, !myFluxId.isEmpty else { return }
        do {
            let doc = try await db.collection("users").document(myFluxId)
                .collection("profile").document("data").getDocument()
            guard let data = doc.data() else { return }
            let remoteProfile = UserProfile.fromJson(data)
            await mergeRemoteProfile(Self.mergeRemoteSnapshot(myProfile, remoteProfile))
        } catch {
            print("Flux: extended profile load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Directory pull

    private func pullDirectory() async {
        guard remote else { return }
        do {
            let snap = try await db.collection("users").limit(to: 200).getDocuments()
            let myFluxId = me?.fluxId
            for doc in snap.documents {
                let data = doc.data()
                let fluxId = data["fluxId"] as? String ?? doc.documentID
                if fluxId == myFluxId { continue }
                upsertContact(Self.userFromDoc(doc.documentID, data))
            }
        } catch {
            print("Flux: directory pull failed: \(error.localizedDescription)")
        }
    }

    private func pullMarketplace() async {
        guard remote else { return }
        do {
            let snap = try await db.collection("marketplace")
                .whereField("sold", isEqualTo: false)
                .order(by: "listedAtMs", descending: true)
                .limit(to: 100)
                .getDocuments()
            let listings = snap.documents.map { MarketplaceListing.fromJson($0.data()) }
            syncMarketplaceListings(listings)
        } catch {
            print("Flux: marketplace pull failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sessions

    private func listenSessions() {
        guard let myFluxId = me?.fluxId, !myFluxId.isEmpty, sessionsListener == nil else { return }
        sessionsListener = db.collection("users/\(myFluxId)/active_devices")
            .order(by: "loginAtMs", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else {
                    if let error { print("Flux: sessions listener failed: \(error.localizedDescription)") }
                    return
                }
                Task { @MainActor in
                    guard let cur = self.me else { return }
                    var updated = cur
                    updated.sessions = snapshot.documents.map { doc in
                        var json = doc.data()
                        json["id"] = doc.documentID
                        return DeviceSession.fromJson(json)
                    }
                    self.me = updated
                    self.persistProfile()
                    self.notify()
                }
            }
    }

    private func mirrorSession(_ session: DeviceSession) {
        guard let myFluxId = me?.fluxId, !myFluxId.isEmpty else { return }
        db.collection("users/\(myFluxId)/active_devices")
            .document(session.id)
            .setData(session.toJson()) { error in
                if let error { print("Flux: session mirror failed: \(error.localizedDescription)") }
            }
    }

    override func recordLoginSession() async {
        await super.recordLoginSession()
        guard remote else { return }
        guard let cur = me else { return }
        for session in cur.sessions {
            mirrorSession(session)
        }
        updatePresence(isOnline: true)
    }

    override func revokeSession(_ sessionId: String) async {
        await super.revokeSession(sessionId)
        guard remote, let myFluxId = me?.fluxId else { return }
        db.collection("users/\(myFluxId)/active_devices")
            .document(sessionId)
            .updateData(["revoked": true]) { error in
                if let error { print("Flux: session revoke mirror failed: \(error.localizedDescription)") }
            }
    }

    override func revokeAllOtherSessions() async {
        await super.revokeAllOtherSessions()
        guard remote, let myFluxId = me?.fluxId, let current = currentSessionId else { return }
        let col = db.collection("users/\(myFluxId)/active_devices")
        do {
            let snap = try await col.getDocuments()
            for doc in snap.documents where doc.documentID != current {
                doc.reference.updateData(["revoked": true]) { error in
                    if let error { print("Flux: revokeAll mirror failed: \(error.localizedDescription)") }
                }
            }
        } catch {
            print("Flux: revokeAll fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Presence

    private func updatePresence(isOnline: Bool) {
        guard let myFluxId = me?.fluxId, !myFluxId.isEmpty else { return }
        db.collection("users").document(myFluxId).updateData([
            "is_online": isOnline,
            "last_seen": isOnline ? NSNull() : FieldValue.serverTimestamp(),
        ]) { error in
            if let error { print("Flux: presence update failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Chats & messages

    private func listenChats() {
        guard let myFluxId = me?.fluxId, !myFluxId.isEmpty, chatsListener == nil else { return }
        chatsListener = db.collection("users/\(myFluxId)/chats")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else {
                    if let error { print("Flux: chats listener failed: \(error.localizedDescription)") }
                    return
                }
                Task { @MainActor in
                    for doc in snapshot.documents {
                        self.ensureRemoteChat(doc.documentID)
                        self.listenMessages(doc.documentID)
                    }
                }
            }
    }

    private func ensureRemoteChat(_ peerFluxId: String) {
        let known = contacts.values.filter { $0.fluxId == peerFluxId }
        let contact: FluxUser
        if let first = known.first {
            contact = first
        } else {
            contact = FluxUser(id: "r-\(peerFluxId.lowercased())", fluxId: peerFluxId, name: "Flux user")
            upsertContact(contact)
        }
        _ = ensureChatForPeer(contact.id)
    }

    private func listenMessages(_ peerFluxId: String) {
        guard let myFluxId = me?.fluxId, messageListeners[peerFluxId] == nil else { return }
        messageListeners[peerFluxId] = db
            .collection("users/\(myFluxId)/chats/\(peerFluxId)/messages")
            .order(by: "sentAtMs")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else {
                    if let error { print("Flux: messages listener failed: \(error.localizedDescription)") }
                    return
                }
                Task { @MainActor in
                    let nowMs = Int(Date().timeIntervalSince1970 * 1000)
                    for doc in snapshot.documents {
                        let data = doc.data()
                        guard data["senderId"] as? String != myFluxId else { continue }
                        guard let contact = self.contacts.values.first(where: { $0.fluxId == peerFluxId }),
                              let chat = self.chatWithPeer(contact.id) else { continue }
                        var json = data
                        json["id"] = doc.documentID
                        json["chatId"] = chat.id
                        json["senderId"] = chat.peerId
                        json["deliveredAtMs"] = nowMs
                        let message = FluxMessage.fromJson(json)
                        self.ingestRemoteMessage(message, preview: data["text"] as? String)
                    }
                }
            }
    }

    override func openChatWithUser(_ user: FluxUser) async -> FluxChat {
        let chat = await super.openChatWithUser(user)
        if remote, let myFluxId = me?.fluxId, !myFluxId.isEmpty, !user.fluxId.isEmpty {
            writeChatMeta(owner: myFluxId, peer: user.fluxId)
            writeChatMeta(owner: user.fluxId, peer: myFluxId)
        }
        return chat
    }

    private func writeChatMeta(owner: String, peer: String) {
        db.collection("users/\(owner)/chats").document(peer)
            .setData([
                "peerId": peer,
                "updatedAt": FieldValue.serverTimestamp(),
            ]) { error in
                if let error { print("Flux: chat meta failed: \(error.localizedDescription)") }
            }
    }

    /// Mirrors an outgoing message to both the sender's and the recipient's
    /// Firestore message subcollections.
    private func mirrorOutgoing(_ chat: FluxChat, _ message: FluxMessage) {
        guard let myFluxId = me?.fluxId, !myFluxId.isEmpty,
              let peerFluxId = contacts[chat.peerId]?.fluxId, !peerFluxId.isEmpty else { return }

        var payload = message.toJson()
        payload["senderId"] = myFluxId

        for owner in [myFluxId, peerFluxId] {
            let peer = owner == myFluxId ? peerFluxId : myFluxId
            db.collection("users/\(owner)/chats/\(peer)/messages")
                .document(message.id)
                .setData(payload) { error in
                    if let error { print("Flux: message mirror failed: \(error.localizedDescription)") }
                }
        }
    }

    private func chatById(_ chatId: String) -> FluxChat? {
        chatStorage[chatId]
    }

    override func sendText(_ chatId: String, _ text: String, replyToId: String? = nil, overrideExpiryMs: Int? = nil) async -> FluxMessage {
        let message = await super.sendText(chatId, text, replyToId: replyToId, overrideExpiryMs: overrideExpiryMs)
        if remote, let chat = chatById(chatId) {
            mirrorOutgoing(chat, message)
        }
        return message
    }

    override func sendImage(_ chatId: String, _ path: String, replyToId: String? = nil) async -> FluxMessage {
        let message = await super.sendImage(chatId, path, replyToId: replyToId)
        if remote, let chat = chatById(chatId) {
            mirrorOutgoing(chat, message)
        }
        return message
    }

    override func sendVoice(_ chatId: String, _ path: String, _ durationMs: Int, replyToId: String? = nil) async -> FluxMessage {
        let message = await super.sendVoice(chatId, path, durationMs, replyToId: replyToId)
        if remote, let chat = chatById(chatId) {
            mirrorOutgoing(chat, message)
        }
        return message
    }

    override func sendFile(_ chatId: String, _ path: String, _ fileName: String, _ fileSize: Int, replyToId: String? = nil) async -> FluxMessage {
        let message = await super.sendFile(chatId, path, fileName, fileSize, replyToId: replyToId)
        if remote, let chat = chatById(chatId) {
            mirrorOutgoing(chat, message)
        }
        return message
    }

    // MARK: - XP & coins sync

    override func awardXp(messageId: String, xp: Int = 1) async -> (level: Int, badges: [FluxBadge])? {
        let result = await super.awardXp(messageId: messageId, xp: xp)
        if remote { publishExtendedProfile() }
        return result
    }

    override func awardCoins(_ amount: Int) async {
        await super.awardCoins(amount)
        if remote { publishExtendedProfile() }
    }

    override func spendCoins(_ amount: Int) async throws {
        try await super.spendCoins(amount)
        if remote { publishExtendedProfile() }
    }

    override func awardCoinsWithTransaction(amount: Int, type: CoinTransactionType, description: String = "", relatedObjectId: String? = nil) async {
        await super.awardCoinsWithTransaction(amount: amount, type: type, description: description, relatedObjectId: relatedObjectId)
        if remote { publishExtendedProfile() }
    }

    override func spendCoinsWithTransaction(amount: Int, type: CoinTransactionType, description: String = "", relatedObjectId: String? = nil) async throws {
        try await super.spendCoinsWithTransaction(amount: amount, type: type, description: description, relatedObjectId: relatedObjectId)
        if remote { publishExtendedProfile() }
    }

    // MARK: - Gifts

    override func sendGift(toUserId: String, catalogId: String, message: String?) async throws -> FluxGift {
        let gift = try await super.sendGift(toUserId: toUserId, catalogId: catalogId, message: message)
        if remote {
            publishExtendedProfile()
            if let recipientFluxId = fluxIdOfUser(toUserId), !recipientFluxId.isEmpty {
                appendGiftToRemoteProfile(recipientFluxId, gift)
            }
        }
        return gift
    }

    /// Atomically prepends the gift to the recipient's remote `gifts` array.
    private func appendGiftToRemoteProfile(_ recipientFluxId: String, _ gift: FluxGift) {
        let ref = db.collection("users").document(recipientFluxId)
            .collection("profile").document("data")
        db.runTransaction({ transaction, errorPointer in
            let doc: DocumentSnapshot
            do {
                doc = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            let data = doc.data() ?? [:]
            var gifts = data["gifts"] as? [[String: Any]] ?? []
            gifts.insert(gift.toJson(), at: 0)
            transaction.setData([
                "gifts": gifts,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: ref, merge: true)
            return nil
        }) { _, error in
            if let error { print("Flux: remote gift append failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Signatures

    override func sendSignature(profileOwnerId: String, text: String) async throws -> ProfileSignature {
        let signature = try await super.sendSignature(profileOwnerId: profileOwnerId, text: text)
        if remote, let ownerFluxId = fluxIdOfUser(profileOwnerId), !ownerFluxId.isEmpty {
            pushSignatureToRemoteProfile(ownerFluxId, signature)
        }
        return signature
    }

    override func updateSignatureStatus(_ signatureId: String, _ status: SignatureStatus) async {
        await super.updateSignatureStatus(signatureId, status)
        if remote { publishExtendedProfile() }
    }

    override func deleteSignature(_ signatureId: String) async {
        await super.deleteSignature(signatureId)
        if remote { publishExtendedProfile() }
    }

    /// Atomically upserts the signature into the owner's remote array.
    private func pushSignatureToRemoteProfile(_ ownerFluxId: String, _ signature: ProfileSignature) {
        let ref = db.collection("users").document(ownerFluxId)
            .collection("profile").document("data")
        db.runTransaction({ transaction, errorPointer in
            let doc: DocumentSnapshot
            do {
                doc = try transaction.getDocument(ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            let data = doc.data() ?? [:]
            var signatures = data["signatures"] as? [[String: Any]] ?? []
            signatures.removeAll { ($0["id"] as? String) == signature.id }
            signatures.insert(signature.toJson(), at: 0)
            transaction.setData([
                "signatures": signatures,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: ref, merge: true)
            return nil
        }) { _, error in
            if let error { print("Flux: remote signature push failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Marketplace

    override func listUsernameForSale(username: String, price: Int) async throws -> MarketplaceListing {
        let listing = try await super.listUsernameForSale(username: username, price: price)
        if remote {
            try? await db.collection("marketplace").document(listing.id).setData(listing.toJson())
        }
        return listing
    }

    override func cancelListing(_ listingId: String) async {
        await super.cancelListing(listingId)
        if remote {
            db.collection("marketplace").document(listingId).delete { error in
                if let error { print("Flux: marketplace cancel mirror failed: \(error.localizedDescription)") }
            }
        }
    }

    override func buyUsername(_ listingId: String) async throws {
        if remote {
            // Server-side atomic purchase: a Firestore transaction
            // re-validates the listing and the balance, then commits the
            // sale, the buyer deduction and the seller credit in one step —
            // two buyers can never purchase the same username.
            try await runRemoteUsernamePurchase(listingId)
        }
        try await super.buyUsername(listingId)
        if remote { publishExtendedProfile() }
    }

    private func runRemoteUsernamePurchase(_ listingId: String) async throws {
        guard let myFluxId = me?.fluxId, !myFluxId.isEmpty else { return }
        let listingRef = db.collection("marketplace").document(listingId)
        let myProfileRef = db.collection("users").document(myFluxId)
            .collection("profile").document("data")
        let myUserId = me?.id ?? "me"

        // The transaction completion assigns the failure here before the
        // continuation resumes, so it can be rethrown to the caller.
        var purchaseError: FluxError?

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            db.runTransaction({ transaction, errorPointer -> Void? in
                let listingDoc: DocumentSnapshot
                let myDoc: DocumentSnapshot
                do {
                    listingDoc = try transaction.getDocument(listingRef)
                    myDoc = try transaction.getDocument(myProfileRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                guard listingDoc.exists else {
                    errorPointer?.pointee = NSError(domain: "Flux", code: -1, userInfo: [NSLocalizedDescriptionKey: "Лот не найден"])
                    return nil
                }
                let listingData = listingDoc.data() ?? [:]
                if listingData["sold"] as? Bool == true {
                    errorPointer?.pointee = NSError(domain: "Flux", code: -2, userInfo: [NSLocalizedDescriptionKey: "Этот username уже продан"])
                    return nil
                }
                let price = (listingData["price"] as? NSNumber)?.intValue ?? 0
                let username = listingData["username"] as? String ?? ""
                let sellerId = listingData["sellerId"] as? String ?? ""

                let myData = myDoc.data() ?? [:]
                let balance = (myData["fluxCoins"] as? NSNumber)?.intValue ?? 0
                if balance < price {
                    errorPointer?.pointee = NSError(domain: "Flux", code: -3, userInfo: [NSLocalizedDescriptionKey: FluxError.insufficientCoins(price, balance).message])
                    return nil
                }

                let nowMs = Int(Date().timeIntervalSince1970 * 1000)

                // Buyer: deduct coins, record the transaction, take ownership.
                var buyerTxs = myData["coinTransactions"] as? [[String: Any]] ?? []
                buyerTxs.insert(CoinTransaction(
                    id: UUID().uuidString, userId: myUserId, amount: -price,
                    type: .usernamePurchase, timestampMs: nowMs,
                    description: "Покупка username @\(username)",
                    relatedObjectId: listingId
                ).toJson(), at: 0)
                var buyerNames = myData["additionalUsernames"] as? [[String: Any]] ?? []
                buyerNames.insert(UsernameEntry(
                    username: username, ownerId: myUserId, acquiredAtMs: nowMs
                ).toJson(), at: 0)
                transaction.setData([
                    "fluxCoins": balance - price,
                    "coinTransactions": buyerTxs,
                    "additionalUsernames": buyerNames,
                    "updatedAt": FieldValue.serverTimestamp(),
                ], forDocument: myProfileRef, merge: true)

                // Listing: sold.
                transaction.updateData(["sold": true], forDocument: listingRef)

                // Credit the seller when their remote doc is known.
                let sellerFluxId = fluxIdOfUser(sellerId)
                if let sellerFluxId, !sellerFluxId.isEmpty, sellerFluxId != myFluxId {
                    let sellerRef = db.collection("users").document(sellerFluxId)
                        .collection("profile").document("data")
                    let sellerDoc: DocumentSnapshot
                    do {
                        sellerDoc = try transaction.getDocument(sellerRef)
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                    let sellerData = sellerDoc.data() ?? [:]
                    let sellerBalance = (sellerData["fluxCoins"] as? NSNumber)?.intValue ?? 0
                    var sellerTxs = sellerData["coinTransactions"] as? [[String: Any]] ?? []
                    sellerTxs.insert(CoinTransaction(
                        id: UUID().uuidString, userId: sellerId, amount: price,
                        type: .usernameSale, timestampMs: nowMs,
                        description: "Продажа username @\(username)",
                        relatedObjectId: listingId
                    ).toJson(), at: 0)
                    var sellerNames = sellerData["additionalUsernames"] as? [[String: Any]] ?? []
                    sellerNames.removeAll {
                        ($0["username"] as? String)?.lowercased() == username.lowercased()
                    }
                    transaction.setData([
                        "fluxCoins": sellerBalance + price,
                        "coinTransactions": sellerTxs,
                        "additionalUsernames": sellerNames,
                        "updatedAt": FieldValue.serverTimestamp(),
                    ], forDocument: sellerRef, merge: true)
                }
                return nil
            }) { _, error in
                if let error {
                    print("Flux: remote username purchase failed: \(error.localizedDescription)")
                    purchaseError = FluxError(error.localizedDescription)
                }
                continuation.resume()
            }
        }

        if let purchaseError {
            throw purchaseError
        }
    }

    // MARK: - Streak / visibility / badge shop

    override func checkAndUpdateDailyStreak() async -> Bool {
        let changed = await super.checkAndUpdateDailyStreak()
        if changed, remote { publishExtendedProfile() }
        return changed
    }

    override func updateVisibility(_ visibility: ProfileVisibility) async {
        await super.updateVisibility(visibility)
        if remote { publishExtendedProfile() }
    }

    override func purchaseBadge(_ badgeId: String) async throws {
        try await super.purchaseBadge(badgeId)
        if remote { publishExtendedProfile() }
    }

    // MARK: - Remote profiles of other users

    override func profileOf(_ userId: String) -> UserProfile? {
        let local = super.profileOf(userId)
        guard remote, let me, me.id != userId else { return local }
        guard let fluxId = fluxIdOfUser(userId), fluxId.count >= 4 else { return local }
        guard !remoteProfileFetches.contains(userId) else { return local }
        remoteProfileFetches.insert(userId)
        Task { [weak self] in
            guard let self else { return }
            await self.refreshRemoteProfile(userId: userId, fluxId: fluxId)
            self.remoteProfileFetches.remove(userId)
        }
        return local
    }

    private func refreshRemoteProfile(userId: String, fluxId: String) async {
        do {
            let doc = try await db.collection("users").document(fluxId)
                .collection("profile").document("data").getDocument()
            guard let data = doc.data() else { return }
            cacheRemoteProfile(userId, UserProfile.fromJson(data))
        } catch {
            print("Flux: remote profile fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Logout

    override func logout() async {
        chatsListener?.remove()
        sessionsListener?.remove()
        chatsListener = nil
        sessionsListener = nil
        messageListeners.values.forEach { $0.remove() }
        messageListeners = [:]
        await super.logout()
    }
}
