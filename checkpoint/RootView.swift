//
//  RootView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI

struct RootView: View {
    @StateObject private var userManager = UserManager()
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ContentView(userManager: userManager)
                .tag(0)

            LogListView()
                .tag(1)

            SettingsView(userManager: userManager)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .bottom) {
            TabBar(selection: $selection)
        }
        .onAppear { userManager.start() }
    }
}

private struct TabBar: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 6) {
            tabButton(0, icon: "shield.fill", label: "Home")
            tabButton(1, icon: "list.bullet.rectangle.fill", label: "Log")
            tabButton(2, icon: "gearshape.fill", label: "Settings")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .padding(.bottom, 6)
    }

    private func tabButton(_ tag: Int, icon: String, label: String) -> some View {
        Button {
            withAnimation(.snappy) { selection = tag }
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(selection == tag ? Color.white : Color.accentColor.opacity(0.5))
                .frame(width: 54, height: 44)
                .background {
                    if selection == tag {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 44, height: 44)
                    }
                }
        }
        .accessibilityLabel(label)
    }
}

#Preview {
    RootView()
}
