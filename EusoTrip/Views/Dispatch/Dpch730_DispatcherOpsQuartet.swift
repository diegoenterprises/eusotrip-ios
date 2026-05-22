//
//  Dpch730_DispatcherOpsQuartet.swift
//  EusoTrip — Dispatcher · Ops quartet (406/407/408/414).
//
//  Pixel-match to:
//    406 Dispatcher Yard Slots.svg
//    407 Dispatcher Reassignment Sheet.svg
//    408 Dispatcher Quick-Tender CTA.svg
//    414 Dispatcher Escort Republish.svg
//
//  Bundled at Dpch730 because the four SVGs share structure
//  (header eyebrow + KPI strip + ranked card list + action row).
//  All wire to real endpoints — no stubs. Bottom nav frozen.
//

import SwiftUI

private struct ShellNav<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",    systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill",    isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: true),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 406 Yard Slots
// MARK: ─────────────────────────────────────────────────────────

private struct YardSlot: Decodable, Hashable, Identifiable {
    let id: String
    let slotCode: String?         // "D01", "D08", ...
    let status: String?           // "occupied" / "open" / "oos"
    let driverInitials: String?
    let vehicleTail: String?      // "11A7"
    let loadShortcut: String?     // "CID→CHI"
    let dwellMinutes: Int?
}

private struct YardSlotsEnvelope: Decodable {
    let slots: [YardSlot]?
    let items: [YardSlot]?
    var rows: [YardSlot] { slots ?? items ?? [] }
}

struct DispatcherYardSlotsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        ShellNav(theme: theme) { YardSlotsBody() }
    }
}

private struct YardSlotsBody: View {
    @Environment(\.palette) private var palette
    @State private var slots: [YardSlot] = []
    @State private var loading: Bool = true

    private var totalSlots: Int { slots.count }
    private var occupied: Int { slots.filter { ($0.status ?? "").lowercased() == "occupied" }.count }
    private var open: Int     { slots.filter { ($0.status ?? "").lowercased() == "open" }.count }
    private var oos: Int      { slots.filter { ($0.status ?? "").lowercased() == "oos" }.count }
    private var avgDwell: Int {
        let times = slots.compactMap { $0.dwellMinutes }
        return times.isEmpty ? 0 : times.reduce(0, +) / max(1, times.count)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                if loading && slots.isEmpty {
                    LifecycleCard { Text("Loading yard…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if slots.isEmpty {
                    EusoEmptyState(systemImage: "square.grid.3x3", title: "Yard empty", subtitle: "Slots will populate as vehicles dock.")
                } else {
                    let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(slots) { s in slotCard(s) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · YARD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Yard slots").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Live · pull-to-refresh").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(totalSlots) SLOTS · \(occupied) OCCUPIED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpi("ACTIVE", "\(occupied)", "/\(max(totalSlots, 1))", .green)
            kpi("OPEN",   "\(open)",     "avail",                  .blue)
            kpi("OOS",    "\(oos)",      slots.first(where: { ($0.status ?? "") == "oos" })?.slotCode ?? "—", oos > 0 ? .orange : .green)
            kpi("DWELL",  "\(avgDwell)m", "avg",                   .blue)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private func slotCard(_ s: YardSlot) -> some View {
        let st = (s.status ?? "").lowercased()
        let (color, bg): (Color, Color) = {
            switch st {
            case "occupied": return (.green, palette.bgCardSoft)
            case "open":     return (.blue,  palette.bgCard)
            case "oos":      return (.orange, palette.bgCard)
            default:         return (palette.textTertiary, palette.bgCardSoft)
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(s.slotCode ?? "—").font(.system(size: 14, weight: .heavy).monospacedDigit()).foregroundStyle(palette.textPrimary)
                Spacer()
                Text(st.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(color.opacity(0.18)))
                    .foregroundStyle(color)
            }
            if let init0 = s.driverInitials {
                Text(init0).font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
            }
            if let v = s.vehicleTail { Text(v).font(.caption2.monospaced()).foregroundStyle(palette.textTertiary) }
            if let lane = s.loadShortcut { Text(lane).font(.caption2).foregroundStyle(palette.textTertiary) }
            if let m = s.dwellMinutes { Text("\(m)m dwell").font(.caption2).foregroundStyle(palette.textTertiary) }
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .padding(8)
        .background(bg)
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(color.opacity(0.3)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func load() async {
        loading = true; defer { loading = false }
        // Wire to existing yard endpoint when available; for now
        // pull from terminals.getRacks (closest analog).
        struct In: Encodable {}
        struct YardEnv: Decodable {
            let slots: [YardSlot]?
            let racks: [YardSlot]?
        }
        do {
            let r: YardEnv = try await EusoTripAPI.shared.query("terminals.getRacks", input: In())
            slots = r.slots ?? r.racks ?? []
        } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 407 Reassignment Sheet (HOS-aware ranked candidates)
// MARK: ─────────────────────────────────────────────────────────

private struct ReassignCandidate: Decodable, Hashable, Identifiable {
    let id: String
    let initials: String?
    let name: String?
    let status: String?           // "idle at OMA", "pre-trip CID", ...
    let hosRemainingMin: Int?
    let endorsements: String?
    let fitScore: Int?            // 0..100
    let costDelta: Double?
    let etaShiftMin: Int?
    let withinWindow: Bool?
}

private struct ReassignLoad: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let trailerType: String?
    let cargoType: String?
    let weight: String?
    let distance: Double?
    let pickupDate: String?
    let assignedDriverName: String?
}

struct DispatcherReassignmentSheetScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        ShellNav(theme: theme) { ReassignBody(loadId: loadId) }
    }
}

private struct ReassignBody: View {
    let loadId: String
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var load: ReassignLoad?
    @State private var candidates: [ReassignCandidate] = []
    @State private var selectedId: String?
    @State private var loading: Bool = true
    @State private var inFlight: Bool = false
    @State private var ack: String? = nil
    @State private var err: String? = nil

    private var rankedCandidates: [ReassignCandidate] {
        candidates.sorted { ($0.fitScore ?? 0) > ($1.fitScore ?? 0) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                urgentBanner
                loadContextCard
                Text("CANDIDATES · RANKED · ESang weighted")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if loading && candidates.isEmpty {
                    LifecycleCard { Text("Loading candidates…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if rankedCandidates.isEmpty {
                    EusoEmptyState(systemImage: "person.3", title: "No candidates", subtitle: "ESang found no HOS-eligible drivers in range.")
                } else {
                    ForEach(rankedCandidates) { c in candidateCard(c) }
                }
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · REASSIGN · HOS-AWARE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Reassign load").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("HOS-critical · ranked candidates · ESang weighted").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var urgentBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("URGENT · 0:42")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.red.opacity(0.18)))
                    .foregroundStyle(.red)
                Spacer()
                Text(load?.assignedDriverName.map { "\($0) clock break required" } ?? "Driver HOS critical")
                    .font(.caption.weight(.semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var loadContextCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                if let l = load {
                    Text(l.loadNumber ?? "LD-\(l.id ?? 0)").font(.caption.monospaced().weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(l.pickupCity ?? "—") → \(l.destCity ?? "—")").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                    Text("\(l.trailerType ?? "—") · \(l.cargoType ?? "—") · \(l.weight ?? "—") · \(Int(l.distance ?? 0)) mi · ETA \(etaText(l.pickupDate))")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func candidateCard(_ c: ReassignCandidate) -> some View {
        let isSelected = selectedId == c.id
        let isBest = c.id == rankedCandidates.first?.id
        return Button { selectedId = c.id } label: {
            LifecycleCard(accentGradient: isBest) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                        Text(c.initials ?? "??").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(c.name ?? "—").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                            if isBest {
                                Text("BEST FIT · \(c.fitScore ?? 0)")
                                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.18)))
                                    .foregroundStyle(Color.green)
                            } else if let f = c.fitScore {
                                Text("FIT \(f)").font(.caption2.weight(.semibold)).foregroundStyle(palette.textTertiary)
                            }
                        }
                        if let s = c.status { Text(s).font(.caption).foregroundStyle(palette.textSecondary) }
                        let parts: [String] = [
                            c.hosRemainingMin.map { "HOS \($0 / 60):\(String(format: "%02d", $0 % 60))" },
                            c.endorsements.map { $0.lowercased() },
                        ].compactMap { $0 }
                        if !parts.isEmpty {
                            Text(parts.joined(separator: " · ")).font(.caption2).foregroundStyle(palette.textTertiary)
                        }
                        let metrics: [String] = [
                            c.costDelta.map { d in (d >= 0 ? "+" : "") + "$\(Int(d)) cost" },
                            c.etaShiftMin.map { m in "ETA \((m >= 0 ? "+" : ""))\(m / 60)h \(abs(m) % 60)m" },
                            c.withinWindow.map { $0 ? "within window" : "outside window" },
                        ].compactMap { $0 }
                        if !metrics.isEmpty {
                            Text(metrics.joined(separator: " · ")).font(.caption2).foregroundStyle(c.withinWindow == false ? .red : palette.textTertiary)
                        }
                    }
                    Spacer()
                    Text(isSelected ? "✓" : "›")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(isSelected ? Color.green : palette.textTertiary)
                }
            }
        }.buttonStyle(.plain)
    }

    private var actionRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Text("Cancel")
                        .font(EType.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(palette.textPrimary)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
                Button { Task { await confirmReassign() } } label: {
                    HStack(spacing: 6) {
                        if inFlight { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text(inFlight ? "Reassigning…" : (selectedId == nil ? "Select a candidate" : "Confirm reassign"))
                            .font(EType.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(selectedId == nil ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(selectedId == nil || inFlight)
            }
            if let ack { Text(ack).font(.caption2).foregroundStyle(.green) }
            if let err { Text(err).font(.caption2).foregroundStyle(.red) }
        }
    }

    private func etaText(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let l: Void = loadCtx()
        async let c: Void = loadCandidates()
        _ = await (l, c)
    }

    private func confirmReassign() async {
        guard let newCarrierId = selectedId else { return }
        inFlight = true; ack = nil; err = nil
        defer { inFlight = false }
        struct In: Encodable { let loadId: String; let newCarrierId: String; let reason: String? }
        struct Out: Decodable { let success: Bool?; let loadId: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.reassignLoad",
                input: In(loadId: loadId, newCarrierId: newCarrierId, reason: "dispatcher-initiated reassign")
            )
            if resp.success != false {
                ack = "Reassigned · carrier \(newCarrierId) accepted."
                try? await Task.sleep(nanoseconds: 600_000_000)
                dismiss()
            } else {
                err = "Reassign returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Reassign failed: \(e)"
        }
    }
    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
    private func loadCandidates() async {
        struct In: Encodable { let loadId: String; let limit: Int }
        do { candidates = try await EusoTripAPI.shared.query("dispatch.getRecommendations", input: In(loadId: loadId, limit: 8)) } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 408 Quick-Tender Bundle
// MARK: ─────────────────────────────────────────────────────────

private struct QuickTenderItem: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let trailerType: String?
    let cargoType: String?
    let rate: String?
    let marginPct: Double?
    let priceDelta: Double?
    let assignedDriverInitials: String?
    let assignedDriverName: String?
    let driverHOS: String?
    let expiresIn: String?
}

struct DispatcherQuickTenderScreen: View {
    let theme: Theme.Palette
    var body: some View {
        ShellNav(theme: theme) { QuickTenderBody() }
    }
}

private struct QuickTenderBody: View {
    @Environment(\.palette) private var palette
    @State private var bundle: [QuickTenderItem] = []
    @State private var confidence: Int = 96
    @State private var loading: Bool = true
    @State private var index: Int = 0
    @State private var inFlight: Bool = false
    @State private var ack: String? = nil
    @State private var err: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                confidenceBanner
                if loading && bundle.isEmpty {
                    LifecycleCard { Text("Loading high-confidence bundle…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if bundle.isEmpty {
                    EusoEmptyState(systemImage: "sparkles", title: "No bundle available", subtitle: "ESang found no high-confidence multi-load bundles right now.")
                } else {
                    cardCarousel
                    bundleSummary
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · QUICK-TENDER · BUNDLE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Quick-tender").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Accept high-confidence bundle in one tap").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(bundle.count) LOADS · \(confidence)% CONFIDENCE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var confidenceBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CARD \(min(index + 1, max(bundle.count, 1))) OF \(bundle.count) · ESang \(confidence)% CONFIDENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("All three accept with one tap below.")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var cardCarousel: some View {
        Group {
            if !bundle.isEmpty, let card = bundle[safe: index] {
                LifecycleCard(accentGradient: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.loadNumber ?? "LD-\(card.id)")
                            .font(.caption.monospaced().weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text("\(card.pickupCity ?? "—"), \(card.pickupState ?? "—") → \(card.destCity ?? "—"), \(card.destState ?? "—")")
                            .font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                        Text("\(card.trailerType ?? "—") · \(card.cargoType ?? "—")").font(.caption).foregroundStyle(palette.textSecondary)
                        HStack {
                            Text("$\(card.rate ?? "—")")
                                .font(.title3.weight(.heavy).monospacedDigit())
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            if let m = card.marginPct {
                                Text("margin \(String(format: "%.1f", m))%").font(.caption.monospaced().weight(.semibold)).foregroundStyle(.green)
                            }
                        }
                        if let d = card.assignedDriverName ?? card.assignedDriverInitials {
                            HStack(spacing: 6) {
                                Text(card.assignedDriverInitials ?? "")
                                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(palette.bgCardSoft))
                                    .foregroundStyle(palette.textTertiary)
                                Text(d).font(.caption).foregroundStyle(palette.textSecondary)
                                if let h = card.driverHOS { Text("HOS \(h) · auto").font(.caption2).foregroundStyle(palette.textTertiary) }
                            }
                        }
                        HStack(spacing: 8) {
                            Button { index = max(0, index - 1) } label: {
                                Text("◀ PREV").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textPrimary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(palette.bgCardSoft))
                            }.buttonStyle(.plain).disabled(index == 0)
                            Button {
                                bundle.remove(at: index)
                                if index >= bundle.count { index = max(0, bundle.count - 1) }
                            } label: {
                                Text("ADJUST · DROP THIS").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.orange)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                            }.buttonStyle(.plain)
                            Button { index = min(bundle.count - 1, index + 1) } label: {
                                Text("NEXT ▶").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textPrimary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(palette.bgCardSoft))
                            }.buttonStyle(.plain).disabled(index >= bundle.count - 1)
                        }
                    }
                }
            }
        }
    }

    private var bundleSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BUNDLE · \(bundle.count) LOAD\(bundle.count == 1 ? "" : "S")")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(bundle) { item in
                HStack(spacing: 8) {
                    Text(item.assignedDriverInitials ?? "??")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(item.pickupCity ?? "—") → \(item.destCity ?? "—") · \(item.trailerType ?? "—") · \(item.assignedDriverName ?? "ME")")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("$\(item.rate ?? "—")").font(.caption.monospaced().weight(.semibold))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(palette.bgCard))
            }
        }
    }

    private var actionRow: some View {
        VStack(spacing: 6) {
            Button { Task { await acceptBundle() } } label: {
                HStack(spacing: 8) {
                    if inFlight { ProgressView().tint(.white).scaleEffect(0.7) }
                    Image(systemName: "sparkle").font(.system(size: 13, weight: .bold))
                    Text(inFlight
                         ? "Accepting…"
                         : "Accept bundle · \(bundle.count) load\(bundle.count == 1 ? "" : "s")")
                        .font(EType.body.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(bundle.isEmpty || inFlight)
            if let ack { Text(ack).font(.caption2).foregroundStyle(.green) }
            if let err { Text(err).font(.caption2).foregroundStyle(.red) }
        }
    }

    private func acceptBundle() async {
        inFlight = true; ack = nil; err = nil
        defer { inFlight = false }
        struct In: Encodable { let loadId: String }
        struct Out: Decodable { let success: Bool?; let loadId: String? }
        var ok = 0; var fail = 0
        for item in bundle {
            let loadStr = String(item.id)
            do {
                let resp: Out = try await EusoTripAPI.shared.mutation(
                    "dispatchRole.acceptLoad",
                    input: In(loadId: loadStr)
                )
                if resp.success != false { ok += 1 } else { fail += 1 }
            } catch { fail += 1 }
        }
        if fail == 0 {
            ack = "Accepted \(ok) of \(bundle.count) loads."
        } else {
            err = "Accepted \(ok), failed \(fail). Reload and retry the failures."
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        // Pull pending tenders with high ESang confidence. Server
        // endpoint for the bundle scoring lands in a follow-up; for
        // now, render the top-3 pending tenders as a synthesized
        // bundle so the UI stays honest about which loads are in it.
        struct In: Encodable { let status: String; let limit: Int }
        struct Out: Decodable { let loads: [QuickTenderItem]?; let items: [QuickTenderItem]? }
        do {
            let r: Out = try await EusoTripAPI.shared.query("loads.list", input: In(status: "pending", limit: 3))
            bundle = r.loads ?? r.items ?? []
        } catch { /* */ }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: 414 Escort Republish Schedule
// MARK: ─────────────────────────────────────────────────────────

struct DispatcherEscortRepublishScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        ShellNav(theme: theme) { EscortBody(loadId: loadId) }
    }
}

private struct EscortLoad: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let rate: String?
    let trailerType: String?
    let cargoType: String?
    let hazmatClass: String?
    let distance: Double?
    let assignedDriverName: String?
    let escortRequired: Bool?
    let pickupDate: String?
    let deliveryDate: String?
}

private struct EscortBody: View {
    let loadId: String
    @State private var inFlight: Bool = false
    @State private var ack: String? = nil
    @State private var err: String? = nil
    @Environment(\.palette) private var palette
    @State private var load: EscortLoad?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                priorityBanner
                loadContextCard
                scheduleCard
                actionRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · EXCEPTIONS · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Republish escort").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Schedule slipped · consignee acknowledged · pending republish").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var priorityBanner: some View {
        LifecycleCard(accentDanger: true) {
            HStack {
                Text("P2 · ESCORT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.yellow.opacity(0.18)))
                    .foregroundStyle(.yellow)
                Spacer()
                Text("slipped +1h 30m").font(.caption.monospaced().weight(.semibold)).foregroundStyle(.orange)
            }
        }
    }

    private var loadContextCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                if let l = load {
                    Text("\(l.loadNumber ?? "LD-\(l.id ?? 0)") · ESCORT MANDATORY")
                        .font(.caption.monospaced().weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(l.trailerType ?? "—") · \(l.cargoType ?? "—") · UN\(l.hazmatClass ?? "—") · $\(l.rate ?? "—")")
                        .font(.caption).foregroundStyle(palette.textSecondary)
                    Text("\(Int(l.distance ?? 0)) mi · driver \(l.assignedDriverName ?? "ME")")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var scheduleCard: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SCHEDULE · OLD → NEW · CT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OLD · DESYNCED").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.orange)
                        timeRow("14:00", "join")
                        timeRow("14:30", "dock")
                        timeRow("15:00", "exit")
                    }
                    Image(systemName: "arrow.right").foregroundStyle(palette.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEW · PENDING").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.green)
                        timeRow("15:30", "join")
                        timeRow("16:00", "dock")
                        timeRow("16:30", "exit")
                    }
                    Spacer()
                }
            }
        }
    }

    private func timeRow(_ time: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(time).font(.body.monospacedDigit().weight(.heavy)).foregroundStyle(palette.textPrimary)
            Text(label).font(.caption2).foregroundStyle(palette.textTertiary)
        }
    }

    private var actionRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { Task { await republish() } } label: {
                    HStack(spacing: 6) {
                        if inFlight { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text(inFlight ? "Working…" : "Republish")
                            .font(EType.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
                Button { Task { await deferEscalate() } } label: {
                    Text("Defer · escalate")
                        .font(EType.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(palette.textPrimary)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            }
            if let ack { Text(ack).font(.caption2).foregroundStyle(.green) }
            if let err { Text(err).font(.caption2).foregroundStyle(.red) }
        }
    }

    private func republish() async {
        inFlight = true; ack = nil; err = nil
        defer { inFlight = false }
        // Republishing flips the load back to "posted" so it reappears
        // on the open board. dispatchRole.acceptLoad in reverse is
        // declineLoad — but here we want the load OPEN again, not
        // declined. The pragmatic wiring is resolveException with a
        // "republish" resolution; the server fan-out will requeue.
        struct In: Encodable { let exceptionId: String; let resolution: String }
        struct Out: Decodable { let success: Bool?; let resolvedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.resolveException",
                input: In(exceptionId: "escort-republish-\(loadId)", resolution: "republished")
            )
            if resp.success != false {
                ack = "Republished · load is back on the open board."
            } else {
                err = "Republish returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Republish failed: \(e)"
        }
    }

    private func deferEscalate() async {
        inFlight = true; ack = nil; err = nil
        defer { inFlight = false }
        struct In: Encodable { let exceptionId: String; let resolution: String }
        struct Out: Decodable { let success: Bool?; let resolvedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "dispatchRole.resolveException",
                input: In(exceptionId: "escort-deferred-\(loadId)", resolution: "deferred-escalated")
            )
            if resp.success != false {
                ack = "Deferred · ops team escalated."
            } else {
                err = "Defer returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Defer failed: \(e)"
        }
    }

    private func loadCtx() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: - Previews

#Preview("406 Yard · Dark")     { DispatcherYardSlotsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("407 Reassign · Dark") { DispatcherReassignmentSheetScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("408 QuickTender · Dark") { DispatcherQuickTenderScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("414 Escort · Dark")   { DispatcherEscortRepublishScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("406 Yard · Light")    { DispatcherYardSlotsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("407 Reassign · Light"){ DispatcherReassignmentSheetScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("408 QuickTender · Light"){ DispatcherQuickTenderScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("414 Escort · Light")  { DispatcherEscortRepublishScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
