//
//  SettingsView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var userManager: UserManager
    @AppStorage(DeviceIdentity.nameKey) private var friendName = ""

    @State private var newFriendCode = ""
    @State private var addError: String?
    @State private var addSuccess: String?
    @State private var showMyQR = false
    @State private var showScanner = false
    @State private var showForceEndConfirm = false
    @State private var forceEndResult: String?

    @AppStorage("autoCallNumber") private var autoCallNumber = ""
    @AppStorage("autoCallDelayMinutes") private var autoCallDelayMinutes = 5
    @AppStorage("autoCallDelaySeconds") private var autoCallDelaySeconds = 0
    @AppStorage(DiscreetMode.storageKey) private var discreetModeRaw = DiscreetMode.lockScreen.rawValue
    @AppStorage("disguiseAlerts") private var disguiseAlerts = true

    /// Clock-style duration picker: two wheels (minutes + seconds) side by side,
    /// each row carries its own unit like the iOS Timer.
    private var autoCallDelayPicker: some View {
        HStack(spacing: 0) {
            delayWheel(selection: $autoCallDelayMinutes,
                       values: Array(0...60), unit: "min")
            delayWheel(selection: $autoCallDelaySeconds,
                       values: Array(stride(from: 0, through: 55, by: 5)), unit: "sec")
        }
        .frame(height: 130)
    }

    private func delayWheel(selection: Binding<Int>, values: [Int], unit: String) -> some View {
        Picker("", selection: selection) {
            ForEach(values, id: \.self) { value in
                Text("\(value) \(unit)").tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    /// Human-readable total escalation delay, e.g. "5 minutes", "10 seconds",
    /// "1 minute 30 seconds". Mirrors the ≥5s floor applied at trigger time.
    private var delayDescription: String {
        let total = max(5, autoCallDelayMinutes * 60 + autoCallDelaySeconds)
        let m = total / 60, s = total % 60
        let minPart = m > 0 ? "\(m) minute\(m == 1 ? "" : "s")" : ""
        let secPart = s > 0 ? "\(s) second\(s == 1 ? "" : "s")" : ""
        return [minPart, secPart].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(CK.textPrimary)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                    profileSection
                    addFriendSection
                    discreetSection
                    disguiseToggleRow
                    escalationSection
                    friendsSection
                    developerSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(CK.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showMyQR) {
                MyQRView(userManager: userManager)
            }
            .sheet(isPresented: $showScanner) {
                ScanFriendView(userManager: userManager)
            }
            .confirmationDialog("Force-end all live sessions?",
                                isPresented: $showForceEndConfirm, titleVisibility: .visible) {
                Button("End all sessions", role: .destructive) {
                    forceEndResult = "Ending…"
                    SessionManager.forceEndAllSessions { count in
                        forceEndResult = count == 0 ? "No live sessions found." : "Ended \(count) session\(count == 1 ? "" : "s")."
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This resolves every currently-live session for everyone, not just you.")
            }
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CKKicker("Profile").padding(.top, 12).padding(.bottom, 6)

            SettingRow {
                Text("Name").ckRowLabel()
                Spacer(minLength: 12)
                TextField(UIDevice.current.name, text: $friendName)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(CK.textSecondary)
                    .textInputAutocapitalization(.words)
                    .onChange(of: friendName) { _, newValue in
                        userManager.updateName(newValue.isEmpty ? UIDevice.current.name : newValue)
                    }
            }
            CKHairline()
            SettingRow {
                Text("Your friend code").ckRowLabel()
                Spacer(minLength: 12)
                Text(userManager.myCode)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(CK.textSecondary)
                    .textSelection(.enabled)
            }
            CKHairline()
            NavigationLink {
                MyProfileView(userManager: userManager)
            } label: {
                SettingRow {
                    Text("My Profile").ckRowLabel()
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CK.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Add a friend

    private var addFriendSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CKKicker("Add a friend").padding(.top, 20).padding(.bottom, 6)

            Button {
                showScanner = true
            } label: {
                SettingRow {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 16))
                        .foregroundStyle(CK.goldText)
                        .frame(width: 22)
                    Text("Scan a friend's QR code").ckRowLabel()
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            CKHairline()
            Button {
                showMyQR = true
            } label: {
                SettingRow {
                    Image(systemName: "qrcode")
                        .font(.system(size: 16))
                        .foregroundStyle(CK.goldText)
                        .frame(width: 22)
                    Text("Show my QR code").ckRowLabel()
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            CKHairline()
            SettingRow {
                TextField("Or enter a friend code", text: $newFriendCode)
                    .foregroundStyle(CK.textPrimary)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Spacer(minLength: 8)
                Button {
                    userManager.addFriend(byCode: newFriendCode) { error in
                        addError = error
                        if error == nil {
                            addSuccess = "Friend added."
                            newFriendCode = ""
                        }
                    }
                } label: {
                    Text("Add")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CK.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(CK.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(newFriendCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let addError {
                Text(addError).font(.system(size: 12)).foregroundStyle(CK.danger)
            } else if let addSuccess {
                Text(addSuccess).font(.system(size: 12)).foregroundStyle(CK.goldText)
            }
            Text("Scan a friend's QR (or enter their code) once — you're both linked instantly, so they don't need to add you back.")
                .ckFootnote()
        }
    }

    // MARK: - Discreet mode

    private var discreetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CKKicker("Discreet mode").padding(.top, 20).padding(.bottom, 6)

            ForEach(Array(DiscreetMode.allCases.enumerated()), id: \.element.id) { index, mode in
                Button {
                    discreetModeRaw = mode.rawValue
                } label: {
                    SettingRow {
                        Text(mode.displayName).ckRowLabel()
                        Spacer()
                        if discreetModeRaw == mode.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CK.goldText)
                        }
                    }
                }
                .buttonStyle(.plain)
                if index < DiscreetMode.allCases.count - 1 {
                    CKHairline()
                }
            }

            Text("What your screen shows when you tap Hide Screen during an emergency. Triple-tap anywhere to return to the livestream.")
                .ckFootnote()
        }
    }

    // MARK: - Disguise toggle

    private var disguiseToggleRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            CKHairline()
            SettingRow(vertical: 14) {
                Text("Disguise lock-screen alerts").ckRowLabel()
                Spacer()
                CKToggle(isOn: $disguiseAlerts)
            }
            CKHairline()
            Text("When a friend responds (coming, called 911, watching), the alert on your lock screen is disguised as an ordinary Duolingo streak reminder so a bystander can't tell you've triggered an emergency. Hiding your screen always disguises alerts, whatever this is set to.")
                .ckFootnote()
        }
        .padding(.top, 8)
    }

    // MARK: - Automatic escalation call

    private var escalationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CKKicker("Automatic escalation call").padding(.top, 20).padding(.bottom, 6)

            SettingRow {
                Text("Auto-call number").ckRowLabel()
                Spacer(minLength: 12)
                TextField("Phone number", text: $autoCallNumber)
                    .keyboardType(.phonePad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(CK.textSecondary)
            }
            CKHairline()
            SettingRow {
                Text("Call after").ckRowLabel()
                Spacer()
                Text(delayDescription).foregroundStyle(CK.textSecondary)
                    .font(.system(size: 15))
            }
            autoCallDelayPicker

            Text("If an emergency stays active for \(delayDescription), an automated AI agent calls this number, tells them you may be in danger with your last known location, and can answer their questions. Leave blank to disable. (Minimum 5 seconds — handy for demos.)")
                .ckFootnote()
        }
    }

    // MARK: - Friends

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CKKicker("Your friends").padding(.top, 20).padding(.bottom, 10)

            if userManager.friends.isEmpty {
                Text("No friends added yet.")
                    .font(.system(size: 15))
                    .foregroundStyle(CK.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(userManager.friends) { friend in
                            NavigationLink {
                                FriendProfileView(
                                    friendId: friend.id,
                                    fallbackName: friend.name,
                                    userManager: userManager
                                )
                            } label: {
                                FriendAvatarLabel(friend: friend, userManager: userManager)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    userManager.removeFriend(friend)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Developer

    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            CKKicker("Developer").padding(.top, 20).padding(.bottom, 10)

            Button {
                showForceEndConfirm = true
            } label: {
                Text("Force-end all live sessions")
            }
            .buttonStyle(.dangerFilled)

            if let forceEndResult {
                Text(forceEndResult).font(.system(size: 12)).foregroundStyle(CK.textSecondary)
                    .padding(.top, 6)
            }
            Text("Resolves every session still marked live, across all devices. Use to clear stuck/zombie sessions that keep re-opening the app.")
                .ckFootnote()
        }
    }
}

// MARK: - Row building blocks

/// A flush settings row: horizontal content with consistent vertical padding.
private struct SettingRow<Content: View>: View {
    var vertical: CGFloat = 11
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.vertical, vertical)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// The dark-track / gold-when-on switch used for "Disguise lock-screen alerts".
private struct CKToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? CK.gold : CK.surface)
                .overlay(Capsule().strokeBorder(CK.divider, lineWidth: isOn ? 0 : 1))
                .frame(width: 44, height: 26)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? CK.onGold : CK.textSecondary)
                        .frame(width: 22, height: 22)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Disguise lock-screen alerts")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private extension View {
    func ckRowLabel() -> some View {
        font(.system(size: 15)).foregroundStyle(CK.textPrimary)
    }

    func ckFootnote() -> some View {
        font(.system(size: 12))
            .foregroundStyle(CK.textTertiary)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FriendAvatarLabel: View {
    let friend: Friend
    let userManager: UserManager

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            AvatarView(image: image, name: friend.name, size: 52)
            Text(friend.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(CK.textSecondary)
        }
        .onAppear {
            userManager.loadPhoto(userId: friend.id) { image = $0 }
        }
    }
}
