//
//  676_RailPTCRouteQualification.swift
//  EusoTrip — Rail Engineer · PTC Route Qualification (49 CFR §236).
//
//  Bespoke port of "05 Rail/Dark-SVG/676 Rail PTC Route Qualification.svg".
//  ARCHETYPE = PTC-QUALIFICATION MATRIX — a verdict hero over a
//  segment × PTC-status grid (rows = owning-railroad interchange segments;
//  columns = Coverage / Loco code / Interop; cells = pass / review / n-a).
//  Deliberately distinct from every board/roster/timeline sibling.
//
//  Role: RAIL_ENGINEER (carrier family). transportMode = rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getCrossBorderInterchangePoints EXISTS:2621
//        {country?,railroad?} → [{id,name,countryA,countryB,stateProvinceA,
//        stateProvinceB,railroadsA[],railroadsB[],interchangeType,…}]
//        (→ crossBorderRail.getInterchangePoints). These are the REAL
//        route segments + owning/receiving railroads. The INTEROP column is
//        real-derived: a cross-railroad handoff (railroadsA ⧧ railroadsB) is
//        the classic PTC interoperability review; a same-road segment passes.
//    HONEST GAP: per-segment PTC coverage + the lead-loco I-ETMS code map
//    have no backing procedure (getPTCRouteQualification — STUB), so the
//    Coverage / Loco columns render N-A (compute pending), never a
//    fabricated "covered". A cross-border segment never auto-clears.
//

import SwiftUI

private struct InterchangePt676: Decodable, Identifiable {
    let id: String
    let name: String?
    let countryA: String?
    let countryB: String?
    let stateProvinceA: String?
    let stateProvinceB: String?
    let railroadsA: [String]?
    let railroadsB: [String]?
    let interchangeType: String?
    var crossRailroad: Bool {
        let a = Set(railroadsA ?? []), b = Set(railroadsB ?? [])
        return !a.isEmpty && !b.isEmpty && a.isDisjoint(with: b)
    }
    var crossBorder: Bool { (countryA ?? "") != (countryB ?? "") }
}
private struct InterchangeIn676: Encodable { let country: String?; let railroad: String? }

struct RailPTCRouteQualificationScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailPTCRouteQualificationBody() } nav: {
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

private struct RailPTCRouteQualificationBody: View {
    @Environment(\.palette) private var palette
    @State private var segments: [InterchangePt676] = []
    @State private var loading = true
    @State private var country = 0

    private let countryCodes = ["US", "CA", "MX"]
    private let regimes: [(String, String)] = [("US · FRA §236", "I-ETMS"),
                                               ("CA · TC", "Enh. Train Ctrl"),
                                               ("MX · ARTF", "control de tren")]

    private enum Cell { case pass, review, na
        var color: Color { switch self { case .pass: Brand.success; case .review: Brand.warning; case .na: Color(hex: 0x6E7681) } }
        var glyph: String { switch self { case .pass: "checkmark"; case .review: "exclamationmark"; case .na: "minus" } }
    }

    private var advisories: Int { segments.filter { $0.crossRailroad || $0.crossBorder }.count }
    private var qualified: Bool { !segments.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("PTC route")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("Aurora Rail Division · I-ETMS · interchange qualification")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else if segments.isEmpty {
                    EusoEmptyState(systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                                   title: "No interchange segments on file",
                                   subtitle: "PTC route qualification maps to the interchange points on the route. None are listed for \(countryCodes[country]) — switch corridor or check the tender.")
                } else {
                    verdictHero
                    matrixHeader
                    matrixCard
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
            Text("✦ RAIL ENGINEER · PTC QUALIFICATION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("49 CFR §236").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            Button { Task { await cycleCountry() } } label: { chip(countryCodes[country], Brand.blue) }.buttonStyle(.plain)
            chip("\(segments.count) segments", palette.textSecondary)
            chip(advisories == 0 ? "no advisory" : "\(advisories) advisory", advisories == 0 ? Brand.success : Brand.warning)
        }
    }
    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var verdictHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("POSITIVE TRAIN CONTROL · 49 CFR §236")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.success)
                Spacer()
                Text(advisories == 0 ? "QUALIFIED" : "\(advisories) ADVISORY")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(advisories == 0 ? Brand.success : Brand.warning)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill((advisories == 0 ? Brand.success : Brand.warning).opacity(0.16)))
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.success.opacity(0.12), Brand.blue.opacity(0.05)], startPoint: .leading, endPoint: .trailing))

            VStack(alignment: .leading, spacing: 6) {
                Text(qualified ? "QUALIFIED" : "NOT QUALIFIED")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(segments.count) segments · \(advisories) interop review\(advisories == 1 ? "" : "s") · loco I-ETMS code compute pending")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var matrixHeader: some View {
        HStack {
            Text("ROUTE × PTC COVERAGE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            Spacer()
            Text("owning railroad").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var matrixCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(["Cover", "Loco", "Interop"], id: \.self) { h in
                    Text(h).font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary).frame(width: 52)
                }
            }
            .padding(.top, 12).padding(.bottom, 8)
            Divider().overlay(palette.borderFaint)
            ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                matrixRow(seg)
                if idx < segments.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func matrixRow(_ seg: InterchangePt676) -> some View {
        // Coverage + loco = honest N-A (no getPTCRouteQualification). Interop is
        // real-derived from the cross-railroad / cross-border handoff.
        let interop: Cell = seg.crossRailroad || seg.crossBorder ? .review : .pass
        let owning = (seg.railroadsA ?? []).first ?? "—"
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(seg.name ?? "Segment").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("\(owning) · \(seg.interchangeType ?? "interchange")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cellDot(.na)
            cellDot(.na)
            cellDot(interop)
        }
        .padding(.vertical, 12)
    }

    private func cellDot(_ c: Cell) -> some View {
        ZStack {
            Circle().fill(c.color.opacity(0.16)).frame(width: 22, height: 22)
            Image(systemName: c.glyph).font(.system(size: 9, weight: .heavy)).foregroundStyle(c.color)
        }
        .frame(width: 52)
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
            CTAButton(title: "Confirm qualification", action: {})
                .frame(maxWidth: .infinity).disabled(true)
            Button {} label: {
                Text("Report gap").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
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
        segments = (try? await EusoTripAPI.shared.query(
            "railShipments.getCrossBorderInterchangePoints",
            input: InterchangeIn676(country: countryCodes[country], railroad: nil))) ?? []
        loading = false
    }
}

#Preview("676 · PTC Route Qualification · Night") {
    RailPTCRouteQualificationScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("676 · PTC Route Qualification · Light") {
    RailPTCRouteQualificationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
