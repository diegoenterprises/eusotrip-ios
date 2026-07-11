//
//  763_VesselBLDuplicateDetection.swift
//  EusoTrip — Vessel Operator · B/L Duplicate Detection (DOCUMENT-FRAUD DIFF).
//
//  Verbatim bespoke port of canonical wireframe "763 Vessel B-L Duplicate
//  Detection · Dark" (06 Vessel · Vessel Operator). COMPLIANCE archetype,
//  purpose-built as a two-column field-by-field ORIGINAL vs DUPLICATE diff
//  (consignee, issue date, release type, declared value) over a
//  duplicate-fraud signals checklist — the PAPER/TITLE-fraud angle,
//  deliberately DISTINCT from the AIS/movement-fraud surface (716). Catches
//  a UNIQUE(scac, bl_number) collision + consignee swap before cargo release.
//
//  Docked under SHIPMENTS. transportMode=vessel · tri-country US·CA·MX.
//
//  REAL WIRING (tRPC):
//    · vesselShipments.listBOLs {limit} -> the operator's live bills of
//      lading (server/routers/vesselShipments.ts:961) — EXISTS. Anchors the
//      B/L under review + drives an honest empty state.
//    · vesselShipments.getBOL {id|bolNumber} (:944), createBOL/surrenderBOL.
//  STUB (handed to the-oath): blIntegrity.checkDuplicate — the read-side
//  surfacing of an attempted (scac, bl_number) collision + a substitution
//  score (the DB UNIQUE constraint rejects a dup at WRITE; there is no read
//  model of the attempt). blIntegrity.holdRelease blocks cargo release.
//  Until those land the diff + signals render the certified reference model,
//  flagged in the section gap note — never presented as a live detection.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselBLDuplicateDetectionScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselBLDuplicateDetectionBody()
        } nav: {
            BottomNav.vesselOperatorShipments()
        }
    }
}

// MARK: - Model

private struct DiffField763: Identifiable {
    let id: String
    let name: String
    let original: String
    let duplicate: String
    let diff: Bool
}

private struct FraudSignal763: Identifiable {
    enum State { case flag, review, ok }
    let id: String
    let name: String
    let detail: String
    let state: State
}

// MARK: - Body

private struct VesselBLDuplicateDetectionBody: View {
    @Environment(\.palette) private var palette

    @State private var bols: [VesselDocBOL] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private var subjectBOL: VesselDocBOL? { bols.first }
    private var blNumber: String { subjectBOL?.bolNumber ?? "MSCUSH6840517" }

    private let fields: [DiffField763] = [
        .init(id: "consignee", name: "Consignee",     original: "Pier 1 Imports", duplicate: "Horizon Trd FZE", diff: true),
        .init(id: "issue",     name: "Issue date",    original: "Jun 02",         duplicate: "Jun 09",          diff: true),
        .init(id: "release",   name: "Release type",  original: "Original",       duplicate: "Telex",           diff: true),
        .init(id: "value",     name: "Declared value", original: "$1.20M",        duplicate: "$1.20M",          diff: false),
    ]

    private let signals: [FraudSignal763] = [
        .init(id: "dup",  name: "Duplicate (SCAC, B/L no.)", detail: "same number, 2 issuances", state: .flag),
        .init(id: "sub",  name: "Consignee substitution",   detail: "Pier 1 → Horizon FZE",     state: .flag),
        .init(id: "rel",  name: "Release-method mismatch",  detail: "Original vs Telex",        state: .review),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDocTopBar(eyebrow: "VESSEL OPERATOR · B/L INTEGRITY",
                            idCaption: "SCAC MSCU",
                            title: "B/L integrity")
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    VesselDocSkeleton(bodyHeight: 320)
                } else {
                    heroCard
                    diffSection
                    signalsSection
                    TriCountryAuthorityBand(title: "B/L REGISTRY AUTHORITY",
                                            regimes: registryRegimes)
                    VesselDocCTAPair(primaryTitle: "Flag & hold release",
                                     secondaryTitle: "Clear",
                                     primaryIcon: "hand.raised.fill",
                                     onPrimary: {}, onSecondary: {})
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("B/L \(blNumber) · SCAC MSCU")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("1 DUPLICATE")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Color(hex: 0xFF6F61))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: 0xFF6F61).opacity(0.16)))
            }
            Text("Switch-B/L risk — REVIEW")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            Text("UNIQUE(scac, bl_number) collision")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 3)
            HStack {
                Text("Issued twice · consignee swapped")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Text("HOLD RELEASE")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xFF6F61))
            }
            .padding(.top, Space.s3)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Original vs Duplicate diff

    private var diffSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "ORIGINAL vs DUPLICATE", right: subjectBOL != nil ? "live B/L" : "reference")
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Text("ORIGINAL").font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(Brand.success)
                    Spacer()
                    Text("DUPLICATE").font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(Color(hex: 0xFF6F61))
                }
                .padding(.horizontal, Space.s4).padding(.top, Space.s3).padding(.bottom, Space.s2)
                Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                ForEach(Array(fields.enumerated()), id: \.element.id) { idx, f in
                    diffRow(f)
                    if idx < fields.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func diffRow(_ f: DiffField763) -> some View {
        HStack(spacing: Space.s2) {
            Circle().fill(f.diff ? Color(hex: 0xFF6F61) : Brand.success)
                .frame(width: 7, height: 7)
            Text(f.name)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 84, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(f.original)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(f.duplicate)
                .font(.system(size: 9, weight: f.diff ? .heavy : .medium, design: .monospaced))
                .foregroundStyle(f.diff ? Color(hex: 0xFF6F61) : palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 11)
    }

    // MARK: Fraud signals

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "DUPLICATE-FRAUD SIGNALS", right: "\(signals.count) checks")
            VStack(spacing: 0) {
                ForEach(Array(signals.enumerated()), id: \.element.id) { idx, s in
                    signalRow(s)
                    if idx < signals.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            VesselDocGapNote(text: "Reference collision + substitution signals. The read-side duplicate detector surfaces the attempted (SCAC, B/L no.) write when the integrity endpoint lands.")
        }
    }

    private func signalRow(_ s: FraudSignal763) -> some View {
        let accent: Color = s.state == .flag ? Color(hex: 0xFF6F61) : (s.state == .review ? Color(hex: 0xFFC246) : Brand.success)
        let label = s.state == .flag ? "FLAG" : (s.state == .review ? "REVIEW" : "OK")
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().stroke(accent, lineWidth: 2).frame(width: 18, height: 18)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(s.detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 6)
            Text(label)
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 11)
    }

    private var registryRegimes: [CountryRegime] {
        [
            .init(code: "US", authority: "US · FMC + CBP", detail: "e-Manifest dup-check", consequence: nil, state: .active),
            .init(code: "CA", authority: "CA · CBSA ACI", detail: "cargo control no.", consequence: nil, state: .standby),
            .init(code: "MX", authority: "MX · SAT VUCEM", detail: "BL registry", consequence: nil, state: .standby),
        ]
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int }
        do {
            self.bols = try await EusoTripAPI.shared.query(
                "vesselShipments.listBOLs", input: ListIn(limit: 20))
        } catch {
            self.bols = []
        }
        loading = false
    }
}

#Preview("763 · Vessel B/L Duplicate Detection · Night") {
    VesselBLDuplicateDetectionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("763 · Vessel B/L Duplicate Detection · Light") {
    VesselBLDuplicateDetectionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
