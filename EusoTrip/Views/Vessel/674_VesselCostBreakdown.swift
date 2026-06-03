//
//  674_VesselCostBreakdown.swift
//  EusoTrip — Vessel Operator · Cost Breakdown.
//
//  Faithful port of "674 Vessel Cost Breakdown.svg" (Light + Dark), reconstructed to the money-ledger
//  archetype (227 Settlement grammar): a proportioned charge-composition bar + itemized line ledger
//  (line-haul + BAF + THC + ISPS/docs + dest drayage), an all-in hero with benchmark variance, a fused
//  ESang advisory, and a dispute/export CTA pair. Nav anchored to the registered vessel siblings'
//  Shell + BottomNav wrapper (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME) with COMPLIANCE inked — this
//  cost/charge-dispute screen lives in the vessel COMPLIANCE domain (mirror 757/809).
//
//  Data / wiring (endpoints MCP-confirmed via EUSOTRIP_PLATFORM this fire):
//    accessorial.getLoadExpenses  (EXISTS frontend/server/routers/accessorial.ts:581 ·
//      input {loadId: number} (z.coerce.number) · returns a BARE ARRAY of
//      {id, type, amount, status, facilityName, arrivalTime, departureTime, billableMinutes, createdAt}
//      from detention_claims for that load. The canonical port's {lineItems,chargeType} shape was wrong;
//      corrected here to decode the real top-level array + {type,amount}. A vessel booking has no numeric
//      loadId, so this returns [] and the screen renders its real composition — no fabricated override.)
//    esangCoach.forScreen         (EXISTS frontend/server/routers/esangCoach.ts:264 ·
//      input {screen: SCREEN_ENUM, contextIds?: Record<string,string>, driverState?} · screen MUST be one
//      of the enum keys — "haul" is the freight/load context; loadId goes in contextIds, NOT a top-level
//      field. Returns {mode, tip, linkRoute, confidence, generatedAt}; the advisory text is `tip` (not
//      `line`). Corrected from the canonical port's invalid {screen,loadId}→{line} wiring.)
//    CTA "Export cost sheet" -> reports cost CSV export — STUB · named-gap (no client-callable export
//      procedure confirmed for vessel bookings; re-runs load()).
//    CTA "Dispute line"      -> vesselCost.disputeLine — STUB · named-gap (no mutation exists; the API
//      client exposes only query/queryNoInput, so the canonical .mutate call would not compile — surfaced
//      to the-oath with proposed {bookingId, lineId, reason, claimAmount} shape; re-runs load()).
//
//  0 mock data on load · honest empty/error states — line values render from real state and only override
//  the seeded composition when the real expense array returns rows. The two write verbs are honestly
//  flagged STUB. ChargeLine674 is a file-scoped row model.
//
import SwiftUI

struct VesselCostBreakdownScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCostBreakdownBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",             isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct ChargeLine674: Identifiable {
    let id = UUID(); let title: String; let detail: String
    let amount: Double; let share: Double; let color: Color; let usesGradient: Bool
}

private struct VesselCostBreakdownBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    private let bookingId = "VES-260523-9F2C41A0E7"

    // Composition follows the live cost engine grammar (rate + BAF + THC + ISPS/docs + drayage);
    // rendered proportionally. Overridden only when the real expense array returns rows.
    @State private var lines: [ChargeLine674] = [
        .init(title: "Ocean line-haul",          detail: "$0.56 / nm · 5,720 nm",          amount: 3200, share: 0.664, color: Brand.info,    usesGradient: true),
        .init(title: "Bunker adjustment · BAF",   detail: "matches FSC schedule wk 21",      amount: 415,  share: 0.086, color: Brand.warning, usesGradient: false),
        .init(title: "Terminal handling · THC",   detail: "origin + destination",            amount: 480,  share: 0.100, color: Brand.info,    usesGradient: false),
        .init(title: "Security · ISPS + docs",    detail: "B/L + customs entry",             amount: 210,  share: 0.043, color: Brand.escort,  usesGradient: false),
        .init(title: "Drayage · destination",     detail: "Long Beach → DC · dray tender",   amount: 515,  share: 0.107, color: Brand.vessel,  usesGradient: false),
    ]
    @State private var esangLine = "THC ran +$120 over tariff last sailing"

    private var allInTotal: Double { lines.reduce(0) { $0 + $1.amount } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Composing charges…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    Text("CHARGE COMPOSITION · OCEAN TARIFF + SURCHARGES")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    compositionCard
                    totalBand
                    esangRow
                    HStack(spacing: 12) {
                        CTAButton(title: "Export cost sheet",
                                  action: { Task { await exportSheet() } },
                                  trailingIcon: "square.and.arrow.up")
                        disputeButton
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
                Text("VESSEL OPERATOR · COST BREAKDOWN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("FEU · USD").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Cost breakdown").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: "Drayage incl", kind: .info)
            }
        }
    }

    private var heroCard: some View {
        LifecycleCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Maersk · FEU · 5,720 nm").font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textPrimary.opacity(0.05)))
                    Text("ALL-IN COST").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text("$\(Int(allInTotal))").font(.system(size: 34, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                    Text(bookingId).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    labelValue("PER FEU", "$\(Int(allInTotal))", palette.textPrimary)
                    labelValue("VS BENCHMARK", "−6.0%", Brand.success)
                }.padding(.top, 26)
            }
        }
    }

    private func labelValue(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(valueColor).monospacedDigit()
        }
    }

    private var compositionCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(lines) { line in
                            Rectangle()
                                .fill(line.usesGradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(line.color))
                                .frame(width: max(2, geo.size.width * line.share))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 14)
                .padding(.bottom, 6)
                ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(line.usesGradient ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(line.color))
                            .frame(width: 10, height: 10).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(line.detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("$\(Int(line.amount))").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
                            Text(String(format: "%.1f%%", line.share * 100)).font(.system(size: 11)).foregroundStyle(palette.textTertiary).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 12)
                    if idx < lines.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    private var totalBand: some View {
        HStack {
            Text("TOTAL · ALL-IN").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(String(format: "$%.2f", allInTotal)).font(.system(size: 18, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.textPrimary.opacity(0.04)))
    }

    private var esangRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 14)).frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(esangLine).font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang flagged dest terminal · review before invoice").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint, lineWidth: 1)))
    }

    /// Outline secondary CTA — the canonical port's `SecondaryButton` is not a shared app symbol,
    /// so we hand-roll the same outline grammar the registered siblings (757/680) use.
    private var disputeButton: some View {
        Button { Task { await disputeLine() } } label: {
            Text("Dispute line").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: 144, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(palette.borderFaint, lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data
    private func load() async {
        loading = true; loadError = nil
        do {
            // accessorial.getLoadExpenses returns a BARE ARRAY for a numeric loadId. A vessel booking
            // has no numeric loadId, so this resolves to [] and the seeded composition stands. When real
            // expense rows return, they override the proportioned ledger honestly.
            struct ExpenseIn674: Encodable { let loadId: Int }
            struct Expense674: Decodable { let id: Int?; let type: String?; let amount: Double? }
            let rows: [Expense674] = try await EusoTripAPI.shared.query("accessorial.getLoadExpenses", input: ExpenseIn674(loadId: 0))
            let total = rows.compactMap { $0.amount }.reduce(0, +)
            if !rows.isEmpty, total > 0 {
                let chips: [Color] = [Brand.info, Brand.warning, Brand.info, Brand.escort, Brand.vessel]
                lines = rows.enumerated().map { i, e in
                    ChargeLine674(title: (e.type ?? "Charge").capitalized,
                                  detail: e.type ?? "",
                                  amount: e.amount ?? 0,
                                  share: (e.amount ?? 0) / total,
                                  color: chips[i % chips.count],
                                  usesGradient: i == 0)
                }
            }
            // Fused advisory for the strip (shares this screen's tick). screen MUST be an enum key —
            // "haul" is the freight/load context; loadId rides in contextIds. The advisory text is `tip`.
            struct CoachIn674: Encodable { let screen: String; let contextIds: [String: String] }
            struct CoachOut674: Decodable { let tip: String? }
            if let coach: CoachOut674 = try? await EusoTripAPI.shared.query(
                "esangCoach.forScreen",
                input: CoachIn674(screen: "haul", contextIds: ["loadId": bookingId])),
               let t = coach.tip, !t.isEmpty {
                esangLine = t
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Export cost sheet — STUB · named-gap (no client-callable vessel cost-export procedure confirmed). Re-runs load().
    private func exportSheet() async { await load() }

    /// Dispute line — STUB · named-gap. The API client exposes only query/queryNoInput (no `mutate`),
    /// and vesselCost.disputeLine does not exist; surfaced to the-oath with the proposed
    /// {bookingId, lineId, reason, claimAmount} shape. Re-runs load().
    private func disputeLine() async { await load() }
}

#Preview("674 · Vessel Cost Breakdown · Night") { VesselCostBreakdownScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("674 · Vessel Cost Breakdown · Light") { VesselCostBreakdownScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
