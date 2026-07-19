//
//  RootView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI

struct RootView: View {
    @StateObject private var userManager = UserManager()
    @StateObject private var logManager = LogManager()
    @StateObject private var logReadState = LogReadState()
    @State private var selection = 0

    private var logHasUnread: Bool {
        logReadState.hasUnseen(among: logManager.entries.map(\.id))
    }

    var body: some View {
        TabView(selection: $selection) {
            ContentView(userManager: userManager)
                .tag(0)

            LogListView(logManager: logManager, readState: logReadState)
                .tag(1)

            SettingsView(userManager: userManager)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(CK.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            TabBar(selection: $selection, logHasUnread: logHasUnread)
        }
        .preferredColorScheme(.dark)
        .tint(CK.goldText)
        .onAppear {
            userManager.start()
            logManager.start()
        }
        // Viewing the Log tab clears the dot; new logs arriving while it's open
        // stay cleared. On any other tab, a new log lights the dot back up.
        .onChange(of: selection) { _, tab in
            if tab == 1 { logReadState.markAllSeen(logManager.entries.map(\.id)) }
        }
        .onChange(of: logManager.entries.map(\.id)) { _, ids in
            if selection == 1 { logReadState.markAllSeen(ids) }
        }
    }
}

private struct TabBar: View {
    @Binding var selection: Int
    var logHasUnread = false

    var body: some View {
        HStack(spacing: 6) {
            tabButton(0, icon: "shield.fill", label: "Home")
            tabButton(1, icon: "list.bullet.rectangle.fill", label: "Log", showsDot: logHasUnread)
            tabButton(2, icon: "gearshape.fill", label: "Settings")
        }
        .padding(6)
        .background(CK.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(CK.divider, lineWidth: 1))
        .padding(.bottom, 6)
    }

    private func tabButton(_ tag: Int, icon: String, label: String, showsDot: Bool = false) -> some View {
        let selected = selection == tag
        return Button {
            withAnimation(.snappy) { selection = tag }
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(selected ? CK.goldText : CK.textTertiary)
                .frame(width: 54, height: 44)
                .background {
                    if selected {
                        Circle()
                            .strokeBorder(CK.gold, lineWidth: 1.5)
                            .frame(width: 44, height: 44)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showsDot {
                        Circle()
                            .fill(CK.danger)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(CK.surface, lineWidth: 1.5))
                            .offset(x: -8, y: 4)
                    }
                }
        }
        .accessibilityLabel(label)
        .accessibilityValue(showsDot ? "New incidents" : "")
    }
}

#Preview {
    RootView()
}
