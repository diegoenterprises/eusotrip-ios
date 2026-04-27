//
//  BOLCopilot.swift
//  EusoTrip Pulse Watch App
//
//  F15 — On-device Bill of Lading + Placard copilot.
//
//  The camera + Foundation Models heavy lifting runs on the iPhone
//  companion: `DataScannerViewController` captures the BOL / placard
//  frame, an on-device vision-language model extracts structured
//  fields, and `ergClassify.matchBOLAndPlacard` runs a zero-network
//  cross-check. The wrist side is a consumer:
//
//    • Voice trigger:  "scan the placard" → WCSession op
//                      `bol.scanRequest` down to the phone
//    • Result ingest:  iOS pushes parsed fields + warnings up as
//                      WCSession op `bol.result`
//    • UI:             `BOLCopilotView` shows the scan summary, driver
//                      confirms or flags
//    • Audit:          mismatches append to BlockchainAudit so the
//                      compliance officer can prove the driver was
//                      warned about the hazmat mismatch in real time
//
//  Why the split? Foundation Models (iOS 18's on-device LLM) is not
//  available on watchOS, and the wrist doesn't have a camera. Pushing
//  vision + LLM to the phone keeps the watch work identical across
//  Series 6+ hardware while still giving the driver a glanceable
//  confirmation loop.
//

import Foundation
import Combine

/// Result of a BOL scan. Every field is optional because real-world
/// BOLs are photocopied, shadowed, and missing half their data — the
/// UI is responsible for showing "—" for missing fields rather than
/// pretending the scan covered everything.
struct BOLScanResult: Codable, Equatable {
    /// ID the phone stamps on each scan so the watch can de-dupe if
    /// WCSession double-delivers (one sendMessage + one applicationContext).
    let scanId: String
    /// Which load this scan is associated with. Phone sets from
    /// `LoadStore.active.id` at capture time, or nil if the driver
    /// scanned something standalone.
    let loadId: String?
    /// Captured at (phone wall-clock, UTC).
    let capturedAt: Date
    /// Which side of the document was captured.
    let documentKind: BOLDocumentKind
    /// Extracted fields. Not all populate on every scan.
    let fields: BOLFields
    /// On-device Foundation Models confidence, 0…1.
    let confidence: Double
    /// Cross-check warnings surfaced to the driver. Empty means the
    /// phone's `ergClassify.matchBOLAndPlacard` found no mismatches.
    let warnings: [BOLWarning]
}

enum BOLDocumentKind: String, Codable {
    case bol        // Bill of Lading
    case placard    // Hazmat placard
    case manifest   // Multi-stop manifest
    case podReceipt // Proof-of-Delivery ticket
    case other
}

struct BOLFields: Codable, Equatable {
    var shipper: String?
    var consignee: String?
    var poNumber: String?
    var bolNumber: String?
    var commodity: String?
    var weightPounds: Int?
    var pieces: Int?
    // Hazmat fields — the placard flow may set these even on a
    // document scan when the BOL has a hazmat section.
    var unNumber: String?       // "UN1203"
    var hazardClass: String?    // "3"
    var packingGroup: String?   // "II"
    var placardColor: String?   // "ORANGE", "RED", …
}

struct BOLWarning: Codable, Equatable, Identifiable {
    var id: String { code }
    let code: String          // e.g. "placard-class-mismatch"
    let severity: Severity
    let message: String

    enum Severity: String, Codable {
        case info
        case warn
        case critical
    }
}

@MainActor
final class BOLCopilot: ObservableObject {
    static let shared = BOLCopilot()

    @Published private(set) var latest: BOLScanResult?
    @Published private(set) var history: [BOLScanResult] = []
    @Published private(set) var isScanRequestInFlight: Bool = false
    @Published private(set) var lastError: String?

    /// Cap the on-watch history at a handful — drivers don't scroll,
    /// dispatch pulls the full log from the backend via
    /// `bol.listScans` if they want the trail.
    private let historyCap = 20

    private let persistURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bol-history.json")
    }()

    // MARK: - Persistence

    func restore() {
        guard let data = try? Data(contentsOf: persistURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let items = try? decoder.decode([BOLScanResult].self, from: data) {
            history = items
            latest = items.first
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(history) {
            try? data.write(to: persistURL, options: .atomic)
        }
    }

    // MARK: - Scan request (wrist → phone)

    /// Ask the iPhone to open the BOL scanner. Driven by Esang voice
    /// ("scan the placard", "scan the BOL") and by the dedicated
    /// SCAN button in the load-detail card. The phone's
    /// `DataScannerViewController` takes the frame, Foundation Models
    /// extracts structured fields, and the result comes back as a
    /// `bol.result` WCSession message.
    func requestScan(kind: BOLDocumentKind, loadId: String?) {
        guard EusoTripConfig.bolCopilotEnabled else { return }
        isScanRequestInFlight = true
        lastError = nil
        WatchConnectivityManager.shared.requestBOLScan(
            kind: kind.rawValue,
            loadId: loadId
        )
        // If the phone doesn't respond in 8s, clear the spinner. The
        // driver can re-try without waiting for the full WCSession
        // transfer timeout.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self else { return }
            if self.isScanRequestInFlight {
                self.isScanRequestInFlight = false
                self.lastError = "Phone didn't respond — try again."
            }
        }
    }

    // MARK: - Result ingest (phone → wrist)

    /// Apply a scan result forwarded from the iPhone. Dedupes against
    /// `scanId` so double-delivery (sendMessage + transferUserInfo)
    /// doesn't double-log. Appends a BlockchainAudit block for any
    /// critical warning so the chain-of-custody has a tamper-evident
    /// record of the driver having been shown the mismatch.
    func applyScanResult(_ result: BOLScanResult) {
        isScanRequestInFlight = false
        lastError = nil

        // De-dupe by scanId.
        if history.contains(where: { $0.scanId == result.scanId }) { return }

        latest = result
        history.insert(result, at: 0)
        if history.count > historyCap {
            history = Array(history.prefix(historyCap))
        }
        persist()

        // Audit: log placard scans + any critical warning so the
        // compliance trail survives offline. Regular BOL scans with
        // no warnings skip the audit to keep the chain compact —
        // those are shippable paperwork events, not compliance flags.
        if EusoTripConfig.blockchainAuditEnabled {
            let critical = result.warnings.first { $0.severity == .critical }
            if result.documentKind == .placard || critical != nil {
                BlockchainAudit.shared.append(
                    kind: .podScan,
                    payload: compactAuditPayload(from: result)
                )
            }
        }
    }

    private func compactAuditPayload(from result: BOLScanResult) -> [String: String] {
        var out: [String: String] = [
            "scanId": result.scanId,
            "kind": result.documentKind.rawValue,
            "conf": String(format: "%.2f", result.confidence)
        ]
        if let loadId = result.loadId { out["loadId"] = loadId }
        if let un = result.fields.unNumber { out["un"] = un }
        if let cls = result.fields.hazardClass { out["class"] = cls }
        // Critical warnings only — the audit row is a crumb, not the
        // whole payload. The full scan JSON lives in
        // `BOLCopilot.history` + the server-side blob store.
        if let warn = result.warnings.first(where: { $0.severity == .critical }) {
            out["warn"] = warn.code
        }
        return out
    }

    // MARK: - Convenience lookups

    /// Cross-reference a placard UN number against the bundled ERG
    /// database. Used by the BOLCopilotView summary card so the
    /// driver sees the ERG guide page + isolation distances without
    /// needing a second tap.
    func ergEntry(for fields: BOLFields) -> ErgEntry? {
        guard let un = fields.unNumber, !un.isEmpty else { return nil }
        return ErgDatabase.shared.guide(un: un)
    }
}
