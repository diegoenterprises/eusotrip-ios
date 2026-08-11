//
//  ES12_MeProfile.swift
//  EusoTrip — Escort · Me — Profile & Settings (ES-12).
//
//  SUPERSEDES-BY-ADOPTION: `620_EscortMeHome.swift` (legacy escort Me hub — a flat
//  chevron list of ten destinations with no data on it). That file is NOT deleted and
//  NOT edited by this brick — the escort nav map still binds the "me" bottom-nav slot
//  to "620" until the single-writer of EscortNavController.swift rewires it. When it
//  does, the "me" slot adopts `EscortMeProfileScreen` and the legacy file retires.
//  Nav entry needed is listed in this brick's manifest; nothing here touches shared
//  nav files.
//
//  Built from the ES-12 design-authority twins
//  ("07 Escort/{Light,Dark}-SVG/ES-12 Me Profile.svg").
//
//  ARCHETYPE HOME/DETAIL (growth ladder). The hero is a certification LADDER drawn as
//  a rising staircase: three rungs of increasing height — the earned one short and
//  solid, the current one gradient-filled, the locked one taller and dashed, carrying
//  its single unmet requirement and its exam date. Below it a capability facet grid,
//  an equipment preview that defers to the registry, and settings as content rows that
//  each carry a value rather than a chevron menu.
//
//  Deliberately NOT ES-08 Cert Reciprocity: ES-08 answers WHERE a credential is
//  honoured (a 51-tile choropleth of law by geography, wallet sorted by expiry). ES-12
//  answers HOW FAR the career has climbed and what the next rung costs — no map, no
//  state tiles, one ordinal axis instead of a spatial one.
//
//  WIRING TRUTH (code-traced this fire)
//    REAL  escorts.getProfile             escorts.ts:3081  return literal :3127-3188
//                                                          positions :3138 · heightPole :3145
//                                                          equipment :3149 · stats :3152-3160
//                                                          over real counts :3101-3125
//    REAL  escorts.getCertificationStatus escorts.ts:924   → getCertificationStatusInternal :487
//                                                          heightPoleCertified :519
//                                                          hazmatEscortCertified :520
//                                                          nightOperationsCertified :521
//                                                          statesCleared :531 · reciprocal :532
//                                                          30-day expiringSoon window :497
//    REAL  escorts.getMyCertifications    escorts.ts:2458  wallet rows behind the ladder
//    REAL  escorts.updateProfile          escorts.ts:3192  facet writes, merge :3216-3229 — ONLINE_ONLY
//
//  NAMED GAPS — honest, not shipped:
//    · No `level` column on escort_certifications and no proc returns one. Levels 1→3
//      are DERIVED below from the three real booleans (L1 = at least one active cert,
//      L2 = heightPole AND nightOps, L3 = hazmat). Owed: a canonical level, otherwise
//      two surfaces can disagree about what level this escort is.
//    · wallet.balance is a hard-coded literal 0 (escorts.ts:3175). This screen renders
//      NO balance; the payout row carries the method and the lifetime figure (a real
//      SUM :3103) and defers any balance to ES-18.
//    · stats.incidentCount and stats.repeatClientRate are hard-coded 0 (:3156-3157) and
//      are therefore not drawn at all.
//    · STEER is unmodelled: positions has exactly four keys (:3138) and
//      escort_assignments.position is enum lead|chase|both. Its facet reads NOT MODELLED
//      rather than a toggle that would silently never persist.
//    · profile.equipment is an untyped metadata blob (:3149) — no equipment table and no
//      registry proc. The strip previews the blob; the registry (ES-30) is owed.
//    · The 30-d/7-d cert-expiry push is ABSENT (same gap ES-08 named). The Alerts row
//      says in-app only and never implies a push.
//
//  OFFLINE (§W): READ_CACHED(60m) through `EscortOfflineCache`. A cached paint swaps the
//  ladder's live dot for the staleness line; past the ttl the screen shows its offline
//  state rather than a stale level presented as current. Every write — facet toggles,
//  availability, sign-out — is ONLINE_ONLY: the phone has no escort outbox (Driver-only
//  mirror, PLANNED per Offline Mode Encyclopedia v2). No queue badge is ever drawn.
//
//  CHAIN: the write half is ONE-SIDED. escorts.updateProfile escorts.ts:3192-3231 is a
//  bare users.metadata write — no audit row (no recordAuditEvent) and no realtime emit —
//  so a capability change is invisible to dispatch, to the marketplace matcher and to
//  other sessions until each cold-refetches. Missing half: recordAuditEvent plus a WS
//  ESCORT_PROFILE_UPDATED on WS_CHANNELS.USER, mirroring escorts.uploadCertification
//  (audit :2556, broadcast :2576). The read half is CLOSED.
//
//  RBAC: a non-admin caller is pinned to their own resolved id and a supplied escortId
//  is ignored (escorts.ts:3089-3091); Shipper NO ACCESS.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Wire projections (screen-local, private)

private struct MpPositions: Codable, Hashable {
    var leadEscort: Bool?
    var rearEscort: Bool?
    var heightPole: Bool?
    var routeSurvey: Bool?
}

private struct MpHomeBase: Codable, Hashable { var city: String?; var state: String? }
private struct MpHeightPole: Codable, Hashable { var maxHeight: Double?; var hasElectronicSensor: Bool? }

private struct MpStats: Codable, Hashable {
    var totalConvoys: Int?
    var totalMiles: Int?
    var onTimePercentage: Int?
    var leadJobs: Int?
    var chaseJobs: Int?
}

private struct MpWallet: Codable, Hashable {
    /// NOTE: `balance` is a hard-coded literal 0 server-side (escorts.ts:3175).
    /// Decoded for completeness; never rendered.
    var balance: Double?
    var lifetimeEarnings: Double?
    var activeJobs: Int?
}

/// `escorts.getProfile` (escorts.ts:3081) — the fields this surface actually paints.
private struct MpProfile: Codable {
    var id: String?
    var name: String?
    var escortCompany: String?
    var positions: MpPositions?
    var preferredPosition: String?
    var yearsExperience: Int?
    var homeBase: MpHomeBase?
    var willingToTravel: Int?
    var heightPole: MpHeightPole?
    var stats: MpStats?
    var wallet: MpWallet?
}

/// One row of `escorts.getCertificationStatus.certifications` (resolver escorts.ts:514-528).
private struct MpCertification: Codable, Identifiable, Hashable {
    var id: String
    var certType: String?
    var certNumber: String?
    var issuingState: String?
    var status: String?
    var expirationDate: String?
    var heightPoleCertified: Bool?
    var hazmatEscortCertified: Bool?
    var nightOperationsCertified: Bool?
    var clearsStates: [String]?
}

private struct MpCertStateRow: Codable, Identifiable, Hashable {
    var id: String { code }
    var code: String
    var name: String?
    var status: String?
    var expirationDate: String?
}

/// `escorts.getCertificationStatus` (escorts.ts:924).
private struct MpCertStatus: Codable {
    var total: Int?
    var active: Int?
    var expiringSoon: Int?
    var expired: Int?
    var statesCleared: [String]?
    var reciprocalStatesCleared: [String]?
    var states: [MpCertStateRow]?
    var certifications: [MpCertification]?
}

private struct MpProfileInput: Encodable { let escortId: String? }
private struct MpUpdatePositionsInput: Encodable { let positions: MpPositionsWire }
private struct MpPositionsWire: Encodable {
    let leadEscort: Bool; let rearEscort: Bool; let heightPole: Bool; let routeSurvey: Bool
}
private struct MpUpdateResult: Decodable { let success: Bool?; let updatedAt: String? }

/// One Codable envelope so the whole surface caches as a single last-good snapshot.
private struct MpSnapshot: Codable {
    var profile: MpProfile?
    var certs: MpCertStatus?
    var capturedAt: Date
}

// MARK: - Derived ladder (there is no server `level` — this is the client rule)

private struct MpRung: Identifiable {
    enum State { case earned, current, locked }
    let id: Int
    let level: Int
    let titleLines: [String]
    let proof: String
    var state: State
    let unmet: String?
    let unlockLine: String?
}

private struct MpLadder {
    let rungs: [MpRung]
    var currentLevel: Int { rungs.last(where: { $0.state != .locked })?.level ?? 1 }
    var total: Int { rungs.count }

    /// L1 = at least one active credential · L2 = high-pole AND night-ops endorsements
    /// · L3 = hazmat-escort endorsement. Every input is a real column on
    /// escort_certifications (escorts.ts:519-521). The LEVELS are ours, not the server's.
    static func derive(from certs: MpCertStatus?) -> MpLadder {
        let rows = certs?.certifications ?? []
        let activeRows = rows.filter { ($0.status ?? "active") == "active" }
        let held = (certs?.statesCleared ?? []).joined(separator: " · ")
        let hasBase = !activeRows.isEmpty
        let hasPole = activeRows.contains { $0.heightPoleCertified == true }
        let hasNight = activeRows.contains { $0.nightOperationsCertified == true }
        let hasHazmat = activeRows.contains { $0.hazmatEscortCertified == true }

        let reciprocalGain = Set(activeRows.flatMap { $0.clearsStates ?? [] })
            .subtracting(Set(certs?.statesCleared ?? []))
            .subtracting(Set(certs?.reciprocalStatesCleared ?? []))
            .count

        var rungs: [MpRung] = [
            MpRung(id: 1, level: 1, titleLines: ["P/EVO"],
                   proof: held.isEmpty ? "no active credential" : "\(held) held",
                   state: hasBase ? .earned : .locked,
                   unmet: hasBase ? nil : "0 of 1 active credential", unlockLine: nil),
            MpRung(id: 2, level: 2, titleLines: ["HIGH-POLE", "+ NIGHT OPS"],
                   proof: "endorse HP · NT",
                   state: (hasPole && hasNight) ? .earned : .locked,
                   unmet: (hasPole && hasNight) ? nil
                        : "\((hasPole ? 1 : 0) + (hasNight ? 1 : 0)) of 2 endorsements",
                   unlockLine: nil),
            MpRung(id: 3, level: 3, titleLines: ["HAZMAT", "ESCORT"],
                   proof: "endorse HM",
                   state: hasHazmat ? .earned : .locked,
                   unmet: hasHazmat ? nil : "0 of 1 endorsement",
                   unlockLine: reciprocalGain > 0 ? "+\(reciprocalGain) states" : nil)
        ]
        // The highest earned rung is the one you stand on.
        if let idx = rungs.lastIndex(where: { $0.state == .earned }) {
            rungs[idx].state = .current
        }
        return MpLadder(rungs: rungs)
    }
}

// MARK: - Screen body

struct EscortMeProfile: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    private enum Phase { case loading, loaded, failed }

    @State private var phase: Phase = .loading
    @State private var snapshot: MpSnapshot? = nil
    @State private var stalenessLine: String? = nil
    @State private var writeNotice: String? = nil
    @State private var showSignOutConfirm = false

    private static let cacheKey = "es12-me-profile"
    private static let cacheTTL: TimeInterval = 60 * 60   // READ_CACHED(60m)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                identityBlock
                iridescentHairline
                switch phase {
                case .loading: loadingBlock
                case .failed:  failedBlock
                case .loaded:
                    certLadder
                    facetGrid
                    equipmentPreview
                    settingsCard
                    signOutRow
                    if let notice = writeNotice {
                        Text(notice).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    provenanceFootnote
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign back in to view assignments, certifications and corridor routing.")
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · ME")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text((snapshot?.profile?.escortCompany ?? "").uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var identityBlock: some View {
        let p = snapshot?.profile
        let displayName = p?.name ?? session.user?.name ?? "Escort"
        return HStack(alignment: .top, spacing: Space.s3) {
            Text(monogram(displayName))
                .font(.system(size: 16, weight: .heavy)).tracking(0.4)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(LinearGradient.diagonal))
            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.system(size: 26, weight: .bold)).tracking(-0.5)
                    .foregroundStyle(LinearGradient.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(credentialLine(p))
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: Space.s2) {
                if let preferred = p?.preferredPosition, !preferred.isEmpty {
                    Text("PREFERS \(preferred.uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.info)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.info.opacity(0.16)))
                }
                Text(careerLine(p))
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .padding(.horizontal, -14)
    }

    // MARK: - Certification ladder (HERO)

    private var certLadder: some View {
        let ladder = MpLadder.derive(from: snapshot?.certs)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CERTIFICATION LADDER · LEVEL \(ladder.currentLevel) OF \(ladder.total)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    if stalenessLine == nil {
                        ZStack {
                            Circle().fill(Brand.success.opacity(0.25)).frame(width: 12, height: 12)
                            Circle().fill(Brand.success).frame(width: 7, height: 7)
                        }
                    }
                    Text(stalenessLine ?? "certs · live")
                        .font(EType.mono(.micro))
                        .foregroundStyle(stalenessLine == nil ? palette.textPrimary : Brand.warning)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(palette.bgCard).overlay(Capsule().stroke(palette.borderFaint)))
            }

            HStack(alignment: .bottom, spacing: 11) {
                ForEach(ladder.rungs) { rung in rungBlock(rung) }
            }
            .frame(height: 152, alignment: .bottom)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.textPrimary.opacity(0.10)).frame(height: 1.5).offset(y: 1)
            }

            HStack(spacing: 0) {
                dataStat("STATES CLEARED",
                         value: "\(statesClearedCount)", gradient: true)
                statDivider
                dataStat("EXPIRING 30 d",
                         value: expiringLabel, tint: Brand.warning)
                statDivider
                dataStat("EXPIRED",
                         value: expiredLabel, tint: Brand.danger)
            }
            .frame(height: 46)
            .padding(.top, Space.s2)
        }
    }

    @ViewBuilder
    private func rungBlock(_ rung: MpRung) -> some View {
        let height: CGFloat = [60, 106, 152][min(rung.level - 1, 2)]
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("LEVEL \(rung.level)")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(rung.state == .current ? Color.white.opacity(0.75)
                                                            : palette.textTertiary)
                Spacer(minLength: 4)
                rungGlyph(rung)
            }
            .padding(.bottom, Space.s2)

            ForEach(Array(rung.titleLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 12.5, weight: .heavy))
                    .foregroundStyle(rung.state == .current ? .white : palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            if let unmet = rung.unmet {
                Text(unmet).font(EType.mono(.micro)).foregroundStyle(Brand.warning)
                    .padding(.top, 6)
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, 7)
                Text("renewal opens in Cert wallet")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
                if let unlock = rung.unlockLine {
                    // ESANG earns its place here — the climb is the coaching moment.
                    HStack(spacing: 7) {
                        Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("ESANG").font(.system(size: 8, weight: .heavy)).tracking(0.3)
                                .foregroundStyle(palette.textPrimary)
                            Text(unlock).font(EType.mono(.micro)).foregroundStyle(Brand.escort)
                        }
                    }
                    .padding(.top, Space.s2)
                }
            } else {
                Text(rung.proof)
                    .font(EType.mono(.micro))
                    .foregroundStyle(rung.state == .current ? Color.white.opacity(0.85) : Brand.success)
                    .padding(.top, 6)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if rung.state == .current {
                    Text("YOU ARE HERE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.5).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                        .padding(.top, Space.s2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .background(rungBackground(rung))
    }

    @ViewBuilder
    private func rungGlyph(_ rung: MpRung) -> some View {
        switch rung.state {
        case .earned:
            ZStack {
                Circle().fill(Brand.success.opacity(0.18)).frame(width: 18, height: 18)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Brand.success)
            }
        case .current:
            ZStack {
                Circle().fill(Color.white.opacity(0.22)).frame(width: 18, height: 18)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
            }
        case .locked:
            Image(systemName: "lock").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private func rungBackground(_ rung: MpRung) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        switch rung.state {
        case .current: shape.fill(LinearGradient.diagonal)
        case .earned:  shape.fill(palette.bgCard).overlay(shape.strokeBorder(palette.borderFaint))
        case .locked:
            shape.fill(palette.bgCard.opacity(0.6))
                .overlay(shape.strokeBorder(Brand.magenta.opacity(0.45),
                                            style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
        }
    }

    // MARK: - Positions & capabilities (facet BentoGrid)

    private struct Facet: Identifiable {
        let id: Int
        let kind: String
        let name: String
        let on: Bool
        let modelled: Bool
        let trailing: String?
        let tint: Color
    }

    private var facets: [Facet] {
        let p = snapshot?.profile
        let pos = p?.positions
        let certRows = snapshot?.certs?.certifications ?? []
        let night = certRows.contains { $0.nightOperationsCertified == true && ($0.status ?? "active") == "active" }
        let poleMax = p?.heightPole?.maxHeight
        return [
            Facet(id: 1, kind: "POSITION", name: "LEAD", on: pos?.leadEscort == true, modelled: true,
                  trailing: (p?.stats?.leadJobs).map { "\($0) jobs" }, tint: Brand.info),
            Facet(id: 2, kind: "POSITION", name: "CHASE", on: pos?.rearEscort == true, modelled: true,
                  trailing: (p?.stats?.chaseJobs).map { "\($0) jobs" }, tint: Brand.escort),
            Facet(id: 3, kind: "CAPABILITY", name: "HIGH-POLE", on: pos?.heightPole == true, modelled: true,
                  trailing: poleMax.map { String(format: "max %.1f ft", $0) }, tint: Brand.hazmat),
            Facet(id: 4, kind: "CAPABILITY", name: "SURVEY", on: pos?.routeSurvey == true, modelled: true,
                  trailing: nil, tint: Brand.success),
            Facet(id: 5, kind: "ENDORSEMENT", name: "NIGHT OPS", on: night, modelled: true,
                  trailing: night ? "cert" : nil, tint: Color(hex: 0x6366F1)),
            // STEER has no server representation at all — see the header's named gap.
            Facet(id: 6, kind: "POSITION", name: "STEER", on: false, modelled: false,
                  trailing: nil, tint: Brand.neutral)
        ]
    }

    private var facetGrid: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("POSITIONS & CAPABILITIES",
                         trailing: "\(facets.filter { $0.modelled && $0.on }.count) ON · \(facets.filter { !$0.modelled }.count) UNMODELLED")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(facets) { facet in facetCell(facet) }
            }
        }
    }

    private func facetCell(_ facet: Facet) -> some View {
        Button(action: { Task { await toggleFacet(facet) } }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(facet.kind)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(facet.name)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(facet.modelled ? palette.textPrimary : palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Text(facet.modelled ? (facet.on ? "ON" : "OFF") : "NOT MODELLED")
                        .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(facet.modelled
                                         ? (facet.on ? facet.tint : palette.textSecondary)
                                         : palette.textSecondary)
                        .padding(.horizontal, Space.s2).padding(.vertical, 3)
                        .background(Capsule().fill(facet.modelled && facet.on
                                                   ? facet.tint.opacity(0.16)
                                                   : Brand.neutral.opacity(0.14)))
                    Spacer(minLength: 0)
                    if let trailing = facet.trailing {
                        Text(trailing).font(EType.mono(.micro))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, 10)
            .frame(height: 58, alignment: .topLeading)
            .background(facetBackground(facet))
        }
        .buttonStyle(.plain)
        .disabled(!facet.modelled)
    }

    @ViewBuilder
    private func facetBackground(_ facet: Facet) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        if facet.modelled {
            shape.fill(palette.bgCard)
                .overlay(shape.strokeBorder(palette.borderFaint))
                .overlay(alignment: .leading) {
                    Rectangle().fill(facet.on ? facet.tint : Brand.neutral.opacity(0.4))
                        .frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 1.5))
                }
        } else {
            shape.fill(palette.bgCard.opacity(0.6))
                .overlay(shape.strokeBorder(palette.textTertiary.opacity(0.45),
                                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }

    // MARK: - Equipment preview (defers to the registry — never a verdict)

    private var equipmentPreview: some View {
        let poleMax = snapshot?.profile?.heightPole?.maxHeight
        let sensor = snapshot?.profile?.heightPole?.hasElectronicSensor == true
        return VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("EQUIPMENT · REGISTRY PREVIEW", trailing: "OPEN REGISTRY →")
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    equipmentCell("HEIGHT POLE",
                                  poleMax.map { String(format: "%.1f ft", $0) } ?? "—")
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 30)
                    equipmentCell("SENSOR", sensor ? "electronic" : "manual")
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 30)
                    equipmentCell("HOME BASE", homeBaseShort)
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 30)
                    equipmentCell("RADIUS",
                                  (snapshot?.profile?.willingToTravel).map { "\($0) mi" } ?? "—")
                }
                .padding(.horizontal, 14).padding(.top, Space.s3).padding(.bottom, 10)

                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 14)

                HStack {
                    Text("pre-trip verdicts live in Vehicle check")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 8)
                    Text("registry not yet built")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, Space.s2)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            )
        }
    }

    private func equipmentCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Settings as content rows (each row carries its value)

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SETTINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                settingsRow(title: "Availability",
                            pill: (snapshot?.profile?.wallet?.activeJobs ?? 0) > 0 ? "ON A MOVE" : "ACCEPTING",
                            pillTint: Brand.success,
                            value: (snapshot?.profile?.willingToTravel).map { "\($0) mi radius" } ?? "—",
                            warning: false,
                            sub: "\(homeBaseShort) home base")
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 14)
                settingsRow(title: "Payout",
                            pill: "NET-7 QUICKPAY", pillTint: Brand.info,
                            value: lifetimeLabel, warning: false,
                            sub: "Balance lives in Earnings — this proc returns a placeholder zero")
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 14)
                settingsRow(title: "Alerts", pill: nil, pillTint: nil,
                            value: "in-app only", warning: true,
                            sub: "Cert-expiry push is not shipped yet")
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            )
        }
    }

    private func settingsRow(title: String, pill: String?, pillTint: Color?,
                             value: String, warning: Bool, sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                if let pill, let tint = pillTint {
                    Text(pill).font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.16)))
                }
                Spacer(minLength: 4)
                Text(value).font(EType.mono(.micro))
                    .foregroundStyle(warning ? Brand.warning : palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
            if let sub {
                Text(sub).font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var signOutRow: some View {
        Button(action: { showSignOutConfirm = true }) {
            HStack(spacing: Space.s3) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("Sign out").font(.system(size: 12.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Brand.danger)
                Spacer(minLength: 0)
                Text("online only").font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Brand.danger.opacity(0.35)))
            )
        }
        .buttonStyle(.plain)
    }

    private var provenanceFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Levels 1–3 are derived on device from the height-pole, night-ops and hazmat endorsement columns — the server stores no level.")
            Text("Capability edits save to your profile but do not yet notify dispatch or the job board; they are seen on their next refresh.")
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(palette.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Register blocks

    private var loadingBlock: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Loading profile…").font(EType.body).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s6)
    }

    private var failedBlock: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Profile unavailable")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("No live read and no snapshot inside the 60-minute window. Your level is not shown rather than shown stale.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { Task { await refreshAll() } }) {
                Text("Retry").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, Space.s5).padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Space.s5)
    }

    // MARK: - Primitives + formatting

    private func sectionLabel(_ text: String, trailing: String) -> some View {
        HStack {
            Text(text).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 8)
            Text(trailing).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var statDivider: some View {
        Rectangle().fill(palette.textPrimary.opacity(0.07)).frame(width: 1, height: 28)
    }

    private func dataStat(_ label: String, value: String, tint: Color? = nil,
                          gradient: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            if gradient {
                Text(value).font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Text(value).font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundStyle(tint ?? palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Space.s3)
    }

    private func monogram(_ s: String) -> String {
        let parts = s.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "—" : String(initials.prefix(2))
    }

    private func credentialLine(_ p: MpProfile?) -> String {
        var bits: [String] = []
        if !homeBaseShort.isEmpty && homeBaseShort != "—" { bits.append(homeBaseShort) }
        if let radius = p?.willingToTravel { bits.append("\(radius) mi") }
        if let company = p?.escortCompany, !company.isEmpty { bits.append(company) }
        return bits.isEmpty ? "Escort profile" : bits.joined(separator: " · ")
    }

    private func careerLine(_ p: MpProfile?) -> String {
        var bits: [String] = []
        if let yrs = p?.yearsExperience, yrs > 0 { bits.append("\(yrs) yr") }
        if let convoys = p?.stats?.totalConvoys { bits.append("\(convoys) escorts") }
        if let ot = p?.stats?.onTimePercentage { bits.append("\(ot)% OT") }
        return bits.joined(separator: " · ")
    }

    private var homeBaseShort: String {
        guard let hb = snapshot?.profile?.homeBase else { return "—" }
        let city = hb.city ?? "", state = hb.state ?? ""
        let joined = [city, state].filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? "—" : joined
    }

    private var statesClearedCount: Int {
        let held = snapshot?.certs?.statesCleared?.count ?? 0
        let reciprocal = snapshot?.certs?.reciprocalStatesCleared?.count ?? 0
        return held + reciprocal
    }

    private var expiringLabel: String {
        let n = snapshot?.certs?.expiringSoon ?? 0
        guard n > 0 else { return "0" }
        return "\(n)"
    }

    private var expiredLabel: String {
        let n = snapshot?.certs?.expired ?? 0
        return "\(n)"
    }

    private var lifetimeLabel: String {
        guard let amount = snapshot?.profile?.wallet?.lifetimeEarnings else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "—"
    }

    // MARK: - Data plumbing

    private func refreshAll() async {
        if snapshot == nil { phase = .loading }
        do {
            async let profile: MpProfile? = try? EusoTripAPI.shared.query(
                "escorts.getProfile", input: MpProfileInput(escortId: nil))
            async let certs: MpCertStatus? = try? EusoTripAPI.shared.query(
                "escorts.getCertificationStatus", input: EmptyInput())

            let fresh = MpSnapshot(profile: await profile, certs: await certs, capturedAt: Date())
            guard fresh.profile != nil || fresh.certs != nil else { throw EscortMeProfileError.empty }
            await MainActor.run {
                snapshot = fresh
                stalenessLine = nil
                phase = .loaded
            }
            EscortOfflineCache.store(fresh, key: Self.cacheKey)
        } catch {
            // READ_CACHED(60m): paint last-good and say so, or show the offline state.
            if let cached = EscortOfflineCache.load(MpSnapshot.self, key: Self.cacheKey,
                                                    ttl: Self.cacheTTL) {
                await MainActor.run {
                    snapshot = cached.value
                    stalenessLine = EscortOfflineCache.stalenessLine(age: cached.age)
                    phase = .loaded
                }
            } else if snapshot == nil {
                await MainActor.run { phase = .failed }
            }
        }
    }

    /// ONLINE_ONLY — escorts.updateProfile merges into users.metadata.escortProfile.
    /// There is no outbox for the escort role, so a failure is reported, never queued.
    /// The write also emits nothing and records no audit row (see CHAIN in the header),
    /// which is why the confirmation copy is deliberately modest.
    private func toggleFacet(_ facet: Facet) async {
        guard facet.modelled, let pos = snapshot?.profile?.positions else { return }
        var next = MpPositionsWire(leadEscort: pos.leadEscort ?? false,
                                   rearEscort: pos.rearEscort ?? false,
                                   heightPole: pos.heightPole ?? false,
                                   routeSurvey: pos.routeSurvey ?? false)
        switch facet.name {
        case "LEAD":      next = MpPositionsWire(leadEscort: !next.leadEscort, rearEscort: next.rearEscort, heightPole: next.heightPole, routeSurvey: next.routeSurvey)
        case "CHASE":     next = MpPositionsWire(leadEscort: next.leadEscort, rearEscort: !next.rearEscort, heightPole: next.heightPole, routeSurvey: next.routeSurvey)
        case "HIGH-POLE": next = MpPositionsWire(leadEscort: next.leadEscort, rearEscort: next.rearEscort, heightPole: !next.heightPole, routeSurvey: next.routeSurvey)
        case "SURVEY":    next = MpPositionsWire(leadEscort: next.leadEscort, rearEscort: next.rearEscort, heightPole: next.heightPole, routeSurvey: !next.routeSurvey)
        default:
            // NIGHT OPS is a certification column, not a profile toggle — read-only here.
            await MainActor.run { writeNotice = "Night ops comes from your certification, not this switch." }
            return
        }
        do {
            let _: MpUpdateResult = try await EusoTripAPI.shared.mutation(
                "escorts.updateProfile", input: MpUpdatePositionsInput(positions: next))
            await MainActor.run { writeNotice = "Saved to your profile." }
            await refreshAll()
        } catch {
            await MainActor.run {
                writeNotice = "Didn't save — check signal and retry. Nothing was queued."
            }
        }
    }
}

private enum EscortMeProfileError: Error { case empty }

/// `escorts.getCertificationStatus` takes no input.
private struct EmptyInput: Encodable {}

// MARK: - Screen wrapper (Shell + BottomNav)

struct EscortMeProfileScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortMeProfile()
        } nav: {
            BottomNav(
                leading: escortNavLeading_ES12(),
                trailing: escortNavTrailing_ES12(),
                orbState: .idle
            )
        }
    }
}

private func escortNavLeading_ES12() -> [NavSlot] {
    [NavSlot(label: "Trip",  systemImage: "house",                        isCurrent: false),
     NavSlot(label: "Comms", systemImage: "dot.radiowaves.left.and.right", isCurrent: false)]
}

private func escortNavTrailing_ES12() -> [NavSlot] {
    [NavSlot(label: "Permit", systemImage: "doc.badge.gearshape", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",              isCurrent: true)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so both variants render in the loading register
// without touching the network.

#Preview("ES-12 · Escort · Me — Profile & Settings · Dark") {
    EscortMeProfileScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("ES-12 · Escort · Me — Profile & Settings · Light") {
    EscortMeProfileScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
