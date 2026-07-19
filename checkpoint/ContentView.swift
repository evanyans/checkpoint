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

    // Whole-screen hold-to-trigger state: press anywhere to start the countdown,
    // release before it completes to cancel. Progress is derived from wall-clock
    // elapsed time so the bar advances smoothly across the full duration.
    @State private var holdStartedAt: Date?
    @State private var isPressingHold = false
    @State private var pendingTrigger: DispatchWorkItem?
    private let holdDuration: TimeInterval = 3

    // Fires after 2 min if no friend has joined yet — asks the backend to fan
    // out the push to any P2 friends. Cancelled when someone joins or the
    // broadcaster ends the session.
    @State private var p2FallbackTask: DispatchWorkItem?
    private let p2FallbackDelay: TimeInterval = 120

    @AppStorage("autoCallNumber") private var autoCallNumber = ""
    @AppStorage("autoCallDelayMinutes") private var autoCallDelayMinutes = 5
    @AppStorage("autoCallDelaySeconds") private var autoCallDelaySeconds = 0

    /// Full escalation delay in seconds (minutes + seconds), floored at 5s so a
    /// 0/0 setting can't fire instantly.
    private var autoCallDelayTotalSeconds: Int {
        max(5, autoCallDelayMinutes * 60 + autoCallDelaySeconds)
    }
    @AppStorage("disguiseAlerts") private var disguiseAlerts = true

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
            .onReceive(locationManager.$readableAddress) { address in
                // Reverse-geocoding resolves after the fix; write the readable address
                // so the escalation call can speak a street, not coordinates.
                guard role == .broadcaster,
                      let address, !address.isEmpty,
                      let id = sessionManager.activeSession?.id else { return }
                sessionManager.updateLocationAddress(sessionId: id, address: address)
            }
            .onChange(of: sessionManager.notifications.first?.id) { _, newId in
                // Buzz the victim's phone every time a friend responds. Driving this
                // off the append-only notification log (not the single `response`
                // field) means every tap buzzes — even repeats or two friends picking
                // the same action. Distinct pulse counts let the victim decode who's
                // helping without looking: 1 = watching, 2 = coming, 3 = called 911.
                guard role == .broadcaster, newId != nil,
                      let response = sessionManager.notifications.first?.response else { return }
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
                if count > 0 {
                    escalation.suppress()
                    // Someone joined — cancel the P2 push fallback.
                    p2FallbackTask?.cancel()
                    p2FallbackTask = nil
                } else {
                    escalation.unsuppress()
                }
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
                        // Viewer's ✕ must run the viewer cleanup (removeViewer, stop
                        // listeners) — not the broadcaster's endSession — otherwise the
                        // viewer's id lingers in viewerIds and the count never drops.
                        onEnd: { role == .viewer ? resetViewer() : endSession() }
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

            VStack(spacing: 8) {
                Text("Checkpoint")
                    .font(.largeTitle.bold())
                Text("Start livestream and alert your friends.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                TimelineView(.animation(paused: holdStartedAt == nil)) { context in
                    let progress = holdProgress(at: context.date)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemGray5))
                            Capsule()
                                .fill(Color(.systemGray))
                                .frame(width: geo.size.width * progress)
                        }
                    }
                }
                .frame(height: 8)

                Text("Hold screen for 3 seconds")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressingHold else { return }
                    isPressingHold = true
                    startHold()
                }
                .onEnded { _ in
                    isPressingHold = false
                    cancelHold()
                }
        )
    }

    // MARK: - Hold gesture

    private func holdProgress(at date: Date) -> CGFloat {
        guard let start = holdStartedAt else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        return CGFloat(min(max(elapsed / holdDuration, 0), 1))
    }

    private func startHold() {
        pendingTrigger?.cancel()
        holdStartedAt = Date()

        let task = DispatchWorkItem {
            triggerEmergency()
            holdStartedAt = nil
        }
        pendingTrigger = task
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: task)
    }

    private func cancelHold() {
        pendingTrigger?.cancel()
        pendingTrigger = nil
        holdStartedAt = nil
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
            p1NotifyIds: userManager.p1FriendIds,
            p2NotifyIds: userManager.p2FriendIds,
            escalationPhone: autoCallNumber,
            // The server uses this only for the agent's spoken "hasn't checked in for
            // N minutes" line — round the true (seconds-granular) delay up to ≥1 min.
            escalationDelayMinutes: max(1, Int((Double(autoCallDelayTotalSeconds) / 60).rounded())),
            disguiseNotifications: disguiseAlerts,
            victimDescription: userManager.myProfile.callSummary,
            medicalNotes: userManager.myProfile.medicalNotes,
            incidentTime: Date().formatted(date: .omitted, time: .shortened)
        )
        locationManager.requestPermission()
        locationManager.startUpdating()

        // Schedule the P2 push fallback: if no one has joined in 2 min, flag the
        // session so the backend fans out to P2 friends.
        if !userManager.p2FriendIds.isEmpty {
            let task = DispatchWorkItem {
                guard let id = sessionManager.createdSessionId else { return }
                if sessionManager.activeSession?.viewerIds.isEmpty ?? true {
                    sessionManager.requestP2Fanout(sessionId: id)
                }
            }
            p2FallbackTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + p2FallbackDelay, execute: task)
        }

        // Auto-capture evidence stills when a person is detected on camera.
        faceCapture.onCapture = { jpeg in
            guard let id = sessionManager.createdSessionId else { return }
            sessionManager.addCapture(sessionId: id, jpeg: jpeg)
        }
        stream.setFrameDelegate(faceCapture)

        // Always arm the on-screen auto-escalation countdown + safety check. Placing
        // the actual call is gated server-side on an auto-call number being set, so
        // the countdown/"are you safe?" prompt shows even without a number configured.
        escalation.onEscalate = {
            guard let id = sessionManager.createdSessionId else { return }
            sessionManager.requestEscalation(sessionId: id)
        }
        escalation.start(delaySeconds: autoCallDelayTotalSeconds)

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
        p2FallbackTask?.cancel()
        p2FallbackTask = nil
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
