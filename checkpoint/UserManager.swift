//
//  UserManager.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  Lightweight per-device identity and friend graph (no accounts). Each device
//  has a stable userId and a short shareable friend code. Your friends list is
//  the set of people alerted when YOU trigger an emergency.
//

import Foundation
import Combine
import UIKit
import FirebaseFirestore

struct Friend: Identifiable, Equatable {
    let id: String
    let name: String
    /// 1 = alerted immediately, 2 = alerted only if no one joins in the first 2 min.
    var priority: Int = 1
}

/// The details a 911 operator would need. Populated by onboarding (TBD); for now
/// editable via Settings → My Profile.
struct UserProfile: Equatable {
    var age = ""
    var height = ""
    var race = ""
    var physicalDescription = ""
    var accessories = ""
    var medicalNotes = ""
    var emergencyContactName = ""
    var emergencyContactPhone = ""

    init() {}

    init(map: [String: Any]) {
        age = map["age"] as? String ?? ""
        height = map["height"] as? String ?? ""
        race = map["race"] as? String ?? ""
        physicalDescription = map["physicalDescription"] as? String ?? ""
        accessories = map["accessories"] as? String ?? ""
        medicalNotes = map["medicalNotes"] as? String ?? ""
        emergencyContactName = map["emergencyContactName"] as? String ?? ""
        emergencyContactPhone = map["emergencyContactPhone"] as? String ?? ""
    }

    var asMap: [String: Any] {
        [
            "age": age,
            "height": height,
            "race": race,
            "physicalDescription": physicalDescription,
            "accessories": accessories,
            "medicalNotes": medicalNotes,
            "emergencyContactName": emergencyContactName,
            "emergencyContactPhone": emergencyContactPhone,
        ]
    }
}

final class UserManager: ObservableObject {
    @Published var friends: [Friend] = []
    @Published var myProfile = UserProfile()
    @Published var myPhoto: UIImage?
    @Published private(set) var myCode: String = ""

    let userId: String

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var tokenObserver: NSObjectProtocol?
    private var photoCache: [String: UIImage] = [:]

    init() {
        if let existing = UserDefaults.standard.string(forKey: "userId") {
            userId = existing
        } else {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: "userId")
            userId = new
        }
        myCode = Self.code(from: userId)
    }

    deinit {
        if let tokenObserver { NotificationCenter.default.removeObserver(tokenObserver) }
    }

    /// A 6-char uppercase code derived from the UUID, shown to friends.
    static func code(from userId: String) -> String {
        let hex = userId.replacingOccurrences(of: "-", with: "").uppercased()
        return String(hex.prefix(6))
    }

    var friendIds: [String] { friends.map(\.id) }
    var p1FriendIds: [String] { friends.filter { $0.priority == 1 }.map(\.id) }
    var p2FriendIds: [String] { friends.filter { $0.priority == 2 }.map(\.id) }

    func start() {
        let ref = db.collection("users").document(userId)
        ref.setData([
            "name": DeviceIdentity.currentName,
            "code": myCode,
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true)

        // Persist FCM push token so the Cloud Function can notify this user's
        // friends when they trigger an emergency. Save whatever is cached now,
        // and update whenever APNs hands us a fresh token.
        if let token = AppDelegate.currentToken {
            savePushToken(token)
        }
        tokenObserver = NotificationCenter.default.addObserver(
            forName: AppDelegate.fcmTokenDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let token = note.object as? String else { return }
            self?.savePushToken(token)
        }

        listener = ref.addSnapshotListener { [weak self] snapshot, _ in
            let data = snapshot?.data()
            let raw = data?["friends"] as? [[String: Any]] ?? []
            // Priority lives in a parallel {friendId: 1|2} map so the existing friends
            // array stays a stable {id, name} shape and arrayUnion/Remove keep working.
            let priorities = data?["friendPriorities"] as? [String: Int] ?? [:]
            let friends = raw.compactMap { dict -> Friend? in
                guard let id = dict["id"] as? String,
                      let name = dict["name"] as? String else { return nil }
                return Friend(id: id, name: name, priority: priorities[id] ?? 1)
            }
            let profile = UserProfile(map: data?["profile"] as? [String: Any] ?? [:])
            let photo = Self.decodePhoto(data?["photo"] as? String)
            DispatchQueue.main.async {
                self?.friends = friends
                self?.myProfile = profile
                if let photo {
                    self?.myPhoto = photo
                    self?.photoCache[self?.userId ?? ""] = photo
                }
            }
        }
    }

    private static func decodePhoto(_ base64: String?) -> UIImage? {
        guard let base64, let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    func updatePhoto(_ image: UIImage) {
        guard let data = downscaledJPEG(image, maxDimension: 256, quality: 0.6) else { return }
        photoCache[userId] = image
        myPhoto = image
        db.collection("users").document(userId).setData(["photo": data.base64EncodedString()], merge: true)
    }

    /// Loads a friend's avatar (cached after first fetch).
    func loadPhoto(userId: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = photoCache[userId] {
            completion(cached)
            return
        }
        db.collection("users").document(userId).getDocument { [weak self] snapshot, _ in
            let image = Self.decodePhoto(snapshot?.data()?["photo"] as? String)
            if let image { self?.photoCache[userId] = image }
            DispatchQueue.main.async { completion(image) }
        }
    }

    func updateName(_ name: String) {
        db.collection("users").document(userId).setData(["name": name], merge: true)
    }

    private func savePushToken(_ token: String) {
        db.collection("users").document(userId).setData(["fcmToken": token], merge: true)
    }

    func updateProfile(_ profile: UserProfile) {
        db.collection("users").document(userId).setData(["profile": profile.asMap], merge: true)
    }

    /// Fetches a friend's display name and profile for the detail view.
    func fetchProfile(userId: String, completion: @escaping (String, UserProfile) -> Void) {
        db.collection("users").document(userId).getDocument { snapshot, _ in
            let data = snapshot?.data()
            let name = data?["name"] as? String ?? "Friend"
            let profile = UserProfile(map: data?["profile"] as? [String: Any] ?? [:])
            DispatchQueue.main.async {
                completion(name, profile)
            }
        }
    }

    /// Adds a friend found by their 6-char code. Instantly mutual — see
    /// `addFriend(toUserId:name:)`. `completion` gets an error string, or nil on success.
    func addFriend(byCode code: String, completion: @escaping (String?) -> Void) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { completion("Enter a code."); return }
        guard trimmed != myCode else { completion("That's your own code."); return }

        db.collection("users").whereField("code", isEqualTo: trimmed).getDocuments { [weak self] snapshot, _ in
            guard let self else { return }
            guard let doc = snapshot?.documents.first else {
                completion("No one found with that code.")
                return
            }
            self.addFriend(toUserId: doc.documentID,
                           name: doc.data()["name"] as? String ?? "Friend",
                           completion: completion)
        }
    }

    /// Adds a friend by userId (e.g. from a scanned QR code) and forms the link in
    /// BOTH directions at once, so the other person never has to add you back:
    /// they go in my friends list, and I go in theirs. Both are then alerted when
    /// either triggers an emergency.
    func addFriend(toUserId id: String, name: String, completion: @escaping (String?) -> Void) {
        let targetId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetId.isEmpty else { completion("Invalid code."); return }
        guard targetId != userId else { completion("That's your own code."); return }
        guard !friendIds.contains(targetId) else { completion("You're already friends with \(name)."); return }

        let them: [String: Any] = ["id": targetId, "name": name]
        let me: [String: Any] = ["id": userId, "name": DeviceIdentity.currentName]

        // My own doc — always writable.
        db.collection("users").document(userId).setData([
            "friends": FieldValue.arrayUnion([them])
        ], merge: true)

        // Their doc — the other half of the link, so they don't have to add me.
        db.collection("users").document(targetId).setData([
            "friends": FieldValue.arrayUnion([me])
        ], merge: true) { error in
            completion(error == nil ? nil : "Couldn't add friend. Try again.")
        }
    }

    func removeFriend(_ friend: Friend) {
        db.collection("users").document(userId).updateData([
            "friends": FieldValue.arrayRemove([["id": friend.id, "name": friend.name]]),
            "friendPriorities.\(friend.id)": FieldValue.delete(),
        ])
    }

    /// Updates the notification priority (1 or 2) for a friend on my own doc.
    /// Dot-notation targets a single key inside the friendPriorities map so we
    /// never clobber other friends' entries.
    func updateFriendPriority(friendId: String, priority: Int) {
        let clamped = max(1, min(2, priority))
        db.collection("users").document(userId).setData([
            "friendPriorities": [friendId: clamped],
        ], merge: true)
    }
}
