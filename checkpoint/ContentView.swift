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
    @StateObject private var escalation = EscalationController()
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
                   sessionManager.activeSession?.ownerId != userManager.userId,
                   sessionManager.activeSession?.isRecent == true {
                    // A new emergency arrived while we're idle: alert this friend.
                    // Never alert on a session we own (e.g. a stale one we triggered),
                    // and never on a stale/old one that's lingered unresolved.
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
            .onChange(of: sessionManager.viewedSessionEnded) { _, ended in
                // The broadcaster ended (or deleted) the session we're watching.
                if ended, role == .viewer { resetViewer() }
            }
            .onChange(of: sessionManager.activeSession?.viewerIds.count ?? 0) { _, count in
                // A friend watching means no auto-call is needed; pause it while
                // anyone is on the stream, resume (fresh countdown) when they leave.
                guard role == .broadcaster else { return }
                if count > 0 { escalation.suppress() } else { escalation.unsuppress() }
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
                        escalation: escalation,
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

            HoldToTriggerButton(title: "Trigger Emergency (Hold)") {
                triggerEmergency()
            }
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
        // Present the emergency screen instantly; everything below loads on-screen.
        role = .broadcaster
        cover = .emergency

        sessionManager.createSession(
            channelName: AgoraConfig.channelName,
            ownerId: userManager.userId,
            notifyIds: userManager.friendIds,
            escalationPhone: autoCallNumber,
            escalationDelayMinutes: autoCallDelayMinutes
        )
        locationManager.requestPermission()
        locationManager.startUpdating()

        // Auto-capture evidence stills when a person is detected on camera.
        faceCapture.onCapture = { jpeg in
            guard let id = sessionManager.createdSessionId else { return }
            sessionManager.addCapture(sessionId: id, jpeg: jpeg)
        }
        stream.setFrameDelegate(faceCapture)

        // Arm the on-screen auto-escalation countdown when an auto-call number is set.
        if !autoCallNumber.isEmpty {
            escalation.onEscalate = {
                guard let id = sessionManager.createdSessionId else { return }
                sessionManager.requestEscalation(sessionId: id)
            }
            escalation.start(delayMinutes: autoCallDelayMinutes)
        }

        // Heavy Agora join runs off the main thread so it never blocks the UI.
        DispatchQueue.global(qos: .userInitiated).async {
            stream.join(asBroadcaster: true)
        }
    }

    private func viewStream() {
        // Show the emergency screen immediately so the response buttons are
        // available right away; the video connects in the background.
        role = .viewer
        cover = .emergency

        if let id = sessionManager.activeSession?.id {
            sessionManager.listenToCaptures(sessionId: id)
            // Watch this exact session so we close the moment the victim ends it.
            sessionManager.watchViewedSession(sessionId: id)
            // Register presence so the victim & other viewers see the watcher count.
            sessionManager.addViewer(sessionId: id, userId: userManager.userId)
        }
        // Manual snapshots from the viewer flow into the same evidence pipeline.
        stream.onSnapshot = { jpeg in
            guard let id = sessionManager.activeSession?.id else { return }
            sessionManager.addCapture(sessionId: id, jpeg: jpeg)
        }
        // Heavy Agora join runs off the main thread so the screen isn't blocked.
        DispatchQueue.global(qos: .userInitiated).async {
            stream.join(asBroadcaster: false)
        }
    }

    private func dismissAlert() {
        if role == .viewer { resetViewer() } else { cover = nil }
    }

    private func resetViewer() {
        if let id = sessionManager.activeSession?.id {
            sessionManager.removeViewer(sessionId: id, userId: userManager.userId)
        }
        stream.leave()
        sessionManager.stopCapturesListener()
        sessionManager.stopNotificationsListener()
        sessionManager.stopWatchingViewedSession()
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
        escalation.stop()
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

/// A capsule-shaped action button that only fires after a sustained hold.
/// A darker fill sweeps left-to-right during the hold so the user sees how
/// close they are to triggering; releasing early cancels cleanly.
private struct HoldToTriggerButton: View {
    let title: String
    let onTrigger: () -> Void

    private let holdDuration: TimeInterval = 3

    @State private var progress: CGFloat = 0
    @State private var isPressing = false
    @State private var pendingTrigger: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.accentColor)

                Rectangle()
                    .fill(Color.accentColor)
                    .brightness(-0.15)
                    .frame(width: geo.size.width * progress)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(Capsule())
        }
        .frame(minHeight: 50)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressing else { return }
                    isPressing = true
                    startHold()
                }
                .onEnded { _ in
                    isPressing = false
                    cancelHold()
                }
        )
    }

    private func startHold() {
        pendingTrigger?.cancel()
        // Snap progress to 0 without animation in case a previous cancel
        // animation is still winding down, then sweep to full over holdDuration.
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }

        withAnimation(.linear(duration: holdDuration)) { progress = 1 }

        let task = DispatchWorkItem {
            onTrigger()
            progress = 0
        }
        pendingTrigger = task
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: task)
    }

    private func cancelHold() {
        pendingTrigger?.cancel()
        pendingTrigger = nil
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}

#Preview {
    ContentView(userManager: UserManager())
}
