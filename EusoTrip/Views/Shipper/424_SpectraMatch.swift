//
//  424_SpectraMatch.swift
//  EusoTrip — Shipper · SpectraMatch™ AI crude oil + product identification.
//
//  Emergency Wave I2 (2026-06-11) — root causes closed:
//    • `spectraMatch.identify` is a `.mutation` on the server; the
//      previous build sent it as a GET query and 405'd
//      (`METHOD_NOT_SUPPORTED`) on every attempt — the screen could
//      only ever render the red error caption, which is exactly what
//      the founder hit with real crude specs.
//    • The old decode contract (`bestMatch`/`confidencePct`) shared
//      ZERO required keys with the real envelope (`primaryMatch.name`
//      / `primaryMatch.confidence` / `alternativeMatches` / …), so it
//      would have kept failing even after the verb fix. The typed
//      `SpectraMatchAPI.identify` mirrors the wire 1:1.
//    • Founder-demanded SpectraMatch→PortIntelligence connection: a
//      successful identify immediately calls
//      `spectraMatch.quickDestinationMatch` and renders the "Where
//      can this grade go" card (top destinations + compatible
//      pipelines, backed by 627 facilities + 542 ports in prod) with
//      a push-nav CTA into 425 pre-filled with the matched grade.
//      Push nav per the standing mandate — never a slide-up.
//

import SwiftUI

struct SpectraMatchScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { SpectraMatchBody() } nav: { shipperLifecycleNav() }
    }
}

private struct SpectraMatchBody: View {
    @Environment(\.palette) private var palette
    @State private var productLabel: String = ""
    @State private var apiGravity: Double? = nil
    @State private var bsw: Double? = nil
    @State private var sulfur: Double? = nil
    @State private var pourPoint: Double? = nil
    @State private var loading = false
    @State private var result: SpectraMatchAPI.IdentifyResult? = nil
    @State private var actionError: String? = nil

    /// Destination intelligence for the matched grade — hydrates
    /// right after a successful identify. `nil` while not yet asked
    /// or in flight; honest server empties render as the explicit
    /// "no destination intelligence yet" caption, never a fabricated
    /// port list.
    @State private var destinations: SpectraMatchAPI.QuickDestinationResult? = nil
    @State private var destinationsLoading = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                inputCard
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                if let r = result {
                    resultCard(r)
                    destinationsCard(for: r)
                }
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "drop.triangle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · SPECTRAMATCH™").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Identify crude / product").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Enter the spec sheet readings. ESANG cross-references the global crude library to identify the closest match.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inputCard: some View {
        LifecycleCard {
            LifecycleSection(label: "SPEC SHEET", icon: "doc.text")
            // Required: identification is evidence-backed against a resolved
            // product profile, so the server matches the readings AGAINST this
            // label. Without it `spectraMatch.identify` refuses the request.
            labelField("Product / sample label", value: $productLabel)
            field("API gravity (°API)", value: $apiGravity)
            field("BS&W (% vol)", value: $bsw)
            field("Sulfur content (% wt)", value: $sulfur)
            field("Pour point (°F)", value: $pourPoint)
        }
    }

    private func labelField(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField("e.g. West Texas Intermediate", text: value)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func field(_ label: String, value: Binding<Double?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField("", value: value, format: .number).keyboardType(.decimalPad).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Best match

    private func resultCard(_ r: SpectraMatchAPI.IdentifyResult) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "BEST MATCH", icon: "checkmark.shield")
            LifecycleRow(label: "Crude / product", value: r.primaryMatch.name)
            LifecycleRow(label: "Confidence",      value: "\(confidencePct(r))%")
            if let cls = classificationLine(r) {
                LifecycleRow(label: "Class", value: cls)
            }
            if let alts = r.alternativeMatches, !alts.isEmpty {
                LifecycleRow(label: "Alternates", value: alts.map(\.name).joined(separator: ", "))
            }
            if let erg = r.ergInfo, let un = erg.unNumber, !un.isEmpty {
                LifecycleRow(
                    label: "ERG",
                    value: [un, erg.guideNumber.map { "Guide \($0)" }, erg.hazardClass.map { "Class \($0)" }]
                        .compactMap { $0 }.joined(separator: " · ")
                )
            }
        }
    }

    /// Server confidence is already 0-100 (crudeOilSpecsDB.ts:174);
    /// clamp defensively so a wire anomaly never renders "240%".
    private func confidencePct(_ r: SpectraMatchAPI.IdentifyResult) -> Int {
        Int(min(100, max(0, r.primaryMatch.confidence)).rounded())
    }

    private func classificationLine(_ r: SpectraMatchAPI.IdentifyResult) -> String? {
        let parts = [r.classification?.apiClass, r.classification?.sulfurClass]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - "Where can this grade go" (SpectraMatch → ports wire)

    @ViewBuilder
    private func destinationsCard(for r: SpectraMatchAPI.IdentifyResult) -> some View {
        LifecycleCard {
            LifecycleSection(label: "WHERE CAN THIS GRADE GO", icon: "ferry")
            if destinationsLoading {
                Text("Checking destinations…")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else if let d = destinations {
                if d.topDestinations.isEmpty {
                    // Honest empty — the intelligence layer found no
                    // capability match. Never a fabricated port list.
                    Text("No destination intelligence for this grade yet. Open Port Intelligence to search the full facility network.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(d.topDestinations.prefix(5)) { dest in
                        destinationRow(dest)
                    }
                    let pipes = d.pipelineRoutes.filter { $0.acceptsProduct ?? false }
                    if !pipes.isEmpty {
                        LifecycleRow(
                            label: "Pipelines",
                            value: pipes.map(\.pipelineName).joined(separator: ", ")
                        )
                    }
                }
            } else {
                // quickDestinationMatch failed transport-level — the
                // identify result stands; surface the gap honestly.
                Text("Destination check unavailable right now.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }

            // Push-nav handoff into 425 with the matched grade
            // pre-filled (the founder's "Port Intelligence is not
            // connected to SpectraMatch" fix). `ShipperSurface`
            // captures the `product` payload and constructs
            // `PortIntelligenceScreen(product:)` over the registry's
            // bare entry.
            Button {
                NotificationCenter.default.post(
                    name: .eusoShipperNavSwap, object: nil,
                    userInfo: ["screenId": "425", "product": r.primaryMatch.name]
                )
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "ferry.fill").font(.system(size: 11, weight: .heavy))
                    Text("Open Port Intelligence for \(r.primaryMatch.name)")
                        .font(.system(size: 12, weight: .heavy)).tracking(0.3)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Port Intelligence pre-filled with \(r.primaryMatch.name)")
        }
    }

    private func destinationRow(_ d: SpectraMatchAPI.DestinationMatch) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.facilityName)
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(destinationSubtitle(d))
                    .font(EType.micro).foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            if let score = d.compatibilityScore {
                Text("\(Int(min(100, max(0, score)).rounded()))%")
                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
        .padding(.vertical, 2)
    }

    private func destinationSubtitle(_ d: SpectraMatchAPI.DestinationMatch) -> String {
        let place = [d.location?.city, d.location?.state]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let kind = (d.facilityType ?? "").replacingOccurrences(of: "_", with: " ").capitalized
        let parts = [kind, place].filter { !$0.isEmpty }
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    private var ctaRow: some View {
        Button { Task { await match() } } label: {
            HStack(spacing: 6) {
                if loading { ProgressView().tint(.white) }
                Text(loading ? "Matching…" : "Run match").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(loading || apiGravity == nil || bsw == nil)
    }

    private func match() async {
        let label = productLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api = apiGravity, let bswV = bsw else { return }
        guard !label.isEmpty else {
            actionError = "Enter the product or sample label — identification is matched against a real product profile, not guessed from the readings alone."
            return
        }
        loading = true; actionError = nil
        destinations = nil
        do {
            let r = try await EusoTripAPI.shared.spectraMatch.identify(
                productName: label,
                apiGravity: api,
                bsw: bswV,
                sulfur: sulfur,
                pourPoint: pourPoint
            )
            result = r
            loading = false
            // SpectraMatch → ports wire: immediately ask where the
            // matched grade can go. Transport failure folds to nil —
            // the card renders an honest "unavailable" caption.
            destinationsLoading = true
            destinations = try? await EusoTripAPI.shared.spectraMatch.quickDestinationMatch(
                productName: r.primaryMatch.name,
                apiGravity: api,
                sulfurContent: sulfur
            )
            destinationsLoading = false
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

#Preview("424 · SpectraMatch · Night") { SpectraMatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("424 · SpectraMatch · Afternoon") { SpectraMatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
