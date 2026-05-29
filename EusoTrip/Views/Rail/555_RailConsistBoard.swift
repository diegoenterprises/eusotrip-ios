//
//  555_RailConsistBoard.swift
//  EusoTrip — Rail Engineer · Consist Board (carrier vantage).
//

import SwiftUI

struct RailConsistBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailConsistBoardBody() } nav: {
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

private struct TrainConsist: Decodable, Identifiable {
    let id: Int
    let consistNumber: String?
    let originYard: String?
    let destinationYard: String?
    let totalCars: Int?
    let assignedCars: Int?
    let hazmatCars: Int?
    let status: String?
    let note: String?
}

private struct ConsistsResponse: Decodable {
    let consists: [TrainConsist]
    let total: Int
}

private struct RailConsistBoardBody: View {
    @Environment(\.palette) private var palette
    @State private var consists: [TrainConsist] = []
    @State private var totalCars = 0
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var building = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading consists…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if consists.isEmpty {
                    EusoEmptyState(systemImage: "tram.fill", title: "No consists",
                                   subtitle: "Building and rolling consists will appear here.")
                } else {
                    VStack(spacing: Space.s2) { ForEach(consists) { consistCard($0) } }
                    CTAButton(title: building ? "Building…" : "Build new consist", leadingIcon: "plus",
                              action: { Task { await buildConsist() } })
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
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Image(systemName: "tram.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · CONSISTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Consist board").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("\(consists.count) consists building / rolling · \(totalCars) cars total")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func consistCard(_ c: TrainConsist) -> some View {
        let rolling = (c.status ?? "").lowercased() == "rolling"
        let total = c.totalCars ?? 0
        let assigned = min(c.assignedCars ?? total, total)
        let hazmat = min(c.hazmatCars ?? 0, total)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(c.consistNumber ?? "—").font(.system(size: 15, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: (c.status ?? "—").uppercased(), kind: rolling ? .info : .neutral)
            }
            Text("\(c.originYard ?? "—") → \(c.destinationYard ?? "—") · \(assigned)/\(total) cars\(c.note.map { " · \($0)" } ?? "")")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            ConsistCarStrip555(total: total, assigned: assigned, hazmat: hazmat, trackTint: palette.textTertiary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func load() async {
        loading = true; loadError = nil
        struct ConsistsIn: Encodable { let limit: Int; let offset: Int }
        do {
            let result: ConsistsResponse = try await EusoTripAPI.shared.query(
                "railShipments.getTrainConsists", input: ConsistsIn(limit: 20, offset: 0))
            self.consists = result.consists
            self.totalCars = result.consists.reduce(0) { $0 + ($1.totalCars ?? 0) }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func buildConsist() async {
        building = true
        building = false
    }
}

// MARK: - Consist car strip (assigned + hazmat indicators)
//
// A horizontal strip of car tiles that reads as the consist being built. The
// strip is bound to the real data model: `assigned` of `total` cars are
// coupled (the real build/load fraction assigned/total), and the trailing
// `hazmat` cars carry the IMDG/hazmat tint.
//
// Motion:
//  • Build sequence — on appear/change, the assigned cars settle in
//    left-to-right with a short per-car stagger and a decelerating spring
//    (transform/opacity only), so the row reads as cars being coupled onto
//    the consist up to the true assigned count. Unassigned slots stay as
//    dashed-empty couplers and never animate in.
//  • Hazmat attention — the hazmat cars carry a seamless ambient breathing
//    glow (autoreversing easeInOut, start == end) signalling a live safety
//    indicator. The build itself is never an indefinite loop.
//  • Reduce Motion — snaps straight to the final state: all assigned cars
//    shown at full presence, no stagger, no hazmat pulse.
private struct ConsistCarStrip555: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Real values from the data model.
    let total: Int
    let assigned: Int
    let hazmat: Int
    /// Tint for empty / unassigned coupler slots.
    let trackTint: Color

    /// How many assigned cars have settled in. Starts at 0 so the consist
    /// "builds up" to its true assigned count on appear.
    @State private var built: Int = 0
    /// Drives the seamless hazmat breathing loop.
    @State private var pulsing = false

    private var hasHazmat: Bool { hazmat > 0 && total > 0 }
    private var pulse: Bool { hasHazmat && !reduceMotion }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 0), id: \.self) { idx in
                car(idx)
            }
        }
        .onAppear { settle() }
        .onChange(of: assigned) { _, _ in settle() }
        .onChange(of: total) { _, _ in settle() }
        .onChange(of: hazmat) { _, _ in settle() }
    }

    @ViewBuilder
    private func car(_ idx: Int) -> some View {
        let isAssigned = idx < assigned
        let isHazmat = isAssigned && idx >= (total - hazmat)
        let shown = idx < built          // has this assigned car settled in yet?
        let fill: AnyShapeStyle = !isAssigned
            ? AnyShapeStyle(Color.clear)
            : (isHazmat ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(Brand.success))

        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .strokeBorder(isAssigned ? Color.clear : trackTint, lineWidth: 1.2)
            )
            .frame(width: 11, height: 14)
            // Hazmat live-safety glow — seamless autoreversing loop.
            .shadow(color: (isHazmat && pulse) ? Brand.warning.opacity(pulsing ? 0.65 : 0.0) : .clear,
                    radius: (isHazmat && pulse) ? (pulsing ? 4 : 0) : 0)
            // Build-in transform: assigned cars rise + scale into place.
            .scaleEffect(isAssigned ? (shown ? 1.0 : 0.4) : 1.0, anchor: .bottom)
            .opacity(isAssigned ? (shown ? 1.0 : 0.0) : 1.0)
    }

    private func settle() {
        if reduceMotion {
            built = assigned
            pulsing = false
            return
        }
        // Re-run the build from empty so a data change re-couples cleanly.
        built = 0
        for i in 0..<max(assigned, 0) {
            // Decelerating spring, staggered left-to-right (cap stagger so very
            // long consists still finish promptly — UI beat stays < 600ms tail).
            let delay = Double(i) * min(0.045, 0.4 / Double(max(assigned, 1)))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78).delay(delay)) {
                built = i + 1
            }
        }
        // Ambient hazmat pulse: continuous, seamless (start == end).
        if hasHazmat {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        } else {
            pulsing = false
        }
    }
}

#Preview("555 · Rail Consist Board · Night") { RailConsistBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("555 · Rail Consist Board · Light") { RailConsistBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
