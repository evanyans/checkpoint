//
//  SessionManager.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import Foundation
import Combine
import CoreLocation
import UIKit
import FirebaseFirestore

struct CaptureItem: Identifiable {
    let id: String
    let image: UIImage
}

struct EmergencySession: Identifiable, Equatable {
    let id: String
    let channelName: String
    let status: String
    let latitude: Double?
    let longitude: Double?
    let response: String?
    let etaMinutes: Int?
    let ownerId: String?
    let notifyIds: [String]
    let viewerIds: [String]
    let createdAt: Date?
    let analysis: SuspectAnalysis?

    /// An emergency older than this is treated as stale — we won't auto-pop its
    /// alert on launch, so leftover/unresolved sessions don't nag every reboot.
    static let recentWindow: TimeInterval = 15 * 60

    init?(id: String, data: [String: Any]) {
        guard let channelName = data["channelName"] as? String,
              let status = data["status"] as? String else { return nil }
        self.id = id
        self.channelName = channelName
        self.status = status
        self.latitude = data["latitude"] as? Double
        self.longitude = data["longitude"] as? Double
        self.response = data["response"] as? String
        self.etaMinutes = data["etaMinutes"] as? Int
        self.ownerId = data["ownerId"] as? String
        self.notifyIds = data["notifyIds"] as? [String] ?? []
        self.viewerIds = data["viewerIds"] as? [String] ?? []
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        self.analysis = SuspectAnalysis(
            data: data["analysis"] as? [String: Any],
            updatedAt: (data["analysisUpdatedAt"] as? Timestamp)?.dateValue()
        )
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// A brand-new session (server timestamp still resolving) counts as recent.
    var isRecent: Bool {
        guard let createdAt else { return true }
        return Date().timeIntervalSince(createdAt) < Self.recentWindow
    }
}

final class SessionManager: ObservableObject {
    @Published var activeSession: EmergencySession?
    @Published var captures: [CaptureItem] = []
    @Published var notifications: [NotificationLogEntry] = []
    /// Flips true when the specific session a viewer is watching gets resolved or
    /// deleted, so the viewer's screen can close instead of hanging on "Connecting…".
    @Published var viewedSessionEnded = false

    private(set) var createdSessionId: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var capturesListener: ListenerRegistration?
    private var notificationsListener: ListenerRegistration?
    private var viewedSessionListener: ListenerRegistration?

    func createSession(channelName: String, ownerId: String,
                       p1NotifyIds: [String], p2NotifyIds: [String],
                       escalationPhone: String? = nil, escalationDelayMinutes: Int? = nil,
                       disguiseNotifications: Bool = false,
                       victimDescription: String? = nil, medicalNotes: String? = nil,
                       incidentTime: String? = nil) {
        let ref = db.collection("sessions").document()
        createdSessionId = ref.documentID
        // Union goes in notifyIds so the existing in-app listener (which shows
        // the alert to anyone in notifyIds) still reaches P2 friends who open
        // the app on their own, even before the delayed push fires.
        let allIds = Array(Set(p1NotifyIds + p2NotifyIds))
        var data: [String: Any] = [
            "channelName": channelName,
            "status": "triggered",
            "triggeredBy": DeviceIdentity.currentName,
            "ownerId": ownerId,
            "notifyIds": allIds,
            "p1NotifyIds": p1NotifyIds,
            "p2NotifyIds": p2NotifyIds,
            "captureCount": 0,
            // When true, responder pushes back to me are disguised (see Cloud Function).
            "disguiseNotifications": disguiseNotifications,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        // If auto-escalation is configured, the backend agent reads these to place
        // an automated phone call once the session has been live past the delay.
        if let escalationPhone, !escalationPhone.isEmpty, let escalationDelayMinutes {
            data["escalationPhone"] = escalationPhone
            data["escalationDelayMinutes"] = escalationDelayMinutes
        }
        // Victim context the escalation-call agent reads out (see placeCall).
        if let victimDescription, !victimDescription.isEmpty { data["victimDescription"] = victimDescription }
        if let medicalNotes, !medicalNotes.isEmpty { data["medicalNotes"] = medicalNotes }
        if let incidentTime, !incidentTime.isEmpty { data["incidentTime"] = incidentTime }
        ref.setData(data)
    }

    /// Signals the backend to fan out the push to P2 friends. Set by the broadcaster
    /// after 2 minutes if no viewer has joined yet.
    func requestP2Fanout(sessionId: String) {
        db.collection("sessions").document(sessionId).updateData([
            "p2Fanout": true,
            "p2FanoutRequestedAt": FieldValue.serverTimestamp(),
        ])
    }

    func resolveSession(_ id: String) {
        db.collection("sessions").document(id).updateData(["status": "resolved"])
    }

    /// Toggle whether responder pushes back to the victim are disguised. Called live
    /// when the victim hides their screen (bystander likely present) or reveals it.
    func setDisguise(sessionId: String, on: Bool) {
        db.collection("sessions").document(sessionId).updateData([
            "disguiseNotifications": on
        ])
    }

    /// Signals the backend to place the escalation call now (the victim didn't
    /// confirm they were safe in time). The Cloud Function watches this flag.
    func requestEscalation(sessionId: String) {
        db.collection("sessions").document(sessionId).updateData([
            "escalate": true,
            "escalationRequestedAt": FieldValue.serverTimestamp(),
        ])
    }

    /// Viewer presence — used for the "N watching" count and to pause auto-escalation
    /// while a friend is on the stream.
    func addViewer(sessionId: String, userId: String) {
        db.collection("sessions").document(sessionId).updateData([
            "viewerIds": FieldValue.arrayUnion([userId])
        ])
    }

    func removeViewer(sessionId: String, userId: String) {
        db.collection("sessions").document(sessionId).updateData([
            "viewerIds": FieldValue.arrayRemove([userId])
        ])
    }

    func updateLocation(sessionId: String, coordinate: CLLocationCoordinate2D) {
        db.collection("sessions").document(sessionId).updateData([
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
        ])
    }

    /// Reverse-geocoded street address; the escalation call speaks this instead of
    /// raw coordinates. Written separately since geocoding resolves asynchronously.
    func updateLocationAddress(sessionId: String, address: String) {
        db.collection("sessions").document(sessionId).updateData([
            "locationAddress": address
        ])
    }

    func respond(sessionId: String, response: String, etaMinutes: Int? = nil) {
        var data: [String: Any] = [
            "response": response,
            "respondedAt": FieldValue.serverTimestamp(),
        ]
        // Attach an ETA for "coming"; clear any stale ETA for other responses.
        data["etaMinutes"] = etaMinutes ?? FieldValue.delete()
        db.collection("sessions").document(sessionId).updateData(data)

        // Also append to the append-only notification log so the broadcaster and
        // every other viewer can see who has already acted (e.g. someone already
        // called 911), instead of only ever seeing the single latest response.
        addNotification(sessionId: sessionId, response: response,
                        actor: DeviceIdentity.currentName, etaMinutes: etaMinutes)
    }

    func addNotification(sessionId: String, response: String, actor: String, etaMinutes: Int? = nil) {
        var data: [String: Any] = [
            "actor": actor,
            "action": response,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if let etaMinutes { data["etaMinutes"] = etaMinutes }
        db.collection("sessions").document(sessionId).collection("notifications").addDocument(data: data)
    }

    func listenToNotifications(sessionId: String) {
        notificationsListener?.remove()
        notificationsListener = db.collection("sessions").document(sessionId).collection("notifications")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                let items = snapshot?.documents.map {
                    NotificationLogEntry(id: $0.documentID, data: $0.data())
                } ?? []
                DispatchQueue.main.async {
                    self?.notifications = items
                }
            }
    }

    func stopNotificationsListener() {
        notificationsListener?.remove()
        notificationsListener = nil
        notifications = []
    }

    /// Watches one specific session document so a viewer closes the instant the
    /// broadcaster ends it (status leaves "triggered") or it's deleted — regardless
    /// of any other lingering sessions the global listener might otherwise latch onto.
    func watchViewedSession(sessionId: String) {
        viewedSessionListener?.remove()
        viewedSessionEnded = false
        viewedSessionListener = db.collection("sessions").document(sessionId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                let ended = !snapshot.exists ||
                    (snapshot.data()?["status"] as? String) != "triggered"
                if ended {
                    DispatchQueue.main.async { self.viewedSessionEnded = true }
                }
            }
    }

    func stopWatchingViewedSession() {
        viewedSessionListener?.remove()
        viewedSessionListener = nil
        viewedSessionEnded = false
    }

    /// Dev tool: force-resolve every session still marked "triggered". Clears zombie
    /// sessions that would otherwise resurface and bug the app. Reports how many were
    /// ended. Static so callers (e.g. Settings) don't need a live SessionManager.
    static func forceEndAllSessions(completion: @escaping (Int) -> Void) {
        let db = Firestore.firestore()
        db.collection("sessions").whereField("status", isEqualTo: "triggered").getDocuments { snapshot, _ in
            let docs = snapshot?.documents ?? []
            guard !docs.isEmpty else {
                DispatchQueue.main.async { completion(0) }
                return
            }
            let batch = db.batch()
            for doc in docs {
                batch.updateData(["status": "resolved"], forDocument: doc.reference)
            }
            batch.commit { _ in
                DispatchQueue.main.async { completion(docs.count) }
            }
        }
    }

    func addCapture(sessionId: String, jpeg: Data) {
        let sessionRef = db.collection("sessions").document(sessionId)
        sessionRef.collection("captures").addDocument(data: [
            "image": jpeg.base64EncodedString(),
            "createdAt": FieldValue.serverTimestamp(),
        ])
        sessionRef.updateData(["captureCount": FieldValue.increment(Int64(1))])
    }

    func listenToCaptures(sessionId: String) {
        capturesListener?.remove()
        capturesListener = db.collection("sessions").document(sessionId).collection("captures")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                let items: [CaptureItem] = snapshot?.documents.compactMap { doc in
                    guard let base64 = doc.data()["image"] as? String,
                          let data = Data(base64Encoded: base64),
                          let image = UIImage(data: data) else { return nil }
                    return CaptureItem(id: doc.documentID, image: image)
                } ?? []
                DispatchQueue.main.async {
                    self?.captures = items
                }
            }
    }

    func stopCapturesListener() {
        capturesListener?.remove()
        capturesListener = nil
        captures = []
    }

    func startListening(myUserId: String) {
        // Surface the most recent still-"triggered" session that concerns me:
        // either I own it (broadcaster) or I'm in its notify list (a friend).
        // Client-side filtering over recent sessions avoids a composite index.
        listener?.remove()
        listener = db.collection("sessions")
            .order(by: "createdAt", descending: true)
            .limit(to: 10)
            .addSnapshotListener { [weak self] snapshot, _ in
                let match = (snapshot?.documents ?? [])
                    .compactMap { EmergencySession(id: $0.documentID, data: $0.data()) }
                    .first { session in
                        session.status == "triggered" &&
                        (session.ownerId == myUserId || session.notifyIds.contains(myUserId))
                    }
                DispatchQueue.main.async {
                    self?.activeSession = match
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}
