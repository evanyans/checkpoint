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
        ZStack(alignment: .top) {
            CK.background.ignoresSafeArea()

            // 6px solid red top accent bar — the single life-safety signal.
            CK.danger
                .frame(height: 6)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .strokeBorder(CK.danger, lineWidth: 1.5)
                        .frame(width: 70, height: 70)
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(CK.danger)
                }

                VStack(spacing: 10) {
                    Text("Emergency Alert")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(CK.textPrimary)
                    Text("A friend needs help right now.")
                        .font(.system(size: 16))
                        .foregroundStyle(CK.textPrimary)
                }

                VStack(spacing: 14) {
                    Button {
                        onView()
                    } label: {
                        Text("View Stream").fontWeight(.bold)
                    }
                    .buttonStyle(FilledPillButtonStyle(fill: CK.danger, textColor: .white))

                    Button {
                        onDismiss()
                    } label: {
                        Text("Dismiss")
                            .font(.system(size: 15))
                            .foregroundStyle(CK.textSecondary)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 32)
        }
    }
}

#Preview {
    IncomingAlertView(onView: {}, onDismiss: {})
}
