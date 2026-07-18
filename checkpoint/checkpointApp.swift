//
//  checkpointApp.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI
import FirebaseCore

@main
struct checkpointApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
