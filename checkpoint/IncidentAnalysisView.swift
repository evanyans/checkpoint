//
//  IncidentAnalysisView.swift
//  checkpoint
//
//  Created by Evan Yan on 2026-07-18.
//
//  AI-generated suspect description, produced server-side by Gemini from the
//  auto-captured evidence stills. Surfaced in the Log (for responders) and live
//  during an emergency, and also fed into the escalation call agent's context.
//

import SwiftUI
import FirebaseFirestore

struct SuspectAnalysis: Equatable {
    let present: Bool
    let summary: String
    let sex: String?
    let ageRange: String?
    let build: String?
    let height: String?
    let hair: String?
    let facialHair: String?
    let clothing: String?
    let accessories: String?
    let distinguishingFeatures: [String]
    let confidence: String?
    let caveats: String?
    let updatedAt: Date?

    /// Fails when there's no analysis map, or nothing worth showing yet.
    init?(data: [String: Any]?, updatedAt: Date?) {
        guard let data else { return nil }
        let present = data["present"] as? Bool ?? true
        let summary = (data["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing to show if the model found no other person and wrote no summary.
        guard present || !summary.isEmpty else { return nil }

        self.present = present
        self.summary = summary
        self.sex = Self.clean(data["sex"])
        self.ageRange = Self.clean(data["ageRange"])
        self.build = Self.clean(data["build"])
        self.height = Self.clean(data["height"])
        self.hair = Self.clean(data["hair"])
        self.facialHair = Self.clean(data["facialHair"])
        self.clothing = Self.clean(data["clothing"])
        self.accessories = Self.clean(data["accessories"])
        self.distinguishingFeatures = (data["distinguishingFeatures"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        self.confidence = Self.clean(data["confidence"])
        self.caveats = Self.clean(data["caveats"])
        self.updatedAt = updatedAt
    }

    /// Gemini returns null / "unknown" for missing attributes — treat those as absent.
    private static func clean(_ value: Any?) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty, s.lowercased() != "unknown", s.lowercased() != "null" else { return nil }
        return s
    }

    /// Label/value pairs for the attributes that were actually observed.
    var attributes: [(String, String)] {
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: String?) { if let value { rows.append((label, value)) } }
        add("Sex", sex)
        add("Age", ageRange)
        add("Build", build)
        add("Height", height)
        add("Hair", hair)
        add("Facial hair", facialHair)
        add("Clothing", clothing)
        add("Accessories", accessories)
        return rows
    }
}

/// The lifecycle of the AI analysis, so the UI is never silently blank.
enum AnalysisDisplayState {
    case analyzing
    case failed(String?)
    case noSuspect
    case result(SuspectAnalysis)
}

/// Renders whichever analysis state applies — spinner, failure, "no suspect", or
/// the full description card.
struct AnalysisSectionView: View {
    let state: AnalysisDisplayState

    var body: some View {
        switch state {
        case .result(let analysis):
            IncidentAnalysisView(analysis: analysis)
        case .analyzing:
            statusCard {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analyzing evidence…").font(.subheadline.bold())
                        Text("The AI is describing the suspect from the captured stills.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        case .noSuspect:
            statusCard {
                Label {
                    Text("No suspect identified in the footage yet.").font(.subheadline)
                } icon: {
                    Image(systemName: "person.fill.questionmark").foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            statusCard {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Analysis couldn't complete", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                    if let message, !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("It will retry automatically as new stills come in.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func statusCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI suspect description", systemImage: "sparkles")
                .font(.subheadline.bold())
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct IncidentAnalysisView: View {
    let analysis: SuspectAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI suspect description", systemImage: "sparkles")
                    .font(.subheadline.bold())
                Spacer()
                if let confidence = analysis.confidence {
                    Text("\(confidence.capitalized) confidence")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(confidenceColor, in: Capsule())
                }
            }

            if analysis.present {
                if !analysis.summary.isEmpty {
                    Text(analysis.summary)
                        .font(.subheadline)
                }

                if !analysis.attributes.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(analysis.attributes, id: \.0) { label, value in
                            HStack(alignment: .top) {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 84, alignment: .leading)
                                Text(value)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if !analysis.distinguishingFeatures.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Distinguishing features")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(analysis.distinguishingFeatures, id: \.self) { feature in
                            Label(feature, systemImage: "exclamationmark.circle")
                                .font(.caption)
                        }
                    }
                }
            } else {
                Text("No other person has been clearly identified in the footage yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let caveats = analysis.caveats {
                Text(caveats)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("AI-generated from captured stills — treat as a lead, not a positive ID.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var confidenceColor: Color {
        switch analysis.confidence?.lowercased() {
        case "high": return .green
        case "medium": return .orange
        default: return Color(.systemGray)
        }
    }
}

#Preview {
    IncidentAnalysisView(analysis: SuspectAnalysis(
        data: [
            "present": true,
            "summary": "A male-presenting person in their 20s-30s wearing a black hoodie and red cap.",
            "sex": "male-presenting",
            "ageRange": "20s-30s",
            "build": "medium",
            "hair": "short dark",
            "clothing": "black hoodie, dark jeans",
            "accessories": "red baseball cap",
            "distinguishingFeatures": ["tattoo on left hand", "white logo on hoodie"],
            "confidence": "medium",
            "caveats": "Face partially obscured; lighting is low.",
        ],
        updatedAt: Date()
    )!)
    .padding()
}
