//
//  FakeScreenView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  Placeholder disguise shown while an emergency is active. A triple-tap returns
//  to the livestream. The user picks which disguise to show from Settings.
//

import SwiftUI

/// User-selectable disguise shown by FakeScreenView. Persisted via @AppStorage
/// under `discreetMode` so both this view and SettingsView read the same value.
enum DiscreetMode: String, CaseIterable, Identifiable {
    case lockScreen
    case blackScreen

    static let storageKey = "discreetMode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lockScreen: "Phone lock screen"
        case .blackScreen: "Black screen"
        }
    }
}

struct FakeScreenView: View {
    let onDismiss: () -> Void

    @AppStorage(DiscreetMode.storageKey) private var discreetModeRaw = DiscreetMode.lockScreen.rawValue

    private var mode: DiscreetMode {
        DiscreetMode(rawValue: discreetModeRaw) ?? .lockScreen
    }

    var body: some View {
        Group {
            switch mode {
            case .lockScreen: lockScreenBody
            case .blackScreen: blackScreenBody
            }
        }
        // Triple-tap anywhere returns to the livestream.
        .contentShape(Rectangle())
        .onTapGesture(count: 3) { onDismiss() }
    }

    private var lockScreenBody: some View {
        ZStack {
            LinearGradient(
                colors: [.black, Color(white: 0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 4) {
                Spacer().frame(height: 90)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 2) {
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 84, weight: .thin))
                            .foregroundStyle(.white)
                    }
                }

                Spacer()

                Image(systemName: "lock.fill")
                    .foregroundStyle(.white.opacity(0.6))
                Text("Triple-tap to return")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.2))
                    .padding(.bottom, 24)
            }
        }
    }

    private var blackScreenBody: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            Text("Triple-tap to return")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.2))
                .padding(.bottom, 24)
        }
    }
}

#Preview {
    FakeScreenView(onDismiss: {})
}
