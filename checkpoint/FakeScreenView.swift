//
//  FakeScreenView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  Placeholder disguise shown while an emergency is active. A triple-tap returns
//  to the livestream. Later, onboarding will let the user pick which screen this
//  shows (e.g. a screenshot of their real home/lock screen).
//

import SwiftUI

struct FakeScreenView: View {
    let onDismiss: () -> Void

    var body: some View {
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
        // Triple-tap anywhere returns to the livestream.
        .contentShape(Rectangle())
        .onTapGesture(count: 3) { onDismiss() }
    }
}

#Preview {
    FakeScreenView(onDismiss: {})
}
