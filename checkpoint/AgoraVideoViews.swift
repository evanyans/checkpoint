//
//  AgoraVideoViews.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI
import AgoraRtcKit

struct LocalVideoView: UIViewRepresentable {
    let agoraEngine: AgoraRtcEngineKit

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let canvas = AgoraRtcVideoCanvas()
        canvas.uid = 0
        canvas.view = view
        canvas.renderMode = .hidden
        agoraEngine.setupLocalVideo(canvas)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct RemoteVideoView: UIViewRepresentable {
    let agoraEngine: AgoraRtcEngineKit
    let uid: UInt

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let canvas = AgoraRtcVideoCanvas()
        canvas.uid = uid
        canvas.view = view
        canvas.renderMode = .hidden
        agoraEngine.setupRemoteVideo(canvas)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
