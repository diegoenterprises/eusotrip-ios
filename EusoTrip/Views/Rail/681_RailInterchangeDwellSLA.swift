//
//  681_RailInterchangeDwellSLA.swift
//  EusoTrip — Rail Engineer · Interchange Dwell-SLA Timer.
//
//  Bespoke port of "05 Rail/Dark-SVG/681 Rail Interchange Dwell-SLA
//  Timer.svg". ARCHETYPE = LIVE SLA COUNTDOWN BOARD — a radial countdown
//  ring hero for the most-at-risk junction over a per-junction list with
//  the receiving railroad, corridor, and SLA basis. Not a static status
//  string, not a board/roster/map sibling.
//
//  Role: RAIL_ENGINEER (carrier family). transportMode = rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getCrossBorderInterchangePoints EXISTS:2621
//        {country?,railroad?} → [{id,name,countryA,countryB,railroadsA[],
//        railroadsB[],interchangeType,hazmatAllowed,hasIntermodal,…}]
//        (→ crossBorderRail.getInterchangePoints). These are the REAL
//        interchange junctions + receiving railroads the dwell clock runs at.
//    HONEST GAP: today "interchange_delay" is only a static status enum —
//    there is no per-car receive timestamp feed and no dwell-clock procedure
//    (getInterchangeDwellSLA / escalateInterchange — STUB). The countdown ring
//    + burn bars therefore render an explicit "clock pending" posture against
//    the AAR 48h free-time basis (a regulatory constant) — never a fabricated
//    remaining-time. A junction never clears against an unverified SLA.
//

import SwiftUI

private struct InterchangePt681: Decodable, Identifiable {
    let id: String
    let name: String?
    let countryA: String?
    let countryB: String?
    let railroadsA: [String]?
    let railroadsB: [String]?
    let interchangeType: String?
    let hazmatAllowed: Bool?
    let hasIntermodal: Bool?
    var receivingRoad: String { (railroadsB ?? []).first ?? (railroadsA ?? []).first ?? "—" }
}
private struct InterchangeIn681: Encodable { let country: String?; let railroad: String? }

struct RailInterchangeDwellSLAScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailInterchangeDwellSLABody() } nav: {
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

private struct RailInterchangeDwellSLABody: View {
    @Environment(\.palette) private var palette
    @State private var junctions: [InterchangePt681] = []
    @State private var loading = true
    @State private var country = 0

    private let countryCodes = ["US", "CA", "MX"]
    private let slaHours = 48    // AAR interchange free-time basis
    private let regimes: [(String, String)] = [("US · AAR", "48h free time"),
                                               ("CA · TC", "CN/CPKC IXN"),
                                               ("MX · ARTF", "Ferromex IXN")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Interchange dwell")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("Aurora Rail Division · \(junctions.count) junctions · SLA 48h")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else if junctions.isEmpty {
                    EusoEmptyState(systemImage: "clock.arrow.circlepath",
                                   title: "No active interchange junctions",
                                   subtitle: "The dwell clock runs at the interchange points on the corridor. None are listed for \(countryCodes[country]).")
                } else {
                    ringHero
                    junctionHeader
                    junctionCard
                    regimeBand
                    footerActions
                }
            }
            .padding(.horizontal, 20).padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ RAIL ENGINEER · INTERCHANGE DWELL SLA")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("AAR IXN").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            Button { Task { await cycleCountry() } } label: { chip(countryCodes[country], Brand.blue) }.buttonStyle(.plain)
            chip("\(junctions.count) junctions", palette.textSecondary)
            chip("SLA \(slaHours)h", Brand.rail)
        }
    }
    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var ringHero: some View {
        let lead = junctions.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DWELL COUNTDOWN · \(lead?.name?.uppercased() ?? "JUNCTION")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.warning).lineLimit(1)
                Spacer()
                Text("CLOCK PENDING")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.3).foregroundStyle(Brand.warning)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.warning.opacity(0.16), Brand.blue.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(palette.bgCardSoft, lineWidth: 9).frame(width: 82, height: 82)
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(Brand.warning.opacity(0.7), style: StrokeStyle(lineWidth: 9, lineCap: .round, dash: [3, 5]))
                        .rotationEffect(.degrees(-90)).frame(width: 82, height: 82)
                    VStack(spacing: 1) {
                        Text("\(slaHours)h").font(.system(size: 20, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        Text("SLA").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free-time basis \(slaHours)h").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(lead.map { "\($0.receivingRoad) receiving · \($0.interchangeType ?? "interchange")" } ?? "receiving road")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    Text("remaining time binds on the receive-timestamp feed")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var junctionHeader: some View {
        HStack {
            Text("ACTIVE INTERCHANGE JUNCTIONS · \(junctions.count)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            Spacer()
            Text("AAR interchange").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var junctionCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(junctions.enumerated()), id: \.element.id) { i, j in
                junctionRow(j)
                if i < junctions.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func junctionRow(_ j: InterchangePt681) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(j.name ?? "Junction") · \(j.receivingRoad)")
                        .font(.system(size: 13.5, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text("\(j.countryA ?? "")→\(j.countryB ?? "") · \(j.interchangeType ?? "interchange")\(j.hazmatAllowed == false ? " · no hazmat" : "")")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                Spacer()
                Text("SLA \(slaHours)h").font(.system(size: 9, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Brand.rail)
                    .padding(.horizontal, 8).frame(height: 18)
                    .background(Capsule().fill(Brand.rail.opacity(0.16)))
            }
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft).frame(height: 8)
                        // No elapsed feed → honest empty burn bar with the SLA
                        // tick marked; never a fabricated fill.
                        Rectangle().fill(palette.textTertiary).frame(width: 2, height: 14)
                            .offset(x: geo.size.width - 2)
                    }
                }
                .frame(height: 14)
                Text("awaiting receive time").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, 12)
    }

    private var regimeBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == country ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == country ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { Task { country = i; await reload() } }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Escalate dwell", action: {}).frame(maxWidth: .infinity).disabled(true)
            Button {} label: {
                Text("Notify").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }.buttonStyle(.plain).disabled(true)
        }
    }

    private func cycleCountry() async { country = (country + 1) % countryCodes.count; await reload() }

    private func reload() async {
        loading = true
        junctions = (try? await EusoTripAPI.shared.query(
            "railShipments.getCrossBorderInterchangePoints",
            input: InterchangeIn681(country: countryCodes[country], railroad: nil))) ?? []
        loading = false
    }
}

#Preview("681 · Interchange Dwell-SLA · Night") {
    RailInterchangeDwellSLAScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("681 · Interchange Dwell-SLA · Light") {
    RailInterchangeDwellSLAScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
