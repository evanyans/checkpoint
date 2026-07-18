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
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class SessionManager: ObservableObject {
    @Published var activeSession: EmergencySession?
    @Published var captures: [CaptureItem] = []
    @Published var notifications: [NotificationLogEntry] = []

    private(set) var createdSessionId: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var capturesListener: ListenerRegistration?
    private var notificationsListener: ListenerRegistration?

    func createSession(channelName: String, ownerId: String, notifyIds: [String]) {
        let ref = db.collection("sessions").document()
        createdSessionId = ref.documentID
        ref.setData([
            "channelName": channelName,
            "status": "triggered",
            "triggeredBy": DeviceIdentity.currentName,
            "ownerId": ownerId,
            "notifyIds": notifyIds,
            "captureCount": 0,
            "createdAt": FieldValue.serverTimestamp(),
        ])
    }

    func resolveSession(_ id: String) {
        db.collection("sessions").document(id).updateData(["status": "resolved"])
    }

    func updateLocation(sessionId: String, coordinate: CLLocationCoordinate2D) {
        db.collection("sessions").document(sessionId).updateData([
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
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
