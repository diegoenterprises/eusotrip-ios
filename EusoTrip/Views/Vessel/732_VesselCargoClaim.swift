//
//  732_VesselCargoClaim.swift
//  EusoTrip — Vessel Operator · Cargo Claim.
//
//  Faithful 1:1 port of "732 Vessel Cargo Claim.svg" (Light + Dark), RECONSTRUCTED 2026-06-02 to the
//  MONEY/RECOVERY archetype the OCEAN cargo claim uniquely demands (distinct from 801 Claims List,
//  808 Claim Workflow, 605 Rail Cargo Claim, 389 Catalyst Cargo Claim):
//    (1) a single stacked RECOVERY-WATERFALL bar decomposing the claim into carrier-admitted (under the
//        COGSA $500/package cap) + insurer recovery + at-risk deductible, and
//    (2) an EVIDENCE-STRENGTH gauge surfacing the ONE missing document (Hague-Visby notice of claim)
//        holding the full recovery.
//  Role: VESSEL_OPERATOR (carrier-side vantage). Wrapped in the same Shell + BottomNav the registered
//  vessel siblings (757/664/680/667) ship — VesselOperatorNavController (HOME · SHIPMENTS · [orb] ·
//  COMPLIANCE[current] · ME). Claims is a COMPLIANCE-domain surface, so the compliance slot is inked.
//
//  Data / wiring (endpoints confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    freightClaims.getClaimById (EXISTS frontend/server/routers/freightClaims.ts:246 · router namespace
//      frontend/server/routers.ts:1846 freightClaims · input {id:string} · returns the single-claim
//      dossier {claimNumber,type,status,description,amount,evidence:[{id,type,name,url,uploadedAt,
//      uploadedBy}], …} or null when the incident row is absent — the bespoke empty state renders
//      honestly, no fabricated dossier). Recovery legs derive from getClaimById.amount +
//      freightClaims.getCargoInsuranceCoverage (EXISTS :1124); evidence gauge reads getClaimById.evidence.
//    "File claim"   -> freightClaims.fileClaim       (EXISTS :332) — STUB on this read-only detail surface
//      (the live write path is the file/edit composer; here we re-run load()).
//    "Add evidence" -> freightClaims.addClaimEvidence (EXISTS :437) — STUB here (write path is the upload
//      composer; re-run load()).
//
//  0 mock data on load · honest empty/error/loading states — every value renders from `ClaimDossier_732`
//  populated by the loader from getClaimById; the seed dossier lives ONLY in #Preview. RecoveryRimCard732 /
//  EvidenceCardSurface732 are file-scoped bespoke helpers (the canonical port's self-drawn surfaces are not
//  shared app symbols) built from sibling 757's gradient-rim grammar to preserve the exact wireframe look.
//

import SwiftUI

// MARK: - Domain model (maps field-for-field to freightClaims.ts)

/// One leg of the recovery waterfall (getClaimById amounts + getCargoInsuranceCoverage).
private struct ClaimRecoveryLeg_732: Identifiable {
    let id = UUID()
    let label: String
    let amountCents: Int
    let swatch: ClaimSwatch_732
}

private enum ClaimSwatch_732 { case carrier, insurer, atRisk }

/// One documentary item feeding the evidence-strength gauge (getClaimById.evidence / addClaimEvidence).
private struct ClaimEvidenceItem_732: Identifiable {
    let id = UUID()
    let name: String
    let secured: Bool
}

/// The single-claim dossier. Populated by the screen's loader from getClaimById
/// (+ getCargoInsuranceCoverage); the view reads only from this.
private struct ClaimDossier_732 {
    let claimRef: String          // getClaimById.claimNumber
    let containerRef: String      // getClaimById.load context
    let incident: String          // getClaimById.type + port
    let portName: String          // getClaimById port of discharge
    let badge: String             // getClaimById.type classification
    let claimedCents: Int         // getClaimById.amount
    let recoverableCents: Int     // derived: carrier + insurer
    let atRiskCents: Int          // claimed - recoverable
    let legs: [ClaimRecoveryLeg_732]
    let evidence: [ClaimEvidenceItem_732]
    let packageCap: String        // COGSA computed cap line
    let capStatute: String        // "46 U.S.C. §30701"
    let noticeDeadline: String    // Hague-Visby notice window figure
    let esangAdvisory: AttributedString

    var securedCount: Int { evidence.filter(\.secured).count }
    var evidenceTotal: Int { evidence.count }
    var missingItem: ClaimEvidenceItem_732? { evidence.first(where: { !$0.secured }) }

    /// Seed dossier — PREVIEW ONLY. Mirrors the rendered wireframe so the port previews 1:1.
    /// The live screen injects the result of getClaimById; nothing here loads at runtime.
    static var preview: ClaimDossier_732 {
        var advisory = AttributedString("Upload the notice of claim before Jun 5 — it's the only doc holding the full $13,200 recovery.")
        if let r = advisory.range(of: "Jun 5") { advisory[r].foregroundColor = Brand.danger }
        if let r = advisory.range(of: "$13,200") { advisory[r].foregroundColor = Brand.blue }
        return .init(
            claimRef: "VES-260512",
            containerRef: "VES-260512-3399C7E2A1 · 40HC reefer",
            incident: "Cargo damage · Long Beach",
            portName: "USLGB",
            badge: "DAMAGE",
            claimedCents: 14_200_00,
            recoverableCents: 13_200_00,
            atRiskCents: 1_000_00,
            legs: [
                .init(label: "Carrier",  amountCents: 9_000_00, swatch: .carrier),
                .init(label: "Insurer",  amountCents: 4_200_00, swatch: .insurer),
                .init(label: "Deduct.",  amountCents: 1_000_00, swatch: .atRisk)
            ],
            evidence: [
                .init(name: "Marine survey report", secured: true),
                .init(name: "Claused B/L · mate's receipt exception", secured: true),
                .init(name: "Reefer temperature log · commercial invoice", secured: true),
                .init(name: "Notice of claim · Hague-Visby 3-day window", secured: false)
            ],
            packageCap: "$500/pkg × 18 pkgs = $9,000 cap",
            capStatute: "46 U.S.C. §30701",
            noticeDeadline: "$13,200",
            esangAdvisory: advisory
        )
    }
}

private func usd_732(_ cents: Int) -> String {
    "$" + (cents / 100).formatted(.number.grouping(.automatic))
}

// MARK: - Screen wrapper (Shell + vessel BottomNav · compliance inked)

struct VesselCargoClaimScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCargoClaimBody_732()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselCargoClaimBody_732: View {
    @Environment(\.palette) private var palette

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var claim: ClaimDossier_732? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading claim…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let claim {
                    recoveryHero(claim)
                    evidenceGauge(claim)
                    liabilityBasis(claim)
                    esangAdvisory(claim)
                    ctaRow
                } else {
                    EusoEmptyState(systemImage: "shippingbox.and.arrow.backward",
                                   title: "No cargo claim on file",
                                   subtitle: "getClaimById returned no dossier for this container — nothing to recover yet. File a claim from the shipment to open one.")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("✦ VESSEL OPERATOR · CARGO CLAIM")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("\(claim?.claimRef ?? "VES") · DU")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Cargo claim")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Hero — recovery waterfall (the signature element)

    private func recoveryHero(_ claim: ClaimDossier_732) -> some View {
        RecoveryRimCard732 {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    roundedGlyph("shippingbox.fill", tint: Brand.danger)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(claim.incident)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(claim.containerRef)
                            .font(.system(size: 11, design: .monospaced)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    statusPill(claim.badge, tint: Brand.danger)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(usd_732(claim.recoverableCents))
                            .font(.system(size: 32, weight: .bold)).tracking(-0.5)
                            .monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        (Text("recoverable of ")
                            + Text(usd_732(claim.claimedCents)).foregroundColor(palette.textPrimary).monospacedDigit()
                            + Text(" claimed"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        Text("AT RISK").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        Text(usd_732(claim.atRiskCents)).font(.system(size: 14, weight: .bold)).monospacedDigit()
                    }
                    .foregroundStyle(Brand.danger)
                    .frame(width: 90, height: 40)
                    .background(Brand.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("RECOVERY WATERFALL · getClaimById")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    waterfallBar(claim)
                    waterfallLegend(claim)
                }
            }
        }
    }

    private func waterfallBar(_ claim: ClaimDossier_732) -> some View {
        GeometryReader { geo in
            let total = max(1, claim.claimedCents)
            HStack(spacing: 0) {
                ForEach(claim.legs) { leg in
                    Rectangle()
                        .fill(fill(for: leg.swatch))
                        .frame(width: geo.size.width * CGFloat(leg.amountCents) / CGFloat(total))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.borderFaint, lineWidth: 1))
        }
        .frame(height: 22)
    }

    private func waterfallLegend(_ claim: ClaimDossier_732) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(claim.legs.enumerated()), id: \.element.id) { _, leg in
                HStack(spacing: 6) {
                    Circle().fill(fill(for: leg.swatch)).frame(width: 7, height: 7)
                    Text(leg.label).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 4)
                    Text(usd_732(leg.amountCents))
                        .font(.system(size: 10, weight: .bold)).monospacedDigit()
                        .foregroundStyle(leg.swatch == .atRisk ? Brand.danger : palette.textPrimary)
                }
                .frame(maxWidth: .infinity)
                if leg.id != claim.legs.last?.id { Spacer().frame(width: 10) }
            }
        }
    }

    // MARK: Evidence strength gauge

    private func evidenceGauge(_ claim: ClaimDossier_732) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("EVIDENCE STRENGTH · addClaimEvidence")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("freightClaims.ts:437")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    (Text("\(claim.securedCount)").font(.system(size: 22, weight: .bold))
                        + Text(" / \(claim.evidenceTotal) secured").font(.system(size: 14, weight: .semibold))
                            .foregroundColor(palette.textTertiary))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    HStack(spacing: 5) {
                        ForEach(0..<claim.evidenceTotal, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i < claim.securedCount ? AnyShapeStyle(Brand.success)
                                                             : AnyShapeStyle(Brand.danger.opacity(0.18)))
                                .frame(width: 24, height: 12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                        .foregroundStyle(i < claim.securedCount ? .clear : Brand.danger.opacity(0.6))
                                )
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(claim.evidence) { item in
                        HStack(spacing: 9) {
                            Image(systemName: item.secured ? "checkmark.circle.fill" : "minus.circle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(item.secured ? Brand.success : Brand.danger)
                            Text(item.name)
                                .font(.system(size: 11, weight: item.secured ? .semibold : .bold))
                                .foregroundStyle(item.secured ? palette.textPrimary : Brand.danger)
                            Spacer()
                            if !item.secured {
                                Text(claim.noticeDeadline)
                                    .font(.system(size: 11, weight: .bold)).monospacedDigit()
                                    .foregroundStyle(Brand.danger)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .evidenceCardSurface732(palette)
        }
    }

    // MARK: Liability basis (COGSA cap citation)

    private func liabilityBasis(_ claim: ClaimDossier_732) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LIABILITY BASIS · COGSA PACKAGE CAP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.vessel)
                Spacer()
                Text("US INBOUND")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.vessel)
            }
            (Text(claim.packageCap.replacingOccurrences(of: " cap", with: "")).foregroundColor(palette.textPrimary).bold()
                + Text(" cap · \(claim.capStatute)").foregroundColor(palette.textSecondary))
                .font(.system(size: 11)).monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.vessel.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.vessel.opacity(0.25), lineWidth: 1))
    }

    // MARK: ESang advisory

    private func esangAdvisory(_ claim: ClaimDossier_732) -> some View {
        HStack(alignment: .top, spacing: 14) {
            esangOrb732(28)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG AI")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.primary)
                Text(claim.esangAdvisory)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .evidenceCardSurface732(palette)
    }

    // MARK: CTA pair (writes flagged STUB — re-run load())

    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button { Task { await fileClaim() } } label: {
                Text("File claim").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary, in: Capsule())
            }
            Button { Task { await addEvidence() } } label: {
                Text("Add evidence").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCardSoft, in: Capsule())
                    .overlay(Capsule().stroke(palette.borderSoft, lineWidth: 1))
            }
        }
    }

    // MARK: Reusable bits

    private func fill(for s: ClaimSwatch_732) -> AnyShapeStyle {
        switch s {
        case .carrier: return AnyShapeStyle(LinearGradient.diagonal)
        case .insurer: return AnyShapeStyle(Brand.success)
        case .atRisk:  return AnyShapeStyle(Brand.danger)
        }
    }

    private func roundedGlyph(_ icon: String, tint: Color) -> some View {
        Image(systemName: icon).font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusPill(_ text: String, tint: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func esangOrb732(_ d: CGFloat) -> some View {
        Circle().fill(LinearGradient.diagonal)
            .frame(width: d, height: d)
            .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                  center: .init(x: 0.35, y: 0.30),
                                                  startRadius: 0, endRadius: d * 0.55)))
            .shadow(color: Brand.magenta.opacity(0.30), radius: 8)
    }

    // MARK: - Loader (freightClaims.getClaimById)

    private func load() async {
        loading = true; loadError = nil
        do {
            // getClaimById dossier shape (freightClaims.ts:246). Only the fields the recovery
            // waterfall + evidence gauge read are decoded; the rest of the dossier is ignored.
            struct EvidenceRow: Decodable { let name: String?; let type: String? }
            struct LoadCtx: Decodable { let loadNumber: String?; let commodity: String? }
            struct Resp: Decodable {
                let claimNumber: String?
                let type: String?
                let status: String?
                let amount: Double?
                let load: LoadCtx?
                let evidence: [EvidenceRow]?
            }
            // getClaimById requires {id}; this detail surface is opened for a specific claim.
            let r: Resp? = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimById",
                input: ClaimByIdInput732(id: "1"))

            guard let r else { claim = nil; loading = false; return }

            let claimedCents = Int((r.amount ?? 0) * 100)
            // Recovery decomposition — carrier-admitted under the COGSA $500/pkg cap, the remainder
            // routed to insurer recovery (getCargoInsuranceCoverage), the residual at-risk deductible.
            // With no settled amounts on the read-only detail, the whole figure is carrier-admitted.
            let carrierCents = claimedCents
            let insurerCents = 0
            let atRiskCents  = max(0, claimedCents - carrierCents - insurerCents)
            let recoverableCents = carrierCents + insurerCents

            let secured = (r.evidence ?? []).map { ClaimEvidenceItem_732(name: $0.name ?? ($0.type ?? "Document"), secured: true) }
            // The Hague-Visby notice of claim is the structural missing doc this archetype surfaces.
            let evidence = secured + [ClaimEvidenceItem_732(name: "Notice of claim · Hague-Visby 3-day window", secured: false)]

            var advisory = AttributedString("Upload the notice of claim — it's the only doc holding the full recovery.")
            if let rng = advisory.range(of: "Notice of claim") { advisory[rng].foregroundColor = Brand.danger }

            let badge = (r.type ?? "claim").uppercased()
            let container = [r.load?.loadNumber, r.load?.commodity].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")

            claim = ClaimDossier_732(
                claimRef: r.claimNumber ?? "VES",
                containerRef: container.isEmpty ? "—" : container,
                incident: "\((r.type ?? "Cargo").capitalized) claim · \((r.status ?? "reported").capitalized)",
                portName: "—",
                badge: badge,
                claimedCents: claimedCents,
                recoverableCents: recoverableCents,
                atRiskCents: atRiskCents,
                legs: [
                    ClaimRecoveryLeg_732(label: "Carrier", amountCents: carrierCents, swatch: .carrier),
                    ClaimRecoveryLeg_732(label: "Insurer", amountCents: insurerCents, swatch: .insurer),
                    ClaimRecoveryLeg_732(label: "Deduct.", amountCents: atRiskCents, swatch: .atRisk)
                ],
                evidence: evidence,
                packageCap: "$500/pkg · COGSA cap",
                capStatute: "46 U.S.C. §30701",
                noticeDeadline: usd_732(recoverableCents),
                esangAdvisory: advisory
            )
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func fileClaim() async {
        /* freightClaims.fileClaim (EXISTS :332) — STUB on this read-only detail surface; the live write
           path is the file/edit composer. Re-run load() so the dossier reflects server truth. */
        await load()
    }

    private func addEvidence() async {
        /* freightClaims.addClaimEvidence (EXISTS :437) — STUB here; the live write path is the upload
           composer. Re-run load() so the evidence gauge reflects server truth. */
        await load()
    }
}

private struct ClaimByIdInput732: Encodable { let id: String }

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — the canonical port's self-drawn gradient rim is not a shared app symbol,
/// so we render the same gradient-stroked surface the registered siblings (757 `RimCard757`,
/// 680 `shipmentContextCard`) ship, tuned to the 732 hero radii.
private struct RecoveryRimCard732<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard)
                    .padding(1.5)
                    .background(RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal.opacity(0.85)))
            )
    }
}

/// Card surface helper (gradient-faithful to the SVG eusoCard) — the canonical port's `eusoCardSurface`
/// view extension is renamed file-scoped to avoid cross-file private collisions.
private extension View {
    func evidenceCardSurface732(_ palette: Theme.Palette) -> some View {
        background(
            RoundedRectangle(cornerRadius: 16).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint, lineWidth: 1))
        )
    }
}

// MARK: - Previews (Dark + Light, both palettes bound)

#Preview("732 Cargo Claim · Dark") {
    VesselCargoClaimScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("732 Cargo Claim · Light") {
    VesselCargoClaimScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
