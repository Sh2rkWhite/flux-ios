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
    private var ownDocListener: ListenerRegistration?
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var remoteProfileFetches: Set<String> = []

    // FluxCoinsBot listeners (shared `coinsBot/` namespace).
    private var botChecksListener: ListenerRegistration?
    private var botOffersListener: ListenerRegistration?
    private var botDealsSellerListener: ListenerRegistration?
    private var botDealsBuyerListener: ListenerRegistration?
    private var remoteDeals: [String: FluxP2pDeal] = [:]

    /// Firebase Auth UID of the signed-in account (nil in local mode or
    /// while the Auth provider is unavailable).
    private var authUid: String?

    private static let bioPasswordKeyPrefix = "flux.bio_password."
    private let vault = KeychainStore()

    override var simulatePeers: Bool { false }

    // MARK: - Init

    override func initBackend() async {
        await super.initBackend()
        remote = FirebaseApp.app() != nil
            && FirebaseApp.app()?.options.projectID != LocalBackend.placeholderProject
            && !(FirebaseApp.app()?.options.projectID ?? "").isEmpty
        guard remote else {
            print("Flux: Firestore disabled — running local-only.")
            return
        }
        print("Flux: Firestore project \"\(FirebaseApp.app()?.options.projectID ?? "")\" connected.")
        // Firebase Auth persists its session across app launches.
        authUid = FluxAuth.currentUid
        await applyRemoteProfile()
        await loadExtendedProfile()
        publishProfile()
        await pullDirectory()
        await pullMarketplace()
        listenSessions()
        listenChats()
        listenCoinsBot()
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
            avatarPath: data["avatar_url"] as? String,
            isPremium: data["isPremium"] as? Bool ?? false,
            isOnline: data["is_online"] as? Bool ?? false,
            isAdmin: data["is_admin"] as? Bool ?? false,
            registeredAtMs: registeredAtMs,
            isVerified: data["is_verified"] as? Bool ?? false,
            mutedUntilMs: (data["mutedUntilMs"] as? NSNumber)?.intValue ?? 0,
            frozenUntilMs: (data["frozenUntilMs"] as? NSNumber)?.intValue ?? 0,
            mutedReason: data["mutedReason"] as? String,
            frozenReason: data["frozenReason"] as? String
        )
    }

    // MARK: - Registration / login hooks

    override func registerSmart(username: String, email: String, password: String, displayName: String) async throws -> FluxUser {
        let user = try await super.registerSmart(username: username, email: email, password: password, displayName: displayName)
        if remote {
            // Create the Firebase Auth account (password verified
            // server-side from now on — works on any device/platform).
            let outcome = await FluxAuth.register(
                fluxId: user.fluxId,
                password: password.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if outcome.ok {
                authUid = outcome.uid
                publishAuthMapping()
            } else {
                print("Flux: Firebase Auth registration skipped (\(outcome.error ?? "unavailable"))")
            }
            publishProfile()
            listenSessions()
            listenChats()
            listenCoinsBot()
        }
        return user
    }

    /// Cross-device login — Firebase Auth is the source of truth for the
    /// password. Legacy accounts (created before the migration) are
    /// verified against the local salted hash first, then their Firebase
    /// Auth account is created on the fly.
    override func loginSmart(username: String, password: String) async throws -> FluxUser {
        guard remote else {
            return try await super.loginSmart(username: username, password: password)
        }

        guard let found = await lookupUsername(username) else {
            throw FluxError.userNotFound
        }
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasLocalHash = (found.passwordHash ?? "").isEmpty == false
        if hasLocalHash, let stored = found.passwordHash,
           !PinHash.verify(trimmed, stored: stored) {
            throw FluxError.wrongPassword
        }

        var uid: String?
        if hasLocalHash {
            // Local hash verified — ensure the Auth account exists
            // (one-time migration for pre-Auth accounts).
            var outcome = await FluxAuth.signIn(fluxId: found.fluxId, password: trimmed)
            if outcome.notFound {
                outcome = await FluxAuth.register(fluxId: found.fluxId, password: trimmed)
            }
            if outcome.ok {
                uid = outcome.uid
            } else if !outcome.unavailable {
                throw FluxError(outcome.error ?? "Ошибка авторизации")
            }
        } else {
            // Remote-only account — Firebase Auth is the sole verifier.
            let outcome = await FluxAuth.signIn(fluxId: found.fluxId, password: trimmed)
            if outcome.ok {
                uid = outcome.uid
            } else if outcome.notFound {
                throw FluxError("Аккаунт создан в старой версии Flux. Войдите сначала на устройстве, где создавали аккаунт — вход выполнится автоматически, после чего вход с других устройств станет доступен.")
            } else {
                throw FluxError(outcome.error ?? "Ошибка авторизации")
            }
        }

        authUid = uid

        // Credentials verified — restore the account on this device.
        let user: FluxUser
        if found.id == "me" {
            user = found
        } else {
            user = await restoreAccountFromRemote(found)
        }
        if uid != nil { publishAuthMapping() }
        publishProfile()
        listenSessions()
        listenChats()
        listenCoinsBot()

        try await postSecurityNotification(welcome: false)
        await recordLoginSession()
        _ = await checkAndUpdateDailyStreak()
        return user
    }

    /// Loads the account document + extended profile from Firestore and
    /// installs them as the local `me` (login on a new device).
    private func restoreAccountFromRemote(_ found: FluxUser) async -> FluxUser {
        let user = FluxUser(
            id: "me",
            fluxId: found.fluxId,
            name: found.name,
            username: found.username,
            status: found.status,
            avatarPath: found.avatarPath,
            isPremium: found.isPremium,
            isAdmin: found.isAdmin,
            registeredAtMs: found.registeredAtMs,
            isVerified: found.isVerified,
            mutedUntilMs: found.mutedUntilMs,
            frozenUntilMs: found.frozenUntilMs,
            mutedReason: found.mutedReason,
            frozenReason: found.frozenReason
        )
        me = user
        persistProfile()

        // Pull the extended profile (XP, coins, gifts, badges, streak, …).
        do {
            let doc = try await db.collection("users").document(found.fluxId)
                .collection("profile").document("data").getDocument()
            if let data = doc.data() {
                let remoteProfile = UserProfile.fromJson(data)
                await mergeRemoteProfile(Self.mergeRemoteSnapshot(UserProfile.initial, remoteProfile))
            }
        } catch {
            print("Flux: remote profile restore failed: \(error.localizedDescription)")
        }
        notify()
        return user
    }

    /// Biometric quick-login still needs a Firebase Auth session for the
    /// Firestore rules — the enrolled account's password is kept in the
    /// Keychain for this purpose.
    override func loginBiometric(username: String) async throws -> FluxUser {
        if remote {
            let pw = vault.read(Self.bioPasswordKeyPrefix + username.lowercased())
            if let pw, !pw.isEmpty, let found = await lookupUsername(username),
               !found.fluxId.isEmpty {
                let outcome = await FluxAuth.signIn(
                    fluxId: found.fluxId,
                    password: pw.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                if outcome.ok { authUid = outcome.uid }
            }
        }
        let user = try await super.loginBiometric(username: username)
        if remote {
            listenSessions()
            listenChats()
            listenCoinsBot()
            publishProfile()
        }
        return user
    }

    /// Stores the password in the Keychain so a future biometric login can
    /// restore the Firebase Auth session without asking for it.
    func saveBiometricPassword(_ username: String, _ password: String) {
        guard !password.isEmpty else { return }
        try? vault.write(Self.bioPasswordKeyPrefix + username.lowercased(), password)
    }

    func deleteBiometricPassword(_ username: String) {
        vault.delete(Self.bioPasswordKeyPrefix + username.lowercased())
    }

    override func saveBiometricLogin(_ username: String, password: String?) async {
        await super.saveBiometricLogin(username, password: password)
        if let password { saveBiometricPassword(username, password) }
    }

    override func clearBiometricLogin() async {
        if let username = biometricLoginUsername { deleteBiometricPassword(username) }
        await super.clearBiometricLogin()
    }

    // MARK: - FluxID confirmation

    override func confirmFluxId(_ fluxId: String) async throws -> FluxUser {
        let user = try await super.confirmFluxId(fluxId)
        if remote {
            publishProfile()
            listenSessions()
            listenChats()
            listenCoinsBot()
        }
        return user
    }

    // MARK: - On-demand user resolution

    /// Resolves a user by id. When the contact is not cached locally yet the
    /// real user document is fetched from Firestore, so opening a profile from
    /// a chat always works even before the directory pull finishes.
    override func ensureUser(_ userId: String) async -> FluxUser? {
        if let local = userById(userId) { return local }
        guard remote, !userId.isEmpty else { return nil }
        if let meId = me?.id, userId == meId { return me }

        var fluxId: String?
        if userId.hasPrefix("r-") {
            fluxId = String(userId.dropFirst(2)).uppercased()
        } else if Self.looksLikeFluxId(userId) {
            fluxId = userId.uppercased()
        }
        guard let fluxId, !fluxId.isEmpty else { return nil }
        if fluxId == me?.fluxId?.uppercased() { return nil }

        do {
            let doc = try await db.collection("users").document(fluxId).getDocument()
            guard doc.exists, let data = doc.data() else { return nil }
            let user = Self.userFromDoc(fluxId, data)
            upsertContact(user)
            return userById(userId) ?? user
        } catch {
            print("Flux: ensureUser fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func looksLikeFluxId(_ value: String) -> Bool {
        value.count == 12 && value.uppercased().hasPrefix("FLX-")
    }

    /// Publishes the `usersByUid/{uid} → fluxId` mapping used by the
    /// Firestore security rules to resolve ownership from `request.auth`.
    private func publishAuthMapping() {
        guard let uid = authUid, let fluxId = me?.fluxId, !fluxId.isEmpty else { return }
        db.collection("usersByUid").document(uid).setData([
            "fluxId": fluxId,
            "username": me?.username?.lowercased() ?? NSNull(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]) { error in
            if let error { print("Flux: auth mapping failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Remote profile sync

    /// Pulls the remote Firestore document for the current user and applies
    /// server-side state the client cannot set itself: `is_admin`,
    /// `is_verified`, moderation (mute/freeze) and the registration date.
    private func applyRemoteProfile() async {
        guard let cur = me, !cur.fluxId.isEmpty else { return }
        do {
            let doc = try await db.collection("users").document(cur.fluxId).getDocument()
            guard let data = doc.data() else { return }
            let remoteAdmin = data["is_admin"] as? Bool ?? false
            let remoteVerified = data["is_verified"] as? Bool ?? false
            let mutedUntilMs = (data["mutedUntilMs"] as? NSNumber)?.intValue ?? 0
            let frozenUntilMs = (data["frozenUntilMs"] as? NSNumber)?.intValue ?? 0
            let mutedReason = data["mutedReason"] as? String
            let frozenReason = data["frozenReason"] as? String
            var registeredAtMs = cur.registeredAtMs
            if let ts = data["created_at"] as? Timestamp, registeredAtMs == nil {
                registeredAtMs = Int(ts.dateValue().timeIntervalSince1970 * 1000)
            }
            let changed = remoteAdmin != cur.isAdmin
                || remoteVerified != cur.isVerified
                || mutedUntilMs != cur.mutedUntilMs
                || frozenUntilMs != cur.frozenUntilMs
                || registeredAtMs != cur.registeredAtMs
            guard changed else { return }
            patchMe { user in
                user.isAdmin = remoteAdmin
                user.isVerified = remoteVerified
                user.mutedUntilMs = mutedUntilMs
                user.frozenUntilMs = frozenUntilMs
                user.mutedReason = mutedReason
                user.frozenReason = frozenReason
                user.registeredAtMs = registeredAtMs
            }
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
        var data: [String: Any] = [
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
        // Link the Firebase Auth UID (security rules resolve ownership
        // through usersByUid + this field).
        if let authUid { data["authUid"] = authUid }
        // created_at / server flags must not be re-merged on every publish —
        // the rules reject writes touching created_at once it exists. Write
        // them only while the doc still lacks them.
        docRef.getDocument { [weak self] snapshot, _ in
            guard let self else { return }
            let existing = snapshot?.data() ?? [:]
            let batch = self.db.batch()
            var backfill: [String: Any] = [:]
            if existing["created_at"] == nil {
                backfill["created_at"] = FieldValue.serverTimestamp()
            }
            if existing["is_admin"] == nil { backfill["is_admin"] = false }
            if existing["is_verified"] == nil { backfill["is_verified"] = false }
            if !backfill.isEmpty {
                batch.setData(backfill, forDocument: docRef, merge: true)
            }
            batch.setData(data, forDocument: docRef, merge: true)
            batch.commit { error in
                if let error {
                    print("Flux: profile publish FAILED: \(error.localizedDescription)")
                }
            }
        }
    }

    override func updateMe(name: String? = nil, status: String? = nil, avatarPath: String? = nil, isPremium: Bool? = nil) async {
        var finalAvatarPath = avatarPath
        if remote, let fluxId = me?.fluxId, !fluxId.isEmpty,
           let localPath = avatarPath,
           !FluxMedia.isStorageRef(localPath),
           FileManager.default.fileExists(atPath: localPath) {
            if let ref = await FluxMedia.uploadFile(localPath: localPath, objectPath: "avatars/\(fluxId.lowercased())") {
                finalAvatarPath = ref
            }
        }
        await super.updateMe(name: name, status: status, avatarPath: finalAvatarPath, isPremium: isPremium)
        if remote { publishProfile() }
    }

    override func updateUsername(_ newUsername: String) async throws {
        try await super.updateUsername(newUsername)
        if remote { publishProfile() }
    }

    // MARK: - Extended profile

    override func updateProfile(bannerPath: String? = nil, location: String? = nil, website: String? = nil, birthday: String? = nil) async {
        var finalBannerPath = bannerPath
        if remote, let fluxId = me?.fluxId, !fluxId.isEmpty,
           let localPath = bannerPath,
           !FluxMedia.isStorageRef(localPath),
           FileManager.default.fileExists(atPath: localPath) {
            if let ref = await FluxMedia.uploadFile(localPath: localPath, objectPath: "banners/\(fluxId)") {
                finalBannerPath = ref
            }
        }
        await super.updateProfile(bannerPath: finalBannerPath, location: location, website: website, birthday: birthday)
        if remote { publishExtendedProfile() }
    }

    @discardableResult
    override func publishStory(mediaPath: String, caption: String? = nil) async -> FluxStory {
        var finalPath = mediaPath
        if remote, let fluxId = me?.fluxId, !fluxId.isEmpty,
           !FluxMedia.isStorageRef(mediaPath),
           FileManager.default.fileExists(atPath: mediaPath) {
            if let ref = await FluxMedia.uploadFile(localPath: mediaPath, objectPath: "stories/\(fluxId)/\(UUID().uuidString)") {
                finalPath = ref
            }
        }
        let story = await super.publishStory(mediaPath: finalPath, caption: caption)
        if remote { publishExtendedProfile() }
        return story
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
                    let sessions = snapshot.documents.map { doc in
                        var json = doc.data()
                        json["id"] = doc.documentID
                        return DeviceSession.fromJson(json)
                    }
                    self.patchMe { user in
                        user.sessions = sessions
                    }
                    self.persistProfile()
                    self.notify()
                }
            }
        listenOwnDoc()
    }

    /// Live-syncs the own user document: moderation (mute/freeze),
    /// verification and admin flags apply immediately, without re-login
    /// (the iOS counterpart of the Android `_listenOwnDoc`).
    private func listenOwnDoc() {
        guard remote, let myFluxId = me?.fluxId, !myFluxId.isEmpty, ownDocListener == nil else { return }
        ownDocListener = db.collection("users").document(myFluxId)
            .addSnapshotListener { [weak self] _, error in
                guard let self, error == nil else { return }
                Task { @MainActor in
                    await self.applyRemoteProfile()
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

    // MARK: - Moderation (admin)

    override func setModeration(_ user: FluxUser, mute: Bool, untilMs: Int, reason: String?) {
        super.setModeration(user, mute: mute, untilMs: untilMs, reason: reason)
        guard remote, !user.fluxId.isEmpty else { return }
        let fields: [String: Any] = mute
            ? ["mutedUntilMs": untilMs, "mutedReason": reason ?? NSNull()]
            : ["frozenUntilMs": untilMs, "frozenReason": reason ?? NSNull()]
        db.collection("users").document(user.fluxId).updateData(fields) { error in
            if let error { print("Flux: moderation write failed: \(error.localizedDescription)") }
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
                        let isOwn = (data["senderId"] as? String) == myFluxId
                        guard let contact = self.contacts.values.first(where: { $0.fluxId == peerFluxId }),
                              let chat = self.chatWithPeer(contact.id) else { continue }
                        var json = data
                        json["id"] = doc.documentID
                        json["chatId"] = chat.id
                        json["senderId"] = isOwn ? (self.me?.id ?? "me") : chat.peerId
                        json["deliveredAtMs"] = nowMs
                        let message = FluxMessage.fromJson(json)
                        self.ingestRemoteMessage(message, preview: data["text"] as? String, incrementUnread: !isOwn)
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
    /// Firestore message subcollections. Local media files are uploaded to
    /// Storage first; the remote payloads then carry the `flux-storage:`
    /// reference while the local message keeps its local path.
    private func mirrorOutgoing(_ chat: FluxChat, _ message: FluxMessage) async {
        guard let myFluxId = me?.fluxId, !myFluxId.isEmpty,
              let peerFluxId = contacts[chat.peerId]?.fluxId, !peerFluxId.isEmpty else { return }

        writeChatMeta(owner: myFluxId, peer: peerFluxId)
        writeChatMeta(owner: peerFluxId, peer: myFluxId)

        var payload = message.toJson()
        payload["senderId"] = myFluxId

        if let mediaPath = message.mediaPath,
           !FluxMedia.isStorageRef(mediaPath),
           FileManager.default.fileExists(atPath: mediaPath) {
            let ext: String
            switch message.kind {
            case .image: ext = "jpg"
            case .voice: ext = "m4a"
            case .text, .file: ext = FluxMedia.ext(of: message.fileName ?? mediaPath)
            }
            if let ref = await FluxMedia.uploadFile(
                localPath: mediaPath,
                objectPath: "chat_media/\(myFluxId)/\(message.id).\(ext)"
            ) {
                payload["mediaPath"] = ref
            }
        }

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
            await mirrorOutgoing(chat, message)
        }
        return message
    }

    override func sendImage(_ chatId: String, _ path: String, replyToId: String? = nil) async -> FluxMessage {
        let message = await super.sendImage(chatId, path, replyToId: replyToId)
        if remote, let chat = chatById(chatId) {
            await mirrorOutgoing(chat, message)
        }
        return message
    }

    override func sendVoice(_ chatId: String, _ path: String, _ durationMs: Int, replyToId: String? = nil) async -> FluxMessage {
        let message = await super.sendVoice(chatId, path, durationMs, replyToId: replyToId)
        if remote, let chat = chatById(chatId) {
            await mirrorOutgoing(chat, message)
        }
        return message
    }

    override func sendFile(_ chatId: String, _ path: String, _ fileName: String, _ fileSize: Int, replyToId: String? = nil) async -> FluxMessage {
        let message = await super.sendFile(chatId, path, fileName, fileSize, replyToId: replyToId)
        if remote, let chat = chatById(chatId) {
            await mirrorOutgoing(chat, message)
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

    // MARK: - FluxCoinsBot (@FluxCoinsBot) — shared `coinsBot/` namespace
    //
    // Every coin mutation runs inside a single Firestore transaction that
    // re-validates balances and record statuses at commit time, so coins can
    // never be double-spent, checks can never be redeemed twice, escrowed
    // coins can never be released twice and balances can never go negative.
    // The transactionId stored on each record is its idempotency key.
    //
    //   coinsBot/checks/{checkId}       — FluxCheck documents
    //   coinsBot/p2p_offers/{offerId}   — FluxP2pOffer documents
    //   coinsBot/p2p_deals/{dealId}     — FluxP2pDeal documents
    //   coinsBot/transfers/{txId}       — transfer receipts (audit trail)

    private func profileDataRef(_ fluxId: String) -> DocumentReference {
        db.collection("users").document(fluxId).collection("profile").document("data")
    }

    private static func balanceOf(_ data: [String: Any]?) -> Int {
        (data?["fluxCoins"] as? NSNumber)?.intValue ?? 0
    }

    private func requireMyFluxId() throws -> String {
        guard let fluxId = me?.fluxId, !fluxId.isEmpty else {
            throw FluxError("Профиль не загружен")
        }
        return fluxId
    }

    /// Runs a Firestore transaction for the bot operations. A [FluxError]
    /// thrown by the body (business validation) is rethrown verbatim; any
    /// other failure surfaces the method-specific Russian fallback message —
    /// the same split as the Dart `on StateError rethrow / catch → generic`.
    private func runCoinsBotTransaction<T>(
        fallback: String,
        _ body: @escaping (Transaction) throws -> T
    ) async throws -> T {
        var result: T?
        var botError: FluxError?

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            db.runTransaction({ transaction, errorPointer -> Void? in
                do {
                    result = try body(transaction)
                    return nil
                } catch let error as FluxError {
                    botError = error
                    errorPointer?.pointee = NSError(domain: "Flux", code: -1, userInfo: [NSLocalizedDescriptionKey: error.message])
                    return nil
                } catch {
                    botError = FluxError(fallback)
                    errorPointer?.pointee = NSError(domain: "Flux", code: -2, userInfo: [NSLocalizedDescriptionKey: fallback])
                    return nil
                }
            }) { _, error in
                if let error {
                    print("Flux: coins bot transaction failed: \(error.localizedDescription)")
                    if botError == nil {
                        botError = FluxError(fallback)
                    }
                }
                continuation.resume()
            }
        }

        if let botError { throw botError }
        guard let result else { throw FluxError(fallback) }
        return result
    }

    private func runCoinsBotTransaction(fallback: String, _ body: @escaping (Transaction) throws -> Void) async throws {
        try await runCoinsBotTransaction(fallback: fallback) { transaction -> Bool in
            try body(transaction)
            return true
        }
    }

    /// Credits `amount` coins to `fluxId` inside the transaction, recording a
    /// ledger entry of `type`. Used for cross-user payouts (transfers, refunds).
    private func creditUserInTx(
        _ transaction: Transaction,
        _ fluxId: String,
        amount: Int,
        type: CoinTransactionType,
        description: String,
        nowMs: Int,
        relatedObjectId: String? = nil
    ) throws {
        let ref = profileDataRef(fluxId)
        let snap = try transaction.getDocument(ref)
        let data = snap.data() ?? [:]
        var txs = data["coinTransactions"] as? [[String: Any]] ?? []
        txs.insert(CoinTransaction(
            id: UUID().uuidString,
            userId: "r-\(fluxId.lowercased())",
            amount: amount,
            type: type,
            timestampMs: nowMs,
            description: description,
            relatedObjectId: relatedObjectId
        ).toJson(), at: 0)
        transaction.setData([
            "fluxCoins": Self.balanceOf(data) + amount,
            "coinTransactions": txs,
            "updatedAt": FieldValue.serverTimestamp(),
        ], forDocument: ref, merge: true)
    }

    /// Re-reads the own balance and history from Firestore after a committed
    /// bot transaction so the local cache mirrors the shared ledger exactly.
    private func reloadCoinsFromRemote() async {
        guard let myFluxId = me?.fluxId, !myFluxId.isEmpty else { return }
        do {
            let doc = try await profileDataRef(myFluxId).getDocument()
            guard let data = doc.data() else { return }
            let txs = (data["coinTransactions"] as? [[String: Any]] ?? []).map(CoinTransaction.fromJson)
            replaceLocalCoins(balance: Self.balanceOf(data), transactions: txs)
        } catch {
            print("Flux: coins reload failed: \(error.localizedDescription)")
        }
    }

    /// Live-syncs the shared FluxCoinsBot state: own checks, the P2P market
    /// and own P2P deals (seller or buyer side).
    private func listenCoinsBot() {
        guard remote, let myFluxId = me?.fluxId, !myFluxId.isEmpty, botChecksListener == nil else { return }

        botChecksListener = db.collection("coinsBot/checks")
            .whereField("creatorFluxId", isEqualTo: myFluxId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else {
                    if let error { print("Flux: checks listener failed: \(error.localizedDescription)") }
                    return
                }
                Task { @MainActor in
                    self.syncBotChecks(snapshot.documents.map { FluxCheck.fromJson($0.data()) })
                }
            }

        botOffersListener = db.collection("coinsBot/p2p_offers")
            .order(by: "createdAtMs", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else {
                    if let error { print("Flux: offers listener failed: \(error.localizedDescription)") }
                    return
                }
                Task { @MainActor in
                    self.syncBotOffers(snapshot.documents.map { FluxP2pOffer.fromJson($0.data()) })
                }
            }

        botDealsSellerListener = db.collection("coinsBot/p2p_deals")
            .whereField("sellerFluxId", isEqualTo: myFluxId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else {
                    if let error { print("Flux: deals listener failed: \(error.localizedDescription)") }
                    return
                }
                Task { @MainActor in
                    for doc in snapshot.documents {
                        self.remoteDeals[doc.documentID] = FluxP2pDeal.fromJson(doc.data())
                    }
                    self.syncBotDeals(Array(self.remoteDeals.values))
                }
            }

        botDealsBuyerListener = db.collection("coinsBot/p2p_deals")
            .whereField("buyerFluxId", isEqualTo: myFluxId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else {
                    if let error { print("Flux: deals listener failed: \(error.localizedDescription)") }
                    return
                }
                Task { @MainActor in
                    for doc in snapshot.documents {
                        self.remoteDeals[doc.documentID] = FluxP2pDeal.fromJson(doc.data())
                    }
                    self.syncBotDeals(Array(self.remoteDeals.values))
                }
            }
    }

    private func cancelCoinsBotListeners() {
        botChecksListener?.remove()
        botOffersListener?.remove()
        botDealsSellerListener?.remove()
        botDealsBuyerListener?.remove()
        botChecksListener = nil
        botOffersListener = nil
        botDealsSellerListener = nil
        botDealsBuyerListener = nil
        remoteDeals = [:]
    }

    override func coinsTransfer(toFluxId: String, amount: Int) async throws -> String {
        guard remote else { return try await super.coinsTransfer(toFluxId: toFluxId, amount: amount) }
        let myFluxId = try requireMyFluxId()
        guard amount > 0 else { throw FluxError("Сумма должна быть больше нуля") }
        let to = toFluxId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !to.isEmpty, to != myFluxId.uppercased() else {
            throw FluxError("Нельзя перевести самому себе")
        }
        let txId = UUID().uuidString
        let myRef = profileDataRef(myFluxId)
        let receiptRef = db.collection("coinsBot/transfers").document(txId)
        let myUserId = me?.id ?? "me"

        try await runCoinsBotTransaction(fallback: "Перевод не выполнен. Попробуйте ещё раз.") { transaction in
            let mySnap = try transaction.getDocument(myRef)
            let myData = mySnap.data() ?? [:]
            let balance = Self.balanceOf(myData)
            guard balance >= amount else {
                throw FluxError.insufficientCoins(amount, balance)
            }
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)

            // Sender: debit + ledger entry.
            var myTxs = myData["coinTransactions"] as? [[String: Any]] ?? []
            myTxs.insert(CoinTransaction(
                id: txId, userId: myUserId, amount: -amount,
                type: .coinsTransferSent, timestampMs: nowMs,
                description: "Перевод → \(to)",
                relatedObjectId: txId
            ).toJson(), at: 0)
            transaction.setData([
                "fluxCoins": balance - amount,
                "coinTransactions": myTxs,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: myRef, merge: true)

            // Recipient: credit + ledger entry (same atomic step).
            try self.creditUserInTx(transaction, to,
                                    amount: amount,
                                    type: .coinsTransferReceived,
                                    description: "Входящий перевод от \(myFluxId)",
                                    nowMs: nowMs,
                                    relatedObjectId: txId)

            // Payment receipt (audit trail, immutable).
            transaction.setData([
                "transactionId": txId,
                "fromFluxId": myFluxId,
                "toFluxId": to,
                "amount": amount,
                "createdAtMs": nowMs,
            ], forDocument: receiptRef)
            return txId
        }
        await reloadCoinsFromRemote()
        return txId
    }

    override func createCheck(amount: Int, recipientFluxId: String? = nil, ttlMs: Int? = nil) async throws -> FluxCheck {
        guard remote else {
            return try await super.createCheck(amount: amount, recipientFluxId: recipientFluxId, ttlMs: ttlMs)
        }
        let myFluxId = try requireMyFluxId()
        guard amount > 0 else { throw FluxError("Сумма должна быть больше нуля") }
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let check = FluxCheck(
            id: UUID().uuidString,
            amount: amount,
            creatorFluxId: myFluxId,
            status: .active,
            transactionId: UUID().uuidString,
            createdAtMs: nowMs,
            recipientFluxId: recipientFluxId,
            expiresAtMs: ttlMs.map { nowMs + $0 }
        )
        let myRef = profileDataRef(myFluxId)
        let myUserId = me?.id ?? "me"
        try await runCoinsBotTransaction(fallback: "Не удалось создать чек. Попробуйте ещё раз.") { transaction in
            let mySnap = try transaction.getDocument(myRef)
            let myData = mySnap.data() ?? [:]
            let balance = Self.balanceOf(myData)
            guard balance >= amount else {
                throw FluxError.insufficientCoins(amount, balance)
            }
            var myTxs = myData["coinTransactions"] as? [[String: Any]] ?? []
            myTxs.insert(CoinTransaction(
                id: check.transactionId, userId: myUserId, amount: -amount,
                type: .checkCreated, timestampMs: nowMs,
                description: "Создание чека на \(amount)",
                relatedObjectId: check.id
            ).toJson(), at: 0)
            transaction.setData([
                "fluxCoins": balance - amount,
                "coinTransactions": myTxs,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: myRef, merge: true)
            transaction.setData(check.toJson(), forDocument: self.db.collection("coinsBot/checks").document(check.id))
        }
        await reloadCoinsFromRemote()
        syncBotChecks([check] + myChecks.filter { $0.id != check.id })
        return check
    }

    override func redeemCheck(_ checkId: String) async throws -> FluxCheck {
        guard remote else { return try await super.redeemCheck(checkId) }
        let myFluxId = try requireMyFluxId()
        let checkRef = db.collection("coinsBot/checks").document(checkId)
        var consumed: FluxCheck?
        try await runCoinsBotTransaction(fallback: "Не удалось получить чек. Попробуйте ещё раз.") { transaction in
            let snap = try transaction.getDocument(checkRef)
            guard snap.exists, let data = snap.data() else { throw FluxError("Чек не найден") }
            let check = FluxCheck.fromJson(data)
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            guard check.status == .active else { throw FluxError("Этот чек уже использован") }
            if check.isExpired(nowMs) { throw FluxError("Срок действия чека истёк") }
            if let recipient = check.recipientFluxId, recipient.uppercased() != myFluxId.uppercased() {
                throw FluxError("Этот чек предназначен другому пользователю")
            }
            try self.creditUserInTx(transaction, myFluxId,
                                    amount: check.amount,
                                    type: .checkRedeemed,
                                    description: "Получение по чеку",
                                    nowMs: nowMs,
                                    relatedObjectId: check.id)
            consumed = check.copyWith(status: .redeemed, redeemedByFluxId: myFluxId, redeemedAtMs: nowMs)
            transaction.updateData([
                "status": CheckStatus.redeemed.rawValue,
                "redeemedByFluxId": myFluxId,
                "redeemedAtMs": nowMs,
            ], forDocument: checkRef)
        }
        await reloadCoinsFromRemote()
        guard let consumed else { throw FluxError("Не удалось получить чек. Попробуйте ещё раз.") }
        return consumed
    }

    override func cancelCheck(_ checkId: String) async throws {
        guard remote else { return try await super.cancelCheck(checkId) }
        let myFluxId = try requireMyFluxId()
        let checkRef = db.collection("coinsBot/checks").document(checkId)
        try await runCoinsBotTransaction(fallback: "Не удалось отменить чек. Попробуйте ещё раз.") { transaction in
            let snap = try transaction.getDocument(checkRef)
            guard snap.exists, let data = snap.data() else { throw FluxError("Чек не найден") }
            let check = FluxCheck.fromJson(data)
            guard check.status == .active else { throw FluxError("Чек уже закрыт") }
            guard check.creatorFluxId.uppercased() == myFluxId.uppercased() else {
                throw FluxError("Отменить может только создатель чека")
            }
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            try self.creditUserInTx(transaction, myFluxId,
                                    amount: check.amount,
                                    type: .checkRefund,
                                    description: "Возврат по чеку",
                                    nowMs: nowMs,
                                    relatedObjectId: check.id)
            transaction.updateData(["status": CheckStatus.cancelled.rawValue], forDocument: checkRef)
        }
        await reloadCoinsFromRemote()
    }

    override func createP2pSellOffer(coinAmount: Int, priceNote: String = "") async throws -> FluxP2pOffer {
        guard remote else {
            return try await super.createP2pSellOffer(coinAmount: coinAmount, priceNote: priceNote)
        }
        let myFluxId = try requireMyFluxId()
        guard coinAmount > 0 else { throw FluxError("Сумма должна быть больше нуля") }
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let offer = FluxP2pOffer(
            id: UUID().uuidString,
            side: .sell,
            coinAmount: coinAmount,
            creatorFluxId: myFluxId,
            status: .open,
            transactionId: UUID().uuidString,
            createdAtMs: nowMs,
            priceNote: priceNote
        )
        let myRef = profileDataRef(myFluxId)
        let myUserId = me?.id ?? "me"
        try await runCoinsBotTransaction(fallback: "Не удалось создать предложение. Попробуйте ещё раз.") { transaction in
            let mySnap = try transaction.getDocument(myRef)
            let myData = mySnap.data() ?? [:]
            let balance = Self.balanceOf(myData)
            guard balance >= coinAmount else {
                throw FluxError.insufficientCoins(coinAmount, balance)
            }
            var myTxs = myData["coinTransactions"] as? [[String: Any]] ?? []
            myTxs.insert(CoinTransaction(
                id: offer.transactionId, userId: myUserId, amount: -coinAmount,
                type: .p2pEscrow, timestampMs: nowMs,
                description: "P2P: блокировка \(coinAmount)",
                relatedObjectId: offer.id
            ).toJson(), at: 0)
            transaction.setData([
                "fluxCoins": balance - coinAmount,
                "coinTransactions": myTxs,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: myRef, merge: true)
            transaction.setData(offer.toJson(), forDocument: self.db.collection("coinsBot/p2p_offers").document(offer.id))
        }
        await reloadCoinsFromRemote()
        return offer
    }

    override func acceptP2pOffer(_ offerId: String) async throws -> FluxP2pDeal {
        guard remote else { return try await super.acceptP2pOffer(offerId) }
        let myFluxId = try requireMyFluxId()
        let offerRef = db.collection("coinsBot/p2p_offers").document(offerId)
        var deal: FluxP2pDeal?
        try await runCoinsBotTransaction(fallback: "Не удалось принять предложение. Попробуйте ещё раз.") { transaction in
            let snap = try transaction.getDocument(offerRef)
            guard snap.exists, let data = snap.data() else { throw FluxError("Предложение не найдено") }
            let offer = FluxP2pOffer.fromJson(data)
            guard offer.status == .open else { throw FluxError("Предложение уже недоступно") }
            guard offer.creatorFluxId.uppercased() != myFluxId.uppercased() else {
                throw FluxError("Нельзя принять собственное предложение")
            }
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            let newDeal = FluxP2pDeal(
                id: UUID().uuidString,
                offerId: offer.id,
                sellerFluxId: offer.creatorFluxId,
                buyerFluxId: myFluxId,
                coinAmount: offer.coinAmount,
                status: .escrow,
                transactionId: UUID().uuidString,
                createdAtMs: nowMs
            )
            // Coins were escrowed when the offer was created; matching only
            // flips statuses. The transaction makes double-accept impossible.
            transaction.updateData(["status": OfferStatus.matched.rawValue], forDocument: offerRef)
            transaction.setData(newDeal.toJson(), forDocument: self.db.collection("coinsBot/p2p_deals").document(newDeal.id))
            deal = newDeal
        }
        guard let deal else { throw FluxError("Не удалось принять предложение. Попробуйте ещё раз.") }
        return deal
    }

    override func confirmP2pDeal(_ dealId: String) async throws -> FluxP2pDeal {
        guard remote else { return try await super.confirmP2pDeal(dealId) }
        let myFluxId = try requireMyFluxId()
        let dealRef = db.collection("coinsBot/p2p_deals").document(dealId)
        var done: FluxP2pDeal?
        try await runCoinsBotTransaction(fallback: "Не удалось подтвердить сделку. Попробуйте ещё раз.") { transaction in
            let snap = try transaction.getDocument(dealRef)
            guard snap.exists, let data = snap.data() else { throw FluxError("Сделка не найдена") }
            let deal = FluxP2pDeal.fromJson(data)
            guard deal.status == .escrow else { throw FluxError("Сделка уже завершена") }
            guard deal.sellerFluxId.uppercased() == myFluxId.uppercased() else {
                throw FluxError("Подтвердить сделку может только продавец")
            }
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            // Release the escrowed coins to the buyer.
            try self.creditUserInTx(transaction, deal.buyerFluxId,
                                    amount: deal.coinAmount,
                                    type: .p2pReleased,
                                    description: "P2P: получение",
                                    nowMs: nowMs,
                                    relatedObjectId: deal.id)
            done = deal.copyWith(status: .completed, resolvedAtMs: nowMs)
            transaction.updateData([
                "status": DealStatus.completed.rawValue,
                "resolvedAtMs": nowMs,
            ], forDocument: dealRef)
        }
        guard let done else { throw FluxError("Не удалось подтвердить сделку. Попробуйте ещё раз.") }
        return done
    }

    override func disputeP2pDeal(_ dealId: String) async throws -> FluxP2pDeal {
        guard remote else { return try await super.disputeP2pDeal(dealId) }
        _ = try requireMyFluxId()
        let dealRef = db.collection("coinsBot/p2p_deals").document(dealId)
        var disputed: FluxP2pDeal?
        try await runCoinsBotTransaction(fallback: "Не удалось открыть спор. Попробуйте ещё раз.") { transaction in
            let snap = try transaction.getDocument(dealRef)
            guard snap.exists, let data = snap.data() else { throw FluxError("Сделка не найдена") }
            let deal = FluxP2pDeal.fromJson(data)
            guard deal.status == .escrow else { throw FluxError("Спор можно открыть только по активной сделке") }
            disputed = deal.copyWith(status: .disputed)
            transaction.updateData(["status": DealStatus.disputed.rawValue], forDocument: dealRef)
        }
        guard let disputed else { throw FluxError("Не удалось открыть спор. Попробуйте ещё раз.") }
        return disputed
    }

    override func cancelP2p(_ refId: String) async throws {
        guard remote else { return try await super.cancelP2p(refId) }
        let myFluxId = try requireMyFluxId()
        let offerRef = db.collection("coinsBot/p2p_offers").document(refId)
        let dealRef = db.collection("coinsBot/p2p_deals").document(refId)
        try await runCoinsBotTransaction(fallback: "Не удалось отменить. Попробуйте ещё раз.") { transaction in
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            let offerSnap = try transaction.getDocument(offerRef)
            if offerSnap.exists {
                let offer = FluxP2pOffer.fromJson(offerSnap.data() ?? [:])
                guard offer.status == .open else { throw FluxError("Предложение уже недоступно") }
                guard offer.creatorFluxId.uppercased() == myFluxId.uppercased() else {
                    throw FluxError("Отменить может только автор предложения")
                }
                // Refund the escrowed coins to the creator.
                try self.creditUserInTx(transaction, myFluxId,
                                        amount: offer.coinAmount,
                                        type: .p2pRefund,
                                        description: "P2P: возврат",
                                        nowMs: nowMs,
                                        relatedObjectId: offer.id)
                transaction.updateData(["status": OfferStatus.cancelled.rawValue], forDocument: offerRef)
                return
            }
            let dealSnap = try transaction.getDocument(dealRef)
            if dealSnap.exists {
                let deal = FluxP2pDeal.fromJson(dealSnap.data() ?? [:])
                guard deal.status == .escrow else { throw FluxError("Сделка уже завершена") }
                // Refund the escrowed coins to the seller.
                try self.creditUserInTx(transaction, deal.sellerFluxId,
                                        amount: deal.coinAmount,
                                        type: .p2pRefund,
                                        description: "P2P: возврат",
                                        nowMs: nowMs,
                                        relatedObjectId: deal.id)
                transaction.updateData([
                    "status": DealStatus.cancelled.rawValue,
                    "resolvedAtMs": nowMs,
                ], forDocument: dealRef)
                return
            }
            throw FluxError("Не найдено")
        }
        await reloadCoinsFromRemote()
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
                let sellerFluxId = self.fluxIdOfUser(sellerId)
                if let sellerFluxId, !sellerFluxId.isEmpty, sellerFluxId != myFluxId {
                    let sellerRef = self.db.collection("users").document(sellerFluxId)
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
        ownDocListener?.remove()
        chatsListener = nil
        sessionsListener = nil
        ownDocListener = nil
        messageListeners.values.forEach { $0.remove() }
        messageListeners = [:]
        cancelCoinsBotListeners()
        FluxAuth.signOut()
        authUid = nil
        await super.logout()
    }
}
