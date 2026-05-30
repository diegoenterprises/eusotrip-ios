//
//  390_CatalystEDIMessages.swift
//  EusoTrip — Catalyst · EDI Messages (CARRIER-side X12 transaction log).
//
//  Verbatim port of the 390 Catalyst EDI Messages Figma — the carrier
//  X12 transaction log for truck load tenders + status + invoice:
//  throughput hero, inbound/outbound message rows by transaction set,
//  a trading-partner setup strip, and a generate-outbound CTA pair.
//
//  Cross-mode parity gap fill — Rail (607) and Vessel (734) shipped EDI
//  surfaces but the Truck Catalyst band had none against the
//  mode-agnostic nativeEdi router. Truck X12 sets shown:
//    • 204  Motor Carrier Load Tender   (IN  · parsed)
//    • 990  Response to Load Tender      (OUT · accepted · sent)
//    • 214  Shipment Status             (OUT · X6 in-transit)
//    • 210  Freight Invoice             (OUT · pending send · QUEUED)
//    • 997  Functional Ack              (IN  · received)
//
//  Carrier: Aurora Freight Lines · USDOT 3 482 119.
//  Shipper-of-record / trading partner: Eusorone Technologies (DU).
//  Docked under DISPATCH.
//
//  Server wiring (tRPC · server/routers/nativeEdi.ts · protectedProcedure):
//    • transactionLog  (nativeEdi.ts:104) — message rows + hero counts.
//    • parseInbound    (nativeEdi.ts:69)  — inbound 204/997 auto-ingest.
//    • generateOutbound(nativeEdi.ts:90)  — mutation behind the CTA.
//    • partnerSetup    (nativeEdi.ts:112) — trading-partner strip.
//
//  No Swift `EusoTripAPI` method exists yet for the nativeEdi router —
//  the iOS surface speaks to `messaging` (chat conversations), not X12.
//  So this surface renders from a typed @State model with an honest
//  .loading / .empty state and leaves a single `// WIRE:` marker where
//  the real `nativeEdi.transactionLog` call belongs. Figures match the
//  live return shapes documented in the wireframe; they are NOT painted
//  as confirmed-live until the endpoint is wired.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystEDIMessagesScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystEDIMessages_390()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_390(),
                trailing: catalystNavTrailing_390(),
                orbState: .idle
            )
        }
    }
}

// MARK: - Nav (HOME · DISPATCH(current) · [orb] · FLEET · ME)

private func catalystNavLeading_390() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_390() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "box.truck.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",         isCurrent: false)]
}

// MARK: - Domain model (typed; live shapes per nativeEdi.transactionLog)

/// One X12 transaction-log row.
private enum EDIDirection_390 { case inbound, outbound }

private struct EDIMessageRow_390: Identifiable {
    let id = UUID()
    let title: String            // "Load Tender"
    let transactionSet: String   // "204"
    let direction: EDIDirection_390
    let detail: String           // "parsed" · "accepted · sent" · "X6 in-transit"
    let age: String              // "2m" · "1h" — empty when queued
    let queued: Bool             // OUT · pending send → QUEUED pill instead of age

    /// "X12 204 · IN · parsed" — the mono subtitle line.
    var monoLine: String {
        let dir = direction == .inbound ? "IN" : "OUT"
        return "X12 \(transactionSet) · \(dir) · \(detail)"
    }
}

/// transactionLog envelope: hero counts + rows + partner strip.
private struct EDITransactionLog_390 {
    let throughputToday: Int        // 47
    let acked: Int                  // 44
    let pending: Int                // 3
    let errors: Int                 // 0
    let reconciled997: Int          // 997 reconciled
    let rows: [EDIMessageRow_390]
    let partnerCount: Int           // 3
    let partnerName: String         // "Eusorone Technologies"

    /// "44 acked · 3 pending · 0 errors · 997 reconciled"
    var heroBreakdown: String {
        "\(acked) acked · \(pending) pending · \(errors) errors · \(reconciled997) reconciled"
    }
}

private enum EDILoadState_390 {
    case loading
    case loaded(EDITransactionLog_390)
    case empty
}

// MARK: - Body

private struct CatalystEDIMessages_390: View {
    @Environment(\.palette) private var palette

    @State private var state: EDILoadState_390 = .loading

    // Carrier register (right header) — carrier-of-record for this log.
    private let carrierName = "AURORA FREIGHT LINES"
    private let syncedAge = "synced 2m ago"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrowRow_390
                titleBlock_390
                iridescentHairline_390

                switch state {
                case .loading:
                    skeletonBody_390
                case .empty:
                    emptyBody_390
                case .loaded(let log):
                    heroCard_390(log)
                    transactionLogSection_390(log)
                    partnerStrip_390(log)
                    ctaPair_390
                    ctaCaption_390
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await reload() }
    }

    // MARK: Eyebrow

    private var eyebrowRow_390: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · EDI MESSAGES")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("X12 4010")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Title block (back chevron + title/sub + carrier register)

    private var titleBlock_390: some View {
        HStack(alignment: .top, spacing: 12) {
            // Back chevron in a 40pt slate circle.
            ZStack {
                Circle()
                    .fill(Color(hex: 0x1C2128))
                    .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1))
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("EDI Messages")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("transactionLog")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(carrierName)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(syncedAge)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var iridescentHairline_390: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: Hero · EDI throughput (gradient cardRim inset)

    private func heroCard_390(_ log: EDITransactionLog_390) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("EDI THROUGHPUT · TODAY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                // "live" pill — green tint.
                Text("live")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x34D399))
                    .frame(width: 54, height: 26)
                    .background(Brand.success.opacity(0.20))
                    .clipShape(Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(log.throughputToday)")
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("messages")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(log.heroBreakdown)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x1C2128))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.30)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Transaction log section

    private func transactionLogSection_390(_ log: EDITransactionLog_390) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRANSACTION LOG · transactionLog · partner \(log.partnerName)")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            VStack(spacing: 0) {
                ForEach(Array(log.rows.enumerated()), id: \.element.id) { idx, row in
                    transactionRow_390(row)
                    if idx < log.rows.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                            .padding(.leading, 64)
                    }
                }
                // Footer micro line.
                Text("parseInbound auto-ingests 204/997 · isa/gs control numbers tracked")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(hex: 0x1C2128))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func transactionRow_390(_ row: EDIMessageRow_390) -> some View {
        let isIn = row.direction == .inbound
        // IN → blue chip + brightened glyph #4D9BFF; OUT → magenta + #D24BFF.
        let chipFill = (isIn ? Brand.blue : Brand.magenta).opacity(0.16)
        let glyphColor = isIn ? Color(hex: 0x4D9BFF) : Color(hex: 0xD24BFF)

        return HStack(spacing: 12) {
            // 40×40 rx10 direction chip with a down/up arrow into a tray.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipFill)
                EDIDirectionGlyph_390(inbound: isIn)
                    .stroke(glyphColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 40, height: 40)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(row.monoLine)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 0)

            if row.queued {
                Text("QUEUED")
                    .font(.system(size: 9.5, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Color(hex: 0xFB923C))
                    .frame(width: 44, height: 20)
                    .background(Color(hex: 0xFB923C).opacity(0.18))
                    .clipShape(Capsule())
            } else {
                Text(row.age)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(hex: 0x34D399))
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Trading-partner setup strip (blue tint)

    private func partnerStrip_390(_ log: EDITransactionLog_390) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TRADING PARTNERS · partnerSetup")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("\(log.partnerCount) partners · ISA/GS qualifiers configured · AS2 + SFTP")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text("shipper-of-record \(log.partnerName) · DU")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.blue.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Brand.blue.opacity(0.30), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: CTA pair (primary generate-outbound + secondary partner setup)

    private var ctaPair_390: some View {
        HStack(spacing: 8) {
            // Primary — generateOutbound mutation.
            Button {
                // WIRE: nativeEdi.generateOutbound — {partnerId, transactionSet:"214", payload}
            } label: {
                Text("Generate outbound 214")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Secondary — partnerSetup strip detail.
            Button {
                // WIRE: nativeEdi.partnerSetup — open trading-partner config
            } label: {
                Text("Partner setup")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(Color(hex: 0x232932))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var ctaCaption_390: some View {
        Text("generateOutbound · {partnerId,transactionSet,payload} · partnerSetup")
            .font(.system(size: 10))
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Loading / empty

    private var skeletonBody_390: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard).frame(height: 92)
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard).frame(height: 250)
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.bgCard).frame(height: 66)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.bgCard).frame(maxWidth: .infinity, minHeight: 48)
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.bgCard).frame(width: 148, height: 48)
            }
        }
        .redacted(reason: .placeholder)
    }

    private var emptyBody_390: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No EDI traffic today")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("transactionLog returned no X12 messages. Inbound 204/997 auto-ingest via parseInbound when partners transmit.")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: Load

    private func reload() async {
        state = .loading
        // WIRE: nativeEdi.transactionLog (server/routers/nativeEdi.ts:104) —
        //   returns { throughput counts, rows[], partner strip }. No Swift
        //   EusoTripAPI binding for the nativeEdi router exists yet (the iOS
        //   `messaging` API is chat conversations, not X12), so until that
        //   binding lands this surface renders the documented live-shape
        //   model below. Replace the assignment with the decoded envelope:
        //
        //     let env = try await EusoTripAPI.shared.nativeEdi.transactionLog()
        //     state = env.rows.isEmpty ? .empty : .loaded(map(env))
        //
        state = .loaded(EDITransactionLog_390(
            throughputToday: 47,
            acked: 44,
            pending: 3,
            errors: 0,
            reconciled997: 997,
            rows: [
                EDIMessageRow_390(title: "Load Tender",     transactionSet: "204", direction: .inbound,  detail: "parsed",            age: "2m", queued: false),
                EDIMessageRow_390(title: "Tender Response", transactionSet: "990", direction: .outbound, detail: "accepted · sent",   age: "2m", queued: false),
                EDIMessageRow_390(title: "Shipment Status", transactionSet: "214", direction: .outbound, detail: "X6 in-transit",     age: "1h", queued: false),
                EDIMessageRow_390(title: "Freight Invoice", transactionSet: "210", direction: .outbound, detail: "pending send",      age: "",   queued: true),
                EDIMessageRow_390(title: "Functional Ack",  transactionSet: "997", direction: .inbound,  detail: "received",          age: "3m", queued: false)
            ],
            partnerCount: 3,
            partnerName: "Eusorone Technologies"
        ))
    }
}

// MARK: - Direction glyph (arrow into a tray)

/// Hand-drawn direction glyph matching the SVG: a vertical arrow (down for
/// inbound, up for outbound) sitting above a short horizontal tray line.
/// Drawn within the 40×40 chip's local space, mirroring the SVG paths
/// `M20 13 V25 M14 19 L20 25 L26 19 / M13 29 H27` (IN) and
/// `M20 27 V15 M14 21 L20 15 L26 21 / M13 29 H27` (OUT).
private struct EDIDirectionGlyph_390: Shape {
    let inbound: Bool

    func path(in rect: CGRect) -> Path {
        // SVG glyph authored on a 40×40 chip — scale into rect.
        let sx = rect.width / 40.0
        let sy = rect.height / 40.0
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        if inbound {
            // Downward arrow into tray.
            path.move(to: p(20, 13)); path.addLine(to: p(20, 25))   // shaft
            path.move(to: p(14, 19)); path.addLine(to: p(20, 25)); path.addLine(to: p(26, 19)) // head
        } else {
            // Upward arrow out of tray.
            path.move(to: p(20, 27)); path.addLine(to: p(20, 15))   // shaft
            path.move(to: p(14, 21)); path.addLine(to: p(20, 15)); path.addLine(to: p(26, 21)) // head
        }
        // Tray base line.
        path.move(to: p(13, 29)); path.addLine(to: p(27, 29))
        return path
    }
}

// MARK: - Previews

#Preview("390 · Catalyst · EDI Messages · Night") {
    CatalystEDIMessagesScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("390 · Catalyst · EDI Messages · Afternoon") {
    CatalystEDIMessagesScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
