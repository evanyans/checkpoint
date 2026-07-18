//
//  AvatarView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI

/// A circular avatar showing a profile photo, or initials on the accent color
/// when no photo is set.
struct AvatarView: View {
    let image: UIImage?
    let name: String
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.25))
                    Text(initials)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        return String(letters).uppercased()
    }
}
