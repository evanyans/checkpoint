//
//  DeviceIdentity.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  Lightweight per-device identity so the log can show who triggered each
//  incident. Defaults to the device name; overridable via the "friendName" key
//  (bound to a TextField with @AppStorage in the Log tab).
//

import Foundation
import UIKit

enum DeviceIdentity {
    static let nameKey = "friendName"

    static var currentName: String {
        let stored = UserDefaults.standard.string(forKey: nameKey) ?? ""
        return stored.isEmpty ? UIDevice.current.name : stored
    }
}
