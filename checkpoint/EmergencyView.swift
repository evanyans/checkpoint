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
    let onEnd: () -> Void

    @State private var showEtaSheet = false
    @State private var etaMinutes: Double = 10
    @State private var showMapOptions = false
    @State private var discreetActive = false

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
            VStack(spacing: 16) {
                Text(stream.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                escalationBanner

                videoArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .cornerRadius(12)
                    .overlay(alignment: .topTrailing) { viewerCountBadge }

                if let response = currentResponse {
                    Label(bannerText(for: response), systemImage: response.iconName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(12)
                }

                NotificationLogView(entries: sessionManager.notifications)

                buzzLegend

                Button {
                    discreetActive = true
                } label: {
                    Text("Hide Screen").primaryActionLabel()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.systemGray))

                Button(role: .destructive) {
                    onEnd()
                } label: {
                    Text("End Emergency").primaryActionLabel()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .squarishButtons()

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
            escalationPill("Emergency call placed", icon: "phone.fill", color: .red)
        } else if escalation.isSuppressed {
            escalationPill("Auto-call paused — a friend is watching",
                           icon: "eye.fill", color: .green)
        } else if escalation.isArmed {
            escalationPill("Auto-call in \(timeString(escalation.secondsRemaining))",
                           icon: "phone.arrow.up.right.fill", color: .orange)
        }
    }

    private func escalationPill(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(color, in: Capsule())
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Explains the covert vibration code so the victim can decode buzzes even with
    /// the screen hidden — the pulse count matches HapticManager.play().
    private var buzzLegend: some View {
        Label("Phone buzzes — 1: watching · 2: coming · 3: 911 called",
              systemImage: "iphone.radiowaves.left.and.right")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var viewerCount: Int { sessionManager.activeSession?.viewerIds.count ?? 0 }

    private var viewerCountBadge: some View {
        Label("\(viewerCount) watching", systemImage: "eye.fill")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
    }

    // MARK: - Viewer

    private var viewerContent: some View {
        VStack(spacing: 10) {
            videoArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .cornerRadius(12)
                .overlay(alignment: .topLeading) { leaveButton }
                .overlay(alignment: .topTrailing) { viewerCountBadge }
                .overlay(alignment: .bottomTrailing) { captureButton }

            if let coordinate = sessionManager.activeSession?.coordinate {
                LocationMapView(coordinate: coordinate)
                    .frame(height: 110)
                    .cornerRadius(12)
                    .overlay(alignment: .bottomTrailing) {
                        Text("Tap for directions")
                            .font(.caption2)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Capsule())
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
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(height: 52)
            }

            if let analysis = sessionManager.activeSession?.analysis, analysis.present, !analysis.summary.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkles").font(.caption)
                    Text(analysis.summary)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }

            if !sessionManager.notifications.isEmpty {
                NotificationLogView(entries: sessionManager.notifications, maxHeight: 84)
            }

            HStack(spacing: 8) {
                responseButton("Coming", tint: .accentColor, prominent: true) { showEtaSheet = true }
                responseButton("911", tint: .orange, prominent: true) { respond(.called911) }
                responseButton("Watching", tint: .accentColor, prominent: false) { respond(.watching) }
            }
        }
        .padding()
    }

    private var leaveButton: some View {
        Button {
            onEnd()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(8)
    }

    private var captureButton: some View {
        Button {
            stream.takeSnapshot()
        } label: {
            Image(systemName: "camera.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(14)
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(stream.remoteUid == nil)
        .padding(12)
    }

    private func responseButton(_ title: String, tint: Color, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(prominent ? tint : Color(.systemGray4))
        .foregroundStyle(prominent ? Color.white : Color.primary)
        .buttonBorderShape(.capsule)
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
                        .primaryActionLabel()
                }
                .buttonStyle(.borderedProminent)
                .squarishButtons()
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
                    Text("I'm safe").primaryActionLabel()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .buttonBorderShape(.capsule)
            }
            .padding()
        }
    }
}
