//
//  AgoraStreamManager.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import Foundation
import Combine
import UIKit
import AgoraRtcKit

final class AgoraStreamManager: NSObject, ObservableObject {
    @Published var statusText = "Not connected"
    @Published var remoteUid: UInt?

    /// Called on the main thread with JPEG data when a manual snapshot succeeds.
    var onSnapshot: ((Data) -> Void)?

    /// Created once, eagerly, at launch. Eager (not lazy) so that building the
    /// SDK never happens on a button tap, and so main-thread video views and a
    /// background-thread `join` can never race to lazily initialize it.
    private(set) var agoraEngine: AgoraRtcEngineKit!

    override init() {
        super.init()
        let config = AgoraRtcEngineConfig()
        config.appId = AgoraConfig.appID
        config.channelProfile = .liveBroadcasting
        agoraEngine = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
    }

    /// Safe to call from a background thread — Agora's engine methods are
    /// internally synchronized. Keep it off main so it never blocks the UI.
    func join(asBroadcaster: Bool) {
        DispatchQueue.main.async { self.statusText = "Connecting…" }

        _ = agoraEngine.enableVideo()
        agoraEngine.setClientRole(asBroadcaster ? .broadcaster : .audience)

        if asBroadcaster {
            // Point the rear camera at the surroundings/harasser, not the selfie cam.
            let cameraConfig = AgoraCameraCapturerConfiguration()
            cameraConfig.cameraDirection = .rear
            agoraEngine.setCameraCapturerConfiguration(cameraConfig)
            _ = agoraEngine.startPreview()
        }

        let result = agoraEngine.joinChannel(
            byToken: AgoraConfig.tempToken,
            channelId: AgoraConfig.channelName,
            info: nil,
            uid: 0
        ) { [weak self] channel, uid, _ in
            DispatchQueue.main.async {
                self?.statusText = "Joined '\(channel)' as uid \(uid)"
            }
        }

        if result != 0 {
            DispatchQueue.main.async { self.statusText = "Join failed, error code \(result)" }
        }
    }

    func setFrameDelegate(_ delegate: AgoraVideoFrameDelegate?) {
        agoraEngine.setVideoFrameDelegate(delegate)
    }

    /// Captures a still of the remote broadcaster's video (viewer side).
    func takeSnapshot() {
        guard let uid = remoteUid else { return }
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("snapshot-\(UUID().uuidString).jpg")
        agoraEngine.takeSnapshot(Int(uid), filePath: path)
    }

    func leave() {
        agoraEngine.setVideoFrameDelegate(nil)
        agoraEngine.stopPreview()
        agoraEngine.leaveChannel(nil)
        statusText = "Left channel"
        remoteUid = nil
    }
}

extension AgoraStreamManager: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        DispatchQueue.main.async {
            self.remoteUid = uid
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        DispatchQueue.main.async {
            if self.remoteUid == uid {
                self.remoteUid = nil
            }
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, snapshotTaken uid: UInt, filePath: String, width: Int, height: Int, errCode: Int) {
        defer { try? FileManager.default.removeItem(atPath: filePath) }
        guard errCode == 0,
              let image = UIImage(contentsOfFile: filePath),
              let data = downscaledJPEG(image) else { return }
        DispatchQueue.main.async {
            self.onSnapshot?(data)
        }
    }
}
