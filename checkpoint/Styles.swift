//
//  Styles.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI

extension View {
    /// Makes a button label fill the available width with a comfortable tap height.
    func primaryActionLabel() -> some View {
        frame(maxWidth: .infinity, minHeight: 44)
            .font(.headline)
    }

    /// Capsule button corners to match the pill navbar.
    func squarishButtons() -> some View {
        buttonBorderShape(.capsule)
    }
}
