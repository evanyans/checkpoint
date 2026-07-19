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
            Form {
                Section("Profile") {
                    TextField(UIDevice.current.name, text: $friendName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: friendName) { _, newValue in
                            userManager.updateName(newValue.isEmpty ? UIDevice.current.name : newValue)
                        }
                    HStack {
                        Text("Your friend code")
                        Spacer()
                        Text(userManager.myCode)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    NavigationLink {
                        MyProfileView(userManager: userManager)
                    } label: {
                        Text("My Profile")
                    }
                }

                Section {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan a friend's QR code", systemImage: "qrcode.viewfinder")
                    }
                    Button {
                        showMyQR = true
                    } label: {
                        Label("Show my QR code", systemImage: "qrcode")
                    }

                    HStack {
                        TextField("Or enter a friend code", text: $newFriendCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button("Add") {
                            userManager.addFriend(byCode: newFriendCode) { error in
                                addError = error
                                if error == nil {
                                    addSuccess = "Friend added."
                                    newFriendCode = ""
                                }
                            }
                        }
                        .disabled(newFriendCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let addError {
                        Text(addError).font(.caption).foregroundStyle(.red)
                    } else if let addSuccess {
                        Text(addSuccess).font(.caption).foregroundStyle(.green)
                    }
                } header: {
                    Text("Add a friend")
                } footer: {
                    Text("Scan a friend's QR (or enter their code) once — you're both linked instantly, so they don't need to add you back.")
                }

                Section {
                    ForEach(DiscreetMode.allCases) { mode in
                        Button {
                            discreetModeRaw = mode.rawValue
                        } label: {
                            HStack {
                                Text(mode.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if discreetModeRaw == mode.rawValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Discreet mode")
                } footer: {
                    Text("What your screen shows when you tap Hide Screen during an emergency. Triple-tap anywhere to return to the livestream.")
                }

                Section {
                    Toggle("Disguise lock-screen alerts", isOn: $disguiseAlerts)
                } footer: {
                    Text("When a friend responds (coming, called 911, watching), the alert on your lock screen is disguised as an ordinary Duolingo streak reminder so a bystander can't tell you've triggered an emergency. Hiding your screen always disguises alerts, whatever this is set to.")
                }

                Section {
                    HStack {
                        Text("Auto-call number")
                        Spacer()
                        TextField("Phone number", text: $autoCallNumber)
                            .keyboardType(.phonePad)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Call after")
                            Spacer()
                            Text(delayDescription)
                                .foregroundStyle(.secondary)
                        }
                        autoCallDelayPicker
                    }
                } header: {
                    Text("Automatic escalation call")
                } footer: {
                    Text("If an emergency stays active for \(delayDescription), an automated AI agent calls this number, tells them you may be in danger with your last known location, and can answer their questions. Leave blank to disable. (Minimum 5 seconds — handy for demos.)")
                }

                Section("Your friends") {
                    if userManager.friends.isEmpty {
                        Text("No friends added yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 10)], spacing: 16) {
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
                        .padding(.vertical, 8)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showForceEndConfirm = true
                    } label: {
                        Label("Force-end all live sessions", systemImage: "bolt.slash.fill")
                    }
                    if let forceEndResult {
                        Text(forceEndResult).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Resolves every session still marked live, across all devices. Use to clear stuck/zombie sessions that keep re-opening the app.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
}

private struct FriendAvatarLabel: View {
    let friend: Friend
    let userManager: UserManager

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            AvatarView(image: image, name: friend.name, size: 58)
            Text(friend.name)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .onAppear {
            userManager.loadPhoto(userId: friend.id) { image = $0 }
        }
    }
}
