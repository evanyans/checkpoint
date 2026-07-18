//
//  ContentView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI
import CoreLocation

private enum CoverKind {
    case alert
    case emergency
}

struct ContentView: View {
    @ObservedObject var userManager: UserManager

    @StateObject private var stream = AgoraStreamManager()
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var locationManager = LocationManager()
    @State private var hapticManager = HapticManager()
    @State private var faceCapture = FaceCaptureManager()
    @State private var role: EmergencyRole?
    @State private var cover: CoverKind?

    @AppStorage("autoCallNumber") private var autoCallNumber = ""
    @AppStorage("autoCallDelayMinutes") private var autoCallDelayMinutes = 5

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        homeScreen
            .onAppear {
                sessionManager.startListening(myUserId: userManager.userId)
                locationManager.requestPermission()
                checkPendingTrigger()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { checkPendingTrigger() }
            }
            .onChange(of: sessionManager.activeSession?.id) { _, newValue in
                // Keep the responder-activity log listener bound to the live session
                // (both broadcaster and viewer resolve the same activeSession).
                if let newValue {
                    sessionManager.listenToNotifications(sessionId: newValue)
                } else {
                    sessionManager.stopNotificationsListener()
                }
                if newValue != nil, role == nil,
                   sessionManager.activeSession?.ownerId != userManager.userId {
                    // A new emergency arrived while we're idle: alert this friend.
                    // Never alert on a session we own (e.g. a stale one we triggered).
                    cover = .alert
                } else if newValue == nil, role == .viewer {
                    // The broadcaster ended the session: reset this viewer cleanly.
                    resetViewer()
                }
            }
            .onReceive(locationManager.$lastLocation) { location in
                guard role == .broadcaster,
                      let location,
                      let id = sessionManager.activeSession?.id else { return }
                sessionManager.updateLocation(sessionId: id, coordinate: location.coordinate)
            }
            .onChange(of: sessionManager.activeSession?.response) { _, newValue in
                guard role == .broadcaster, let newValue, let response = FriendResponse(rawValue: newValue) else { return }
                hapticManager.play(response)
            }
            .fullScreenCover(isPresented: coverBinding) {
                switch cover {
                case .alert:
                    IncomingAlertView(onView: viewStream, onDismiss: dismissAlert)
                case .emergency:
                    EmergencyView(
                        role: role ?? .viewer,
                        stream: stream,
                        sessionManager: sessionManager,
                        onEnd: endSession
                    )
                case .none:
                    EmptyView()
                }
            }
    }

    // MARK: - Home

    private var homeScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "shield.fill")
                .font(.system(size: 88))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Emergency")
                    .font(.largeTitle.bold())
                Text("Start a livestream and alert your friends with your live location.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                triggerEmergency()
            } label: {
                Text("Trigger Emergency")
                    .primaryActionLabel()
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        }
        .padding()
        .squarishButtons()
    }

    // MARK: - Cover binding

    private var coverBinding: Binding<Bool> {
        Binding(
            get: { cover != nil },
            set: { if !$0 { cover = nil } }
        )
    }

    // MARK: - Actions

    private func triggerEmergency() {
        guard role == nil else { return }
        role = .broadcaster
        sessionManager.createSession(
            channelName: AgoraConfig.channelName,
            ownerId: userManager.userId,
            notifyIds: userManager.friendIds,
            escalationPhone: autoCallNumber,
            escalationDelayMinutes: autoCallDelayMinutes
        )
        stream.join(asBroadcaster: true)
        locationManager.requestPermission()
        locationManager.startUpdating()

        // Auto-capture evidence stills when a person is detected on camera.
        faceCapture.onCapture = { jpeg in
            guard let id = sessionManager.createdSessionId else { return }
            sessionManager.addCapture(sessionId: id, jpeg: jpeg)
        }
        stream.setFrameDelegate(faceCapture)

        cover = .emergency
    }

    private func viewStream() {
        role = .viewer
        // Show the emergency screen immediately so the response buttons are
        // available right away; the video connects in the background.
        cover = .emergency
        if let id = sessionManager.activeSession?.id {
            sessionManager.listenToCaptures(sessionId: id)
        }
        // Manual snapshots from the viewer flow into the same evidence pipeline.
        stream.onSnapshot = { jpeg in
            guard let id = sessionManager.activeSession?.id else { return }
            sessionManager.addCapture(sessionId: id, jpeg: jpeg)
        }
        // Defer the heavy Agora join so the screen appears without a hitch.
        DispatchQueue.main.async {
            stream.join(asBroadcaster: false)
        }
    }

    private func dismissAlert() {
        if role == .viewer { resetViewer() } else { cover = nil }
    }

    private func resetViewer() {
        stream.leave()
        sessionManager.stopCapturesListener()
        sessionManager.stopNotificationsListener()
        role = nil
        cover = nil
    }

    private func endSession() {
        if role == .broadcaster,
           let id = sessionManager.activeSession?.id ?? sessionManager.createdSessionId {
            sessionManager.resolveSession(id)
        }
        stream.leave()
        locationManager.stopUpdating()
        role = nil
        cover = nil
    }

    /// Auto-trigger when launched via the Back Tap App Intent.
    private func checkPendingTrigger() {
        let key = "pendingEmergencyTrigger"
        guard UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(false, forKey: key)
        triggerEmergency()
    }
}

#Preview {
    ContentView(userManager: UserManager())
}
