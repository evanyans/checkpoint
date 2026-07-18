//
//  IncomingAlertView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI

struct IncomingAlertView: View {
    let onView: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.accentColor.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                Text("Emergency Alert")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("A friend needs help right now.")
                    .foregroundStyle(.white.opacity(0.9))

                Button {
                    onView()
                } label: {
                    Text("View Stream")
                        .primaryActionLabel()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color.accentColor)
                .squarishButtons()

                Button("Dismiss") {
                    onDismiss()
                }
                .foregroundStyle(.white)
                .padding(.top, 4)
            }
            .padding()
        }
    }
}

#Preview {
    IncomingAlertView(onView: {}, onDismiss: {})
}
