//
//  ProfileViews.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI
import PhotosUI

/// Read-only profile of a friend — the details a 911 operator would need.
struct FriendProfileView: View {
    let friendId: String
    let fallbackName: String
    let userManager: UserManager

    @State private var name = ""
    @State private var profile = UserProfile()
    @State private var photo: UIImage?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    AvatarView(image: photo, name: name.isEmpty ? fallbackName : name, size: 96)
                    Text(name.isEmpty ? fallbackName : name)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Description") {
                infoRow("Age", profile.age)
                infoRow("Height", profile.height)
                infoRow("Race", profile.race)
                infoRow("Appearance", profile.physicalDescription)
                infoRow("Accessories", profile.accessories)
            }

            Section("Medical") {
                infoRow("Notes", profile.medicalNotes)
            }

            Section("Emergency contact") {
                infoRow("Name", profile.emergencyContactName)
                if profile.emergencyContactPhone.isEmpty {
                    infoRow("Phone", "")
                } else {
                    HStack {
                        Text("Phone").foregroundStyle(.secondary)
                        Spacer()
                        Link(profile.emergencyContactPhone, destination: telURL(profile.emergencyContactPhone))
                    }
                }
            }

            if loaded, isEmpty {
                Section {
                    Text("This friend hasn't filled out their profile yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(name.isEmpty ? fallbackName : name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            userManager.fetchProfile(userId: friendId) { name, profile in
                self.name = name
                self.profile = profile
                self.loaded = true
            }
            userManager.loadPhoto(userId: friendId) { photo = $0 }
        }
    }

    private var isEmpty: Bool {
        profile == UserProfile()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "Not provided" : value)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func telURL(_ phone: String) -> URL {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return URL(string: "tel://\(digits)") ?? URL(string: "tel://")!
    }
}

/// Editable version of the current user's own profile (stopgap for onboarding).
struct MyProfileView: View {
    @ObservedObject var userManager: UserManager
    @State private var profile = UserProfile()
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    AvatarView(image: userManager.myPhoto, name: DeviceIdentity.currentName, size: 96)
                    PhotosPicker("Change Photo", selection: $photoItem, matching: .images)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section("Description") {
                labeledField("Age", text: $profile.age, keyboard: .numberPad)
                labeledField("Height", text: $profile.height)
                labeledField("Race", text: $profile.race)
                labeledField("Appearance", text: $profile.physicalDescription)
                labeledField("Accessories", text: $profile.accessories)
            }

            Section {
                labeledField("Notes", text: $profile.medicalNotes)
            } header: {
                Text("Medical")
            } footer: {
                Text("Shared with friends so they can relay it to emergency services.")
            }

            Section("Emergency contact") {
                labeledField("Name", text: $profile.emergencyContactName)
                labeledField("Phone", text: $profile.emergencyContactPhone, keyboard: .phonePad)
            }
        }
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { profile = userManager.myProfile }
        .onDisappear { userManager.updateProfile(profile) }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    userManager.updatePhoto(image)
                }
            }
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            TextField("Not set", text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
        }
    }
}
