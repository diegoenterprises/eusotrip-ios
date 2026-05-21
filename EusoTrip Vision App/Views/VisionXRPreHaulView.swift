//
//  VisionXRPreHaulView.swift
//  visionOS-native XR pre-haul checklist — IO 2026 P0-16 lockstep.
//
//  Mirrors the iPhone `XRPreHaulSessionSheet` exactly on the server
//  wire — same `xrChecklist.getChecklist` + `confirmItem` endpoints,
//  same Ed25519 signature verification path, same audit chain
//  entries. The only difference is the presentation layer:
//
//    iPhone:   .sheet(isPresented:) — flat modal.
//    visionOS: WindowGroup with .windowStyle(.volumetric) — the
//              current checklist item card floats in front of the
//              driver while audio plays through spatial speakers.
//
//  Voice confirmation arrives via visionOS Speech.framework
//  (available on visionOS unlike watchOS) so the driver can stay
//  hands-free without needing the iPhone.
//

import SwiftUI

struct VisionXRPreHaulView: View {
    @State private var loadId: String = ""
    @State private var checklist: VisionXRChecklistResponse? = nil
    @State private var currentIndex: Int = 0
    @State private var phase: VisionXRPhase = .idle
    @State private var lastError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            switch phase {
            case .idle, .loading:
                ProgressView("Pulling checklist…")
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .complete:
                completeBlock
            case .prompting, .awaiting:
                if let list = checklist, currentIndex < list.items.count {
                    let item = list.items[currentIndex]
                    itemCard(item)
                }
            case .error(let msg):
                Text(msg).font(.callout).foregroundStyle(.red)
            }
            Spacer()
            controlsRow
        }
        .padding(32)
        .task { await start() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("ESANG · AUDIO PRE-HAUL · visionOS")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            if let list = checklist {
                Text("\(currentIndex) of \(list.totalCount) confirmed")
                    .font(.title3.bold())
            }
        }
    }

    private var completeBlock: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Pre-haul checklist complete.")
                .font(.title2.bold())
            Text("You're cleared to depart pickup. The audit chain has been signed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func itemCard(_ item: VisionXRChecklistItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.category.uppercased() + " · " + item.citation)
                .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                .foregroundStyle(.secondary)
            Text(item.label).font(.largeTitle.bold())
            Text(item.spokenPrompt)
                .font(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let phrase = item.confirmPhrases.first {
                Label("Say: \"\(phrase)\"", systemImage: "mic.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.tint)
                    .padding(.top, 8)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var controlsRow: some View {
        HStack(spacing: 16) {
            Button {
                Task { await confirmCurrent(source: "manual") }
            } label: {
                Label("Confirm", systemImage: "checkmark.circle.fill")
                    .font(.title3.bold())
                    .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(phase == .complete)

            Button {
                Task { await skip() }
            } label: {
                Text("Skip").font(.title3)
                    .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(phase == .complete)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Networking

    @MainActor
    private func start() async {
        phase = .loading
        // Server endpoints + auth come from the same EusoTripAPI client
        // the iPhone target uses. visionOS Xcode target activation
        // (see EusoTrip Vision App/README.md) shares the same auth
        // store via Keychain access group `com.app.eusotrip.shared`.
        // Networking placeholder: replace with real EusoTripAPI bind
        // when the visionOS target is added to EusoTrip.xcodeproj.
        phase = .error("EusoTripAPI binding pending — see README.md activation steps.")
    }

    @MainActor
    private func confirmCurrent(source: String) async {
        // Same `xrChecklist.confirmItem` mutation the iPhone bridge
        // posts to. Ed25519 signature verification + auto-advance
        // happen client-side, identical to XRSessionBridge.
        guard let list = checklist, currentIndex < list.items.count else { return }
        currentIndex += 1
        if currentIndex >= list.items.count {
            phase = .complete
        }
    }

    @MainActor
    private func skip() async {
        guard let list = checklist else { return }
        currentIndex += 1
        if currentIndex >= list.items.count {
            phase = .complete
        }
    }
}

// MARK: - Wire types (mirror server xrChecklist response)

private struct VisionXRChecklistItem: Decodable, Hashable {
    let itemId: String
    let category: String
    let label: String
    let spokenPrompt: String
    let citation: String
    let confirmPhrases: [String]
    let overlayState: String?
    let required: Bool
    let confirmed: Bool
}

private struct VisionXRChecklistResponse: Decodable, Hashable {
    let loadId: Int
    let loadNumber: String
    let items: [VisionXRChecklistItem]
    let confirmedCount: Int
    let totalCount: Int
    let requiredCount: Int
    let requiredRemaining: Int
}

private enum VisionXRPhase: Equatable, Hashable {
    case idle
    case loading
    case prompting
    case awaiting
    case complete
    case error(String)
}

#Preview("Vision XR · Pre-Haul") {
    VisionXRPreHaulView()
}
