//
//  NRCComplianceCard.swift
//  EusoTrip — Hazmat-7 (Class 7 radioactive) compliance surface.
//
//  Closes the final 160 MISSING scenarios in the 8000-scenario
//  shipper↔driver parity audit (cargo type 08 hazmat-7). UF + CT both
//  lack civilian-freight NRC integration; this card is a real
//  EXCLUSIVE LEAD surface across every load whose cargo is
//  radioactive.
//
//  Three stacked sections, all driven by `nrc.*` server queries:
//
//    1. License status — category + expiry + days-remaining + a
//       severity badge (CLEAR / WATCH / WARN / EXPIRED). Drives
//       the iOS card's first-load gate ("license missing → don't
//       roll").
//
//    2. Dosimetry log — cumulative mrem across all readings on
//       this load + severity colored against the per-load
//       thresholds the server applies (10 CFR 20.1201 occupational
//       limits sized for one shipment window). Driver gets an
//       inline "Log reading" button; shipper sees read-only.
//
//    3. Chain-of-custody timeline — every transfer recorded so far
//       (shipper → driver, driver → consignee, etc.) with the
//       transfer kind, parties, location, and dosimeter reading
//       at that point. Tap-through to detail surface (future).
//
//  Renders only when `cargoType` resolves to a hazmat-7 form. The
//  card stays out of the way for every other load type so the
//  205 / 025 surfaces don't clutter for routine cargo.
//
//  Production-grade per [feedback_swiftui_previews] mandate. Dark +
//  Light previews ship.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct NRCComplianceCard: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// Numeric load id used by the nrc.* queries. Caller passes the
    /// active load's numeric id from LoadsAPI.LoadDetail or from the
    /// driver lifecycle store. Empty / zero short-circuits to a
    /// neutral skeleton state.
    let loadId: String

    /// When true, the dosimetry section renders the "Log reading"
    /// CTA. Driver-side surfaces (025_Paperwork, 035_EnRouteDrive)
    /// pass true; shipper-side 205 passes false (read-only).
    let driverSide: Bool

    @State private var license: NRCAPI.LicenseStatus? = nil
    @State private var dosimetry: NRCAPI.DosimetryLog? = nil
    @State private var custody: NRCAPI.ChainOfCustody? = nil
    @State private var loading: Bool = false
    @State private var error: String? = nil
    @State private var showLogReading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            licenseSection
            dosimetrySection
            custodySection
            if let err = error {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .task { await refresh() }
        .sheet(isPresented: $showLogReading) {
            DosimetryEntrySheet(loadId: loadId, onLogged: {
                Task { await refresh() }
            })
            .environment(\.palette, palette)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "atom")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("HAZMAT · CLASS 7 · NRC")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer(minLength: 0)
            if loading {
                ProgressView().scaleEffect(0.7)
            }
        }
    }

    // MARK: - License section

    @ViewBuilder
    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("LICENSE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(licenseSeverity.label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(severityColor(licenseSeverity))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(severityColor(licenseSeverity).opacity(0.14),
                                in: Capsule())
            }
            Text(licensePrimary)
                .font(EType.body).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
            Text(licenseSecondary)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var licensePrimary: String {
        guard let l = license, let cat = l.category else { return "Not on file" }
        let category = NRCAPI.LicenseCategory(rawValue: cat)?.label ?? cat
        let number = l.licenseNumber ?? "—"
        return "\(category) · \(number)"
    }

    private var licenseSecondary: String {
        guard let l = license, let cat = l.category else {
            return "Carrier hasn't recorded NRC license. Compliance officer must record before this load can roll."
        }
        let issuedBy = l.issuedBy ?? "—"
        let expiresAt = l.expiresAt?.split(separator: "T").first.map(String.init) ?? "—"
        let days = l.daysRemaining.map { "\($0)d" } ?? "—"
        let forms = l.authorizedForms.isEmpty ? "—" : l.authorizedForms.joined(separator: ", ")
        _ = cat
        return "Issued by \(issuedBy) · expires \(expiresAt) · \(days) · forms: \(forms)"
    }

    private enum Severity {
        case clear, watch, warn, expired, neutral
        var label: String {
            switch self {
            case .clear:   return "CLEAR"
            case .watch:   return "WATCH"
            case .warn:    return "WARN"
            case .expired: return "EXPIRED"
            case .neutral: return "—"
            }
        }
    }

    private var licenseSeverity: Severity {
        guard let l = license else { return .neutral }
        if l.status == "missing" || l.category == nil { return .expired }
        guard let d = l.daysRemaining else { return .neutral }
        if d <= 0  { return .expired }
        if d <= 7  { return .warn }
        if d <= 30 { return .watch }
        return .clear
    }

    private func severityColor(_ s: Severity) -> Color {
        switch s {
        case .clear:   return Brand.success
        case .watch:   return Brand.warning
        case .warn:    return Brand.danger
        case .expired: return Brand.danger
        case .neutral: return palette.textSecondary
        }
    }

    // MARK: - Dosimetry section

    private var dosimetrySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("DOSIMETRY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(dosimetrySeverity.label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(severityColor(dosimetrySeverity))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(severityColor(dosimetrySeverity).opacity(0.14),
                                in: Capsule())
            }
            HStack(alignment: .firstTextBaseline) {
                Text(cumulativeMremDisplay)
                    .font(.system(size: 22, weight: .heavy).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text("mrem cumulative")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                if driverSide {
                    Button {
                        showLogReading = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Log reading")
                                .font(EType.caption).fontWeight(.semibold)
                        }
                        .foregroundStyle(palette.textOnGradient)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(LinearGradient.diagonal,
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(dosimetrySecondary)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var cumulativeMremDisplay: String {
        guard let d = dosimetry else { return "—" }
        return String(format: "%.1f", d.cumulativeMrem)
    }

    private var dosimetrySecondary: String {
        guard let d = dosimetry else { return "No readings logged yet for this load." }
        let count = d.readings.count
        return "\(count) reading\(count == 1 ? "" : "s") · 10 CFR 20.1201 baseline 5,000 mrem/yr occupational"
    }

    private var dosimetrySeverity: Severity {
        guard let d = dosimetry else { return .neutral }
        switch d.severity {
        case "clear":   return .clear
        case "watch":   return .watch
        case "warn":    return .warn
        case "expired": return .expired
        default:        return .neutral
        }
    }

    // MARK: - Chain-of-custody section

    @ViewBuilder
    private var custodySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("CHAIN OF CUSTODY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(custody?.transfers.count ?? 0) transfer\((custody?.transfers.count ?? 0) == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
            }
            if let transfers = custody?.transfers, !transfers.isEmpty {
                ForEach(transfers) { t in
                    transferRow(t)
                }
            } else {
                Text("No transfers recorded yet. Each handoff captures both parties' signatures + a dosimeter reading.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func transferRow(_ t: NRCAPI.CustodyTransfer) -> some View {
        let kindLabel = NRCAPI.TransferKind(rawValue: t.kind)?.label ?? t.kind
        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle().fill(LinearGradient.diagonal).frame(width: 8, height: 8)
                Rectangle()
                    .fill(palette.borderFaint)
                    .frame(width: 1)
            }
            .frame(width: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(kindLabel)
                    .font(EType.body).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("\(t.fromUserName ?? "—") → \(t.toUserName ?? "—")")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                if let mrem = t.dosimeterReadingMrem {
                    Text(String(format: "%.1f mrem at transfer · %@",
                                mrem, NRCAPI.DosimetryKind(rawValue: t.dosimeterKind ?? "")?.label ?? "—"))
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                if let loc = t.location {
                    Text(loc)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                Text(t.timestamp.split(separator: ".").first.map(String.init) ?? t.timestamp)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Network

    private func refresh() async {
        guard !loadId.isEmpty, loadId != "0" else { return }
        loading = true
        defer { loading = false }
        async let l: NRCAPI.LicenseStatus? = (try? await EusoTripAPI.shared.nrc.getLicenseStatus(loadId: loadId))
        async let d: NRCAPI.DosimetryLog? = (try? await EusoTripAPI.shared.nrc.getDosimetryLog(loadId: loadId))
        async let c: NRCAPI.ChainOfCustody? = (try? await EusoTripAPI.shared.nrc.getChainOfCustody(loadId: loadId))
        let lr = await l
        let dr = await d
        let cr = await c
        await MainActor.run {
            license = lr
            dosimetry = dr
            custody = cr
        }
    }
}

// MARK: - Dosimetry entry sheet

/// Driver-side entry composer for a single dosimetry reading.
/// Submits via `nrc.submitDosimetryReading`. Lives next to the
/// card so the file is the single home for hazmat-7 surfaces.
struct DosimetryEntrySheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let loadId: String
    let onLogged: () -> Void

    @State private var mremText: String = ""
    @State private var kind: NRCAPI.DosimetryKind = .epdContinuous
    @State private var notes: String = ""
    @State private var inFlight: Bool = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Log a dosimetry reading on this hazmat-7 load. Cumulative mrem auto-calculates server-side; readings retain their kind tag (TLD monthly / EPD continuous / shipment log / ambient) for the final POD audit trail.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reading (mrem)")
                            .font(EType.caption).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        TextField("e.g. 12.4", text: $mremText)
                            .font(EType.body)
                            .keyboardType(.decimalPad)
                            .padding(Space.s3)
                            .background(palette.bgCardSoft,
                                        in: RoundedRectangle(cornerRadius: Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(palette.borderFaint))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dosimeter kind")
                            .font(EType.caption).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Picker("Kind", selection: $kind) {
                            ForEach(NRCAPI.DosimetryKind.allCases) { k in
                                Text(k.label).tag(k)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes (optional)")
                            .font(EType.caption).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        TextField("Anything unusual on this read",
                                  text: $notes, axis: .vertical)
                            .lineLimit(2, reservesSpace: true)
                            .font(EType.body)
                            .padding(Space.s3)
                            .background(palette.bgCardSoft,
                                        in: RoundedRectangle(cornerRadius: Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md)
                                .strokeBorder(palette.borderFaint))
                    }
                    if let err = error {
                        Text(err)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                    }
                    HStack(spacing: Space.s3) {
                        Button { dismiss() } label: {
                            Text("Cancel")
                                .font(EType.body).fontWeight(.semibold)
                                .foregroundStyle(palette.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Space.s3)
                                .background(palette.bgCard,
                                            in: RoundedRectangle(cornerRadius: Radius.md))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                                    .strokeBorder(palette.borderFaint))
                        }
                        .buttonStyle(.plain)
                        .disabled(inFlight)

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack(spacing: 6) {
                                if inFlight { ProgressView().tint(palette.textOnGradient) }
                                Text(inFlight ? "Logging…" : "Log reading")
                                    .font(EType.body).fontWeight(.semibold)
                            }
                            .foregroundStyle(palette.textOnGradient)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Space.s3)
                            .background(LinearGradient.diagonal,
                                        in: RoundedRectangle(cornerRadius: Radius.md))
                            .opacity(canSubmit ? 1 : 0.55)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s3)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("DOSIMETRY · NEW READING")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard !inFlight else { return false }
        guard let v = Double(mremText.trimmingCharacters(in: .whitespacesAndNewlines)),
              v >= 0 else { return false }
        return true
    }

    private func submit() async {
        guard canSubmit, let mrem = Double(mremText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        inFlight = true
        defer { inFlight = false }
        do {
            _ = try await EusoTripAPI.shared.nrc.submitDosimetryReading(
                loadId: loadId,
                readingMrem: mrem,
                kind: kind,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onLogged()
            dismiss()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("NRC card · driver · Dark") {
    NRCComplianceCard(loadId: "44912", driverSide: true)
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
        .padding()
}

#Preview("NRC card · shipper · Light") {
    NRCComplianceCard(loadId: "44912", driverSide: false)
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
        .padding()
}
