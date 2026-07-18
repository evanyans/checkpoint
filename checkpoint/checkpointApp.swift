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
    // AppDelegate configures Firebase and registers for push notifications.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
