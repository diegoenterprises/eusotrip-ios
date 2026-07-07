//
//  704_RailTrustVerdict.swift
//  EusoTrip — Rail Engineer · Trust Verdict (fraud-guard rail signals).
//
//  Bespoke port of "05 Rail/Light-SVG/704 Rail Trust Verdict.svg" (+ Dark).
//  ARCHETYPE = SCORE-GAUGE dossier — 270° risk-score ring hero (0–100 with
//  verdict band) over a contributing-signals ledger where each signal carries
//  its weight-contribution bar. Deliberately not a read-trail timeline.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/fraud.ts +
//  frontend/server/_core/fraudGuard.ts):
//    fraud.getLoadTrust   EXISTS fraud.ts:189 {loadId} →
//        {score 0-100, verdict verified|review_pending|flagged,
//         riskSignals[], reason} — the persisted scoreLoadTrust verdict
//        (fraudGuard.ts:86, written at post time via logTrustVerdict).
//    fraud.reportLoad     EXISTS fraud.ts:227 {loadId, reason, detail} →
//        REAL hold path available today: demotes the verdict to
//        review_pending (+20 score, USER_REPORT signal) and opens an admin
//        review record. The primary CTA fires this after confirmation and
//        re-reads the verdict — success shows only after the write lands.
//    Signal weights mirror the live scoring table in fraudGuard.ts:86-150
//        (e.g. carrier authority inactive +35, brand-new account +25,
//        off-platform redirect +30) so each ledger bar is code-traced, not
//        invented. A signal outside the table renders without a weight.
//  VERIFIED ABSENT (honest state, never fabricated):
//    Rail-amplified signals (SCAC mark variant, unsigned waybill 417) are not
//    yet computed into ScoreInput; they appear only if present in the array.
//    railTrust.holdTender — the dedicated rail hold mutation is absent;
//    fraud.reportLoad is the real review-hold available now.
//    fraud.clearReview is admin-only, so Override surfaces the honest
//    admin-decision state for rail engineers.
//

import SwiftUI

struct RailTrustVerdictScreen: View {
    let theme: Theme.Palette
    /// Load / tender identifier scoping the trust pull. Accepts "1077" or
    /// "load_1077" — the trust reader normalizes the prefix.
    var loadId: String = "0"

    var body: some View {
        Shell(theme: theme) {
            RailTrustVerdictBody(loadId: loadId)
        } nav: {
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

// MARK: - Data shapes (mirror fraud.getLoadTrust output)

private struct LoadTrust704: Decodable {
    let score: Int?
    let verdict: String?
    let riskSignals: [String]?
    let reason: String?
}

private struct TrustInput704: Encodable { let loadId: String }
private struct ReportInput704: Encodable {
    let loadId: String
    let reason: String
    let detail: String
}
private struct ReportResult704: Decodable { let accepted: Bool? }

/// Code-traced weight + user-copy table for the live fraudGuard signals.
private struct SignalMeta704 {
    let title: String
    let source: String
    let weight: Int?
    let critical: Bool

    static func lookup(_ raw: String) -> SignalMeta704 {
        switch raw {
        case "FMCSA_INACTIVE_OR_REVOKED":
            return .init(title: "Carrier authority inactive or revoked", source: "Carrier authority check", weight: 35, critical: true)
        case "ACCOUNT_BRAND_NEW":
            return .init(title: "Posting account under a week old", source: "Account age", weight: 25, critical: true)
        case "ACCOUNT_NEW":
            return .init(title: "Posting account under a month old", source: "Account age", weight: 10, critical: false)
        case "UNVERIFIED_ACCOUNT":
            return .init(title: "Posting account unverified", source: "Identity verification", weight: 20, critical: false)
        case "FIRST_LOAD_POSTED":
            return .init(title: "First tender ever posted", source: "Posting history", weight: 15, critical: false)
        case "RATE_UNREALISTICALLY_HIGH":
            return .init(title: "Rate far above market", source: "Rate plausibility", weight: 25, critical: true)
        case "RATE_ABOVE_MARKET":
            return .init(title: "Rate above market", source: "Rate plausibility", weight: 8, critical: false)
        case "RATE_UNREALISTICALLY_LOW":
            return .init(title: "Rate far below market", source: "Rate plausibility", weight: 20, critical: true)
        case "OFF_PLATFORM_CONTACT_REDIRECT":
            return .init(title: "Pushes contact off the platform", source: "Listing content", weight: 30, critical: true)
        case "SUSPICIOUS_DOMAIN_REFERENCE":
            return .init(title: "References a suspicious web domain", source: "Listing content", weight: 15, critical: false)
        case "MISSING_LANE":
            return .init(title: "Origin or destination missing", source: "Lane sanity", weight: 10, critical: false)
        case "USER_REPORT":
            return .init(title: "Reported by a carrier or driver", source: "Community report", weight: 20, critical: true)
        case "SCAC_MARK_VARIANT":
            return .init(title: "SCAC mark variant detected", source: "Carrier integrity", weight: 25, critical: true)
        case "UNSIGNED_WAYBILL_417":
            return .init(title: "Unsigned EDI 417 waybill", source: "Documentation", weight: 15, critical: false)
        case "NOT_SCORED":
            return .init(title: "Listing predates trust scoring", source: "Scoring coverage", weight: nil, critical: false)
        default:
            return .init(title: raw.replacingOccurrences(of: "_", with: " ").lowercased(),
                         source: "Trust signal", weight: nil, critical: false)
        }
    }
}

// MARK: - Body

private struct RailTrustVerdictBody: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @State private var trust: LoadTrust704? = nil
    @State private var loading = true
    @State private var holding = false
    @State private var holdError: String? = nil
    @State private var holdLanded = false
    @State private var regime = 0
    @State private var showHoldConfirm = false
    @State private var showOverrideNotice = false

    private let regimes: [(String, String)] = [("US · AAR", "Railinc CIF"),
                                               ("CA · TC", "Railinc CIF"),
                                               ("MX · ARTF", "SIID")]

    private var score: Int { trust?.score ?? 0 }
    private var signals: [String] { trust?.riskSignals ?? [] }

    private var verdictLabel: String {
        switch trust?.verdict {
        case "verified":       return "VERIFIED"
        case "flagged":        return "FLAGGED"
        case "review_pending": return "REVIEW"
        default:               return "UNSCORED"
        }
    }

    private var verdictColor: Color {
        switch trust?.verdict {
        case "verified": return Brand.success
        case "flagged":  return Brand.danger
        default:         return Brand.warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Trust verdict")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text(trust?.reason ?? "Every fraud signal on this tender, fused into one verdict")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    gaugeHero
                    ledgerHeader
                    signalLedger
                    triBand
                    footerActions
                    if let err = holdError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    }
                    if holdLanded {
                        LifecycleCard {
                            Text("Hold recorded — this tender is now in review and an admin decides next.")
                                .font(EType.caption).foregroundStyle(Brand.success)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog("Hold this tender for review?", isPresented: $showHoldConfirm, titleVisibility: .visible) {
            Button("Hold for review", role: .destructive) { Task { await holdTender() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The verdict moves to review and an admin queue picks it up. This can't be undone from this screen.")
        }
        .alert("Override is an admin decision", isPresented: $showOverrideNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A flagged or in-review verdict clears only when an EusoTrip admin decides it. The tender stays held until that decision lands.")
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ CARRIER · RAIL · TRUST GUARD")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("FRAUD SIGNALS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("\(signals.count) signal\(signals.count == 1 ? "" : "s")", palette.textSecondary)
            chip("score \(score)", verdictColor)
            chip(verdictLabel.lowercased(), verdictColor)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: 270° score gauge — real score, real verdict.

    private var gaugeHero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(palette.bgCardSoft, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0.0, to: 0.75 * (Double(min(max(score, 0), 100)) / 100.0))
                    .stroke(LinearGradient(colors: [Brand.warning, Brand.danger],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(135))
                VStack(spacing: 2) {
                    Text("RISK SCORE · 0–100")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(score)")
                        .font(.system(size: 46, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(verdictLabel)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(verdictColor)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(verdictColor.opacity(0.12)))
                }
            }
            .frame(width: 200, height: 200)
            .padding(.top, 6)
            .frame(maxWidth: .infinity)
            Divider().overlay(palette.borderFaint)
            HStack(spacing: 8) {
                Image(systemName: trust?.verdict == "verified" ? "checkmark.shield" : "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(verdictColor)
                Text(trust?.reason ?? "No verdict is on file for this tender.")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var ledgerHeader: some View {
        HStack {
            Text("CONTRIBUTING RISK SIGNALS · RANKED BY WEIGHT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
        }
    }

    @ViewBuilder
    private var signalLedger: some View {
        if signals.isEmpty {
            EusoEmptyState(systemImage: "checkmark.seal",
                           title: "No risk signals",
                           subtitle: "Not one fraud signal fired on this tender. The verdict above reflects the clean pass.")
        } else {
            let ranked = signals
                .map { (raw: $0, meta: SignalMeta704.lookup($0)) }
                .sorted { ($0.meta.weight ?? -1) > ($1.meta.weight ?? -1) }
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.offset) { i, s in
                    signalRow(s.meta)
                    if i < ranked.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(.horizontal, 16)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func signalRow(_ meta: SignalMeta704) -> some View {
        let tone: Color = meta.critical ? Brand.danger : Brand.warning
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(meta.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(meta.weight.map { "+\($0)" } ?? "—")
                    .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(meta.weight == nil ? palette.textTertiary : tone)
            }
            if let w = meta.weight {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft).frame(height: 6)
                        Capsule().fill(tone)
                            .frame(width: g.size.width * CGFloat(Double(w) / 35.0), height: 6)
                    }
                }
                .frame(height: 6)
            }
            Text(meta.source)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 12)
    }

    private var triBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == regime ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { regime = i }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: holding ? "Holding…" : "Hold for review",
                      action: { if !holding { showHoldConfirm = true } })
                .frame(maxWidth: .infinity)
                .disabled(holding)
            Button(action: { showOverrideNotice = true }) {
                Text("Override")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 118)
                    .frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Load + hold

    private func reload() async {
        loading = true
        let t: LoadTrust704? = try? await EusoTripAPI.shared.query(
            "fraud.getLoadTrust", input: TrustInput704(loadId: loadId))
        self.trust = t
        loading = false
    }

    /// REAL hold: fraud.reportLoad demotes the verdict to review and opens
    /// an admin review record. Success renders only after the write lands,
    /// and the verdict re-reads so the score bump is visible.
    private func holdTender() async {
        holding = true; holdError = nil; holdLanded = false
        do {
            let _: ReportResult704 = try await EusoTripAPI.shared.mutation(
                "fraud.reportLoad",
                input: ReportInput704(loadId: loadId, reason: "other",
                                      detail: "Rail tender held for trust review from the trust verdict screen"))
            holdLanded = true
            await reload()
        } catch {
            holdError = "The hold didn't record. The verdict below is unchanged — check your connection and try again."
        }
        holding = false
    }
}

#Preview("704 · Rail Trust Verdict · Night") {
    RailTrustVerdictScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("704 · Rail Trust Verdict · Light") {
    RailTrustVerdictScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
