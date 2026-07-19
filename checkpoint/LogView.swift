//
//  LogView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-17.
//

import SwiftUI
import CoreLocation

struct LogListView: View {
    @ObservedObject var logManager: LogManager
    @ObservedObject var readState: LogReadState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Log")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(CK.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 14)

                    if logManager.entries.isEmpty {
                        Text("No incidents yet.")
                            .font(.system(size: 15))
                            .foregroundStyle(CK.textSecondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    } else {
                        ForEach(logManager.entries) { entry in
                            NavigationLink {
                                LogDetailView(entry: entry, logManager: logManager)
                                    .onAppear { readState.markOpened(entry.id) }
                            } label: {
                                LogRow(entry: entry, unread: !readState.isOpened(entry.id))
                            }
                            .buttonStyle(.plain)
                            CKHairline()
                        }
                    }
                }
            }
            .background(CK.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry
    let unread: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if unread {
                    Circle().fill(CK.gold).frame(width: 6, height: 6)
                }
                Text(entry.triggeredBy)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CK.textPrimary)
                Spacer()
                if entry.status == "triggered" {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CK.danger)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(CK.danger, lineWidth: 1))
                }
            }
            if let date = entry.createdAt {
                Text(date, format: .dateTime.month().day().hour().minute())
                    .font(.system(size: 13))
                    .foregroundStyle(CK.textSecondary)
                    .padding(.top, 1)
            }
            HStack(spacing: 14) {
                if let raw = entry.response, let response = FriendResponse(rawValue: raw) {
                    Label(response.shortLabel, systemImage: response.iconName)
                        .font(.system(size: 12))
                }
                if entry.captureCount > 0 {
                    Label("\(entry.captureCount)", systemImage: "camera.fill")
                        .font(.system(size: 12))
                }
            }
            .foregroundStyle(CK.textSecondary)
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct LogDetailView: View {
    let entry: LogEntry
    let logManager: LogManager

    @State private var captures: [CaptureItem] = []
    @State private var expandedCapture: CaptureItem?
    @State private var showMapOptions = false
    @State private var notes = ""
    @FocusState private var notesFocused: Bool

    /// Maps the incident's raw analysis fields to a display state — nil hides the
    /// section entirely (no evidence to analyze yet).
    private var analysisState: AnalysisDisplayState? {
        if let analysis = entry.analysis, analysis.present { return .result(analysis) }
        switch entry.analysisStatus {
        case "failed": return .failed(entry.analysisError)
        case "done": return .noSuspect
        case "analyzing": return .analyzing
        default: return entry.captureCount > 0 ? .analyzing : nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let date = entry.createdAt {
                    Text(date, format: .dateTime.weekday().month().day().hour().minute())
                        .font(.system(size: 15))
                        .foregroundStyle(CK.textSecondary)
                }

                if let raw = entry.response, let response = FriendResponse(rawValue: raw) {
                    Label(response.shortLabel, systemImage: response.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CK.textPrimary)
                }

                if let coordinate = entry.coordinate {
                    LocationMapView(coordinate: coordinate)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(CK.divider, lineWidth: 1))
                        .overlay(
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { showMapOptions = true }
                        )

                    Button {
                        showMapOptions = true
                    } label: {
                        Text("Get Directions")
                    }
                    .buttonStyle(.ghost)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Notes")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CK.textPrimary)
                        Spacer()
                        if notesFocused {
                            Button("Done") { notesFocused = false }
                                .font(.subheadline)
                                .tint(CK.goldText)
                        }
                    }
                    TextField("Tap to add notes about this incident…", text: $notes, axis: .vertical)
                        .lineLimit(3...10)
                        .foregroundStyle(CK.textPrimary)
                        .focused($notesFocused)
                        .padding(notesFocused ? 10 : 0)
                        .background(
                            notesFocused ? CK.surface : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }

                if let state = analysisState {
                    AnalysisSectionView(state: state)
                }

                Text("Captured evidence (\(captures.count))")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CK.textPrimary)

                if captures.isEmpty {
                    Text("No photos were captured for this incident.")
                        .font(.system(size: 15))
                        .foregroundStyle(CK.textSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(captures) { capture in
                            Image(uiImage: capture.image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CK.divider, lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { expandedCapture = capture }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CK.background.ignoresSafeArea())
        .navigationTitle(entry.triggeredBy)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: notesFocused) { _, focused in
            // Leaving the editor hardens the text and saves it.
            if !focused {
                logManager.updateNotes(sessionId: entry.id, notes: notes)
            }
        }
        .onAppear {
            logManager.fetchCaptures(sessionId: entry.id) { captures = $0 }
            notes = entry.notes
        }
        .onDisappear {
            logManager.updateNotes(sessionId: entry.id, notes: notes)
        }
        .fullScreenCover(item: $expandedCapture) { capture in
            FullScreenPhotoView(image: capture.image) {
                expandedCapture = nil
            }
        }
        .directionsChooser(isPresented: $showMapOptions, coordinate: entry.coordinate)
    }
}
