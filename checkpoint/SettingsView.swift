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
                    HStack {
                        TextField("Enter friend code", text: $newFriendCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button("Add") {
                            userManager.addFriend(byCode: newFriendCode) { error in
                                addError = error
                                if error == nil { newFriendCode = "" }
                            }
                        }
                        .disabled(newFriendCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let addError {
                        Text(addError).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Add a friend")
                } footer: {
                    Text("Share your code with a friend and enter theirs. Friends you add are alerted when you trigger an emergency.")
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
