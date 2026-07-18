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
                    HStack {
                        Text("Auto-call number")
                        Spacer()
                        TextField("Phone number", text: $autoCallNumber)
                            .keyboardType(.phonePad)
                            .multilineTextAlignment(.trailing)
                    }
                    Stepper(value: $autoCallDelayMinutes, in: 1...60) {
                        HStack {
                            Text("After")
                            Spacer()
                            Text("\(autoCallDelayMinutes) min")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Automatic escalation call")
                } footer: {
                    Text("If an emergency stays active for \(autoCallDelayMinutes) minute\(autoCallDelayMinutes == 1 ? "" : "s"), an automated AI agent calls this number, tells them you may be in danger with your last known location, and can answer their questions. Leave blank to disable.")
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
