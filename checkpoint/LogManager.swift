//
//  LogManager.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  Read-only history of every emergency session, newest first, for the Log tab.
//

import Foundation
import Combine
import CoreLocation
import FirebaseFirestore

struct LogEntry: Identifiable {
    let id: String
    let triggeredBy: String
    let createdAt: Date?
    let status: String
    let latitude: Double?
    let longitude: Double?
    let response: String?
    let captureCount: Int
    let notes: String
    let analysis: SuspectAnalysis?

    init(id: String, data: [String: Any]) {
        self.id = id
        self.triggeredBy = data["triggeredBy"] as? String ?? "Unknown"
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        self.status = data["status"] as? String ?? "unknown"
        self.latitude = data["latitude"] as? Double
        self.longitude = data["longitude"] as? Double
        self.response = data["response"] as? String
        self.captureCount = data["captureCount"] as? Int ?? 0
        self.notes = data["notes"] as? String ?? ""
        self.analysis = SuspectAnalysis(
            data: data["analysis"] as? [String: Any],
            updatedAt: (data["analysisUpdatedAt"] as? Timestamp)?.dateValue()
        )
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class LogManager: ObservableObject {
    @Published var entries: [LogEntry] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func start() {
        listener = db.collection("sessions")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                let items = snapshot?.documents.map {
                    LogEntry(id: $0.documentID, data: $0.data())
                } ?? []
                DispatchQueue.main.async {
                    self?.entries = items
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func updateNotes(sessionId: String, notes: String) {
        db.collection("sessions").document(sessionId).updateData(["notes": notes])
    }

    func fetchCaptures(sessionId: String, completion: @escaping ([CaptureItem]) -> Void) {
        db.collection("sessions").document(sessionId).collection("captures")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, _ in
                let items: [CaptureItem] = snapshot?.documents.compactMap { doc in
                    guard let base64 = doc.data()["image"] as? String,
                          let data = Data(base64Encoded: base64),
                          let image = UIImage(data: data) else { return nil }
                    return CaptureItem(id: doc.documentID, image: image)
                } ?? []
                DispatchQueue.main.async {
                    completion(items)
                }
            }
    }
}
