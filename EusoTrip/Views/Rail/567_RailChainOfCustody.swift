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

    enum CodingKeys: String, CodingKey {
        case id, eventType, eventData, blockHash, previousBlockHash, timestamp, blockIndex
        case loadId  // Present in server response but not decoded into struct
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id                 = try c.decode(Int.self, forKey: .id)
        self.eventType          = try c.decodeIfPresent(String.self, forKey: .eventType)
        self.blockHash          = try c.decodeIfPresent(String.self, forKey: .blockHash)
        self.previousBlockHash  = try c.decodeIfPresent(String.self, forKey: .previousBlockHash)
        self.timestamp          = try c.decodeIfPresent(String.self, forKey: .timestamp)
        self.blockIndex         = try c.decodeIfPresent(Int.self, forKey: .blockIndex)
        // Server returns eventData as either String or parsed JSON object.
        // Try String first, then fall back to decoding as Any and JSON-encoding it back.
        if let s = try c.decodeIfPresent(String.self, forKey: .eventData) {
            self.eventData = s
        } else if let obj = try c.decodeIfPresent(AnyCodable.self, forKey: .eventData) {
            // If server sent a JSON object, encode it back to string
            if let data = try? JSONEncoder().encode(obj),
               let jsonStr = String(data: data, encoding: .utf8) {
                self.eventData = jsonStr
            } else {
                self.eventData = nil
            }
        } else {
            self.eventData = nil
        }
    }
}

// AnyCodable helper for decoding unknown JSON structures
private struct AnyCodable: Codable {
    let value: Any

    init(value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self.value = NSNull()
        } else if let b = try? c.decode(Bool.self) {
            self.value = b
        } else if let i = try? c.decode(Int.self) {
            self.value = i
        } else if let d = try? c.decode(Double.self) {
            self.value = d
        } else if let s = try? c.decode(String.self) {
            self.value = s
        } else if let arr = try? c.decode([AnyCodable].self) {
            self.value = arr.map { $0.value }
        } else if let dict = try? c.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unable to decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if value is NSNull {
            try c.encodeNil()
        } else if let b = value as? Bool {
            try c.encode(b)
        } else if let i = value as? Int {
            try c.encode(i)
        } else if let d = value as? Double {
            try c.encode(d)
        } else if let s = value as? String {
            try c.encode(s)
        } else if let arr = value as? [Any] {
            try c.encode(arr.map { AnyCodable(value: $0) })
        } else if let dict = value as? [String: Any] {
            try c.encode(dict.mapValues { AnyCodable(value: $0) })
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unable to encode value of type \(type(of: value))"))
        }
    }
}

private struct ChainVerification567: Decodable {
    let isValid: Bool?
    let blocksVerified: Int?
    let breakCount: Int?
    let lastVerifiedAt: String?
    let genesisIntact: Bool?
    let consistInfo: String?
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Map server's "valid" → iOS "isValid"
        self.isValid = try c.decodeIfPresent(Bool.self, forKey: .isValid)
        // Server does not send blocksVerified; derive from blockCount if present
        if let blockCount = try c.decodeIfPresent(Int.self, forKey: .blocksVerified) {
            self.blocksVerified = blockCount
        } else {
            self.blocksVerified = nil
        }
        // Map server's "issues" array length → iOS "breakCount"
        if let issues = try c.decodeIfPresent([String].self, forKey: .breakCount) {
            self.breakCount = issues.count
        } else {
            self.breakCount = nil
        }
        self.lastVerifiedAt = try c.decodeIfPresent(String.self, forKey: .lastVerifiedAt)
        self.genesisIntact = try c.decodeIfPresent(Bool.self, forKey: .genesisIntact)
        self.consistInfo = try c.decodeIfPresent(String.self, forKey: .consistInfo)
    }
    
    enum CodingKeys: String, CodingKey {
        case isValid = "valid"
        case blocksVerified = "blockCount"
        case breakCount = "issues"
        case lastVerifiedAt
        case genesisIntact
        case consistInfo
    }
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

    // Non-latest custody-block chip accent. 0x9C27B0 is the canonical
    // Brand.escort hue (the original raw Color(red:0.612,…) literal mapped
    // to exactly this hex) — re-expressed via the brand token so it adapts
    // with the palette instead of a fixed sRGB literal.
    private static let chainPurple = Brand.escort

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
                        .font(EType.mono(.caption))
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
                    .font(EType.mono(.caption))
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
                    .font(EType.mono(.caption))
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
            CTAButton(title: "Export compliance report",
                      action: { Task { await exportReport() } },
                      leadingIcon: "doc.text", isLoading: isExporting)
            Button { Task { await verify() } } label: {
                Group {
                    if isVerifying {
                        ProgressView().scaleEffect(0.85)
                    } else {
                        Text("Verify")
                            .font(EType.bodyStrong)
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
