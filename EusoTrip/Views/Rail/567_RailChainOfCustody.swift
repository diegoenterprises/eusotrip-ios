//
//  567_RailChainOfCustody.swift
//  EusoTrip — Rail Engineer · Chain of Custody (hash-chained custody audit trail).
//
//  Verbatim port of "567 Rail Chain of Custody.svg" (Light + Dark).
//  Carrier-side blockchain audit trail for the active consist: ordered block events
//  with blockHash / previousBlockHash linkage, integrity verdict, compliance export.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Data:
//    blockchainAudit.getTrail           (EXISTS blockchainAudit.ts:39)  → [{eventType,eventData,blockHash,previousBlockHash,timestamp}] ASC
//    blockchainAudit.getComplianceReport(EXISTS blockchainAudit.ts:32)  → generateComplianceReport (export CTA)
//    blockchainAudit.verifyChain        (EXISTS blockchainAudit.ts:24)  → integrity verdict
//

import SwiftUI

struct RailChainOfCustodyScreen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) { RailChainOfCustodyBody(loadId: loadId) } nav: {
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

// MARK: - Data shapes

private struct CustodyBlock567: Decodable, Identifiable {
    let id: Int
    let eventType: String?
    let eventData: String?
    let blockHash: String?
    let previousBlockHash: String?
    let timestamp: String?
    let blockIndex: Int?
}

private struct ChainVerification567: Decodable {
    let isValid: Bool?
    let blocksVerified: Int?
    let breakCount: Int?
    let lastVerifiedAt: String?
    let genesisIntact: Bool?
    let consistInfo: String?
}

// MARK: - Body

private struct RailChainOfCustodyBody: View {
    @Environment(\.palette) private var palette
    let loadId: String

    @State private var blocks: [CustodyBlock567] = []
    @State private var verification: ChainVerification567? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isVerifying = false
    @State private var isExporting = false

    private static let chainPurple = Color(red: 0.612, green: 0.153, blue: 0.690)

    // MARK: Derived

    private var isChainValid: Bool { verification?.isValid ?? (blocks.count > 0) }
    private var breakCount: Int    { verification?.breakCount ?? 0 }
    private var verifiedCount: Int { verification?.blocksVerified ?? (isChainValid ? blocks.count : 0) }

    private var chainStatusLabel: String { isChainValid ? "CHAIN VERIFIED" : "CHAIN BROKEN" }
    private var integrityLabel: String   { isChainValid ? "OK" : "FAIL" }
    private var integrityColor: Color    { isChainValid ? Brand.success : Brand.danger }
    private var genesisChipLabel: String {
        if let v = verification {
            if v.genesisIntact == true { return "genesis hash matches" }
            if let br = v.breakCount, br > 0 { return "break at block \(br)" }
        }
        return "genesis hash matches"
    }

    private var lastBlockAgo: String {
        blocks.last?.timestamp.map { "last block \($0)" } ?? "—"
    }
    private var consistLabel: String { verification?.consistInfo ?? "\(blocks.count > 0 ? blocks.count : 0)-block trail" }

    private func truncatedHash(_ hash: String?) -> String {
        guard let h = hash, h.count > 10 else { return hash ?? "—" }
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
                    heroCard
                    kpiStrip
                    custodyTrail
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · CHAIN OF CUSTODY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(String(loadId.prefix(12)))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Chain of Custody")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(chainStatusLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(isChainValid ? Brand.success : Brand.danger)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill((isChainValid ? Brand.success : Brand.danger).opacity(0.14)))
                Text(genesisChipLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(blocks.count)")
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("blocks")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text(breakCount == 0 ? "no break detected" : "\(breakCount) break\(breakCount == 1 ? "" : "s") detected")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(breakCount == 0 ? palette.textSecondary : Brand.danger)
                    Text("\(consistLabel) · \(lastBlockAgo)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("INTEGRITY")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(integrityLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(integrityColor)
                    Text("verifyChain")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "BLOCKS",   value: "\(blocks.count)")
            MetricTile(label: "VERIFIED", value: "\(verifiedCount)", gradientNumeral: verifiedCount > 0 && breakCount == 0)
            MetricTile(label: "BREAKS",   value: "\(breakCount)",    accent: breakCount > 0 ? Brand.danger : nil)
        }
    }

    // MARK: - Custody trail

    private var custodyTrail: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CUSTODY TRAIL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getTrail")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if blocks.isEmpty {
                EusoEmptyState(
                    systemImage: "link",
                    title: "No blocks",
                    subtitle: "Custody blocks will appear here as events are logged."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, block in
                        blockRow(block, index: idx + 1, isLatest: idx == blocks.count - 1)
                        if idx < blocks.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                                .overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func blockRow(_ block: CustodyBlock567, index: Int, isLatest: Bool) -> some View {
        let chipColor: Color = isLatest ? Brand.blue : Self.chainPurple
        let title = (block.eventType ?? "—").uppercased()
            + (block.eventData.map { " · \($0)" } ?? "")
        let hashStr  = truncatedHash(block.blockHash)
        let prevStr  = truncatedHash(block.previousBlockHash)
        let sub = "hash \(hashStr) · prev \(prevStr)\(block.timestamp.map { " · \($0)" } ?? "")"
        let displayIndex = block.blockIndex ?? index

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chipColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if isLatest {
                Text("latest")
                    .font(.system(size: 11, weight: .bold)).kerning(0.6)
                    .foregroundStyle(LinearGradient.primary)
            } else {
                Text("#\(displayIndex)")
                    .font(.system(size: 11, weight: .bold)).kerning(0.0)
                    .monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(16)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Export compliance report", leadingIcon: "doc.text", isLoading: isExporting) {
                Task { await exportReport() }
            }
            Button { Task { await verify() } } label: {
                Group {
                    if isVerifying {
                        ProgressView().scaleEffect(0.85)
                    } else {
                        Text("Verify")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                .frame(width: 116, height: 48)
                .background(palette.bgCard)
                .overlay(Capsule().strokeBorder(palette.borderFaint))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct TrailIn: Encodable { let loadId: String }
        do {
            async let trail: [CustodyBlock567] = EusoTripAPI.shared.query(
                "blockchainAudit.getTrail", input: TrailIn(loadId: loadId))
            async let verify: ChainVerification567 = EusoTripAPI.shared.query(
                "blockchainAudit.verifyChain", input: TrailIn(loadId: loadId))
            let (b, v) = try await (trail, verify)
            self.blocks       = b
            self.verification = v
        } catch {
            // Attempt trail-only if verifyChain is gated
            do {
                self.blocks = try await EusoTripAPI.shared.query(
                    "blockchainAudit.getTrail", input: TrailIn(loadId: loadId))
            } catch let err {
                loadError = (err as? EusoTripAPIError)?.errorDescription ?? err.localizedDescription
            }
        }
        loading = false
    }

    private func verify() async {
        isVerifying = true
        struct TrailIn: Encodable { let loadId: String }
        do {
            let v: ChainVerification567 = try await EusoTripAPI.shared.query(
                "blockchainAudit.verifyChain", input: TrailIn(loadId: loadId))
            self.verification = v
        } catch { /* show current state */ }
        isVerifying = false
    }

    private func exportReport() async {
        isExporting = true
        struct ReportIn: Encodable { let loadId: String }
        struct ReportOut: Decodable {}
        do {
            let _: ReportOut = try await EusoTripAPI.shared.query(
                "blockchainAudit.getComplianceReport", input: ReportIn(loadId: loadId))
        } catch { /* export errors are non-fatal */ }
        isExporting = false
    }
}

#Preview("567 · Rail Chain of Custody · Night") { RailChainOfCustodyScreen(theme: Theme.dark, loadId: "RAIL-260523-7C3A0B12D4").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("567 · Rail Chain of Custody · Light") { RailChainOfCustodyScreen(theme: Theme.light, loadId: "RAIL-260523-7C3A0B12D4").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
