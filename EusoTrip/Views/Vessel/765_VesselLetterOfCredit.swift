//
//  765_VesselLetterOfCredit.swift
//  EusoTrip — Vessel Operator · Letter of Credit (PRESENTATION-CHECKLIST + CHAIN).
//
//  Verbatim bespoke port of canonical wireframe "765 Vessel Letter of Credit
//  · Dark" (06 Vessel · Vessel Operator). Documentary-credit (UCP 600)
//  archetype, purpose-built as a document-presentation compliance checklist
//  (each required doc COMPLIANT/DISCREPANT with the article cite) over a
//  horizontal Issuing→Advising→Negotiating→Endorse-B/L bank chain —
//  deliberately DISTINCT from every B/L-title surface (005/715/719/679/718).
//  Catches an insurance-cover discrepancy before the bank endorses and cargo
//  releases.
//
//  Docked under COMPLIANCE (surfaced to the operator under SHIPMENTS).
//  transportMode=vessel · tri-country US·CA·MX.
//
//  REAL WIRING (tRPC):
//    · vesselShipments.listBOLs / getBOL -> the negotiable B/L under the
//      credit (server/routers/vesselShipments.ts:961/:944) — EXISTS. Anchors
//      the credit's underlying ocean bill.
//    · createBOLSignatureRequest (server/services/signatures.ts:475) +
//      services/bol.ts:326 back the endorsement/signature chain events.
//  STUB (handed to the-oath): lc.checkPresentation / lc.endorse — there is
//  no documentary-credit model server-wide (grep 'documentaryCredit' = 0).
//  The UCP-600 checklist + the bank chain render the certified reference
//  model, flagged in the section gap note — a wrong "complying" finding pays
//  out against bad docs, so the decision is human-gated, never auto-live.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselLetterOfCreditScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselLetterOfCreditBody()
        } nav: {
            BottomNav.vesselOperatorShipments()
        }
    }
}

// MARK: - Model

private struct LCDoc765: Identifiable {
    enum State { case compliant, discrepant }
    let id: String
    let name: String
    let cite: String
    let state: State
}

private struct BankNode765: Identifiable {
    enum State { case done, current, pending }
    let id: String
    let role: String
    let bank: String
    let state: State
}

// MARK: - Body

private struct VesselLetterOfCreditBody: View {
    @Environment(\.palette) private var palette

    @State private var bols: [VesselDocBOL] = []
    @State private var loading = true

    private var subjectBOL: VesselDocBOL? {
        bols.first(where: { ($0.bolType ?? "").lowercased() == "master" }) ?? bols.first
    }

    private let docs: [LCDoc765] = [
        .init(id: "invoice", name: "Commercial invoice",  cite: "art. 18 · amount matches LC",       state: .compliant),
        .init(id: "obl",     name: "Ocean bill of lading", cite: "art. 20 · clean on board · to order", state: .compliant),
        .init(id: "packing", name: "Packing list",        cite: "consistent · 1×40' HC reefer",       state: .compliant),
        .init(id: "origin",  name: "Certificate of origin", cite: "USMCA · matches goods desc",       state: .compliant),
        .init(id: "insure",  name: "Insurance certificate", cite: "art. 28 · cover 100%, LC needs 110%", state: .discrepant),
    ]

    private let chain: [BankNode765] = [
        .init(id: "issuing", role: "Issuing",     bank: "BoC",    state: .done),
        .init(id: "advising", role: "Advising",   bank: "DBS SG", state: .done),
        .init(id: "negotiate", role: "Negotiating", bank: "HSBC", state: .current),
        .init(id: "endorse", role: "Endorse B/L", bank: "to order", state: .pending),
    ]

    private var discrepancyCount: Int { docs.filter { $0.state == .discrepant }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDocTopBar(eyebrow: "VESSEL OPERATOR · LETTER OF CREDIT",
                            idCaption: "UCP 600 · BoC",
                            title: "Letter of credit")
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    VesselDocSkeleton(bodyHeight: 340)
                } else {
                    heroCard
                    presentationSection
                    chainSection
                    TriCountryAuthorityBand(title: "LC GOVERNING LAW · PRESENTING BANK",
                                            regimes: lawRegimes)
                    VesselDocCTAPair(primaryTitle: "Endorse & release",
                                     secondaryTitle: "Flag discrepancy",
                                     primaryIcon: "signature",
                                     primaryDisabled: discrepancyCount > 0,
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
                Text("LC IRREV-26-7741203 · sight credit")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("\(discrepancyCount) DISCREPANT")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Color(hex: 0xFFC246))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: 0xFFC246).opacity(0.16)))
            }
            Text(vesselDocCurrency(1_200_000))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .padding(.top, Space.s3)
            Text("Irrevocable · UCP 600 · payable at sight")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 3)
            Text("Issuing: Bank of China · expiry Jun 30")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Document presentation checklist

    private var presentationSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "DOCUMENT PRESENTATION · UCP 600",
                                right: subjectBOL != nil ? "B/L bound" : "reference")
            VStack(spacing: 0) {
                ForEach(Array(docs.enumerated()), id: \.element.id) { idx, d in
                    docRow(d)
                    if idx < docs.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            VesselDocGapNote(text: "Reference UCP-600 presentation. The discrepancy decision is human-gated; the automated presentation check lands with the documentary-credit endpoint.")
        }
    }

    private func docRow(_ d: LCDoc765) -> some View {
        let ok = d.state == .compliant
        let accent: Color = ok ? Brand.success : Color(hex: 0xFFC246)
        return HStack(spacing: Space.s3) {
            ZStack {
                if ok {
                    Circle().fill(Brand.success).frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black)).foregroundStyle(.white)
                } else {
                    Circle().stroke(accent, lineWidth: 2).frame(width: 18, height: 18)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 10, weight: .black)).foregroundStyle(accent)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(d.name)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(d.cite)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            Text(ok ? "COMPLIANT" : "DISCREPANT")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 11)
    }

    // MARK: Bank endorsement chain

    private var chainSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "BANK ENDORSEMENT CHAIN", right: "3 of 4")
            VStack(spacing: 0) {
                ZStack(alignment: .center) {
                    // Track + progress.
                    GeometryReader { geo in
                        let w = geo.size.width
                        Capsule().fill(palette.borderFaint)
                            .frame(height: 3)
                            .frame(maxHeight: .infinity, alignment: .center)
                        Capsule().fill(Brand.success)
                            .frame(width: w * 0.62, height: 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 22)
                    HStack(spacing: 0) {
                        ForEach(Array(chain.enumerated()), id: \.element.id) { idx, node in
                            chainNode(node)
                                .frame(maxWidth: .infinity,
                                       alignment: idx == 0 ? .leading : (idx == chain.count - 1 ? .trailing : .center))
                        }
                    }
                }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func chainNode(_ node: BankNode765) -> some View {
        VStack(spacing: 5) {
            Text(node.role)
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            ZStack {
                switch node.state {
                case .done:
                    Circle().fill(Brand.success).frame(width: 20, height: 20)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(.white)
                case .current:
                    Circle().fill(palette.bgCard).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(LinearGradient.primary, lineWidth: 2.5))
                    Circle().fill(LinearGradient.primary).frame(width: 8, height: 8)
                case .pending:
                    Circle().fill(palette.bgCard).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(palette.borderSoft, lineWidth: 2.5))
                }
            }
            Text(node.bank)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var lawRegimes: [CountryRegime] {
        [
            .init(code: "US", authority: "US · UCP 600 + UCC Art.5", detail: "USD", consequence: nil, state: .active),
            .init(code: "CA", authority: "CA · UCP 600 + bills of exch.", detail: "CAD", consequence: nil, state: .standby),
            .init(code: "MX", authority: "MX · UCP 600 + LGTOC", detail: "MXN", consequence: nil, state: .standby),
        ]
    }

    private func load() async {
        loading = true
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

#Preview("765 · Vessel Letter of Credit · Night") {
    VesselLetterOfCreditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("765 · Vessel Letter of Credit · Light") {
    VesselLetterOfCreditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
