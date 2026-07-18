//
//  TriggerEmergencyIntent.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  Exposes "Trigger Emergency" to the Shortcuts app so it can be bound to
//  iOS Back Tap (Settings > Accessibility > Touch > Back Tap). Running it opens
//  the app and sets a pending flag that ContentView acts on when it becomes active.
//

import AppIntents
import Foundation

struct TriggerEmergencyIntent: AppIntent {
    static var title: LocalizedStringResource = "Trigger Emergency"
    static var description = IntentDescription("Silently start an emergency livestream and alert your friends.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "pendingEmergencyTrigger")
        return .result()
    }
}

struct CheckpointShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TriggerEmergencyIntent(),
            phrases: ["Trigger emergency in \(.applicationName)"],
            shortTitle: "Trigger Emergency",
            systemImageName: "exclamationmark.triangle.fill"
        )
    }
}
