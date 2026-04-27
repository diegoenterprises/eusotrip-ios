//
//  BOLCopilotView.swift
//  EusoTrip Pulse Watch App
//
//  F15 — Wrist-side result viewer for the BOL / placard copilot.
//
//  Layout (top → bottom):
//    1. Big capture button with spinner while the phone is capturing
//    2. Warnings banner (if any) — color-coded by severity
//    3. Field grid for the last scan (shipper, consignee, PO, etc.)
//    4. If the scan included a UN number, an ERG guide card with the
//       bundled isolation distance so the driver sees the compliance
//       surface in one glance
//    5. History carousel for quick recall of recent scans
//

import SwiftUI
import WatchKit

struct BOLCopilotView: View {
    @ObservedObject private var copilot = BOLCopilot.shared
    @EnvironmentObject var loads: LoadStore

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                scanButtons
                if let err = copilot.lastError {
                    errorBanner(err)
                }
                if let latest = copilot.latest {
                    warningsBlock(latest)
                    fieldsCard(latest)
                    if let erg = copilot.ergEntry(for: latest.fields) {
                        ergCard(erg)
                    }
                    confidencePill(latest.confidence)
                } else {
                    emptyState
                }
                if copilot.history.count > 1 {
                    historyList
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .navigationTitle("BOL")
    }

    // MARK: - Scan buttons

    @ViewBuilder
    private var scanButtons: some View {
        HStack(spacing: 6) {
            scanButton(label: "BOL", kind: .bol)
            scanButton(label: "Placard", kind: .placard)
        }
    }

    @ViewBuilder
    private func scanButton(label: String, kind: BOLDocumentKind) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            copilot.requestScan(kind: kind, loadId: loads.active?.id)
        } label: {
            VStack(spacing: 2) {
                if copilot.isScanRequestInFlight {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: kind == .bol ? "doc.text.viewfinder" : "exclamationmark.triangle")
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                LinearGradient.esangPrimary,
                in: RoundedRectangle(cornerRadius: R.sm)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(copilot.isScanRequestInFlight)
    }

    // MARK: - Warnings banner

    @ViewBuilder
    private func warningsBlock(_ result: BOLScanResult) -> some View {
        if !result.warnings.isEmpty {
            VStack(spacing: 4) {
                ForEach(result.warnings) { w in
                    HStack(spacing: 6) {
                        Image(systemName: glyph(for: w.severity))
                            .foregroundStyle(tint(for: w.severity))
                        Text(w.message)
                            .font(.system(size: 11, weight: .semibold))
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: R.sm)
                            .fill(tint(for: w.severity).opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: R.sm)
                            .stroke(tint(for: w.severity).opacity(0.5), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func tint(for severity: BOLWarning.Severity) -> Color {
        switch severity {
        case .info:     return .esangBlue
        case .warn:     return .esangAmber
        case .critical: return .esangDanger
        }
    }

    private func glyph(for severity: BOLWarning.Severity) -> String {
        switch severity {
        case .info:     return "info.circle.fill"
        case .warn:     return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    // MARK: - Fields card

    @ViewBuilder
    private func fieldsCard(_ result: BOLScanResult) -> some View {
        let f = result.fields
        VStack(alignment: .leading, spacing: 3) {
            Text(titleFor(result.documentKind))
                .font(.system(size: 9, weight: .medium))
                .tracking(1)
                .foregroundStyle(.secondary)
            fieldRow("Shipper",   f.shipper)
            fieldRow("Consignee", f.consignee)
            fieldRow("BOL #",     f.bolNumber)
            fieldRow("PO",        f.poNumber)
            fieldRow("Commodity", f.commodity)
            if let w = f.weightPounds { fieldRow("Weight", "\(w) lbs") }
            if let p = f.pieces       { fieldRow("Pieces", "\(p)") }
            if let un = f.unNumber    { fieldRow("UN",     un) }
            if let cls = f.hazardClass { fieldRow("Class", cls) }
            if let pg = f.packingGroup { fieldRow("Group", pg) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    @ViewBuilder
    private func fieldRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value ?? "—")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    private func titleFor(_ kind: BOLDocumentKind) -> String {
        switch kind {
        case .bol:        return "BILL OF LADING"
        case .placard:    return "PLACARD"
        case .manifest:   return "MANIFEST"
        case .podReceipt: return "POD RECEIPT"
        case .other:      return "SCAN"
        }
    }

    // MARK: - ERG card

    @ViewBuilder
    private func ergCard(_ erg: ErgEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("ERG")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("GUIDE \(erg.guide)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.esangAmber)
            }
            Text(erg.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if let pad = erg.protectiveActionDistance {
                Text("Isolate \(pad.smallSpillIsolationFeet) ft · protect \(formatMiles(pad.smallSpillProtectiveMiles)) mi")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: R.sm)
                .fill(Color.esangAmber.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: R.sm)
                .stroke(Color.esangAmber.opacity(0.5), lineWidth: 1)
        )
    }

    private func formatMiles(_ miles: Double) -> String {
        if miles < 1 { return String(format: "%.1f", miles) }
        return String(format: "%.0f", miles)
    }

    // MARK: - Confidence + error + history

    @ViewBuilder
    private func confidencePill(_ c: Double) -> some View {
        let pct = Int((c * 100).rounded())
        HStack(spacing: 4) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 9))
            Text("\(pct)% confidence")
                .font(.system(size: 9))
        }
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(.caption2)
            .foregroundStyle(Color.esangDanger)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: R.sm)
                    .fill(Color.esangDanger.opacity(0.15))
            )
    }

    @ViewBuilder
    private var historyList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RECENT")
                .font(.system(size: 9, weight: .medium))
                .tracking(1)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            ForEach(copilot.history.dropFirst().prefix(5)) { item in
                HStack {
                    Image(systemName: item.documentKind == .placard
                          ? "exclamationmark.triangle"
                          : "doc.text")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(titleFor(item.documentKind))
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Text(relativeTime(item.capturedAt))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                Divider()
                    .overlay(Color.white.opacity(0.1))
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 60 { return "\(Int(s))s" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No scan yet")
                .font(.caption.bold())
            Text("Tap BOL or Placard to start.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Identifiable conformance

extension BOLScanResult: Identifiable {
    var id: String { scanId }
}

#if DEBUG
struct BOLCopilotView_Previews: PreviewProvider {
    static var previews: some View {
        BOLCopilotView()
            .environmentObject(LoadStore.shared)
    }
}
#endif
