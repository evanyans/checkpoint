//
//  LogReadState.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-18.
//
//  Tracks which incident logs the user has *seen* (drives the red dot on the Log
//  tab) and which they've *opened* (drives the per-row unread dot). Persisted to
//  UserDefaults so both survive relaunches.
//

import Foundation
import Combine

final class LogReadState: ObservableObject {
    @Published private(set) var seenIds: Set<String>
    @Published private(set) var openedIds: Set<String>

    private let seenKey = "logSeenIds"
    private let openedKey = "logOpenedIds"

    init() {
        let defaults = UserDefaults.standard
        seenIds = Set(defaults.stringArray(forKey: "logSeenIds") ?? [])
        openedIds = Set(defaults.stringArray(forKey: "logOpenedIds") ?? [])
    }

    /// True if any of these logs hasn't been seen yet — shows the Log tab dot.
    func hasUnseen(among ids: [String]) -> Bool {
        ids.contains { !seenIds.contains($0) }
    }

    func isOpened(_ id: String) -> Bool { openedIds.contains(id) }

    /// Call while the user is viewing the Log tab — clears the tab dot.
    func markAllSeen(_ ids: [String]) {
        let updated = seenIds.union(ids)
        guard updated != seenIds else { return }
        seenIds = updated
        persist(updated, key: seenKey)
    }

    /// Call when the user opens a specific incident — clears that row's unread dot.
    func markOpened(_ id: String) {
        guard !openedIds.contains(id) else { return }
        openedIds.insert(id)
        persist(openedIds, key: openedKey)
        if !seenIds.contains(id) {
            seenIds.insert(id)
            persist(seenIds, key: seenKey)
        }
    }

    private func persist(_ set: Set<String>, key: String) {
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}
