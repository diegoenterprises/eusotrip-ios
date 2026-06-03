//
//  669_RailOverchargeRecovery.swift
//  EusoTrip — Rail Engineer · Overcharge Recovery (carrier-side freight-audit money recovery-waterfall).
//
//  Bespoke port of "05 Rail/Code/669_RailOverchargeRecovery.swift" (Light + Dark) adapted to
//  the app's design system + rail nav convention. Role = RAIL_ENGINEER (carrier-side vantage).
//
//  Archetype = MONEY RECOVERY-WATERFALL. Signature device is a recovery waterfall: Identified
//  (full column) steps DOWN through Audited-out (write-off leak) and In-dispute (pending) to
//  land on Recovered (cash secured); the floating decrements sum back to the identified total
//  so leakage is the visible gap. Per-invoice rows carry a 3-stage recovery stepper
//  (identified -> disputed -> recovered). Hero is numbers-first: recovered $ over recovery RATE.
//
//  Data (MCP-confirmed shape · freightClaims.ts:952):
//    freightClaims.getOverchargeRecovery  (protectedProcedure, companyId-scoped)
//      input  { status?: identified|disputed|recovered|written_off, limit=20, offset=0 }
//      output { recoveries:[{ id, invoiceNumber, carrier, overchargeAmount, recoveredAmount,
//                             status, identifiedDate, recoveredDate, type }],
//               total,
//               summary{ totalIdentified, totalRecovered, pendingRecovery, recoveryRate,
//                        avgRecoveryDays } }
//    Waterfall (identified -> audited-out -> in-dispute -> recovered) derived from summary +
//    per-status recovery sums, scaled to a 144pt plot. Stepper stage derived from status.
//  STUB · 'Push disputes' CTA -> freightClaims.fileClaim (writes claim row) is NOT wired here;
//    no per-invoice disputeDeadline / disputedDate fields on the API yet (named-gap to the-oath).
//    Both CTAs re-run load() honestly — no fake success.
//  NAV: HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME.
//

import SwiftUI

struct RailOverchargeRecoveryScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailOverchargeRecoveryBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Per-file input (no module-level EmptyInput)

private struct OverchargeInput669: Encodable {
    let limit: Int
    let offset: Int
}

// MARK: - Wire shapes (map 1:1 to freightClaims.getOverchargeRecovery)

private struct OverchargeResp669: Decodable {
    let recoveries: [RecoveryRow669]
    let total: Int
    let summary: RecoverySummary669
}

private struct RecoveryRow669: Decodable, Identifiable {
    let id: String
    let invoiceNumber: String?
    let carrier: String?
    let overchargeAmount: Double?
    let recoveredAmount: Double?
    let status: String?
    let identifiedDate: String?
    let recoveredDate: String?
    let type: String?
}

private struct RecoverySummary669: Decodable {
    let totalIdentified: Double?
    let totalRecovered: Double?
    let pendingRecovery: Double?
    let recoveryRate: Double?
    let avgRecoveryDays: Double?
}

// MARK: - Derived model

private enum RecoveryStage669: Int { case identified = 1, disputed = 2, recovered = 3 }

private enum RecoveryStatus669 {
    case identified, disputed, recovered, writtenOff
    init(_ raw: String?) {
        switch (raw ?? "").lowercased() {
        case "disputed":      self = .disputed
        case "recovered":     self = .recovered
        case "written_off":   self = .writtenOff
        default:              self = .identified
        }
    }
    var word: String {
        switch self {
        case .identified: return "IDENTIFIED"
        case .disputed:   return "DISPUTED"
        case .recovered:  return "RECOVERED"
        case .writtenOff: return "WRITTEN OFF"
        }
    }
    var tint: Color {
        switch self {
        case .identified: return Brand.info
        case .disputed:   return Brand.warning
        case .recovered:  return Brand.success
        case .writtenOff: return Brand.danger
        }
    }
    var stage: RecoveryStage669 {
        switch self {
        case .identified:           return .identified
        case .disputed, .writtenOff: return .disputed
        case .recovered:            return .recovered
        }
    }
}

private struct WaterfallStep669: Identifiable {
    let id = UUID()
    let label: String; let value: String
    let topY: CGFloat; let height: CGFloat; let color: Color; let textColor: Color
}

// MARK: - Body

private struct RailOverchargeRecoveryBody: View {
    @Environment(\.palette) private var palette

    @State private var rows: [RecoveryRow669] = []
    @State private var summary: RecoverySummary669? = nil
    @State private var total = 0
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Currency formatting (compact $K for waterfall labels, full $ for amounts)

    private func usd(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
    private func usdCompact(_ v: Double) -> String {
        let sign = v < 0 ? "-" : ""
        let a = abs(v)
        if a >= 1000 { return "\(sign)$\(String(format: "%.1f", a / 1000))K" }
        return "\(sign)$\(Int(a))"
    }

    // MARK: Derived summary values

    private var totalIdentified: Double { summary?.totalIdentified ?? 0 }
    private var totalRecovered:  Double { summary?.totalRecovered ?? 0 }
    private var pendingRecovery: Double { summary?.pendingRecovery ?? 0 }
    private var recoveryRatePct: Int {
        let r = summary?.recoveryRate ?? 0
        // API may express rate as 0…1 fraction or 0…100 percent — normalize.
        return Int((r <= 1.0 ? r * 100 : r).rounded())
    }
    private var avgDays: Int { Int((summary?.avgRecoveryDays ?? 0).rounded()) }

    /// Audited-out (write-off leak) = identified − recovered − pending. The decrements sum
    /// back to the identified total, so leakage is the visible gap in the waterfall.
    private var auditedOut: Double {
        max(0, totalIdentified - totalRecovered - pendingRecovery)
    }

    private var recoveredCount: Int { rows.filter { RecoveryStatus669($0.status) == .recovered }.count }
    private var openCount: Int { rows.filter { RecoveryStatus669($0.status) != .recovered && RecoveryStatus669($0.status) != .writtenOff }.count }

    /// Open recoveries, largest-overcharge first (the rendered per-invoice list).
    private var openRows: [RecoveryRow669] {
        rows
            .filter { RecoveryStatus669($0.status) != .recovered && RecoveryStatus669($0.status) != .writtenOff }
            .sorted { ($0.overchargeAmount ?? 0) > ($1.overchargeAmount ?? 0) }
    }

    /// Largest open recovery — the ESANG escalation target.
    private var largestOpen: RecoveryRow669? { openRows.first }

    /// Waterfall scaled to the identified total over a 144pt plot.
    private var steps: [WaterfallStep669] {
        let plot: CGFloat = 144
        let topY: CGFloat = 24
        let denom = max(totalIdentified, 1)
        let hRecovered = CGFloat(totalRecovered / denom) * plot
        let hDispute   = CGFloat(pendingRecovery / denom) * plot
        let hAudited   = CGFloat(auditedOut / denom) * plot
        // Floating bars stack from the baseline (topY + plot) upward:
        //   recovered sits at the bottom, dispute above it, audited-out above that.
        let baseline = topY + plot
        let recoveredTopY = baseline - hRecovered
        let disputeTopY   = recoveredTopY - hDispute
        let auditedTopY   = disputeTopY - hAudited
        return [
            .init(label: "IDENTIFIED",  value: usdCompact(totalIdentified),
                  topY: topY, height: plot,
                  color: palette.textSecondary.opacity(0.30), textColor: palette.textPrimary),
            .init(label: "AUDITED OUT", value: "-" + usdCompact(auditedOut),
                  topY: auditedTopY, height: max(2, hAudited),
                  color: Brand.danger, textColor: Brand.danger),
            .init(label: "IN DISPUTE",  value: usdCompact(pendingRecovery),
                  topY: disputeTopY, height: max(2, hDispute),
                  color: Brand.warning, textColor: Brand.warning),
            .init(label: "RECOVERED",   value: usdCompact(totalRecovered),
                  topY: recoveredTopY, height: max(2, hRecovered),
                  color: Brand.success, textColor: Brand.success)
        ]
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if loading {
                    LifecycleCard { Text("Loading recoveries…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if rows.isEmpty {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No overcharges flagged",
                                   subtitle: "Run a freight audit to surface billing leakage on this carrier's invoices.")
                    runAuditButton
                } else {
                    hero
                    waterfallCard
                    recoveriesCard
                    esangRow
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · FREIGHT AUDIT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("RECOVERY")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Overcharge recovery")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("BNSF · Q2")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: Hero — recovered $ over recovery rate

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("RECOVERED OF \(usd(totalIdentified)) IDENTIFIED")
                        .font(.system(size: 9, weight: .heavy)).kerning(1.0)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(recoveryRatePct)%").font(.system(size: 26, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("recovery rate").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.success)
                    }
                }
                Text(usd(totalRecovered)).font(.system(size: 34, weight: .bold)).kerning(-0.6).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal).padding(.top, 6)
                Spacer(minLength: 8)
                HStack {
                    Text("\(total) invoice\(total == 1 ? "" : "s") flagged · \(recoveredCount) recovered")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text("avg \(avgDays) day\(avgDays == 1 ? "" : "s") to recover")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
            }.padding(20)
        }.frame(height: 116)
    }

    // MARK: Signature — recovery waterfall

    private var waterfallCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECOVERY WATERFALL · QUARTER TO DATE")
                .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.borderFaint))
                GeometryReader { geo in
                    let theSteps = steps
                    let cols = theSteps.count
                    let usable = geo.size.width - 48
                    let w = min(58, usable / CGFloat(cols) - 12)
                    let gap = (usable - w * CGFloat(cols)) / CGFloat(cols - 1)
                    ForEach(Array(theSteps.enumerated()), id: \.element.id) { i, s in
                        let x = 24 + CGFloat(i) * (w + gap)
                        RoundedRectangle(cornerRadius: 5).fill(s.color)
                            .frame(width: w, height: s.height).position(x: x + w/2, y: s.topY + s.height/2)
                        Text(s.value).font(.system(size: 11, weight: i == 3 ? .heavy : .bold)).monospacedDigit()
                            .foregroundStyle(s.textColor)
                            .position(x: x + w/2, y: s.topY - 8)
                        Text(s.label).font(.system(size: 9, weight: .heavy)).kerning(0.4)
                            .foregroundStyle(s.textColor.opacity(0.9))
                            .position(x: x + w/2, y: 184)
                    }
                    Rectangle().fill(palette.textPrimary.opacity(0.10)).frame(height: 1)
                        .position(x: geo.size.width/2, y: 168)
                }.frame(height: 200)
            }.frame(height: 200)
        }
    }

    // MARK: per-invoice recovery rows with 3-stage stepper

    private var recoveriesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("OPEN RECOVERIES · LARGEST FIRST")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(openCount) of \(total) open").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(openRows.prefix(6).enumerated()), id: \.element.id) { i, r in
                    recoveryRow(r)
                    if i < min(openRows.count, 6) - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.borderFaint)))
        }
    }

    private func recoveryRow(_ r: RecoveryRow669) -> some View {
        let status = RecoveryStatus669(r.status)
        let basis = (r.type ?? "overcharge").replacingOccurrences(of: "_", with: " ")
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(status.tint.opacity(0.14))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "doc.text").font(.system(size: 16, weight: .regular)).foregroundStyle(status.tint))
            VStack(alignment: .leading, spacing: 4) {
                Text(r.carrier ?? "—").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(r.invoiceNumber ?? "—") · \(basis)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
                stepper(status.stage)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(usd(r.overchargeAmount ?? 0)).font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text(status.word).font(.system(size: 9, weight: .heavy)).kerning(0.4).foregroundStyle(status.tint)
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func stepper(_ stage: RecoveryStage669) -> some View {
        let labels = ["identified", "disputed", "recovered"]
        return HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                let done = i + 1 <= stage.rawValue
                Circle().fill(done ? Brand.blue : Color.clear)
                    .overlay(Circle().stroke(done ? Color.clear : palette.textSecondary, lineWidth: 1.5))
                    .frame(width: 6, height: 6)
                if i < 2 {
                    Rectangle().fill(i + 1 < stage.rawValue ? Brand.blue : palette.textPrimary.opacity(0.14))
                        .frame(width: 34, height: 1.5)
                }
            }
            Text(labels[stage.rawValue - 1]).font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textSecondary).padding(.leading, 8)
        }
    }

    // MARK: ESang

    @ViewBuilder private var esangRow: some View {
        if let r = largestOpen {
            let amount = usd(r.overchargeAmount ?? 0)
            let invoice = r.invoiceNumber ?? "this invoice"
            let carrier = r.carrier ?? "the carrier"
            HStack(spacing: 0) {
                OrbeSang(state: .idle, diameter: 32).padding(.trailing, 12)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ESANG AI").font(.system(size: 9, weight: .heavy)).kerning(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Escalate \(invoice) — \(amount), \(carrier)\u{2019}s audit")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text("it\u{2019}s your largest open recovery — push it to dispute next.")
                        .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(palette.borderFaint)))
        }
    }

    // MARK: CTA pair

    private var ctaRow: some View {
        HStack(spacing: 8) {
            // STUB: 'Push disputes' has no backing mutation (freightClaims.fileClaim NOT wired
            // here); re-runs load() honestly rather than fake a write.
            Button { Task { await load() } } label: {
                Text("Push disputes · \(usdCompact(pendingRecovery))")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
            // STUB: 'Run audit' (freightClaims.runFreightAudit) re-runs load() to re-surface.
            Button { Task { await load() } } label: {
                Text("Run audit")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint)))
            }
            .buttonStyle(.plain)
        }
    }

    private var runAuditButton: some View {
        CTAButton(title: "Run freight audit", action: { Task { await load() } }, leadingIcon: "magnifyingglass")
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        do {
            let resp: OverchargeResp669 = try await EusoTripAPI.shared.query(
                "freightClaims.getOverchargeRecovery",
                input: OverchargeInput669(limit: 20, offset: 0)
            )
            self.rows = resp.recoveries
            self.summary = resp.summary
            self.total = resp.total
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("669 · Overcharge recovery · Light") {
    RailOverchargeRecoveryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("669 · Overcharge recovery · Night") {
    RailOverchargeRecoveryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
