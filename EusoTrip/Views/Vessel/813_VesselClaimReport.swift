//
//  813_VesselClaimReport.swift
//  EusoTrip — Vessel Operator · Claim Report.
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/813 Vessel Claim Report.svg" (Light + Dark),
//  built on the canonical DesignSystem (Shell · BottomNav · Theme.Palette · CTAButton ·
//  IridescentHairline) at the golden-era bar. Archetype = REPORT-BUILDER (NOT the money-board
//  skeleton): a claim-summary card, a FORMAT selector, a PURPOSE selector, REPORT-CONTENTS toggle
//  rows, then the CTA pair. Role VESSEL_OPERATOR (carrier-side). Nav anchored to
//  VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME) — an
//  export/compliance surface, so the COMPLIANCE slot is inked.
//
//  Data / wiring (endpoints confirmed on disk this fire):
//    freightClaims.getClaimById   EXISTS frontend/server/routers/freightClaims.ts:523 · query ·
//      input {id:string} · returns {id, claimNumber, type, status, description, amount, ...}. Fills
//      the summary card when a claim is threaded (claimId). Zero-arg use renders the honest empty
//      summary — never a fabricated claim.
//    freightClaims.generateClaimReport EXISTS freightClaims.ts:3269 · mutation ·
//      input {claimId:string, format:"pdf"|"csv"|"xlsx", includeEvidence:Bool, includeTimeline:Bool,
//      includeFinancials:Bool, purpose:"insurance"|"legal"|"internal"|"regulatory"} · returns
//      {success, reportId, filename, contentType, content, generatedAt, expiresAt}. Wired to
//      "Generate claim report". HONEST server limit: the resolver renders CSV only today (PDF/XLSX
//      are queued to the document service) — the CSV-only server message is surfaced verbatim, never
//      swallowed. RBAC isolatedApprovedProcedure (approved, tenant-scoped).
//    Governing-law ledger = published cargo-liability regimes by discharge country (US COGSA/Hague ·
//      CA Marine Liability Act/Hague-Visby · MX LNCM/Hamburg) — regulatory reference constants, not
//      tenant data. STUB · named-gap handed to the-oath: vessel.getClaimRegime({claimId,country}).
//
//  ClaimSummary813 / ReportFormat813 / ReportPurpose813 are file-scoped bespoke types suffixed by
//  the screen number to avoid cross-file collisions. Dark + Light #Preview.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes

/// `freightClaims.getClaimById` -> permissive subset the summary card reads.
private struct ClaimSummary813: Decodable {
    let id: String?
    let claimNumber: String?
    let type: String?
    let status: String?
    let amount: Double?
    let description: String?
}

private struct GenerateReport813: Decodable {
    let success: Bool?
    let reportId: String?
    let filename: String?
    let expiresAt: String?
}

private enum ReportFormat813: String, CaseIterable, Identifiable {
    case pdf, csv, xlsx
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

private enum ReportPurpose813: String, CaseIterable, Identifiable {
    case insurance, legal, `internal`, regulatory
    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

// MARK: - Screen wrapper (Shell + vessel nav · COMPLIANCE inked)

struct VesselClaimReportScreen: View {
    let theme: Theme.Palette
    /// The claim this report is built for. Empty (registry / zero-arg) means "no claim threaded":
    /// the summary renders an honest empty state and Generate stays disabled until a claim is opened.
    var claimId: String

    init(theme: Theme.Palette, claimId: String = "") {
        self.theme = theme
        self.claimId = claimId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselClaimReportBody813(claimId: claimId)
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

private struct VesselClaimReportBody813: View {
    @Environment(\.palette) private var palette
    let claimId: String

    @State private var summary: ClaimSummary813? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var format: ReportFormat813 = .pdf
    @State private var purpose: ReportPurpose813 = .insurance
    @State private var includeEvidence = true
    @State private var includeTimeline = true
    @State private var includeFinancials = true

    @State private var generating = false
    @State private var genDone: String? = nil
    @State private var genError: String? = nil

    private var hasClaim: Bool { !claimId.isEmpty }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                topBar
                IridescentHairline()
                summaryCard
                formatSection
                purposeSection
                contentsSection
                actionRow
                esangCard
                governingLawLedger
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Eyebrow + top bar

    private var eyebrow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · CLAIM REPORT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text(summary?.claimNumber ?? (hasClaim ? claimId : "—"))
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Claim report")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("EXPORT").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("\(format.label) · \(purpose.rawValue)")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Claim summary card (gradient-rim)

    private var summaryCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            if loading {
                HStack { ProgressView().tint(Brand.magenta); Spacer() }.padding(Space.s5)
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary?.claimNumber ?? (hasClaim ? claimId : "No claim threaded"))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                        Text(hasClaim
                             ? "\(claimTypeLabel) · link expires in 1h"
                             : "Open this from a claim to build its report")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Space.s3)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(claimValueText)
                            .font(.system(size: 20, weight: .bold, design: .monospaced)).tracking(-0.4)
                            .foregroundStyle(hasClaim ? AnyShapeStyle(LinearGradient.diagonal)
                                                      : AnyShapeStyle(palette.textTertiary))
                        Text("CLAIM VALUE").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .padding(Space.s4)
            }
        }
        .frame(height: 76)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var claimTypeLabel: String {
        let t = (summary?.type ?? "cargo").replacingOccurrences(of: "_", with: " ")
        return t.contains("claim") ? t : "\(t) claim"
    }
    private var claimValueText: String {
        guard hasClaim else { return "—" }
        guard let a = summary?.amount else { return "$—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: a)) ?? String(Int(a)))
    }

    // MARK: FORMAT

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FORMAT")
            segmented(ReportFormat813.allCases, selected: format, label: { $0.label }) { format = $0 }
            Text("CSV export is live now · PDF/XLSX render through the document service.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: PURPOSE

    private var purposeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("PURPOSE")
            segmented(ReportPurpose813.allCases, selected: purpose, label: { $0.label }) { purpose = $0 }
        }
    }

    // Generic segmented control matching the SVG pill selector.
    private func segmented<T: Identifiable & Equatable>(
        _ items: [T], selected: T, label: @escaping (T) -> String, onPick: @escaping (T) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let isOn = item == selected
                Button(action: { onPick(item) }) {
                    Text(label(item))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isOn ? Color.white : palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            Group {
                                if isOn { LinearGradient.primary } else { Color.clear }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: REPORT CONTENTS

    private var contentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("REPORT CONTENTS")
            VStack(spacing: 0) {
                toggleRow(icon: "photo.stack", tint: Brand.escort,
                          title: "Evidence pack", sub: "Photos · inspection report · seal log",
                          isOn: $includeEvidence)
                divider
                toggleRow(icon: "clock.arrow.circlepath", tint: Brand.info,
                          title: "Timeline", sub: "All status transitions & events",
                          isOn: $includeTimeline)
                divider
                toggleRow(icon: "dollarsign.square", tint: Brand.success,
                          title: "Financials", sub: "Claim value · payments · recovery",
                          isOn: $includeFinancials)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func toggleRow(icon: String, tint: Color, title: String, sub: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(sub).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Toggle("", isOn: isOn).labelsHidden().tint(Brand.blue)
        }
        .padding(Space.s4)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 68)
    }

    // MARK: Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = genError { Text(e).font(EType.caption).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true) }
            if let d = genDone { Text(d).font(EType.caption).foregroundStyle(Brand.success) }
            HStack(spacing: Space.s2) {
                CTAButton(title: generating ? "Generating…" : "Generate claim report",
                          action: { Task { await generate() } },
                          isLoading: generating || !hasClaim)
                    .frame(maxWidth: .infinity)
                Button(action: {}) {
                    Text("Preview")
                        .font(EType.title).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).frame(maxWidth: 132)
            }
            if !hasClaim {
                Text("Open a claim to generate its report.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: ESang card

    private var esangCard: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .clear], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 16))
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ESang: insurer wants the seal log included")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(includeEvidence ? "evidence pack is on · link auto-expires in 1h"
                                     : "turn on the evidence pack · link auto-expires in 1h")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Governing-law ledger (regulatory reference · by discharge country)

    private var governingLawLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("GOVERNING LAW · CARGO-LIABILITY REGIME BY DISCHARGE COUNTRY")
            regimeRow(active: true,  code: "US", body: "COGSA · Hague (46 USC 30701)", limit: "$500/pkg · 1yr · USD")
            regimeRow(active: false, code: "CA", body: "Marine Liability Act · Hague-Visby", limit: "666.67 SDR/pkg · 1yr · CAD")
            regimeRow(active: false, code: "MX", body: "LNCM · Hamburg Rules", limit: "835 SDR/pkg · 2yr · MXN")
        }
    }

    private func regimeRow(active: Bool, code: String, body: String, limit: String) -> some View {
        HStack(spacing: Space.s2) {
            Circle().fill(active ? Brand.info : palette.textTertiary).frame(width: 7, height: 7)
            Text("\(code) · \(body)")
                .font(.system(size: 10.5, weight: .heavy))
                .foregroundStyle(active ? Brand.info : palette.textSecondary).lineLimit(1)
            Spacer(minLength: Space.s2)
            Text(limit).font(EType.mono(.micro))
                .foregroundStyle(active ? Brand.info.opacity(0.85) : palette.textTertiary)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, 8)
        .background(active ? Brand.info.opacity(0.10) : palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(active ? Brand.info.opacity(0.45) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: Helpers

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }

    // MARK: Load + generate

    private func load() async {
        loading = true; loadError = nil
        guard hasClaim else { loading = false; return }
        struct In813: Encodable { let id: String }
        do {
            summary = try await EusoTripAPI.shared.query("freightClaims.getClaimById", input: In813(id: claimId))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func generate() async {
        guard hasClaim else { genError = "Open a claim to generate its report."; return }
        generating = true; genError = nil; genDone = nil
        struct In813: Encodable {
            let claimId: String
            let format: String
            let includeEvidence: Bool
            let includeTimeline: Bool
            let includeFinancials: Bool
            let purpose: String
        }
        do {
            let out: GenerateReport813 = try await EusoTripAPI.shared.mutation(
                "freightClaims.generateClaimReport",
                input: In813(claimId: claimId, format: format.rawValue,
                             includeEvidence: includeEvidence, includeTimeline: includeTimeline,
                             includeFinancials: includeFinancials, purpose: purpose.rawValue))
            genDone = out.filename.map { "Report ready · \($0)" } ?? "Report generated."
        } catch {
            // The resolver renders CSV only today (PDF/XLSX queue to the document service);
            // surface its message verbatim rather than a dead retry.
            genError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        generating = false
    }
}

// MARK: - Previews

#Preview("813 · Vessel Claim Report · Night") {
    VesselClaimReportScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("813 · Vessel Claim Report · Light") {
    VesselClaimReportScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
