//
//  Styles.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  Design system for the "dark editorial" visual pass: a warm near-black ground,
//  a muted gold accent, hairline/outlined chrome, and two button treatments
//  (semantic-filled pills + outlined ghosts). See the design handoff for tokens.
//

import SwiftUI

// MARK: - Color tokens

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Checkpoint palette — the whole app renders dark in this pass.
enum CK {
    /// Screen background — warm near-black.
    static let background = Color(hex: 0x191715)
    /// Elevated chip/card/plate fill.
    static let surface = Color(hex: 0x242220)
    /// Headings, primary labels — warm off-white.
    static let textPrimary = Color(hex: 0xF2EFE9)
    /// Secondary labels, timestamps.
    static let textSecondary = Color(hex: 0xF2EFE9, alpha: 0.65)
    /// Captions, placeholders, muted meta.
    static let textTertiary = Color(hex: 0xF2EFE9, alpha: 0.55)
    /// 1px borders and row separators.
    static let divider = Color(hex: 0xF2EFE9, alpha: 0.16)
    /// Brand accent — icon strokes, focal rings, filled gold buttons.
    static let gold = Color(hex: 0xB68235)
    /// Accent for text/icons on the near-black ground (a lighter gold).
    static let goldText = Color(hex: 0xE1AD66)
    /// Dark text placed on the gold fill.
    static let onGold = Color(hex: 0x201F1D)
    /// Danger red — live badges, End Emergency, 911, incoming alert. Always solid.
    static let danger = Color(hex: 0xB3261E)
    /// Neutral mid — the "Watching" secondary filled button.
    static let neutralMid = Color(hex: 0x9B9797)
}

// MARK: - Text treatments

extension View {
    /// Small-caps gold kicker label above a section (e.g. "ADD A FRIEND").
    func ckKicker() -> some View {
        self
            .font(.system(size: 12, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(CK.goldText)
    }
}

/// A gold small-caps section header.
struct CKKicker: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).ckKicker()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A 1px hairline in the divider color, used as a flush row separator.
struct CKHairline: View {
    var body: some View {
        Rectangle()
            .fill(CK.divider)
            .frame(height: 1)
    }
}

// MARK: - Containers

extension View {
    /// Fills the screen with the warm near-black ground behind the content.
    func ckScreenBackground() -> some View {
        background(CK.background.ignoresSafeArea())
    }

    /// Wraps content in an outlined, hairline-bordered card.
    func ckOutlinedCard(cornerRadius: CGFloat = 10, padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(CK.divider, lineWidth: 1)
            )
    }
}

// MARK: - Button styles

/// Solid, semantic-colored pill. Use for primary calls-to-action and true
/// action buttons (gold "Coming", red "End Emergency"/"911", neutral "Watching").
struct FilledPillButtonStyle: ButtonStyle {
    var fill: Color
    var textColor: Color
    var minHeight: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Transparent, hairline/accent-outlined pill. Use for secondary, less-urgent
/// actions ("Hide Screen", "Scan a friend's code", "Get Directions").
struct OutlinedPillButtonStyle: ButtonStyle {
    var stroke: Color = CK.divider
    var textColor: Color = CK.textPrimary
    var minHeight: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(Capsule().strokeBorder(stroke, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == FilledPillButtonStyle {
    static var goldFilled: FilledPillButtonStyle { .init(fill: CK.gold, textColor: CK.onGold) }
    static var dangerFilled: FilledPillButtonStyle { .init(fill: CK.danger, textColor: .white) }
    static var neutralFilled: FilledPillButtonStyle { .init(fill: CK.neutralMid, textColor: CK.textPrimary) }
}

extension ButtonStyle where Self == OutlinedPillButtonStyle {
    static var ghost: OutlinedPillButtonStyle { .init() }
}
