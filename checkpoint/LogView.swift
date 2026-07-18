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
            List {
                if logManager.entries.isEmpty {
                    Text("No incidents yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logManager.entries) { entry in
                        NavigationLink {
                            LogDetailView(entry: entry, logManager: logManager)
                                .onAppear { readState.markOpened(entry.id) }
                        } label: {
                            LogRow(entry: entry, unread: !readState.isOpened(entry.id))
                        }
                    }
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry
    let unread: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Reserve the dot's space when read so rows stay aligned.
            Circle()
                .fill(unread ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.triggeredBy)
                        .font(.headline)
                    Spacer()
                    if entry.status == "triggered" {
                        Text("LIVE")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
                if let date = entry.createdAt {
                    Text(date, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if let raw = entry.response, let response = FriendResponse(rawValue: raw) {
                        Label(response.shortLabel, systemImage: response.iconName)
                            .font(.caption)
                    }
                    if entry.captureCount > 0 {
                        Label("\(entry.captureCount)", systemImage: "camera.fill")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 2)
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
                        .foregroundStyle(.secondary)
                }

                if let raw = entry.response, let response = FriendResponse(rawValue: raw) {
                    Label(response.shortLabel, systemImage: response.iconName)
                        .font(.headline)
                }

                if let coordinate = entry.coordinate {
                    LocationMapView(coordinate: coordinate)
                        .frame(height: 200)
                        .cornerRadius(12)
                        .overlay(
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { showMapOptions = true }
                        )

                    Button {
                        showMapOptions = true
                    } label: {
                        Text("Get Directions")
                            .primaryActionLabel()
                    }
                    .buttonStyle(.borderedProminent)
                    .squarishButtons()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Notes")
                            .font(.headline)
                        Spacer()
                        if notesFocused {
                            Button("Done") { notesFocused = false }
                                .font(.subheadline)
                        }
                    }
                    TextField("Tap to add notes about this incident…", text: $notes, axis: .vertical)
                        .lineLimit(3...10)
                        .focused($notesFocused)
                        .padding(notesFocused ? 10 : 0)
                        .background(
                            notesFocused ? Color(.secondarySystemBackground) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }

                if let state = analysisState {
                    AnalysisSectionView(state: state)
                }

                Text("Captured evidence (\(captures.count))")
                    .font(.headline)

                if captures.isEmpty {
                    Text("No photos were captured for this incident.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(captures) { capture in
                            Image(uiImage: capture.image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { expandedCapture = capture }
                        }
                    }
                }
            }
            .padding()
        }
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
