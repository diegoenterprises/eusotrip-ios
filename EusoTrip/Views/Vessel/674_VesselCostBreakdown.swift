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
//    CTA "Export cost sheet" -> vesselCost.exportCostSheet (EXISTS · exports the same real
//      detention_claims/accessorial rows as CSV and opens a native share artifact).
//    CTA "Dispute line"      -> vesselCost.disputeLine (EXISTS · marks the selected real charge row
//      disputed and writes an audit row).
//
//  ZERO-FALLBACK (2026-06-09 · B22 fix): the seeded ledger ("Ocean line-haul $0.56/nm · 5,720 nm",
//  drayage rows, "−6.0% VS BENCHMARK", hardcoded VES- booking ref) and the dead-end
//  getLoadExpenses(loadId: 0) probe are DELETED. The screen now threads a REAL shipment id:
//  the navigation context can pass one via init(shipmentId:); when none is threaded it anchors
//  to the operator's newest live booking via vesselShipments.getVesselShipments(limit:1)
//  (for vessel, the booking id IS the loadId — server comment vesselShipments.ts:368). Expenses
//  query with that real id; no rows ⇒ honest empty state. The benchmark tile renders an em-dash
//  (no benchmark feed exists), the chip renders the real bookingNumber, and the ESang line only
//  shows a real esangCoach tip. ChargeLine674 is a file-scoped row model.
//
import SwiftUI
import Foundation

struct VesselCostBreakdownScreen: View {
    let theme: Theme.Palette
    /// Real vessel shipment (booking) the ledger scopes to. nil (registry/zero-arg use)
    /// anchors to the operator's newest live booking — never a fabricated id.
    var shipmentId: Int? = nil
    init(theme: Theme.Palette, shipmentId: Int? = nil) { self.theme = theme; self.shipmentId = shipmentId }
    var body: some View {
        Shell(theme: theme) {
            VesselCostBreakdownBody(threadedShipmentId: shipmentId)
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
    let id: String
    let expenseId: Int?
    let title: String
    let detail: String
    let amount: Double; let share: Double; let color: Color; let usesGradient: Bool
}

private struct ExportDoc674: Identifiable {
    let id = UUID()
    let url: URL
    let filename: String
    let rowCount: Int
}

private struct VesselCostBreakdownBody: View {
    @Environment(\.palette) private var palette
    let threadedShipmentId: Int?

    @State private var loading = true
    @State private var loadError: String? = nil

    // B22: nil/empty initial state — the ledger, booking identity and ESang line
    // all hydrate from live data. No fixture rows, no fabricated booking ref.
    @State private var resolvedShipmentId: Int? = nil
    @State private var bookingRef: String? = nil
    @State private var lines: [ChargeLine674] = []
    @State private var esangLine: String? = nil
    @State private var actionBanner: String? = nil
    @State private var actionError: String? = nil
    @State private var busyAction: String? = nil
    @State private var showDisputeSheet = false
    @State private var selectedLineId: String = ""
    @State private var disputeReason: String = ""
    @State private var exportDoc: ExportDoc674? = nil

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
                } else if resolvedShipmentId == nil {
                    EusoEmptyState(systemImage: "shippingbox",
                                   title: "No booking on file",
                                   subtitle: "Cost composition appears here once a vessel booking exists to accrue charges.")
                } else if lines.isEmpty {
                    EusoEmptyState(systemImage: "list.bullet.rectangle.portrait",
                                   title: "No charges accrued",
                                   subtitle: "No charges have been recorded against \(bookingRef ?? "this booking") yet — this ledger shows recorded charges only, nothing estimated.")
                } else {
                    heroCard
                    actionStatus
                    Text("CHARGE COMPOSITION · OCEAN TARIFF + SURCHARGES")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    compositionCard
                    totalBand
                    if esangLine != nil { esangRow }
                    HStack(spacing: 12) {
                        CTAButton(title: busyAction == "export" ? "Exporting..." : "Export cost sheet",
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
        .eusoRefreshable { await load() }
        .sheet(isPresented: $showDisputeSheet) { disputeSheet }
        .sheet(item: $exportDoc) { doc in exportSheetView(doc) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · COST BREAKDOWN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("USD").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Cost breakdown").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                if !lines.isEmpty {
                    StatusPill(text: "\(lines.count) charge\(lines.count == 1 ? "" : "s")", kind: .info)
                }
            }
        }
    }

    private var heroCard: some View {
        LifecycleCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    // Real booking identity chip — em-dash until the booking resolves.
                    Text(bookingRef ?? "—").font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textPrimary.opacity(0.05)))
                    Text("ALL-IN COST").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text("$\(Int(allInTotal))").font(.system(size: 34, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                    Text(resolvedShipmentId.map { "shipment \($0)" } ?? "—").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    labelValue("PER MOVE", "$\(Int(allInTotal))", palette.textPrimary)
                    // No benchmark feed exists — honest em-dash, never an invented variance.
                    labelValue("VS BENCHMARK", "—", palette.textTertiary)
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
                // Only a REAL esangCoach tip reaches here (the row is hidden otherwise).
                Text(esangLine ?? "—").font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · live coach tip for this booking").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
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
        Button {
            selectedLineId = selectedLineId.isEmpty ? (lines.first?.id ?? "") : selectedLineId
            showDisputeSheet = true
        } label: {
            Text(busyAction == "dispute" ? "Filing..." : "Dispute line").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: 144, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(palette.borderFaint, lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    private var actionStatus: some View {
        Group {
            if let actionError {
                LifecycleCard(accentDanger: true) {
                    Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
                }
            } else if let actionBanner {
                LifecycleCard {
                    Text(actionBanner).font(EType.caption).foregroundStyle(Brand.success)
                }
            }
        }
    }

    private var disputeSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dispute charge line").font(.system(size: 22, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(bookingRef ?? "Current booking").font(.system(size: 12, design: .monospaced)).foregroundStyle(palette.textSecondary)

                Picker("Charge line", selection: $selectedLineId) {
                    ForEach(lines.filter { $0.expenseId != nil }) { line in
                        Text("\(line.title) · $\(Int(line.amount))").tag(line.id)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 6) {
                    Text("REASON").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    TextEditor(text: $disputeReason)
                        .font(.system(size: 14))
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                }

                HStack(spacing: 8) {
                    outlineButton674("Cancel") { showDisputeSheet = false }
                    CTAButton(title: busyAction == "dispute" ? "Filing..." : "File dispute",
                              action: { Task { await disputeLine() } },
                              trailingIcon: "exclamationmark.bubble")
                }
            }
            .padding(Space.s5)
        }
        .background(palette.bgPrimary)
        .presentationDetents([.medium, .large])
    }

    private func exportSheetView(_ doc: ExportDoc674) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cost sheet ready").font(.system(size: 22, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("\(doc.filename) · \(doc.rowCount) row\(doc.rowCount == 1 ? "" : "s")")
                .font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            ShareLink(item: doc.url) {
                Label("Share CSV", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            outlineButton674("Done") { exportDoc = nil }
            Spacer(minLength: 0)
        }
        .padding(Space.s5)
        .background(palette.bgPrimary)
        .presentationDetents([.medium])
    }

    private func outlineButton674(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data
    private func load() async {
        loading = true; loadError = nil
        do {
            // 1. Resolve the REAL shipment scope (B22): threaded id wins; otherwise anchor
            //    to the operator's newest live booking. For vessel, the booking id IS the
            //    loadId in cross-table contexts (server comment vesselShipments.ts:368).
            var sid = threadedShipmentId
            var ref: String? = nil
            if sid == nil {
                struct ListIn674: Encodable { let limit: Int; let offset: Int }
                struct ShipRow674: Decodable { let id: Int; let bookingNumber: String? }
                struct ShipEnv674: Decodable { let shipments: [ShipRow674] }
                let env: ShipEnv674 = try await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipments", input: ListIn674(limit: 1, offset: 0))
                sid = env.shipments.first?.id
                ref = env.shipments.first?.bookingNumber
            }
            resolvedShipmentId = sid
            bookingRef = ref ?? sid.map { "shipment \($0)" }
            guard let loadId = sid else {
                lines = []; esangLine = nil; loading = false
                return
            }

            // 2. Live expense rows for the REAL id — bare array; empty decodes to the
            //    honest empty state, never a fixture.
            struct ExpenseIn674: Encodable { let loadId: Int }
            struct Expense674: Decodable { let id: Int?; let type: String?; let amount: Double? }
            let rows: [Expense674] = try await EusoTripAPI.shared.query("accessorial.getLoadExpenses", input: ExpenseIn674(loadId: loadId))
            let total = rows.compactMap { $0.amount }.reduce(0, +)
            if !rows.isEmpty, total > 0 {
                let chips: [Color] = [Brand.info, Brand.warning, Brand.info, Brand.escort, Brand.vessel]
                lines = rows.enumerated().map { i, e in
                    ChargeLine674(id: e.id.map { String($0) } ?? "row-\(i)",
                                  expenseId: e.id,
                                  title: (e.type ?? "Charge").capitalized,
                                  detail: e.type ?? "",
                                  amount: e.amount ?? 0,
                                  share: (e.amount ?? 0) / total,
                                  color: chips[i % chips.count],
                                  usesGradient: i == 0)
                }
            } else {
                lines = []
            }
            selectedLineId = lines.first?.id ?? ""
            // 3. Fused advisory (real tip or hidden row). screen MUST be an enum key —
            //    "haul" is the freight/load context; the REAL loadId rides in contextIds.
            struct CoachIn674: Encodable { let screen: String; let contextIds: [String: String] }
            struct CoachOut674: Decodable { let tip: String? }
            if let coach: CoachOut674 = try? await EusoTripAPI.shared.query(
                "esangCoach.forScreen",
                input: CoachIn674(screen: "haul", contextIds: ["loadId": String(loadId)])),
               let t = coach.tip, !t.isEmpty {
                esangLine = t
            } else {
                esangLine = nil
            }
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func exportSheet() async {
        actionError = nil
        actionBanner = nil
        guard let loadId = resolvedShipmentId else {
            actionError = "No booking is available for export."
            return
        }
        busyAction = "export"
        do {
            struct ExportIn674: Encodable { let loadId: Int }
            struct ExportOut674: Decodable { let filename: String; let rowCount: Int; let csv: String }
            let out: ExportOut674 = try await EusoTripAPI.shared.mutation(
                "vesselCost.exportCostSheet",
                input: ExportIn674(loadId: loadId)
            )
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(out.filename)
            guard let data = out.csv.data(using: .utf8) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: [.atomic])
            exportDoc = ExportDoc674(url: url, filename: out.filename, rowCount: out.rowCount)
            actionBanner = "Cost sheet export ready."
        } catch {
            actionError = error.eusoUserCopy
        }
        busyAction = nil
    }

    private func disputeLine() async {
        actionError = nil
        actionBanner = nil
        guard let loadId = resolvedShipmentId else {
            actionError = "No booking is available for dispute."
            return
        }
        guard let line = lines.first(where: { $0.id == selectedLineId }), let lineId = line.expenseId else {
            actionError = "Select a charge line."
            return
        }
        let reason = disputeReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reason.count >= 10 else {
            actionError = "Add a dispute reason with at least 10 characters."
            return
        }
        busyAction = "dispute"
        do {
            struct DisputeIn674: Encodable { let loadId: Int; let lineId: Int; let reason: String; let claimAmount: Double? }
            struct DisputeOut674: Decodable { let success: Bool; let status: String? }
            let out: DisputeOut674 = try await EusoTripAPI.shared.mutation(
                "vesselCost.disputeLine",
                input: DisputeIn674(loadId: loadId, lineId: lineId, reason: reason, claimAmount: line.amount)
            )
            actionBanner = out.success ? "Charge line marked \(out.status ?? "disputed")." : "Dispute submitted."
            showDisputeSheet = false
            disputeReason = ""
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
        busyAction = nil
    }
}

#Preview("674 · Vessel Cost Breakdown · Night") { VesselCostBreakdownScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("674 · Vessel Cost Breakdown · Light") { VesselCostBreakdownScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
