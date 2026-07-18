//
//  HapticManager.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import Foundation
import CoreHaptics
import AudioToolbox
import AVFoundation

enum FriendResponse: String {
    case watching
    case coming
    case called911

    var iconName: String {
        switch self {
        case .coming: return "figure.walk"
        case .called911: return "phone.fill"
        case .watching: return "eye.fill"
        }
    }

    /// Short label for compact contexts (log rows).
    var shortLabel: String {
        switch self {
        case .coming: return "Friend coming"
        case .called911: return "Called 911"
        case .watching: return "Watching"
        }
    }

    /// Full sentence for the broadcaster's banner.
    var bannerText: String {
        switch self {
        case .coming: return "A friend is coming to help"
        case .called911: return "A friend called 911"
        case .watching: return "A friend is watching your stream"
        }
    }
}

final class HapticManager {
    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    init() {
        print("HapticManager: init, supportsHaptics=\(supportsHaptics)")
        prepareEngine()
    }

    private func prepareEngine() {
        guard supportsHaptics else {
            print("HapticManager: this device does not support Core Haptics.")
            return
        }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.stoppedHandler = { [weak self] reason in
                print("HapticManager: engine stopped (\(reason.rawValue)).")
                self?.engine = nil
            }
            engine.resetHandler = { [weak self] in
                print("HapticManager: engine reset, restarting.")
                try? self?.engine?.start()
            }
            try engine.start()
            self.engine = engine
            print("HapticManager: engine started.")
        } catch {
            print("HapticManager: engine failed to start: \(error)")
        }
    }

    func play(_ response: FriendResponse) {
        let taps: Int
        switch response {
        case .watching: taps = 1
        case .coming: taps = 2
        case .called911: taps = 3
        }
        print("HapticManager: play(\(response.rawValue)) -> \(taps) tap(s)")

        // While the victim is broadcasting, Agora holds the audio session in
        // .playAndRecord — and iOS suppresses ALL vibration/haptics during recording
        // by design, so the buzz silently never fires on device. Opt back in first;
        // Agora reconfigures the session dynamically, so we re-apply on every buzz.
        // https://developer.apple.com/documentation/avfaudio/avaudiosession/setallowhapticsandsystemsoundsduringrecording(_:)
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)

        // Classic vibration motor via AudioServices — the most noticeable buzz for a
        // victim who may only feel (not see) the phone. Now permitted by the flag above.
        playFallback(taps: taps)
    }

    /// Returns true if it successfully scheduled a Core Haptics pattern.
    private func playCoreHaptics(taps: Int) -> Bool {
        guard supportsHaptics else { return false }
        if engine == nil { prepareEngine() }
        guard let engine else {
            print("HapticManager: no engine available.")
            return false
        }

        let events = (0..<taps).map { i in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                ],
                relativeTime: Double(i) * 0.2
            )
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.start()
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            print("HapticManager: Core Haptics pattern started.")
            return true
        } catch {
            print("HapticManager: failed to play Core Haptics pattern: \(error)")
            return false
        }
    }

    /// Uses the classic vibration motor via AudioServices, which does not share
    /// Core Haptics' audio session and is far harder for an active call to suppress.
    private func playFallback(taps: Int) {
        for i in 0..<taps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
    }
}
