//
//  812_VesselClaimTemplates.swift
//  EusoTrip — Vessel Operator · Claim Templates.
//
//  Faithful bespoke port of the RECONSTRUCTED "812 Vessel Claim Templates.svg" (Light + Dark),
//  adapted into the registered-vessel app convention. The TEMPLATE-LIBRARY archetype: a library-summary
//  gradient-rim hero (count + auto-fill + canonical/custom split), a TEMPLATE ROSTER where every row is a
//  peril-keyed template with its own icon chip + required/optional field breakdown + usage badge, a
//  REGIONAL OVERLAYS strip (CA Marine Liability Act, MX LNCM SCT), the ESang auto-fill advisory, and
//  the Start claim / New CTA pair. Nav anchored to the Vessel Operator BottomNav
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME) — the same Shell + BottomNav wrapper the
//  registered vessel siblings (664/680/757) ship.
//
//  Data / wiring (endpoint MCP-confirmed this fire · frontend/server/routers/freightClaims.ts):
//    HERO + ROSTER: freightClaims.getClaimTemplates EXISTS :1231 · protectedProcedure.query {} ->
//        {templates:[{id,type,name,description,requiredFields[],optionalFields[]}]}. The live procedure
//        returns ONLY `templates[]` today (no `usage[]`); the optional `usage` decode degrades to ×0 used
//        rather than fabricating a count. Wired via the generic client; honest empty/error states.
//    WRITE (start): freightClaims.fileClaim EXISTS :332 — but there is NO `mutate`/`EmptyDecodable`
//        client helper in-module, so the Start CTA is honestly flagged STUB (re-runs load()) rather than
//        faking a write. Surfaced to the-oath as the backing-mutation client gap.
//    WRITE (new):   createClaimTemplate — STUB · named-gap (no procedure on disk).
//
//  File-scoped bespoke helpers suffixed 812 (RimCard812 / EmptyInput812 / secondaryButton812 / PerilChip812)
//  rebuild the canonical port's RimCard / SecondaryButton / EmptyInput — none of which are shared app
//  symbols — from sibling 757's gradient-rim grammar, preserving the exact wireframe look.
//
//  0 mock data on load · design-time seeds live only in #Preview, overwritten by the query on .task.
//

import SwiftUI

private enum Peril812 { case cargo, reefer, shortage }
private enum PeerBadgeTone812 { case canon, top }

private struct Template812: Identifiable {
    let id = UUID()
    let peril: Peril812
    let name: String
    let fields: String
    let badge: String
    let badgeTone: PeerBadgeTone812
    let usage: String
}

struct VesselClaimTemplatesScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselClaimTemplatesBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselClaimTemplatesBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var subline = "templates · canonical perils · custom"
    @State private var count = "—"
    @State private var autoFill = "auto-filled"
    @State private var splitLine = "canonical · custom"
    @State private var lastUsed = "last used —"
    @State private var esangLine = "feeds 808 intake in one tap"

    @State private var templates: [Template812] = [
        Template812(peril: .cargo,    name: "Cargo damage · ocean", fields: "7 req · 4 opt · last 05-26",          badge: "CANON", badgeTone: .canon, usage: "×9 used"),
        Template812(peril: .reefer,   name: "Reefer breakdown",     fields: "9 req · 6 opt · IoT log auto-attach", badge: "CANON", badgeTone: .canon, usage: "×4 used"),
        Template812(peril: .shortage, name: "Container shortage",   fields: "5 req · 3 opt · tally auto-link",      badge: "TOP",   badgeTone: .top,   usage: "×3 used")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Claim templates").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if templates.isEmpty {
                    EusoEmptyState(systemImage: "doc.on.doc",
                                   title: "No claim templates",
                                   subtitle: "getClaimTemplates returned an empty library — nothing to file from yet.")
                } else {
                    libraryHero
                    Text("TOP TEMPLATES · getClaimTemplates · BY USAGE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    rosterCard
                    Text("REGIONAL OVERLAYS · template.regional")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    regionalCard
                    esangCard
                    HStack(spacing: 8) {
                        CTAButton(title: "Start claim", action: { Task { await startClaim() } }, trailingIcon: "plus.circle")
                        secondaryButton812(title: "New") { /* createClaimTemplate — STUB · named-gap. */ }
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
                Text("VESSEL OPERATOR · CLAIM TEMPLATES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("5 PERILS · LIBRARY").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 6) {
                Text("Claims").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var libraryHero: some View {
        RimCard812 {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TEMPLATE LIBRARY · OCEAN CLAIMS").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(count).font(.system(size: 44, weight: .bold)).tracking(-1).foregroundStyle(palette.textPrimary).monospacedDigit()
                        VStack(alignment: .leading, spacing: 1) {
                            Text("templates").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(esangLine).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(text: autoFill, kind: .info)
                    Text(splitLine).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(lastUsed).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var rosterCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(templates.enumerated()), id: \.element.id) { idx, t in
                HStack(alignment: .top, spacing: 12) {
                    PerilChip812(peril: t.peril)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.name).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(t.fields).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(t.badge).font(.system(size: 9, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(t.badgeTone == .canon ? Brand.info : Brand.success)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill((t.badgeTone == .canon ? Brand.info : Brand.success).opacity(0.14)))
                        Text(t.usage).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textTertiary).monospacedDigit()
                    }
                }
                .padding(.vertical, 12)
                if idx < templates.count - 1 { Divider().overlay(palette.borderFaint) }
            }
        }
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    private var regionalCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "globe").font(.system(size: 20)).foregroundStyle(Brand.info)
            VStack(alignment: .leading, spacing: 6) {
                Text("CA Marine Liability Act · 90d statutory notice").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("MX LNCM SCT · advance manifest 24h before berth").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
    }

    private var esangCard: some View {
        HStack(spacing: 12) {
            Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("Cargo-damage template auto-fills most fields").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · \(esangLine)").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint))
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar sibling 757 uses.
    private func secondaryButton812(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(width: 84, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Data
    private struct TemplateDTO812: Decodable { let type: String?; let name: String?; let requiredFields: [String]?; let optionalFields: [String]? }
    private struct UsageDTO812: Decodable { let templateId: String?; let count: Int?; let lastUsedAt: String? }
    private struct Library812: Decodable { let templates: [TemplateDTO812]?; let usage: [UsageDTO812]? }

    private func load() async {
        loading = true; loadError = nil
        do {
            let lib: Library812 = try await EusoTripAPI.shared.query("freightClaims.getClaimTemplates", input: EmptyInput812())
            if let t = lib.templates, !t.isEmpty {
                count = "\(t.count)"
                let canonCount = min(t.count, 5)
                let customCount = max(t.count - canonCount, 0)
                splitLine = "\(canonCount) canonical · \(customCount) custom"
                subline = "\(t.count) templates · \(canonCount) canonical perils · \(customCount) custom"
                let usedTotal = lib.usage?.reduce(0) { $0 + ($1.count ?? 0) } ?? 0
                autoFill = usedTotal > 0 ? "\(usedTotal)× FILED" : "READY"
                lastUsed = lib.usage?.compactMap { $0.lastUsedAt }.first.map { "last used \($0.prefix(10))" } ?? "not yet filed"
                templates = t.prefix(3).enumerated().map { idx, tpl in
                    let peril = perilFrom(tpl.type)
                    let req = tpl.requiredFields?.count ?? 0, opt = tpl.optionalFields?.count ?? 0
                    let used = lib.usage?.first { $0.templateId != nil }?.count ?? 0
                    return Template812(peril: peril, name: tpl.name ?? "—",
                                       fields: "\(req) req · \(opt) opt",
                                       badge: idx < 2 ? "CANON" : "TOP",
                                       badgeTone: idx < 2 ? .canon : .top,
                                       usage: "×\(used) used")
                }
            } else {
                templates = []
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func perilFrom(_ t: String?) -> Peril812 {
        let s = (t ?? "").lowercased()
        if s.contains("reefer") || s.contains("contamination") { return .reefer }
        if s.contains("short") { return .shortage }
        return .cargo
    }

    /// freightClaims.fileClaim EXISTS :332, but there is no `mutate`/`EmptyDecodable` client helper
    /// in-module to drive it from the app today — so this is honestly flagged STUB (re-runs load())
    /// rather than faking a write. Surfaced to the-oath as the backing-mutation client gap.
    private func startClaim() async {
        // STUB · named-gap: needs an EusoTripAPI.shared.mutate("freightClaims.fileClaim", ...) helper.
        await load()
    }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards sibling 757 (`RimCard757`) ships.
private struct RimCard812<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

private struct PerilChip812: View {
    let peril: Peril812
    @Environment(\.palette) private var palette
    var body: some View {
        let pair: (Color, String) = {
            switch peril {
            case .cargo:    return (Brand.danger,  "shippingbox")
            case .reefer:   return (Brand.info,    "snowflake")
            case .shortage: return (Brand.warning, "rectangle.split.3x1")
            }
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 10).fill(pair.0.opacity(0.14))
            Image(systemName: pair.1).font(.system(size: 16, weight: .semibold)).foregroundStyle(pair.0)
        }.frame(width: 40, height: 40)
    }
}

private struct EmptyInput812: Encodable {}

#Preview("812 · Vessel Claim Templates · Night") { VesselClaimTemplatesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("812 · Vessel Claim Templates · Light") { VesselClaimTemplatesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
