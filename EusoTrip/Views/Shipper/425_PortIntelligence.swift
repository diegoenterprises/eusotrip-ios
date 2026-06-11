//
//  425_PortIntelligence.swift
//  EusoTrip — Shipper · Port intelligence (ports / refineries / terminals by product grade).
//
//  Emergency Wave I2 (2026-06-11) — root causes closed:
//    • `init(product:)` lands the 424→425 handoff: SpectraMatch
//      pushes this screen with the matched grade pre-filled and the
//      search auto-fires. Default nil keeps the bare registry
//      registration compiling regardless of merge order.
//    • Post-search `[]` previously rendered IDENTICALLY to the
//      never-searched prompt ("Enter a product grade…"), so the
//      founder couldn't tell "no results" from "didn't run".
//      `hasSearched`/`lastQuery` now drive a distinct, explicit
//      `No ports found for "<query>"` card.
//    • Explicit Search button mirroring 424's ctaRow — `.onSubmit`
//      was the only trigger before.
//    • Destination-intelligence wire: alongside the observed-traffic
//      `portIntelligence.findByProduct` history query, the search
//      consults `spectraMatch.getDestinationIntelligence` (627
//      facilities + 542 ports, capability-matched) so a real grade
//      like "WTI 0.4% sulfur" resolves rows even when no vessel
//      shipment in the 90-day window mentions it verbatim. The two
//      sources render under separate, honestly-labeled sections —
//      observed traffic vs capability — nothing is fabricated.
//

import SwiftUI

struct PortIntelligenceScreen: View {
    let theme: Theme.Palette
    /// Product grade handed off by 424_SpectraMatch ("the matched
    /// grade pre-filled"). nil = bare open from the registry / nav.
    var product: String? = nil

    var body: some View {
        Shell(theme: theme) { PortIntelBody(initialProduct: product) } nav: { shipperLifecycleNav() }
    }
}

private struct PortRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let country: String?
    let acceptedProducts: [String]?
    let utilizationPct: Int?
    let avgDwellHours: Double?
}

private struct PortIntelBody: View {
    @Environment(\.palette) private var palette
    @State private var product: String
    @State private var ports: [PortRow] = []
    /// Capability-matched facilities from the destination-intelligence
    /// layer — the SpectraMatch↔PortIntelligence connection.
    @State private var capabilityMatches: [SpectraMatchAPI.DestinationMatch] = []
    @State private var loading = false
    @State private var loadError: String? = nil
    /// True once a search round-trip has completed — drives the
    /// explicit no-results card (distinct from the pre-search prompt).
    @State private var hasSearched = false
    /// The query the latest completed search ran with, echoed in the
    /// no-results copy so the user sees exactly what found nothing.
    @State private var lastQuery = ""
    /// Auto-search trigger for the 424 handoff (fires once).
    private let autoSearch: Bool

    init(initialProduct: String?) {
        let pre = initialProduct?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _product = State(initialValue: pre)
        autoSearch = !pre.isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                productInput
                searchButton
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task {
            // 424 handoff: matched grade arrives pre-filled →
            // auto-run the search exactly once on mount.
            if autoSearch && !hasSearched && !loading {
                await search()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ferry.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · PORT INTELLIGENCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Ports + terminals by product").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var productInput: some View {
        TextField("Product grade (e.g. 'WTI 0.4% sulfur')", text: $product)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onSubmit { Task { await search() } }
    }

    /// Explicit Search CTA — mirrors 424's ctaRow grammar so the two
    /// halves of the SpectraMatch→ports flow read as one system.
    private var searchButton: some View {
        Button { Task { await search() } } label: {
            HStack(spacing: 6) {
                if loading { ProgressView().tint(.white) }
                Text(loading ? "Searching…" : "Search").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(loading || product.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Search ports and facilities for \(product)")
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Searching…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if !hasSearched {
            LifecycleCard { Text("Enter a product grade to find ports / refineries / terminals that accept it.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true) }
        }
        else if ports.isEmpty && capabilityMatches.isEmpty {
            noResultsCard
        }
        else {
            if !ports.isEmpty {
                LifecycleSection(label: "PORTS · OBSERVED TRAFFIC", icon: "ferry")
                ForEach(ports) { p in portCard(p) }
            }
            if !capabilityMatches.isEmpty {
                LifecycleSection(label: "FACILITIES · CAPABILITY MATCH", icon: "building.2")
                ForEach(capabilityMatches) { m in capabilityCard(m) }
            }
        }
    }

    /// Explicit, distinct no-results state — never the pre-search
    /// prompt. Echoes the exact query so "found nothing" is
    /// unambiguous.
    private var noResultsCard: some View {
        LifecycleCard(accentWarning: true) {
            LifecycleSection(label: "NO MATCHES", icon: "magnifyingglass")
            Text("No ports found for \"\(lastQuery)\".")
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("No vessel traffic in the last 90 days matches this grade and no capability match resolved. Try a broader term (e.g. \"crude\" or the grade family name).")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func portCard(_ p: PortRow) -> some View {
        LifecycleCard {
            LifecycleSection(label: p.name.uppercased(), icon: "ferry")
            LifecycleRow(label: "Country",     value: dashIfEmpty(p.country))
            LifecycleRow(label: "Utilization", value: p.utilizationPct.map { "\($0)%" } ?? "-")
            LifecycleRow(label: "Avg dwell",   value: p.avgDwellHours.map { String(format: "%.1f hr", $0) } ?? "-")
            LifecycleRow(label: "Accepts",     value: (p.acceptedProducts ?? []).joined(separator: ", ").isEmpty ? "-" : (p.acceptedProducts ?? []).joined(separator: ", "))
        }
    }

    /// Capability rows are honestly labeled as such (the facility can
    /// HANDLE the grade per its profile — distinct from observed
    /// shipment traffic).
    private func capabilityCard(_ m: SpectraMatchAPI.DestinationMatch) -> some View {
        LifecycleCard {
            LifecycleSection(label: m.facilityName.uppercased(), icon: "building.2")
            LifecycleRow(label: "Type",     value: dashIfEmpty((m.facilityType ?? "").replacingOccurrences(of: "_", with: " ").capitalized))
            LifecycleRow(label: "Location", value: capabilityPlace(m))
            LifecycleRow(label: "Operator", value: dashIfEmpty(m.operatorName))
            if let score = m.compatibilityScore {
                LifecycleRow(label: "Compatibility", value: "\(Int(min(100, max(0, score)).rounded()))%")
            }
            if let reasons = m.matchReasons, !reasons.isEmpty {
                LifecycleRow(label: "Why", value: reasons.prefix(2).joined(separator: " · "))
            }
        }
    }

    private func capabilityPlace(_ m: SpectraMatchAPI.DestinationMatch) -> String {
        let parts = [m.location?.city, m.location?.state, m.location?.country]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "-" : parts.joined(separator: ", ")
    }

    private func search() async {
        let query = product.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        loading = true; loadError = nil
        struct In: Encodable { let product: String }
        // Two real sources, queried concurrently:
        //   • portIntelligence.findByProduct — observed vessel traffic
        //   • spectraMatch.getDestinationIntelligence — capability
        //     match over the facility/port network (the SpectraMatch
        //     connection the founder demanded)
        // The capability call folds transport failures to empty so a
        // single-source outage never hides the other source's truth.
        async let observed: [PortRow] = EusoTripAPI.shared.query(
            "portIntelligence.findByProduct",
            input: In(product: query)
        )
        async let capability: SpectraMatchAPI.DestinationIntelligence? =
            (try? await EusoTripAPI.shared.spectraMatch.getDestinationIntelligence(productName: query))
        do {
            ports = try await observed
            capabilityMatches = (await capability)?.topDestinations ?? []
            lastQuery = query
            hasSearched = true
        } catch {
            // findByProduct failed transport-level — surface the error,
            // but still show capability rows if that source resolved.
            ports = []
            capabilityMatches = (await capability)?.topDestinations ?? []
            if capabilityMatches.isEmpty {
                loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
            lastQuery = query
            hasSearched = true
        }
        loading = false
    }
}

#Preview("425 · Port intel · Night") { PortIntelligenceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("425 · Port intel · Afternoon") { PortIntelligenceScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
