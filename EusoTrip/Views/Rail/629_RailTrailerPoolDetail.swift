//
//  629_RailTrailerPoolDetail.swift
//  EusoTrip — Rail Engineer · Trailer Pool Detail (carrier-side equipment pool).
//
//  Verbatim port of "629 Rail Trailer Pool Detail · Dark".
//  Flagship DETAIL grammar (mirrors 621 / 609 / 02-Shipper-205):
//    back chevron + eyebrow + mono caption · title 28/-0.4 ·
//    gradient-rimmed hero ActiveCard (lead figure + progress) ·
//    3-cell KPI strip (cell-1 eusoDiagonal) · itemized ListRow stack
//    (40x40 icon chip + title + mono sub + short status pill + right
//    tabular value) · NEXT INSPECTION context strip · Move unit /
//    Inspection CTA pair. A yard planner sees the whole trailer pool's
//    availability + repair backlog at a glance to move the right unit fast.
//
//  WIRING (grep-confirmed in-repo this fire):
//    pool roster + by-status counts ← yardManagement.getTrailerPool
//      (server routers/yardManagement.ts:867, protectedProcedure).
//      Output: { trailers: [...], summary: { total, available,
//      loaded, empty, inRepair, reserved } }. Each trailer carries
//      condition ("needs_inspection" | "good") + lastInspection, which
//      drives the "needs inspection" / "NEXT INSPECTION · DUE" secondary
//      — so a single endpoint covers both the desc's :867 roster anchor
//      and the :501 next-inspection-due secondary.
//    RBAC: server mounts getTrailerPool as protectedProcedure (NOT a
//      dedicated railProcedure); transportMode=rail surface.
//

import SwiftUI

struct RailTrailerPoolDetailScreen: View {
    let theme: Theme.Palette
    /// LB ICTF · the yard whose pool this detail is scoped to. Defaulted
    /// so the top-level struct only requires `theme`.
    var poolLabel: String = "LB ICTF"

    var body: some View {
        Shell(theme: theme) {
            RailTrailerPoolDetailBody(poolLabel: poolLabel)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror yardManagement.getTrailerPool output)

private struct PoolTrailer: Decodable, Identifiable {
    let id: String
    let trailerNumber: String?
    let type: String?
    let status: String?           // available | loaded | empty | in_repair | reserved | …
    let spotId: String?
    let condition: String?        // "needs_inspection" | "good"
    let lastInspection: String?
    let length: Int?
    let make: String?
    let year: Int?
}

private struct PoolSummary: Decodable {
    let total: Int?
    let available: Int?
    let loaded: Int?
    let empty: Int?
    let inRepair: Int?
    let reserved: Int?
}

private struct TrailerPoolResponse: Decodable {
    let trailers: [PoolTrailer]
    let summary: PoolSummary
}

// MARK: - Body

private struct RailTrailerPoolDetailBody: View {
    let poolLabel: String

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var trailers: [PoolTrailer] = []
    @State private var summary: PoolSummary? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Derived counts off the real roster + summary.
    private var total: Int     { summary?.total ?? trailers.count }
    private var available: Int { summary?.available ?? trailers.filter { $0.status == "available" }.count }
    private var loaded: Int    { summary?.loaded ?? trailers.filter { $0.status == "loaded" }.count }
    private var inRepair: Int  { summary?.inRepair ?? trailers.filter { $0.status == "in_repair" }.count }
    private var reserved: Int  { summary?.reserved ?? trailers.filter { $0.status == "reserved" }.count }

    private var needsInspection: Int {
        trailers.filter { ($0.condition ?? "") == "needs_inspection" }.count
    }
    private var repairNeedsInspection: Int {
        trailers.filter { $0.status == "in_repair" && ($0.condition ?? "") == "needs_inspection" }.count
    }

    /// Oldest past-inspection trailer number (for the NEXT INSPECTION strip).
    private var oldestPastDue: String? {
        trailers
            .filter { ($0.condition ?? "") == "needs_inspection" }
            .compactMap { t -> (String, Date)? in
                guard let iso = t.lastInspection,
                      let d = ISO8601DateFormatter().date(from: iso) else { return nil }
                return (t.trailerNumber ?? t.id, d)
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    /// Progress fraction — available / total (matches the hero bar's
    /// "ready vs. pool" reading, ~125/360 in the wireframe).
    private var availFraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(available) / CGFloat(total))
    }

    /// Reference identifier shown in the context strip — verbatim grammar
    /// of the wireframe's "Eusorone Technologies (DU) · RAIL-… · LB ICTF".
    /// AuthUser carries no tenant-name field (only companyId), so the
    /// canonical tenant label is used with the signed-in user's initial.
    private var refLine: String {
        let initial = session.user?.firstName.first.map(String.init) ?? "D"
        return "Eusorone Technologies (\(initial)) · RAIL-POOL · \(poolLabel)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                IridescentHairline()
                    .padding(.top, Space.s4)

                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    heroCard
                        .padding(.top, Space.s5)
                    kpiStrip
                        .padding(.top, Space.s4)
                    byStatusCard
                        .padding(.top, Space.s4)
                    inspectionStrip
                        .padding(.top, Space.s4)
                    ctaPair
                        .padding(.top, Space.s5)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Header (back chevron · eyebrow · title · right caption)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · TRAILER POOL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("EQUIPMENT")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Button {
                        RailEngineerNavDispatcher.handle("Shipments")
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                    Text("Trailer pool")
                        .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(poolLabel)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("synced 3m ago")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, Space.s3)
        }
    }

    // MARK: - Hero ActiveCard (gradient rim + lead figure + progress)

    private var heroCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text("equipment")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    Text("\(inRepair) in repair")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color(hex: 0xFF6B5E))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Brand.danger.opacity(0.18)))
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Text("\(available)")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("of \(total) trailers")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text("\(poolLabel) · \(needsInspection) need inspection")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("53 FT FLEET")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(available > 0 ? "READY" : "TIGHT")
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(available > 0 ? Color(hex: 0x34D8A6) : Brand.warning)
                    }
                }
                // Progress bar — available vs. pool.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: max(6, geo.size.width * availFraction))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - 3-cell KPI strip (cell-1 eusoDiagonal)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiCell(label: "TOTAL",  value: "\(total)",     gradientFill: true)
            kpiCell(label: "AVAIL",  value: "\(available)", valueColor: Color(hex: 0x34D8A6))
            kpiCell(label: "REPAIR", value: "\(inRepair)",  valueColor: Color(hex: 0xFF6B5E))
        }
    }

    private func kpiCell(label: String, value: String,
                         gradientFill: Bool = false,
                         valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(gradientFill ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(gradientFill ? Color.white : (valueColor ?? palette.textPrimary))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            Group {
                if gradientFill {
                    LinearGradient.diagonal
                } else {
                    palette.bgCard
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(gradientFill ? Color.clear : palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - POOL · BY STATUS card

    private var byStatusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("POOL · BY STATUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(total) UNITS")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            VStack(spacing: 0) {
                statusRow(
                    iconBuild: AnyView(trailerGlyph(stroke: Color(hex: 0x34D8A6))),
                    chipColor: Color(hex: 0x00C48C),
                    iconBg: Color(hex: 0x00C48C).opacity(0.20),
                    title: "Available · ready",
                    sub: "\(available) units · 53 ft dry van",
                    pill: "READY",
                    pillColor: Color(hex: 0x34D8A6),
                    value: "\(available)",
                    valueColor: Color(hex: 0x34D8A6)
                )
                Divider().overlay(palette.borderFaint)
                statusRow(
                    iconBuild: AnyView(trailerGlyph(stroke: Color(hex: 0x5BB0F5))),
                    chipColor: Brand.info,
                    iconBg: Brand.info.opacity(0.20),
                    title: "Loaded · in use",
                    sub: "\(loaded) units · linehaul + dray",
                    pill: "IN USE",
                    pillColor: Color(hex: 0x5BB0F5),
                    value: "\(loaded)",
                    valueColor: Color(hex: 0x5BB0F5)
                )
                Divider().overlay(palette.borderFaint)
                statusRow(
                    iconBuild: AnyView(warningGlyph(stroke: Color(hex: 0xFF6B5E))),
                    chipColor: Brand.danger,
                    iconBg: Brand.danger.opacity(0.18),
                    title: "In repair · maint",
                    sub: "\(inRepair) units · \(repairNeedsInspection) need inspection",
                    pill: "DOWN",
                    pillColor: Color(hex: 0xFF6B5E),
                    value: "\(inRepair)",
                    valueColor: Color(hex: 0xFF6B5E)
                )
            }

            Text("+ Reserved · held \(reserved) units pre-assigned · \(total) units active total")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s4)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func statusRow(iconBuild: AnyView,
                           chipColor: Color,
                           iconBg: Color,
                           title: String,
                           sub: String,
                           pill: String,
                           pillColor: Color,
                           value: String,
                           valueColor: Color) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconBg)
                    .frame(width: 40, height: 40)
                iconBuild
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Space.s2)
            Text(pill)
                .font(.system(size: 11, weight: .bold)).tracking(0.5)
                .foregroundStyle(pillColor)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(pillColor.opacity(0.22)))
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .frame(minWidth: 24, alignment: .trailing)
        }
        .padding(.vertical, Space.s3)
    }

    // 20x14 trailer glyph (3 vertical ribs) — matches the SVG.
    private func trailerGlyph(stroke: Color) -> some View {
        TrailerRibShape()
            .stroke(stroke, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            .frame(width: 20, height: 14)
    }

    // Triangle warning glyph with center bar — matches the SVG.
    private func warningGlyph(stroke: Color) -> some View {
        WarningTriangleShape()
            .stroke(stroke, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .frame(width: 20, height: 17)
    }

    // MARK: - NEXT INSPECTION · DUE context strip

    private var inspectionStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NEXT INSPECTION · DUE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(needsInspection) PAST DUE")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(pastDueLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(refLine)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var pastDueLine: String {
        if let oldest = oldestPastDue {
            return "\(needsInspection) trailers past inspection date · \(oldest) oldest"
        }
        return needsInspection > 0
            ? "\(needsInspection) trailers past inspection date"
            : "No trailers past inspection date"
    }

    // MARK: - CTA pair (Move unit · Inspection)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Move unit", action: {
                RailEngineerNavDispatcher.handle("Shipments")
            })
            Button {
                RailEngineerNavDispatcher.handle("Compliance")
            } label: {
                Text("Inspection")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(hex: 0x232932))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 148)
        }
    }

    // MARK: - Loading / error states

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .strokeBorder(palette.borderFaint))
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 72)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
        .padding(.top, Space.s5)
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            EusoEmptyState(systemImage: "exclamationmark.triangle",
                           title: "Couldn't load the trailer pool",
                           subtitle: err)
        }
        .padding(.top, Space.s7)
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct PoolIn: Encodable { let limit: Int }
        do {
            let resp: TrailerPoolResponse = try await EusoTripAPI.shared.query(
                "yardManagement.getTrailerPool", input: PoolIn(limit: 200))
            self.trailers = resp.trailers
            self.summary = resp.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - SVG glyph shapes

/// 20x14 box with three interior vertical ribs (the trailer side glyph).
private struct TrailerRibShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.addRoundedRect(in: CGRect(x: 0, y: 0, width: w, height: h),
                         cornerSize: CGSize(width: 1.5, height: 1.5))
        for i in 1...3 {
            let x = w * CGFloat(i) / 4
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: h))
        }
        return p
    }
}

/// Triangle with a short center bar (the "in repair / maint" warning glyph).
private struct WarningTriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w / 2, y: 0))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
        p.move(to: CGPoint(x: w / 2, y: h * 0.35))
        p.addLine(to: CGPoint(x: w / 2, y: h * 0.65))
        return p
    }
}

#Preview("629 · Rail Trailer Pool Detail · Night") {
    RailTrailerPoolDetailScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("629 · Rail Trailer Pool Detail · Light") {
    RailTrailerPoolDetailScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
