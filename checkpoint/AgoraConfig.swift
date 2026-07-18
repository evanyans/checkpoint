//
//  AgoraConfig.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//
//  Hackathon-only: temp token expires in 24h and is bound to `channelName` below.
//  Regenerate both in the Agora console before the token expires or before making this repo public.
//

import Foundation

enum AgoraConfig {
    static let appID = Secrets.agoraAppID
    static let tempToken = Secrets.agoraToken
    static let channelName = Secrets.agoraChannel
}
