//
//  605_RailCargoClaim.swift
//  EusoTrip — Rail Engineer · Cargo Claim (CARRIER-SIDE case-file).
//
//  Verbatim port of wireframe "605 Rail Cargo Claim · Dark".
//  Runs ONE intermodal cargo claim end to end: a case header (claim id +
//  subject + filed status + RAIL mode badge), an exposure ledger married to
//  the statutory Carmack burndown clock (days left to file), a PARTY CHAIN
//  triad (claimant Eusorone → carrier BNSF → all-risk insurer), an evidence
//  document tile shelf, an ESANG next-best-action advisory, and the
//  file-claim CTA.
//
//  Endpoint (REAL · tRPC freightClaims.ts, protectedProcedure):
//    • freightClaims.getClaims     — resolves the newest real claim when the
//      navigator injects no claimId (zero-fallback: no invented case id).
//    • freightClaims.getClaimById  — case header + parties + evidence +
//      workflow step (returns null when not found). Wired below.
//
//  ZERO-FALLBACK (2026-06-09): every cell renders live server data or an
//  em-dash. No invented amounts, lanes, parties, or evidence tiles.
//
//  WIRE-GAPs (server fields the case-file needs but getClaimById does NOT
//  return — every one renders as an em-dash, never a fabrication):
//    • freightClaims.getClaimById.amount        — hardcoded 0 server-side
//    • freightClaims.getClaimById.load.*        — loadNumber "-", empty lane
//    • freightClaims.getClaimById.shipper/carrier.name — hardcoded "-"
//    • freightClaims.getClaimById.evidence      — hardcoded []
//    • freightClaims.getClaimById.cargoValue    — field does not exist
//    • freightClaims.getClaimById.estRecovery   — field does not exist
//    • freightClaims.getClaimById.carmackDeadline — no field; the 270-day
//      countdown is derived client-side from filedDate (real createdAt)
//    • freightClaims.getClaimById.insurer       — no insurer party
//    • claims.subscribeStatus                   — proposed WS channel
//      Subscription<{claimId,status,estRecovery,daysToDeadline}> (not built)
//

import SwiftUI

struct RailCargoClaimScreen: View {
    let theme: Theme.Palette

    /// Claim id the case-file is opened against. Empty by default: the body
    /// resolves the newest REAL claim via freightClaims.getClaims so the
    /// screen never opens against an invented case id. Injected by the
    /// navigator when pushed from a claim row.
    var claimId: String = ""

    var body: some View {
        Shell(theme: theme) { RailCargoClaimBody(claimId: claimId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (decode the slice of freightClaims.getClaimById we render)

private struct RailClaimParty: Decodable {
    let id: String?
    let name: String?
    let contact: String?
    let email: String?
    let phone: String?
}

private struct RailClaimLoad: Decodable {
    let loadNumber: String?
    let origin: String?
    let destination: String?
    let commodity: String?
    let weight: Double?
}

private struct RailClaimEvidence: Decodable, Identifiable {
    let id: String
    let type: String?
    let name: String?
    let url: String?
    let uploadedAt: String?
}

private struct RailClaimWorkflowStep: Decodable, Identifiable {
    let step: Int
    let name: String?
    let completed: Bool?
    var id: Int { step }
}

private struct RailClaimWorkflow: Decodable {
    let currentStep: Int?
    let steps: [RailClaimWorkflowStep]?
}

private struct RailClaimDetail: Decodable {
    let id: String?
    let claimNumber: String?
    let type: String?
    let status: String?
    let description: String?
    let severity: String?
    let amount: Double?
    let filedDate: String?
    let load: RailClaimLoad?
    let shipper: RailClaimParty?
    let carrier: RailClaimParty?
    let evidence: [RailClaimEvidence]?
    let workflow: RailClaimWorkflow?
}

// MARK: - Body

private struct RailCargoClaimBody: View {
    let claimId: String

    @Environment(\.palette) private var palette
    @State private var claim: RailClaimDetail? = nil
    @State private var resolvedClaimId: String? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var filing = false
    @State private var fileAck: String? = nil
    @State private var esangLoading = false
    @State private var esangReply: String? = nil
    @State private var esangError: String? = nil
    @State private var esangSessionId: String? = nil

    // Statutory Carmack notice window — fixed 270 days. The wireframe shows
    // "188 of 270 days left". With no carmackDeadline field on the server
    // (PORT-GAP), the elapsed count is derived client-side from filedDate.
    private let carmackWindowDays: Int = 270

    private var filedDate: Date? {
        guard let s = claim?.filedDate, !s.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private var daysElapsed: Int {
        guard let filed = filedDate else { return 0 }
        let secs = Date().timeIntervalSince(filed)
        return max(0, Int(secs / 86_400))
    }

    private var daysLeft: Int { max(0, carmackWindowDays - daysElapsed) }

    private var deadlineDate: Date? {
        filedDate.map { $0.addingTimeInterval(Double(carmackWindowDays) * 86_400) }
    }

    private var deadlineLabel: String {
        guard let d = deadlineDate else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d yyyy"
        return f.string(from: d)
    }

    private var burndownFraction: CGFloat {
        guard carmackWindowDays > 0, filedDate != nil else { return 0 }
        return min(1, max(0, CGFloat(daysElapsed) / CGFloat(carmackWindowDays)))
    }

    private var claimNumber: String {
        claim?.claimNumber ?? resolvedClaimId ?? (claimId.isEmpty ? "—" : claimId)
    }

    /// Live money or em-dash. The server hardcodes amount: 0 on getClaimById
    /// (WIRE-GAP), so a zero is "the server can't answer" — em-dash, never a
    /// fabricated figure.
    private func money(_ v: Double?) -> String {
        guard let v, v > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(Int(v)))
    }

    /// Maps the server's "-" / "" stub sentinels to nil so stubs render as
    /// em-dashes instead of leaking sentinel hyphens into the case file.
    private func real(_ s: String?) -> String? {
        guard let s, !s.isEmpty, s != "-" else { return nil }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
                .padding(.top, Space.s3)

            if loading {
                loadingState
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            } else if claim == nil {
                EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                               title: claimNumber == "—" ? "No claims on file" : "Claim not found",
                               subtitle: claimNumber == "—"
                                   ? "File a cargo claim from a shipment to open a case file."
                                   : "No case file matches \(claimNumber).")
                    .padding(.top, Space.s7)
            } else {
                VStack(alignment: .leading, spacing: Space.s4) {
                    caseHeaderCard
                    exposureSection
                    partiesSection
                    evidenceSection
                    esangAdvisory
                    ctaPair
                    esangResponsePanel
                    if let ack = fileAck {
                        Text(ack).font(EType.caption).foregroundStyle(Brand.success)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                EusoTripEyebrow(verbatim: "RAIL ENGINEER · CARGO CLAIM")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(claimNumber)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Text("Cargo claim")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 96)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
    }

    // MARK: - Case header

    private var caseHeaderCard: some View {
        // Live or em-dash. The server stubs load.loadNumber to "-" and the
        // lane to "" on getClaimById (WIRE-GAP) — those render as em-dashes.
        let subject = real(claim?.description) ?? "—"
        let load = claim?.load
        let lane: String = {
            let o = real(load?.origin)
            let d = real(load?.destination)
            if o == nil && d == nil { return "—" }
            return "\(o ?? "—") → \(d ?? "—")"
        }()
        let loadNumber = real(load?.loadNumber) ?? "—"
        let statusText = (real(claim?.status) ?? "—").uppercased()
        let workflowStepLabel: String = {
            guard let wf = claim?.workflow,
                  let step = wf.currentStep,
                  let steps = wf.steps, !steps.isEmpty else { return "WORKFLOW · —" }
            let name = steps.first(where: { $0.step == step })?.name?.uppercased() ?? "STEP"
            return "\(name) · \(step) OF \(steps.count)"
        }()

        return HStack(alignment: .top, spacing: Space.s3) {
            // Amber accent bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Brand.warning)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(claimNumber)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    railModeBadge
                }
                Text(subject)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, Space.s5)
                Text("\(loadNumber) · \(lane)")
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, Space.s2)
                HStack(spacing: Space.s2) {
                    Text(statusText)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.warning.opacity(0.18)))
                    Text(workflowStepLabel)
                        .font(.system(size: 10, weight: .bold)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .padding(.top, Space.s3)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var railModeBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "tram.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
            Text("RAIL")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Brand.rail))
    }

    // MARK: - Exposure + Carmack window

    private var exposureSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("EXPOSURE · CARMACK WINDOW")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .top, spacing: 0) {
                    // Server hardcodes amount: 0 (WIRE-GAP) → em-dash via money().
                    ledgerCell(label: "CLAIMED", value: money(claim?.amount),
                               gradient: true)
                    ledgerDivider
                    // WIRE-GAP: freightClaims.getClaimById.cargoValue — no
                    // cargo declared value field on the server. Em-dash.
                    ledgerCell(label: "CARGO VALUE", value: "—",
                               valueColor: palette.textPrimary)
                    ledgerDivider
                    // WIRE-GAP: freightClaims.getClaimById.estRecovery — no
                    // recovery estimate field on the server. Em-dash.
                    ledgerCell(label: "RECOVERY EST", value: "—",
                               valueColor: Brand.success)
                }

                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(filedDate != nil
                         ? "\(daysLeft) of \(carmackWindowDays) days left to file · deadline \(deadlineLabel)"
                         : "Filing window — · no filed date on record")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 8)
                            Capsule()
                                .fill(Brand.warning)
                                .frame(width: geo.size.width * burndownFraction, height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func ledgerCell(label: String, value: String,
                            gradient: Bool = false,
                            valueColor: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Group {
                if gradient {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(valueColor)
                }
            }
            .font(.system(size: 20, weight: .bold))
            .monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ledgerDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 42)
    }

    // MARK: - Party chain

    private var partiesSection: some View {
        // Server stubs shipper/carrier name to "-" (WIRE-GAP) → em-dash.
        let claimant = real(claim?.shipper?.name) ?? "—"
        let carrier  = real(claim?.carrier?.name) ?? "—"

        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("PARTIES")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            HStack(spacing: 0) {
                partyNode(label: "CLAIMANT", name: claimant) {
                    Circle().fill(LinearGradient.diagonal)
                        .overlay(Text(initials(claimant))
                            .font(.system(size: 14, weight: .bold)).tracking(0.4)
                            .foregroundStyle(.white))
                }
                chainArrow
                partyNode(label: "CARRIER", name: carrier) {
                    Circle().fill(Brand.rail)
                        .overlay(Image(systemName: "tram.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white))
                }
                chainArrow
                // WIRE-GAP: freightClaims.getClaimById.insurer — no insurer
                // party on the server payload. Em-dash, never an invented
                // insurer or certificate number.
                partyNode(label: "INSURER", name: "—") {
                    Circle().fill(Brand.info)
                        .overlay(Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white))
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func partyNode<Glyph: View>(label: String, name: String,
                                        @ViewBuilder glyph: () -> Glyph) -> some View {
        VStack(spacing: Space.s2) {
            glyph()
                .frame(width: 48, height: 48)
            Text(name)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var chainArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.textTertiary)
            .frame(width: 20)
            .padding(.bottom, 28)
    }

    private func initials(_ s: String) -> String {
        guard s != "—" else { return "—" }
        let parts = s.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map { String($0) }
        let joined = chars.joined().uppercased()
        return joined.isEmpty ? "—" : joined
    }

    // MARK: - Evidence shelf

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("EVIDENCE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            let serverTiles = (claim?.evidence ?? []).prefix(4).map { ev in
                EvidenceTile(icon: evidenceIcon(ev.type),
                             tint: evidenceTint(ev.type),
                             title: ev.name ?? (ev.type ?? "Document").capitalized,
                             detail: ev.uploadedAt.map { _ in "filed" } ?? "attached",
                             detailColor: Brand.success)
            }

            if serverTiles.isEmpty {
                // WIRE-GAP: getClaimById hardcodes evidence: [] server-side.
                // Honest empty shelf — never the wireframe's fabricated tiles.
                HStack(spacing: Space.s3) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Text("No evidence attached yet")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                HStack(spacing: Space.s2) {
                    ForEach(Array(serverTiles.enumerated()), id: \.offset) { _, tile in
                        tile
                    }
                }
            }
        }
    }

    private func evidenceIcon(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "photo", "damage", "image": return "camera.fill"
        case "osd", "os&d":              return "doc.text.fill"
        case "bol":                      return "doc.plaintext.fill"
        case "cert", "certificate":      return "checkmark.shield.fill"
        default:                         return "paperclip"
        }
    }

    private func evidenceTint(_ type: String?) -> Color {
        switch (type ?? "").lowercased() {
        case "photo", "damage", "image": return Color(hex: 0x5AB0FF)
        case "bol":                      return Brand.warning
        default:                         return Brand.success
        }
    }

    // MARK: - ESANG advisory

    private var esangAdvisory: some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Text(filedDate != nil
                     ? "File before the Carmack window closes — \(daysLeft)d left."
                     : "No filed date on record — filing window unknown.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Attach BOL, OS&D, and damage photos to substantiate recovery.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "File claim",
                      action: { Task { await fileClaim() } },
                      isLoading: filing)
            Button {
                Task { await messageESang() }
            } label: {
                HStack(spacing: 8) {
                    if esangLoading {
                        ProgressView().controlSize(.small)
                    }
                    Text(esangLoading ? "Asking ESang" : "Message ESang")
                }
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(esangLoading || claim == nil)
        }
    }

    @ViewBuilder
    private var esangResponsePanel: some View {
        if let esangError {
            LifecycleCard(accentDanger: true) {
                Text(esangError)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let esangReply {
            LifecycleCard {
                HStack(alignment: .top, spacing: Space.s3) {
                    OrbeSang(state: .idle, diameter: 34)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ESANG RESPONSE")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.primary)
                        Text(esangReply)
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct Input: Encodable { let id: String }
        struct ListInput: Encodable { let limit: Int; let offset: Int }
        struct ClaimRow: Decodable { let id: String? }
        struct ClaimsPage: Decodable { let claims: [ClaimRow]? }
        do {
            // Resolve a REAL claim id when none was injected: newest claim
            // first (freightClaims.getClaims orders by createdAt desc). No
            // invented case id, ever.
            var targetId = claimId
            if targetId.isEmpty {
                let page: ClaimsPage = try await EusoTripAPI.shared.query(
                    "freightClaims.getClaims", input: ListInput(limit: 1, offset: 0))
                if let newest = page.claims?.first?.id, !newest.isEmpty {
                    targetId = newest
                } else {
                    // Honest empty: no claims on file.
                    self.claim = nil
                    self.resolvedClaimId = nil
                    loading = false
                    return
                }
            }
            self.resolvedClaimId = targetId
            // freightClaims.getClaimById — returns null when not found, so
            // decode as Optional to avoid a decode error on a missing case.
            let result: RailClaimDetail? = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimById", input: Input(id: targetId))
            self.claim = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - File claim (primary CTA → freightClaims.fileClaim)

    private func fileClaim() async {
        guard let load = claim?.load else { return }
        // Honest gate: the server stubs load.loadNumber to "-" on getClaimById
        // (WIRE-GAP). Filing against an invented load id would fabricate a
        // legal record — refuse with the real reason instead.
        guard let loadNumber = real(load.loadNumber) else {
            loadError = "No load is linked to this claim — it cannot be filed."
            return
        }
        filing = true; fileAck = nil
        struct Input: Encodable {
            let loadId: String
            let type: String
            let amount: Double
            let description: String
            let commodity: String?
            let damageExtent: String?
        }
        struct Result: Decodable { let id: Int?; let status: String?; let claimNumber: String? }
        do {
            let res: Result = try await EusoTripAPI.shared.mutation(
                "freightClaims.fileClaim",
                input: Input(
                    loadId: loadNumber,
                    type: claim?.type ?? "damage",
                    amount: claim?.amount ?? 0,
                    description: real(claim?.description) ?? "",
                    commodity: load.commodity,
                    damageExtent: claim?.severity
                ))
            fileAck = "Claim filed · \(res.claimNumber ?? res.status ?? "submitted")"
            await reload()
        } catch {
            fileAck = nil
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        filing = false
    }

    // MARK: - ESANG claim context

    private func messageESang() async {
        guard let claim else { return }
        esangLoading = true
        esangError = nil
        esangReply = nil
        struct Input: Encodable {
            let message: String
            let sessionId: String?
            let feature: String
        }
        struct Output: Decodable {
            let message: String?
            let sessionId: String?
        }
        do {
            let out: Output = try await EusoTripAPI.shared.mutation(
                "esangAIv2.chat",
                input: Input(message: esangPrompt(for: claim),
                             sessionId: esangSessionId,
                             feature: "rail_cargo_claim")
            )
            esangSessionId = out.sessionId
            esangReply = out.message ?? "ESang returned no guidance for this claim."
        } catch {
            esangError = esangFailureCopy(error)
        }
        esangLoading = false
    }

    /// Operator-language copy for a failed ESang request.
    ///
    /// A raw `NSError` string ("EusoTripAPIError error 5") tells a claims
    /// handler nothing they can act on, so each failure class is mapped to
    /// the sentence that says what happened and what to do next. Refusal
    /// reasons that already carry human copy are surfaced verbatim.
    private func esangFailureCopy(_ error: Error) -> String {
        guard let api = error as? EusoTripAPIError else {
            if (error as NSError).domain == NSURLErrorDomain {
                return "No connection reached ESang. Check your signal, then ask again."
            }
            return "ESang couldn't answer that. Ask again in a moment."
        }
        switch api {
        case .unauthenticated:
            return "Your session expired before ESang could answer. Sign in again, then ask about this claim."
        case .forbidden(let reason):
            return reason
        case .trpcError(let reason):
            return reason
        case .httpStatus(let code, _):
            return "ESang is unavailable right now (\(code)). Ask again in a moment."
        case .decodingFailed:
            return "ESang replied in a form this app version can't read. Update the app, then ask again."
        case .empty:
            return "ESang returned nothing for this claim. Ask again in a moment."
        case .notConfigured, .badURL:
            return "ESang isn't reachable from this build. Restart the app, then try again."
        case .queuedForOfflineReplay:
            return "You're offline — ESang can't answer until you reconnect."
        }
    }

    private func esangPrompt(for claim: RailClaimDetail) -> String {
        let load = claim.load
        let origin = real(load?.origin) ?? "unknown origin"
        let destination = real(load?.destination) ?? "unknown destination"
        let evidenceCount = claim.evidence?.count ?? 0
        return """
        Review this rail cargo claim and give the next best action in plain operational language.
        Claim: \(claimNumber)
        Status: \(real(claim.status) ?? "unknown")
        Type: \(real(claim.type) ?? "unknown")
        Severity: \(real(claim.severity) ?? "unknown")
        Description: \(real(claim.description) ?? "not recorded")
        Claimed amount: \(money(claim.amount))
        Filed date: \(claim.filedDate ?? "not recorded")
        Carmack days left: \(filedDate == nil ? "unknown" : "\(daysLeft)")
        Lane: \(origin) to \(destination)
        Commodity: \(real(load?.commodity) ?? "not recorded")
        Evidence files: \(evidenceCount)
        Tell the user what to attach next, whether the filing window is urgent, and what role should act next. Do not invent missing amounts, parties, lanes, or evidence.
        """
    }
}

// MARK: - Evidence tile primitive

private struct EvidenceTile: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let detailColor: Color
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Spacer(minLength: Space.s2)
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(detailColor)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview("605 · Rail Cargo Claim · Night") { RailCargoClaimScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("605 · Rail Cargo Claim · Light") { RailCargoClaimScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
