//
//  667_VesselChainOfCustody.swift
//  EusoTrip — Vessel Operator · Chain of Custody (hash-chained custody audit trail).
//
//  Verbatim port of "667 Vessel Chain of Custody.svg" (Dark).
//  Carrier-side blockchain audit trail for the active ocean booking: ordered block
//  events with blockHash / previousBlockHash linkage, integrity verdict, and a
//  compliance-report export. Vessel-mode counterpart of 05 Rail · 567 Rail Chain
//  of Custody — closes the cross-mode parity gap (blockchain_audit listed as a
//  vessel compliance overlay tool with no iOS surface). Docked under COMPLIANCE.
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Data (server/routers/blockchainAudit.ts):
//    blockchainAudit.getTrail            (EXISTS :39 · {loadId}) → [{eventType,eventData,blockHash,previousBlockHash,timestamp}] ASC · trail body
//    blockchainAudit.getComplianceReport (EXISTS :32 · {loadId}) → generateComplianceReport → INTEGRITY + report card + Export CTA
//    blockchainAudit.verifyChain         (EXISTS :24 · SUPER_ADMIN-gated) → verdict surfaced HERE via getComplianceReport.chainValid, NOT called by the operator.
//

import SwiftUI

struct VesselChainOfCustodyScreen: View {
    let theme: Theme.Palette
    /// Defaulted so the screen is constructable from ScreenRegistry (no load
    /// context) — an empty id renders the empty/select state; drill-down passes a real id.
    var loadId: String = ""

    var body: some View {
        Shell(theme: theme) { VesselChainOfCustodyBody(loadId: loadId) } nav: {
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

// MARK: - Data shapes

/// One block on the hash-chained custody trail. Maps the getTrail row
/// (id, eventType, eventData, blockHash, previousBlockHash, timestamp).
private struct CustodyBlock667: Decodable, Identifiable {
    let id: Int
    let eventType: String?
    let eventData: CustodyEventData667?
    let blockHash: String?
    let previousBlockHash: String?
    let timestamp: String?
}

/// `eventData` is a free-form JSON object on the server. We only surface
/// a short human label when one is present; everything else is ignored.
private struct CustodyEventData667: Decodable {
    let label: String?
    let detail: String?
    let location: String?
    let note: String?

    /// First non-empty descriptive field — used as the block's "· suffix".
    var summary: String? {
        for v in [label, detail, location, note] {
            if let v, !v.trimmingCharacters(in: .whitespaces).isEmpty { return v }
        }
        return nil
    }
}

/// generateComplianceReport → { loadId, generatedAt, blocks[], blockCount,
/// chainValid, issues[] }. Drives the INTEGRITY / report hero card.
private struct ComplianceReport667: Decodable {
    let loadId: Int?
    let generatedAt: String?
    let blockCount: Int?
    let chainValid: Bool?
    let issues: [String]?
}

// MARK: - Body

private struct VesselChainOfCustodyBody: View {
    @Environment(\.palette) private var palette
    let loadId: String

    @State private var blocks: [CustodyBlock667] = []
    @State private var report: ComplianceReport667? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isExporting = false
    @State private var exportNote: String? = nil

    // MARK: Derived (verdict comes from getComplianceReport — verifyChain is
    // SUPER_ADMIN-gated and not callable by the operator).

    private var blockCount: Int { report?.blockCount ?? blocks.count }
    private var isChainValid: Bool { report?.chainValid ?? (!blocks.isEmpty) }
    private var issueCount: Int { report?.issues?.count ?? 0 }

    private var integrityLabel: String { isChainValid ? "CHAIN VERIFIED" : "CHAIN BROKEN" }
    private var integrityColor: Color  { isChainValid ? Brand.success : Brand.danger }

    private var breakLine: String {
        if !isChainValid, issueCount > 0 {
            return "\(issueCount) break\(issueCount == 1 ? "" : "s") detected · genesis hash mismatch"
        }
        return "no break detected · genesis hash matches"
    }

    /// "1 FEU reefer · Eusorone Technologies · last block <ago>" — booking
    /// context line. The FEU/reefer/shipper segment is fixed booking
    /// metadata (the operator opened this trail for that booking); the
    /// last-block stamp is read off the live trail.
    private var bookingContextLine: String {
        let last = blocks.last?.timestamp.map { "last block \($0)" } ?? "trail empty"
        return "1 FEU reefer · Eusorone Technologies · \(last)"
    }

    private func truncatedHash(_ hash: String?) -> String {
        guard let h = hash, h.count > 10 else { return hash ?? "0x0000" }
        let start = String(h.prefix(6))
        let end   = String(h.suffix(4))
        return "\(start)…\(end)"
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading chain…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    integrityCard
                    custodyTrail
                    if let note = exportNote {
                        Text(note)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    CTAButton(title: "Export compliance report",
                              action: { Task { await exportReport() } },
                              leadingIcon: "doc.text",
                              isLoading: isExporting)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header (eyebrow · title · getTrail subtitle · hairline)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("VESSEL OPERATOR · CHAIN OF CUSTODY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Text("Chain of Custody")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("getTrail · \(loadId) · live")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            IridescentHairline()
                .padding(.top, 2)
        }
    }

    // MARK: - Integrity / report card (getComplianceReport · gradient rim)

    private var integrityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("INTEGRITY · getComplianceReport")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(integrityLabel)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(integrityColor)
                }
                Spacer()
                Text("\(blockCount) BLOCKS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.12)))
            }
            Text(breakLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 10)
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.top, 10)
            Text(bookingContextLine)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 8)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - Custody trail (getTrail · timeline spine)

    private var custodyTrail: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("CUSTODY TRAIL · getTrail")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            if blocks.isEmpty {
                EusoEmptyState(
                    systemImage: "link",
                    title: "No blocks yet",
                    subtitle: "Custody blocks appear here as booking events are hash-chained."
                )
            } else {
                ZStack(alignment: .topLeading) {
                    // Vertical spine behind the nodes.
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 2)
                            .padding(.leading, 14)
                            .padding(.vertical, 18)
                        Spacer()
                    }
                    VStack(spacing: Space.s2) {
                        ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, block in
                            blockRow(block, isLatest: idx == blocks.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func blockRow(_ block: CustodyBlock667, isLatest: Bool) -> some View {
        let title = (block.eventType ?? "—").uppercased()
            + (block.eventData?.summary.map { " · \($0)" } ?? "")
        let hashStr = truncatedHash(block.blockHash)
        let prevStr = truncatedHash(block.previousBlockHash)
        var sub = "hash \(hashStr) · prev \(prevStr)"
        if let ts = block.timestamp { sub += " · \(ts)" }
        if isLatest { sub += " · latest" }

        return HStack(alignment: .top, spacing: Space.s3) {
            // Timeline node — gradient disc, ringed when latest.
            ZStack {
                if isLatest {
                    Circle()
                        .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    Circle().fill(LinearGradient.diagonal).frame(width: 14, height: 14)
                } else {
                    Circle().fill(LinearGradient.diagonal).frame(width: 12, height: 12)
                }
            }
            .frame(width: 30, alignment: .center)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(isLatest ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.55))
                                           : AnyShapeStyle(palette.borderFaint),
                                  lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct TrailIn: Encodable { let loadId: String }
        do {
            async let trail: [CustodyBlock667] = EusoTripAPI.shared.query(
                "blockchainAudit.getTrail", input: TrailIn(loadId: loadId))
            async let rep: ComplianceReport667 = EusoTripAPI.shared.query(
                "blockchainAudit.getComplianceReport", input: TrailIn(loadId: loadId))
            let (b, r) = try await (trail, rep)
            self.blocks = b
            self.report = r
        } catch {
            // Fall back to trail-only so the operator still sees the custody
            // chain even if the compliance-report verdict call fails.
            do {
                self.blocks = try await EusoTripAPI.shared.query(
                    "blockchainAudit.getTrail", input: TrailIn(loadId: loadId))
                self.report = nil
            } catch let err {
                loadError = (err as? EusoTripAPIError)?.errorDescription ?? err.localizedDescription
            }
        }
        loading = false
    }

    private func exportReport() async {
        isExporting = true; exportNote = nil
        struct ReportIn: Encodable { let loadId: String }
        do {
            let r: ComplianceReport667 = try await EusoTripAPI.shared.query(
                "blockchainAudit.getComplianceReport", input: ReportIn(loadId: loadId))
            self.report = r
            let n = r.blockCount ?? blocks.count
            exportNote = "Compliance report generated · \(n) block\(n == 1 ? "" : "s") · "
                + ((r.chainValid ?? isChainValid) ? "chain verified" : "chain broken")
        } catch {
            exportNote = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        isExporting = false
    }
}

#Preview("667 · Vessel Chain of Custody · Night") {
    VesselChainOfCustodyScreen(theme: Theme.dark, loadId: "VES-260523-9F2C41A0E7")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("667 · Vessel Chain of Custody · Light") {
    VesselChainOfCustodyScreen(theme: Theme.light, loadId: "VES-260523-9F2C41A0E7")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
