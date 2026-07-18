//
//  Item.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
