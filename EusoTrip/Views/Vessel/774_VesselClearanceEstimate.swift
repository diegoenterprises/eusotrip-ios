//
//  774_VesselClearanceEstimate.swift
//  EusoTrip — Vessel Operator · Customs Clearance Estimate.
//
//  Verbatim port of wireframe 774 (06 Vessel · Dark) — a purpose-built
//  CUMULATIVE-TIME-LADDER (time waterfall): each clearance step's hours
//  accumulate left-to-right on one shared 0→total track, so the operator
//  sees which step (discharge, CBP hold) dominates the critical path and
//  can quote the consignee a firm ready-time.
//
//  Endpoints (server/routers/vesselShipments.ts):
//    estimateVesselClearanceTime (:3454 · {portId, hasHazmat, containerCount}
//      → {estimatedHours, breakdown:[{step, hours}]}) — the server's arg is
//      used as the clearance `direction`, so we pass "US_import" to drive the
//      US-import ladder (doc review · exam · IMDG · discharge · CBP hold ·
//      release) verbatim from services/crossBorderVessel.ts.
//    getDutyEstimate (:3336 · {htsCode, declaredValue, countryOfOrigin}) —
//      the duty-owed line (Avalara, optional).
//

import SwiftUI

struct VesselClearanceEstimateScreen: View {
    let theme: Theme.Palette
    var direction: String = "US_import"
    var containerCount: Int = 110
    var hasHazmat: Bool = true

    var body: some View {
        Shell(theme: theme) {
            VesselClearanceEstimateBody(direction: direction, containerCount: containerCount, hasHazmat: hasHazmat)
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

// MARK: - Data shapes

private struct ClearanceEstimate774: Decodable {
    let estimatedHours: Double
    let breakdown: [ClearanceStep774]
    private enum CodingKeys: String, CodingKey { case estimatedHours, breakdown }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let h = try? c.decode(Double.self, forKey: .estimatedHours) { estimatedHours = h }
        else if let s = try? c.decode(String.self, forKey: .estimatedHours), let h = Double(s) { estimatedHours = h }
        else { estimatedHours = 0 }
        breakdown = (try? c.decode([ClearanceStep774].self, forKey: .breakdown)) ?? []
    }
}

private struct ClearanceStep774: Decodable, Identifiable {
    var id: String { step }
    let step: String
    let hours: Double
    private enum CodingKeys: String, CodingKey { case step, hours }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        step = (try? c.decode(String.self, forKey: .step)) ?? "Step"
        if let h = try? c.decode(Double.self, forKey: .hours) { hours = h }
        else if let s = try? c.decode(String.self, forKey: .hours), let h = Double(s) { hours = h }
        else { hours = 0 }
    }
}

private struct DutyLine774: Decodable {
    let totalFees: Double
    private enum CodingKeys: String, CodingKey { case totalFees }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        if let v = try? c.decode(Double.self, forKey: .totalFees) { totalFees = v }
        else if let s = try? c.decode(String.self, forKey: .totalFees), let v = Double(s) { totalFees = v }
        else { totalFees = 0 }
    }
}

// MARK: - Body

private struct VesselClearanceEstimateBody: View {
    @Environment(\.palette) private var palette
    let direction: String
    let containerCount: Int
    let hasHazmat: Bool

    @State private var est: ClearanceEstimate774? = nil
    @State private var duty: DutyLine774? = nil
    @State private var dutyUnavailable = false
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · CLEARANCE",
                caption: "USLGB · CBP",
                title: "Clearance ETA",
                idText: "VES-260524-E64F90"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else if let est {
                    hero(est)
                    ladder(est)
                    esang(est)
                    dutyBasis
                    ctaPair
                }
                Color.clear.frame(height: Space.s6)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func hero(_ e: ClearanceEstimate774) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                    Text("~\(Fmt774.h(e.estimatedHours))")
                        .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("to clear · ready by \(readyBy(e.estimatedHours))")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text("USLGB · US import · \(hasHazmat ? "DG · " : "")\(containerCount) containers")
                            .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("DUTY OWED").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(dutyUnavailable ? "—" : Fmt774.money(duty?.totalFees ?? 0))
                            .font(.system(size: 20, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                HStack(spacing: Space.s2) {
                    if hasHazmat {
                        Text("IMDG DG").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.danger)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(palette.tintDanger))
                    }
                    Text("US IMPORT · 7501").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.info)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(palette.tintInfo))
                }
            }
        }
    }

    // Cumulative-time waterfall ladder
    private func ladder(_ e: ClearanceEstimate774) -> some View {
        let total = max(e.estimatedHours, e.breakdown.reduce(0) { $0 + $1.hours }, 1)
        var cum: Double = 0
        var rungs: [(step: ClearanceStep774, start: Double)] = []
        for s in e.breakdown { rungs.append((s, cum)); cum += s.hours }
        return VStack(alignment: .leading, spacing: Space.s3) {
            SectionLabel774(text: "CLEARANCE STEPS", endpoint: "estimateVesselClearanceTime")
            VStack(spacing: Space.s4) {
                HStack {
                    Text("0h").font(.system(size: 8)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(Fmt774.h(total))").font(.system(size: 8)).foregroundStyle(palette.textTertiary)
                }
                ForEach(rungs, id: \.step.id) { rung in
                    rungRow(rung.step, start: rung.start, total: total)
                }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func rungRow(_ s: ClearanceStep774, start: Double, total: Double) -> some View {
        let color = Palette774.color(for: s.step)
        let startFrac = max(0, min(1, start / total))
        let widthFrac = max(0, min(1 - startFrac, s.hours / total))
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.14)).frame(width: 30, height: 30)
                Image(systemName: Palette774.icon(for: s.step))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(s.step).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("+\(Fmt774.h(s.hours))").font(.system(size: 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(color)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.borderFaint.opacity(0.6)).frame(height: 6)
                        // prior cumulative (dim)
                        Capsule().fill(palette.textTertiary.opacity(0.35))
                            .frame(width: geo.size.width * startFrac, height: 6)
                        // this step (colored), offset by the cumulative start
                        Capsule().fill(color)
                            .frame(width: geo.size.width * widthFrac, height: 6)
                            .offset(x: geo.size.width * startFrac)
                    }
                }.frame(height: 6)
            }
        }
    }

    private func esang(_ e: ClearanceEstimate774) -> some View {
        let critical = e.breakdown.max(by: { $0.hours < $1.hours })
        return EsangAdvisory774(
            title: "Pre-file the 7501 to drop the exam wait",
            message: critical.map { "\($0.step) (\(Fmt774.h($0.hours))) is the critical path — pre-book the hold slot" }
                ?? "Pre-book the hold slot to compress the critical path"
        )
    }

    // Tri-country duty basis (country-done)
    private var dutyBasis: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("DUTY BASIS · BY DESTINATION REGIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("US ACTIVE").font(.system(size: 8, weight: .heavy)).foregroundStyle(Brand.info)
            }
            HStack(spacing: Space.s2) {
                regimeChip(flag: "US", authority: "CBP", detail: "HTS+MPF+HMF · USD", active: true)
                regimeChip(flag: "CA", authority: "CBSA", detail: "Duty+GST 5% · CAD", active: false)
                regimeChip(flag: "MX", authority: "SAT", detail: "IGI+IVA 16% · MXN", active: false)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func regimeChip(flag: String, authority: String, detail: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Text(flag).font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textTertiary.opacity(0.4))))
            VStack(alignment: .leading, spacing: 1) {
                Text(authority).font(.system(size: 10, weight: .bold)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                Text(detail).font(.system(size: 8)).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(active ? Brand.blue.opacity(0.14) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .strokeBorder(active ? Brand.blue.opacity(0.5) : palette.borderFaint))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Pre-file entry", action: {})
            Button {} label: {
                Text("Duty detail").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 140, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            }.buttonStyle(.plain)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 84)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 320)
        }
    }

    private func readyBy(_ hours: Double) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d HH:mm"
        return f.string(from: Date().addingTimeInterval(hours * 3600))
    }

    // MARK: - Networking

    private func load() async {
        loading = true; loadError = nil; dutyUnavailable = false
        struct EstIn: Encodable { let portId: String; let hasHazmat: Bool; let containerCount: Int }
        struct DuIn: Encodable { let htsCode: String; let declaredValue: Double; let countryOfOrigin: String }
        do {
            async let estTask: ClearanceEstimate774? = EusoTripAPI.shared.query(
                "vesselShipments.estimateVesselClearanceTime",
                input: EstIn(portId: direction, hasHazmat: hasHazmat, containerCount: containerCount))
            async let duTask: DutyLine774? = EusoTripAPI.shared.query(
                "vesselShipments.getDutyEstimate",
                input: DuIn(htsCode: "0810", declaredValue: 184_200, countryOfOrigin: "CN"))
            let e = try await estTask
            let d = try await duTask
            self.est = e
            self.duty = d
            self.dutyUnavailable = (d == nil)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

private enum Palette774 {
    static func color(for step: String) -> Color {
        let s = step.lowercased()
        if s.contains("imdg") || s.contains("dangerous") { return Brand.danger }
        if s.contains("discharge") { return Brand.warning }
        if s.contains("hold") || s.contains("cbp") { return Brand.escort }
        if s.contains("release") || s.contains("gate") { return Brand.success }
        return Brand.info
    }
    static func icon(for step: String) -> String {
        let s = step.lowercased()
        if s.contains("document") || s.contains("manifest") { return "doc.text" }
        if s.contains("exam") || s.contains("selection") { return "magnifyingglass" }
        if s.contains("imdg") || s.contains("dangerous") { return "diamond.fill" }
        if s.contains("discharge") { return "arrow.down.to.line" }
        if s.contains("hold") || s.contains("cbp") { return "shield.lefthalf.filled" }
        if s.contains("release") || s.contains("gate") { return "checkmark.circle" }
        return "clock"
    }
}

private enum Fmt774 {
    static func h(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(v))h" }
        return String(format: "%.1fh", v)
    }
    static func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(Int(v)))
    }
}

private struct SectionLabel774: View {
    @Environment(\.palette) private var palette
    let text: String; var endpoint: String? = nil
    var body: some View {
        HStack {
            Text(text).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            if let endpoint { Text(endpoint).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(palette.textTertiary) }
        }
    }
}

private struct EsangAdvisory774: View {
    @Environment(\.palette) private var palette
    let title: String; let message: String
    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("774 · Clearance ETA · Night") { VesselClearanceEstimateScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("774 · Clearance ETA · Light") { VesselClearanceEstimateScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
