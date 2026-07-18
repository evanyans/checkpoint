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

    @AppStorage("autoCallNumber") private var autoCallNumber = ""
    @AppStorage("autoCallDelayMinutes") private var autoCallDelayMinutes = 5
    @AppStorage(DiscreetMode.storageKey) private var discreetModeRaw = DiscreetMode.lockScreen.rawValue

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

                if !userManager.incomingRequests.isEmpty {
                    Section {
                        ForEach(userManager.incomingRequests) { request in
                            HStack(spacing: 12) {
                                AvatarView(image: nil, name: request.name, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.name).font(.subheadline.bold())
                                    Text("wants to be your safety contact")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    userManager.acceptFriendRequest(request)
                                } label: {
                                    Text("Accept").font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.capsule)
                                Button {
                                    userManager.declineFriendRequest(request)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Friend requests")
                    } footer: {
                        Text("Accepting links you both — you'll each be alerted when the other triggers an emergency.")
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
                        Button("Send") {
                            userManager.sendFriendRequest(byCode: newFriendCode) { error in
                                addError = error
                                if error == nil {
                                    addSuccess = "Request sent."
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
                    Text("Scan a friend's QR (or send a code). They accept the request, and you're both linked — no need to add each other separately.")
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
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showMyQR) {
                MyQRView(userManager: userManager)
            }
            .sheet(isPresented: $showScanner) {
                ScanFriendView(userManager: userManager)
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
