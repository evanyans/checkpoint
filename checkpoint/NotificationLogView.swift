//
//  NotificationLogView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  An append-only log of responder actions on an emergency session. Every time
//  a viewer taps a response (Coming / 911 / Watching) it lands here, so both the
//  broadcaster and every viewer can see who has already acted — and nobody has
//  to double-call 911 or double-drive to the scene. It informs, it never blocks.
//

import SwiftUI
import FirebaseFirestore

struct NotificationLogEntry: Identifiable {
    let id: String
    let actor: String
    let action: String
    let etaMinutes: Int?
    let createdAt: Date?

    init(id: String, data: [String: Any]) {
        self.id = id
        self.actor = data["actor"] as? String ?? "Someone"
        self.action = data["action"] as? String ?? ""
        self.etaMinutes = data["etaMinutes"] as? Int
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
    }

    var response: FriendResponse? { FriendResponse(rawValue: action) }

    /// One-line, human summary of who did what.
    var summary: String {
        switch response {
        case .called911: return "\(actor) called 911"
        case .coming:
            if let etaMinutes { return "\(actor) is on the way · ETA \(etaMinutes) min" }
            return "\(actor) is on the way"
        case .watching: return "\(actor) is watching"
        case .none: return "\(actor) responded"
        }
    }

    var tint: Color {
        switch response {
        case .called911: return .orange
        case .coming: return .accentColor
        case .watching: return Color(.systemGray)
        case .none: return Color(.systemGray)
        }
    }
}

/// Compact, self-contained activity feed. Drop it into any screen that has the
/// current list of notifications; it scrolls internally so it never blows out a
/// space-constrained layout.
struct NotificationLogView: View {
    let entries: [NotificationLogEntry]
    var maxHeight: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Responder activity", systemImage: "bell.badge.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                Text("No one has responded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { NotificationLogRow(entry: $0) }
                    }
                }
                .frame(maxHeight: maxHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NotificationLogRow: View {
    let entry: NotificationLogEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.response?.iconName ?? "bell.fill")
                .font(.caption)
                .foregroundStyle(entry.tint)
                .frame(width: 18)

            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            if let date = entry.createdAt {
                Text(date, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NotificationLogView(entries: [
        NotificationLogEntry(id: "1", data: ["actor": "Mom", "action": "called911"]),
        NotificationLogEntry(id: "2", data: ["actor": "Alex", "action": "coming", "etaMinutes": 8]),
        NotificationLogEntry(id: "3", data: ["actor": "Sam", "action": "watching"]),
    ])
    .padding()
}
