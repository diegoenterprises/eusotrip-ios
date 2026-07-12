//
//  819_VesselContainerDeconSchedule.swift
//  EusoTrip — Vessel Operator · Container Decon Schedule.
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/819 Vessel Container Decon Schedule.svg" (Light + Dark),
//  built on the canonical DesignSystem at the golden-era bar. Archetype = DURATION-REFERENCE (a
//  reference Gantt, NOT the stamped KPI-band+list skeleton): every decon TYPE row carries a
//  method-glyph chip + title + residue-cleared sub + a duration pill AND a minute-scaled duration bar
//  (45..180 min, scaled to the 180-min longest) so the operator reads turnaround at a glance, closed
//  by an FSMA cross-contamination RULES sheet. Role VESSEL_OPERATOR · nav COMPLIANCE inked.
//
//  Data / wiring (endpoint confirmed on disk this fire):
//    appointments.getDeconSchedule EXISTS frontend/server/routers/appointments.ts:821 · query ·
//      input {facilityId?, date?, bayId?} · returns {schedule:[], deconTypes:[{id, name, avgMinutes,
//      description}], crossContaminationRules:[{from, to, requiresDecon, note}], regulation:"49 CFR
//      173.29 · 21 CFR 1.908"}. Drives the type board + the rules sheet LIVE — real durations
//      (standard_wash 45 · chemical_decon 90 · vapor_purge 60 · cryogenic_warmup 120 · full_decon
//      180 min) and real FSMA changeover rules. No fabricated data. RBAC isolatedProcedure.
//    STUB · named-gap handed to the-oath: appointments.createDeconBooking({bayId,containerId,
//      deconTypeId,start}) -> writes an appointment row + blockchainAuditTrail + WS_EVENTS.DECON_BOOKED
//      — booking a slot is a write not yet modelled; "Schedule by bay" stays disabled with an honest
//      note until it lands.
//    Food-grade washout-authority band = published references (US FDA FSMA 21 CFR 117 · CA CFIA SFCR ·
//      MX COFEPRIS SENASICA) — regulatory constants.
//
//  DeconType819 / DeconRule819 are file-scoped bespoke types. Dark + Light #Preview.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes (appointments.getDeconSchedule)

private struct DeconType819: Decodable, Identifiable {
    let id: String
    let name: String?
    let avgMinutes: Int?
    let description: String?
}
private struct DeconRule819: Decodable, Identifiable {
    let from: String?
    let to: String?
    let requiresDecon: String?
    let note: String?
    var id: String { "\(from ?? "")→\(to ?? "")" }
}
private struct DeconScheduleResponse819: Decodable {
    let deconTypes: [DeconType819]?
    let crossContaminationRules: [DeconRule819]?
    let regulation: String?
}

// MARK: - Screen wrapper (Shell + vessel nav · COMPLIANCE inked)

struct VesselContainerDeconScheduleScreen: View {
    let theme: Theme.Palette
    var facilityId: String

    init(theme: Theme.Palette, facilityId: String = "") { self.theme = theme; self.facilityId = facilityId }

    var body: some View {
        Shell(theme: theme) {
            VesselContainerDeconBody819(facilityId: facilityId)
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

private struct VesselContainerDeconBody819: View {
    @Environment(\.palette) private var palette
    let facilityId: String

    @State private var types: [DeconType819] = []
    @State private var rules: [DeconRule819] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showRules = false

    private var maxMinutes: Int { max(1, types.compactMap { $0.avgMinutes }.max() ?? 180) }
    private var fsmaRuleCount: Int { rules.filter { ($0.note ?? "").uppercased().contains("FSMA") }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                topBar
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    heroCard
                    typeBoard
                    washoutBand
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showRules) {
            DeconRulesSheet819(rules: rules).environment(\.palette, palette)
        }
    }

    // MARK: Eyebrow + top bar

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · CONTAINER DECON")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("CFS · WASH RACK").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Decon schedule").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Wash Rack · getDeconSchedule · food-grade rules")
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft).frame(height: 86)
            RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft).frame(height: 300)
        }.padding(.top, Space.s2)
    }
    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Decon reference degraded").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Hero (reference summary · gradient rim)

    private var heroCard: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            Text("\(types.count)").font(.system(size: 30, weight: .bold, design: .monospaced)).tracking(-0.4)
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("decon types · \(rules.count) changeover rules")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("product changeover · \(minRange) · bars scaled to time")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("FSMA").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text("\(fsmaRuleCount) rules").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var minRange: String {
        let mins = types.compactMap { $0.avgMinutes }
        guard let lo = mins.min(), let hi = mins.max() else { return "—" }
        return "\(lo)–\(hi) min"
    }

    // MARK: Type board (minute-scaled bars)

    private var typeBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("DECONTAMINATION TYPES")
                Spacer()
                Text("getDeconSchedule:821").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                if types.isEmpty {
                    EusoEmptyState(systemImage: "drop", title: "No decon types configured",
                                   subtitle: "Wash-rack decon methods appear here from the terminal reference.")
                        .padding(Space.s4)
                } else {
                    ForEach(Array(types.enumerated()), id: \.offset) { idx, t in
                        typeRow(t)
                        if idx < types.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, Space.s4) }
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private func typeRow(_ t: DeconType819) -> some View {
        let g = glyph(for: t.id)
        let mins = t.avgMinutes ?? 0
        let frac = CGFloat(mins) / CGFloat(maxMinutes)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(g.color.opacity(0.16)).frame(width: 40, height: 40)
                    Image(systemName: g.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(g.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name ?? t.id).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(t.description ?? "—").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                Text("\(mins) MIN").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(palette.bgCardSoft))
            }
            // Minute-scaled duration bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 6)
                    Capsule().fill(g.color).frame(width: max(6, geo.size.width * frac), height: 6)
                }
            }
            .frame(height: 6)
            .padding(.leading, 52)
        }
        .padding(Space.s4)
    }

    private struct Glyph819 { let icon: String; let color: Color }
    private func glyph(for id: String) -> Glyph819 {
        switch id {
        case "standard_wash":     return Glyph819(icon: "drop.fill", color: Brand.info)
        case "chemical_decon":    return Glyph819(icon: "flask.fill", color: Brand.warning)
        case "vapor_purge":       return Glyph819(icon: "wind", color: Brand.escort)
        case "cryogenic_warmup":  return Glyph819(icon: "thermometer.snowflake", color: Brand.info)
        case "full_decon":        return Glyph819(icon: "sparkles", color: Brand.danger)
        default:                  return Glyph819(icon: "drop", color: palette.textSecondary)
        }
    }

    // MARK: Food-grade washout authority band

    private var washoutBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("FOOD-GRADE WASHOUT AUTHORITY · BY COUNTRY")
            HStack(spacing: Space.s2) {
                washCell(active: true,  code: "US", body: "FDA FSMA", detail: "21 CFR 117 · active")
                washCell(active: false, code: "CA", body: "CFIA",     detail: "SFCR · standby")
                washCell(active: false, code: "MX", body: "COFEPRIS", detail: "SENASICA · standby")
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func washCell(active: Bool, code: String, body: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(code).font(.system(size: 11, weight: .heavy)).foregroundStyle(active ? Brand.info : palette.textSecondary)
                Text(body).font(.system(size: 10.5, weight: .bold)).foregroundStyle(active ? Brand.info : palette.textPrimary)
            }
            Text(detail).font(EType.mono(.micro)).foregroundStyle(active ? palette.textSecondary : palette.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2).padding(.vertical, 8)
        .background(active ? Brand.info.opacity(0.10) : palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s2) {
                CTAButton(title: "Schedule by bay", action: {}, isLoading: true)
                    .frame(maxWidth: .infinity)
                Button(action: { showRules = true }) {
                    Text("Rules")
                        .font(EType.title).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).frame(maxWidth: 132)
            }
            Text("Booking a decon slot is a write — live when createDeconBooking lands. Tap Rules for the FSMA changeover matrix.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct In819: Encodable { let facilityId: String? }
        do {
            let resp: DeconScheduleResponse819 = try await EusoTripAPI.shared.query(
                "appointments.getDeconSchedule", input: In819(facilityId: facilityId.isEmpty ? nil : facilityId))
            types = resp.deconTypes ?? []
            rules = resp.crossContaminationRules ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Rules sheet (crossContaminationRules)

private struct DeconRulesSheet819: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let rules: [DeconRule819]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("FSMA cross-contamination rules")
                        .font(EType.h2).foregroundStyle(palette.textPrimary)
                    ForEach(rules) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(r.from ?? "—").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
                                Text(r.to ?? "—").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text((r.requiresDecon ?? "").replacingOccurrences(of: "_", with: " ").uppercased())
                                    .font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.warning)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
                            }
                            Text(r.note ?? "").font(EType.caption).foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                }
                .padding(Space.s4)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Changeover rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Previews

#Preview("819 · Vessel Container Decon · Night") {
    VesselContainerDeconScheduleScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("819 · Vessel Container Decon · Light") {
    VesselContainerDeconScheduleScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
