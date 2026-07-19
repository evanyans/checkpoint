//
//  EmergencyView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  The active-emergency screen, presented over Home when you trigger an
//  emergency (broadcaster) or open a friend's stream (viewer).
//

import SwiftUI

enum EmergencyRole {
    case broadcaster
    case viewer
}

struct EmergencyView: View {
    let role: EmergencyRole
    @ObservedObject var stream: AgoraStreamManager
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var escalation: EscalationController
    @ObservedObject var userManager: UserManager
    let onEnd: () -> Void

    @State private var showEtaSheet = false
    @State private var etaMinutes: Double = 10
    @State private var showMapOptions = false
    @State private var discreetActive = false
    @State private var showVictimInfo = false

    @AppStorage("disguiseAlerts") private var disguiseAlerts = true

    var body: some View {
        Group {
            switch role {
            case .broadcaster: broadcasterContent
            case .viewer: viewerContent
            }
        }
        .sheet(isPresented: $showEtaSheet) {
            EtaSheet(minutes: $etaMinutes) { eta in
                respond(.coming, eta: eta)
            }
        }
        .sheet(isPresented: $showVictimInfo) {
            VictimInfoSheet(
                userManager: userManager,
                ownerId: sessionManager.activeSession?.ownerId
            )
        }
        .onChange(of: discreetActive) { _, hidden in
            // A hidden screen means someone may be looking, so force-disguise
            // incoming responder pushes; revert to the user's setting when revealed.
            guard role == .broadcaster,
                  let id = sessionManager.activeSession?.id ?? sessionManager.createdSessionId else { return }
            sessionManager.setDisguise(sessionId: id, on: hidden || disguiseAlerts)
        }
        .directionsChooser(isPresented: $showMapOptions, coordinate: sessionManager.activeSession?.coordinate)
    }

    // MARK: - Broadcaster

    private var broadcasterContent: some View {
        ZStack {
            CK.background.ignoresSafeArea()

            VStack(spacing: 11) {
                Text(stream.statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(CK.textSecondary)

                escalationBanner

                videoArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CK.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) { viewerCountBadge }

                if let response = currentResponse {
                    responseStatePill(bannerText(for: response))
                }

                NotificationLogView(entries: sessionManager.notifications)

                buzzLegend

                Button {
                    discreetActive = true
                } label: {
                    Text("Hide Screen")
                }
                .buttonStyle(.ghost)

                Button {
                    onEnd()
                } label: {
                    Text("End Emergency")
                }
                .buttonStyle(.dangerFilled)
            }
            .padding()

            if discreetActive {
                FakeScreenView { discreetActive = false }
            }

            // Sits above everything (including discreet mode) so the safety check
            // can never be missed.
            if escalation.showConfirmation {
                SafetyCheckOverlay(progress: escalation.confirmationProgress) {
                    escalation.dismissAndRearm()
                }
            }
        }
    }

    @ViewBuilder
    private var escalationBanner: some View {
        if escalation.didEscalate {
            // A placed emergency call is a true danger state — keep it solid red.
            escalationPill("Emergency call placed", icon: "phone.fill",
                           color: .white, fill: CK.danger)
        } else if escalation.isSuppressed {
            escalationPill("Auto-call paused — a friend is watching",
                           icon: "eye.fill", color: CK.textSecondary)
        } else if escalation.isArmed {
            escalationPill("Auto-call in \(timeString(escalation.secondsRemaining))",
                           icon: "phone.arrow.up.right.fill", color: CK.goldText)
        }
    }

    /// Escalation banner. Defaults to an outlined gold pill; pass a `fill` to render
    /// a solid danger state instead.
    private func escalationPill(_ text: String, icon: String, color: Color, fill: Color? = nil) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background {
                if let fill {
                    RoundedRectangle(cornerRadius: 10).fill(fill)
                } else {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(CK.gold, lineWidth: 1)
                }
            }
    }

    /// The friend-response state ("Friend coming · ETA 10 min") as an outlined pill.
    private func responseStatePill(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CK.goldText)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CK.textPrimary)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(CK.divider, lineWidth: 1))
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Explains the covert vibration code so the victim can decode buzzes even with
    /// the screen hidden — the pulse count matches HapticManager.play().
    private var buzzLegend: some View {
        Text("Phone buzzes — 1: watching · 2: coming · 3: 911 called")
            .font(.system(size: 11))
            .foregroundStyle(CK.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var viewerCount: Int { sessionManager.activeSession?.viewerIds.count ?? 0 }

    private var viewerCountBadge: some View {
        Text("\(viewerCount) watching")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CK.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(CK.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(CK.divider, lineWidth: 1))
            .padding(12)
    }

    // MARK: - Viewer

    private var viewerContent: some View {
        VStack(spacing: 10) {
            videoArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CK.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) { leaveButton }
                .overlay(alignment: .topTrailing) { viewerCountBadge }
                .overlay(alignment: .bottomLeading) { infoButton }
                .overlay(alignment: .bottomTrailing) { captureButton }

            if let coordinate = sessionManager.activeSession?.coordinate {
                LocationMapView(coordinate: coordinate)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CK.divider, lineWidth: 1))
                    .overlay(alignment: .bottomTrailing) {
                        Text("Tap for directions")
                            .font(.system(size: 10))
                            .foregroundStyle(CK.textPrimary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(CK.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(CK.divider, lineWidth: 1))
                            .padding(6)
                    }
                    .overlay(
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { showMapOptions = true }
                    )
            }

            if !sessionManager.captures.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sessionManager.captures) { capture in
                            Image(uiImage: capture.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(CK.divider, lineWidth: 1))
                        }
                    }
                }
                .frame(height: 48)
            }

            if let analysis = sessionManager.activeSession?.analysis, analysis.present, !analysis.summary.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(CK.goldText)
                    Text(analysis.summary)
                        .font(.system(size: 12))
                        .foregroundStyle(CK.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .ckOutlinedCard(cornerRadius: 10, padding: 10)
            }

            if !sessionManager.notifications.isEmpty {
                NotificationLogView(entries: sessionManager.notifications, maxHeight: 84)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button { showEtaSheet = true } label: { Text("Coming") }
                    .buttonStyle(.goldFilled)
                Button { respond(.called911) } label: { Text("911") }
                    .buttonStyle(.dangerFilled)
                Button { respond(.watching) } label: { Text("Watching") }
                    .buttonStyle(.neutralFilled)
            }
        }
        .padding()
        .background(CK.background.ignoresSafeArea())
    }

    private var leaveButton: some View {
        Button {
            onEnd()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CK.textPrimary)
                .frame(width: 32, height: 32)
                .background(CK.surface, in: Circle())
                .overlay(Circle().strokeBorder(CK.divider, lineWidth: 1))
        }
        .padding(12)
    }

    /// Opens the victim's profile details so a viewer can describe them to police.
    private var infoButton: some View {
        Button {
            showVictimInfo = true
        } label: {
            Image(systemName: "info")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CK.textPrimary)
                .frame(width: 42, height: 42)
                .background(CK.surface, in: Circle())
                .overlay(Circle().strokeBorder(CK.divider, lineWidth: 1))
        }
        .padding(12)
        .accessibilityLabel("Victim details")
    }

    private var captureButton: some View {
        Button {
            stream.takeSnapshot()
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 17))
                .foregroundStyle(CK.textPrimary)
                .frame(width: 42, height: 42)
                .background(CK.surface, in: Circle())
                .overlay(Circle().strokeBorder(CK.divider, lineWidth: 1))
        }
        .disabled(stream.remoteUid == nil)
        .padding(12)
    }

    // MARK: - Helpers

    private func respond(_ response: FriendResponse, eta: Int? = nil) {
        guard let id = sessionManager.activeSession?.id else { return }
        sessionManager.respond(sessionId: id, response: response.rawValue, etaMinutes: eta)
    }

    private var currentResponse: FriendResponse? {
        guard let raw = sessionManager.activeSession?.response else { return nil }
        return FriendResponse(rawValue: raw)
    }

    private func bannerText(for response: FriendResponse) -> String {
        if response == .coming, let eta = sessionManager.activeSession?.etaMinutes {
            return "A friend is coming to help • ETA \(eta) min"
        }
        return response.bannerText
    }

    @ViewBuilder
    private var videoArea: some View {
        switch role {
        case .broadcaster:
            LocalVideoView(agoraEngine: stream.agoraEngine)
        case .viewer:
            if let uid = stream.remoteUid {
                RemoteVideoView(agoraEngine: stream.agoraEngine, uid: uid)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Connecting to livestream…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

struct EtaSheet: View {
    @Binding var minutes: Double
    let onConfirm: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("How long until you arrive?")
                    .font(.headline)

                Text("\(Int(minutes)) min")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)

                Slider(value: $minutes, in: 1...60, step: 1) {
                    Text("ETA")
                } minimumValueLabel: {
                    Text("1")
                } maximumValueLabel: {
                    Text("60")
                }

                Spacer()

                Button {
                    onConfirm(Int(minutes))
                    dismiss()
                } label: {
                    Text("Confirm & Send")
                }
                .buttonStyle(.goldFilled)
            }
            .padding()
            .navigationTitle("On My Way")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// The victim's profile details, opened by a viewer from the livestream so they can
/// describe the person (age, height, appearance, accessories) and relay medical notes
/// to a 911 operator. Read-only; pulled live from the session owner's profile.
struct VictimInfoSheet: View {
    @ObservedObject var userManager: UserManager
    let ownerId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var profile = UserProfile()
    @State private var photo: UIImage?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    section("Description") {
                        infoRow("Age", profile.age)
                        infoRow("Height", profile.height)
                        infoRow("Race", profile.race)
                        infoRow("Appearance", profile.physicalDescription)
                        infoRow("Accessories", profile.accessories, divider: false)
                    }

                    section("Medical") {
                        infoRow("Notes", profile.medicalNotes, divider: false)
                    }

                    section("Emergency contact") {
                        infoRow("Name", profile.emergencyContactName)
                        phoneRow
                    }

                    if loaded, profile == UserProfile() {
                        Text("This friend hasn't filled out their profile yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(CK.textTertiary)
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(CK.background.ignoresSafeArea())
            .navigationTitle("Victim details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(CK.goldText)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard let ownerId else { return }
            userManager.fetchProfile(userId: ownerId) { name, profile in
                self.name = name
                self.profile = profile
                self.loaded = true
            }
            userManager.loadPhoto(userId: ownerId) { photo = $0 }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            AvatarView(image: photo, name: name.isEmpty ? "Friend" : name, size: 72)
            Text(name.isEmpty ? "Friend" : name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CK.textPrimary)
            Text("Read these details to the 911 operator.")
                .font(.system(size: 13))
                .foregroundStyle(CK.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        CKKicker(title).padding(.top, 20).padding(.bottom, 4)
        content()
    }

    private func infoRow(_ label: String, _ value: String, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(CK.textSecondary)
                Spacer(minLength: 16)
                Text(value.isEmpty ? "Not provided" : value)
                    .font(.system(size: 15))
                    .foregroundStyle(value.isEmpty ? CK.textTertiary : CK.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 11)
            if divider { CKHairline() }
        }
    }

    @ViewBuilder
    private var phoneRow: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Phone")
                    .font(.system(size: 15))
                    .foregroundStyle(CK.textSecondary)
                Spacer(minLength: 16)
                if profile.emergencyContactPhone.isEmpty {
                    Text("Not provided")
                        .font(.system(size: 15))
                        .foregroundStyle(CK.textTertiary)
                } else {
                    Link(profile.emergencyContactPhone, destination: telURL(profile.emergencyContactPhone))
                        .font(.system(size: 15, weight: .semibold))
                        .tint(CK.goldText)
                }
            }
            .padding(.vertical, 11)
        }
    }

    private func telURL(_ phone: String) -> URL {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return URL(string: "tel://\(digits)") ?? URL(string: "tel://")!
    }
}

/// The "are you safe?" dead-man's-switch popup. It has no "call now" action — the
/// call fires automatically when the shrinking bar runs out. Tapping "I'm safe"
/// cancels and re-arms the countdown.
struct SafetyCheckOverlay: View {
    let progress: Double
    let onSafe: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)

                Text("Are you safe?")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Text("An emergency call is about to be placed automatically. Tap below if you're safe to stop it.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal)

                // Shrinking bar — visual for the seconds remaining before the call.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(Color.orange)
                            .frame(width: max(0, geo.size.width * progress))
                    }
                }
                .frame(height: 12)
                .padding(.horizontal)
                .animation(.linear(duration: 0.06), value: progress)

                Button(action: onSafe) {
                    Text("I'm safe")
                }
                .buttonStyle(.goldFilled)
            }
            .padding()
        }
    }
}
