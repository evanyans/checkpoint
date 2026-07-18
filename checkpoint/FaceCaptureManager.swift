//
//  FaceCaptureManager.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  Observes the broadcaster's camera frames via Agora's raw video frame delegate,
//  runs on-device Vision face detection, and captures a throttled still whenever a
//  person is in frame. Captures are handed off via `onCapture` for upload.
//

import Foundation
import AgoraRtcKit
import Vision
import CoreImage
import UIKit

final class FaceCaptureManager: NSObject {
    /// Called on the main thread with a compressed JPEG whenever a face is captured.
    var onCapture: ((Data) -> Void)?

    private let ciContext = CIContext()
    private let minInterval: TimeInterval = 5.0
    private var lastCaptureAt: Date?
    private var isProcessing = false

    // MARK: Throttle

    private func shouldCapture(now: Date) -> Bool {
        guard !isProcessing else { return false }
        if let last = lastCaptureAt, now.timeIntervalSince(last) < minInterval {
            return false
        }
        return true
    }

    // MARK: Frame -> JPEG

    private func jpegData(from pixelBuffer: CVPixelBuffer, rotation: Int) -> Data? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        // Agora reports clockwise rotation to apply before display; match it.
        if rotation != 0 {
            let radians = -CGFloat(rotation) * .pi / 180
            image = image.transformed(by: CGAffineTransform(rotationAngle: radians))
        }
        // Downscale so the base64 JPEG stays well under Firestore's 1MB doc limit.
        let maxDimension: CGFloat = 640
        let extent = image.extent
        let scale = min(1, maxDimension / max(extent.width, extent.height))
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cg = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.5)
    }
}

extension FaceCaptureManager: AgoraVideoFrameDelegate {
    func onCapture(_ videoFrame: AgoraOutputVideoFrame, sourceType: AgoraVideoSourceType) -> Bool {
        guard let pixelBuffer = videoFrame.pixelBuffer else { return true }

        // Timestamps are unavailable in-process; use wall clock for throttling only.
        let now = Date()
        guard shouldCapture(now: now) else { return true }
        isProcessing = true

        let rotation = Int(videoFrame.rotation)
        let request = VNDetectFaceRectanglesRequest { [weak self] request, _ in
            guard let self else { return }
            defer { self.isProcessing = false }

            let faceCount = (request.results as? [VNFaceObservation])?.count ?? 0
            guard faceCount > 0 else { return }

            guard let data = self.jpegData(from: pixelBuffer, rotation: rotation) else { return }
            self.lastCaptureAt = now
            DispatchQueue.main.async {
                self.onCapture?(data)
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            isProcessing = false
        }
        return true
    }

    // Ask Agora for CVPixelBuffer-backed frames so Vision can read them directly.
    func getVideoFormatPreference() -> AgoraVideoFormat {
        .cvPixelBGRA
    }

    func getVideoFrameProcessMode() -> AgoraVideoFrameProcessMode {
        .readOnly
    }

    func getObservedFramePosition() -> AgoraVideoFramePosition {
        .postCapture
    }

    func getRotationApplied() -> Bool {
        false
    }

    func getMirrorApplied() -> Bool {
        false
    }
}
