//
//  CV375_CatalystM04FleetTrackPair.swift
//  EusoTrip — Catalyst · M-04 fleet-track pair (CV375-CV376).
//
//  Pixel-match to:
//    375 Catalyst In Transit Fleet Track Cel M04
//    376 Catalyst At Delivery Fleet Track Cel M04
//
//  Closes the M-04 scenario chain (CV369-CV376). Both screens track
//  the CEL fleet (Carolina Express Logistics) over the Atlanta →
//  Charlotte leg. Body reads `loads.getById`. Bottom nav frozen.
//

import SwiftUI

private struct CFLoadCtx: Decodable, Hashable {
    let id: Int?
    let loadNumber: String?
    let pickupCity: String?
    let destCity: String?
    let distance: Double?
    let deliveryDate: String?
}

enum CatalystM04TrackKind: String {
    case inTransit, atDelivery
}

private struct CTConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let chainPill: String
    let progressMiles: Int       // 62 / 245
    let totalMiles: Int           // 245
    let eta: String                 // "12:43 EDT" / "appt 14:00"
    let stage: String              // "ROLLING" / "ARRIVED"
}

private extension CatalystM04TrackKind {
    var config: CTConfig {
        switch self {
        case .inTransit:
            return .init(eyebrow: "CATALYST · DISPATCH · IN-TRANSIT · FLEET-TRACK",
                         citation: "§395 · CHAIN PORT 20/N · TRANSIT · 2/4 · CEL ROLLING",
                         title: "In-transit · CEL fleet rolling · I-85 SE",
                         subhead: "Atlanta GA → Charlotte NC · 53' Dry Van · 62/245 mi · ETA 12:43 EDT",
                         pillCopy: "IN-TRANSIT · ROLLING · I-85 SE · ETA 12:43",
                         chainPill: "M-04 · CHAIN PORT 20/N · 09:48 EDT 5/21 · CEL JR rolling I-85 SE",
                         progressMiles: 62, totalMiles: 245,
                         eta: "12:43 EDT", stage: "ROLLING")
        case .atDelivery:
            return .init(eyebrow: "CATALYST · DISPATCH · AT-DELIVERY · FLEET-TRACK",
                         citation: "§399 · CHAIN PORT 21/N · DELIVERY · 2/4 · CEL ARRIVED",
                         title: "At delivery · CEL fleet arrived · CLT Newell",
                         subhead: "Atlanta GA → Charlotte NC · 53' Dry Van · 245/245 mi · appt 14:00 EDT",
                         pillCopy: "AT-DELIVERY · CLT NEWELL · ARRIVED · appt 14:00",
                         chainPill: "M-04 · CHAIN PORT 21/N · 12:46 EDT 5/21 · CEL JR arrived CLT Newell",
                         progressMiles: 245, totalMiles: 245,
                         eta: "appt 14:00", stage: "ARRIVED")
        }
    }
}

private struct CatalystM04TrackShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",          isCurrent: false),
                          NavSlot(label: "Fleet", systemImage: "truck.box.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CatalystM04TrackBody: View {
    let loadId: String
    let kind: CatalystM04TrackKind

    @Environment(\.palette) private var palette
    @State private var load: CFLoadCtx?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                progressCard(c)
                identityRow
                kpiGrid(c)
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadCtx() }
        .refreshable { await loadCtx() }
    }

    private func header(_ c: CTConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CTConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(c.chainPill).font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func progressCard(_ c: CTConfig) -> some View {
        let pct = Double(c.progressMiles) / Double(max(c.totalMiles, 1))
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("LEG PROGRESS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(c.progressMiles)/\(c.totalMiles) mi").font(.caption2.weight(.semibold)).foregroundStyle(palette.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(palette.bgPage).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient.diagonal)
                            .frame(width: max(8, geo.size.width * pct), height: 8)
                    }
                }
                .frame(height: 8)
                Text("CEL JR · \(c.stage) · ETA \(c.eta)").font(.caption2).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("DU").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eusorone Technologies · Diego Usoro · catalyst").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("LD-260427-E5C9A41B22 · CEL-MC712944 · driver JR · 53' Dry Van").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CTConfig) -> some View {
        let pctInt = Int(Double(c.progressMiles) / Double(max(c.totalMiles, 1)) * 100)
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .inTransit:
                return [
                    ("ETA",     c.eta,                     "rolling · live",      .blue),
                    ("DIST",    "\(c.progressMiles) mi",    "\(c.totalMiles - c.progressMiles) mi left", .blue),
                    ("STAGE",   c.stage,                     "I-85 SE",            .green),
                    ("PROGRESS","\(pctInt)%",                 "of leg",             .green),
                ]
            case .atDelivery:
                return [
                    ("APPT",    "14:00",                     "EDT · receiver",     .blue),
                    ("STAGE",   c.stage,                      "CLT Newell · 0:00 ago", .green),
                    ("DIST",    "245/245 mi",                  "leg complete",      .green),
                    ("PROGRESS","100%",                          "of leg",          .green),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    private var nextStepCard: some View {
        let copy: String = {
            switch kind {
            case .inTransit:  return "CEL fleet rolling I-85 SE. ESang nudges DU if ETA drifts >10 min vs the 12:43 EDT target."
            case .atDelivery: return "CEL fleet arrived at CLT Newell. Appt holds at 14:00 EDT; receiver-bay queue arms on dock placement."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadCtx() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* */ }
    }
}

// MARK: - Screens (CV375-CV376)

struct CatalystM04InTransitTrackScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystM04TrackShell(theme: theme) { CatalystM04TrackBody(loadId: loadId, kind: .inTransit) } }
}
struct CatalystM04AtDeliveryTrackScreen: View {
    let theme: Theme.Palette; let loadId: String
    var body: some View { CatalystM04TrackShell(theme: theme) { CatalystM04TrackBody(loadId: loadId, kind: .atDelivery) } }
}

// MARK: - Previews

#Preview("CV375 Transit · Dark")   { CatalystM04InTransitTrackScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV376 Delivered · Light"){ CatalystM04AtDeliveryTrackScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
