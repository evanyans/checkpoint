//
//  EscalationController.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-18.
//
//  Drives the on-screen auto-escalation "dead-man's switch" for the victim:
//  a visible countdown, then a short confirmation window. If the victim doesn't
//  tap "I'm safe" before that window expires, we escalate (the agent calls the
//  number in Settings). Tapping "I'm safe" re-arms the countdown from the top.
//

import Foundation
import Combine

final class EscalationController: ObservableObject {
    /// Whether the countdown is running for this emergency (only when an auto-call
    /// number is configured).
    @Published private(set) var isArmed = false
    /// Whole seconds left on the main countdown, for the on-screen pill.
    @Published private(set) var secondsRemaining = 0
    /// True while the "Are you safe?" confirmation popup is showing.
    @Published private(set) var showConfirmation = false
    /// 1 → 0 over the confirmation window, for the shrinking bar.
    @Published private(set) var confirmationProgress = 1.0
    /// Set once the call has been requested, so the UI can switch to a placed state.
    @Published private(set) var didEscalate = false
    /// Paused because a friend is actively watching the stream — no auto-call needed.
    @Published private(set) var isSuppressed = false

    /// How long the victim has to tap "I'm safe" before the call goes out.
    let confirmationWindow: TimeInterval = 10

    private var mainTimer: AnyCancellable?
    private var confirmTimer: AnyCancellable?
    private var escalationDeadline: Date?
    private var confirmDeadline: Date?
    private var delay: TimeInterval = 300

    /// Called when the confirmation window expires without a dismiss — go call.
    var onEscalate: (() -> Void)?

    func start(delaySeconds: Int) {
        delay = TimeInterval(max(1, delaySeconds))
        didEscalate = false
        arm()
    }

    /// User tapped "I'm safe": cancel this cycle and restart the countdown.
    func dismissAndRearm() {
        confirmTimer?.cancel()
        arm()
    }

    /// A friend started watching — pause the whole countdown (and cancel any live
    /// confirmation), since a human is now on the stream.
    func suppress() {
        guard isArmed, !didEscalate, !isSuppressed else { return }
        isSuppressed = true
        mainTimer?.cancel()
        confirmTimer?.cancel()
        showConfirmation = false
    }

    /// The last friend left — resume watching from a fresh countdown.
    func unsuppress() {
        guard isArmed, !didEscalate, isSuppressed else { return }
        isSuppressed = false
        arm()
    }

    func stop() {
        mainTimer?.cancel()
        confirmTimer?.cancel()
        mainTimer = nil
        confirmTimer = nil
        isArmed = false
        showConfirmation = false
        didEscalate = false
        isSuppressed = false
    }

    // MARK: - Private

    private func arm() {
        showConfirmation = false
        escalationDeadline = Date().addingTimeInterval(delay)
        secondsRemaining = Int(delay)
        isArmed = true
        mainTimer = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tickMain() }
    }

    private func tickMain() {
        guard let deadline = escalationDeadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        secondsRemaining = max(0, Int(ceil(remaining)))
        if remaining <= 0 {
            mainTimer?.cancel()
            beginConfirmation()
        }
    }

    private func beginConfirmation() {
        confirmDeadline = Date().addingTimeInterval(confirmationWindow)
        confirmationProgress = 1.0
        showConfirmation = true
        confirmTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tickConfirm() }
    }

    private func tickConfirm() {
        guard let deadline = confirmDeadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        confirmationProgress = max(0, remaining / confirmationWindow)
        if remaining <= 0 {
            confirmTimer?.cancel()
            showConfirmation = false
            didEscalate = true
            onEscalate?()
        }
    }
}
