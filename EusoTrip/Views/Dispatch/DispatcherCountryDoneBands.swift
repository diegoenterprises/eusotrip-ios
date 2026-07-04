//
//  DispatcherCountryDoneBands.swift
//  EusoTrip 2027 · Dispatcher · COUNTRY-DONE tri-country bands (§dispatcher-countrydone 403·405·407)
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Ported from the truck-lane staging (STATIC-REVIEWED → compile lane). These are NEW,
//  distinctly-named band views mounted into the live Dispatcher screens:
//    · DispatcherTenderOriginSplitBand   → Tender Queue (403) — tenders grouped by origin country
//    · DispatcherCrossBorderOpsChannelRow → Comms Hub (405)   — #cross-border-ops channel row
//    · DispatcherLaneEligibilityGate     → Reassignment (407) — lane-jurisdiction eligibility gate
//
//  Each renders whatever the caller passes from the real procedures (dispatch.getPendingTenders,
//  messaging.getChannels, loads.getById). Per-country customs/HOS/cert labels are regulatory
//  constants (ACE/ACI/Carta Porte · CBP/CBSA/SAT-Aduanas · 49 CFR 395 / SOR/2005-313 / NOM-087).
//  Named gaps handed to the-oath: dispatch.getTendersByOriginCountry ·
//  borderEligible on dispatch.getAvailableDrivers · eld.getActiveHosRuleset ·
//  cross-border customs-broker channel seeding in communicationHub.
//

import SwiftUI

// MARK: - Shared region model -------------------------------------------------

/// One US/CA/MX corridor row used by the tri-country bands. `count` is nil when the band
/// is a per-lane gate (407) rather than a per-origin tally (403).
struct CBRegion: Identifiable {
    enum Code: String { case US, CA, MX }
    var id: String { code.rawValue }
    let code: Code
    let accentHex: String        // region accent (reads on both themes)
    let count: Int?              // 403: tender count by origin · nil otherwise
    let customs: String          // 403: "ACE"/"ACI"/"CARTA PORTE" · 405: "CBP"/"CBSA"/"SAT-Aduanas"
    let hosLabel: String?        // 407: "11h"/"13h"/"14h" · nil otherwise
    let certLabel: String?       // 407: "CDL"/"FAST"/"SENTRI+Lic Fed" · nil otherwise
}

// MARK: - 403 · tri-country tender-origin split (tinted CELLS) -----------------

struct DispatcherTenderOriginSplitBand: View {
    @Environment(\.palette) private var palette
    let regions: [CBRegion]      // US/CA/MX with .count + .customs
    let crossBorderCount: Int    // header "· N CROSS-BORDER"
    let onViewAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TENDERS BY ORIGIN · \(crossBorderCount) CROSS-BORDER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundColor(palette.textTertiary)
                Spacer()
                Button(action: onViewAll) {
                    Text("SORT BY LANE →").font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        .foregroundColor(Brand.blue)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                ForEach(regions) { r in
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: r.accentHex)).frame(width: 6, height: 6)
                        Text("\(r.code.rawValue) \(r.count.map(String.init) ?? "—") · \(r.customs)")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(Color(hex: r.accentHex))
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: r.accentHex).opacity(0.12)))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6).frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.borderFaint, lineWidth: 1)))
    }
}

// MARK: - 405 · cross-border ops channel (CHANNEL ROW) -------------------------

struct DispatcherCrossBorderOpsChannelRow: View {
    @Environment(\.palette) private var palette
    let channelName: String      // real channel name from messaging.getChannels
    let authoritiesLine: String  // "US CBP · CA CBSA · MX SAT-Aduanas"
    let unread: Int?             // real unread count, when present
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Brand.blue.opacity(0.14)).frame(width: 26, height: 26)
                Image(systemName: "globe").font(.system(size: 13, weight: .regular))
                    .foregroundColor(Brand.blue)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(channelName).font(.system(size: 12, weight: .heavy))
                    .foregroundColor(palette.textPrimary)
                Text(authoritiesLine)
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
            if let unread, unread > 0 {
                Text("\(unread)")
                    .font(.system(size: 11, weight: .heavy))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Brand.danger))
                    .foregroundStyle(.white)
            }
            Button(action: onOpen) {
                Text("ALL DMS →").font(.system(size: 11, weight: .heavy)).tracking(0.5)
                    .foregroundColor(Brand.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.borderFaint, lineWidth: 1)))
    }
}

// MARK: - 407 · cross-border lane-eligibility gate (VERDICT GATE + segments) ---

struct DispatcherLaneEligibilityGate: View {
    @Environment(\.palette) private var palette
    let laneLabel: String        // "MIL→MSP"
    let verdict: String          // "US DOMESTIC · CDL ONLY"
    let verdictOK: Bool          // true → success wash; false → warning
    let regions: [CBRegion]      // US/CA/MX with .hosLabel + .certLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LANE JURISDICTION · \(laneLabel)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundColor(palette.textTertiary)
                Spacer()
                Text(verdict).font(.system(size: 9, weight: .heavy)).tracking(0.3)
                    .foregroundColor(verdictOK ? Brand.success : Brand.warning)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill((verdictOK ? Brand.success : Brand.warning).opacity(0.16)))
            }
            HStack(spacing: 0) {
                ForEach(regions) { r in
                    Text("\(r.code.rawValue) \(r.hosLabel ?? "") · \(r.certLabel ?? "")")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: r.accentHex))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.borderFaint, lineWidth: 1)))
    }
}

// MARK: - Previews

#Preview("Dispatcher country bands · Dark") {
    VStack(spacing: 14) {
        DispatcherTenderOriginSplitBand(
            regions: [
                .init(code: .US, accentHex: "1473FF", count: 5, customs: "ACE", hosLabel: nil, certLabel: nil),
                .init(code: .CA, accentHex: "00C48C", count: 2, customs: "ACI", hosLabel: nil, certLabel: nil),
                .init(code: .MX, accentHex: "FF7A00", count: 1, customs: "CARTA PORTE", hosLabel: nil, certLabel: nil),
            ],
            crossBorderCount: 3, onViewAll: {})
        DispatcherCrossBorderOpsChannelRow(
            channelName: "#cross-border-ops",
            authoritiesLine: "US CBP · CA CBSA · MX SAT-Aduanas",
            unread: 2, onOpen: {})
        DispatcherLaneEligibilityGate(
            laneLabel: "MIL→MSP",
            verdict: "US DOMESTIC · CDL ONLY",
            verdictOK: true,
            regions: [
                .init(code: .US, accentHex: "1473FF", count: nil, customs: "ACE", hosLabel: "11h", certLabel: "CDL"),
                .init(code: .CA, accentHex: "00C48C", count: nil, customs: "ACI", hosLabel: "13h", certLabel: "FAST"),
                .init(code: .MX, accentHex: "FF7A00", count: nil, customs: "CARTA PORTE", hosLabel: "14h", certLabel: "SENTRI·Lic Fed"),
            ])
    }
    .padding()
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Dispatcher country bands · Light") {
    VStack(spacing: 14) {
        DispatcherTenderOriginSplitBand(
            regions: [
                .init(code: .US, accentHex: "1473FF", count: 5, customs: "ACE", hosLabel: nil, certLabel: nil),
                .init(code: .CA, accentHex: "00C48C", count: 2, customs: "ACI", hosLabel: nil, certLabel: nil),
                .init(code: .MX, accentHex: "FF7A00", count: 1, customs: "CARTA PORTE", hosLabel: nil, certLabel: nil),
            ],
            crossBorderCount: 3, onViewAll: {})
        DispatcherCrossBorderOpsChannelRow(
            channelName: "#cross-border-ops",
            authoritiesLine: "US CBP · CA CBSA · MX SAT-Aduanas",
            unread: nil, onOpen: {})
        DispatcherLaneEligibilityGate(
            laneLabel: "LAR→MTY",
            verdict: "US → MX · SENTRI + LIC FED",
            verdictOK: false,
            regions: [
                .init(code: .US, accentHex: "1473FF", count: nil, customs: "ACE", hosLabel: "11h", certLabel: "CDL"),
                .init(code: .CA, accentHex: "00C48C", count: nil, customs: "ACI", hosLabel: "13h", certLabel: "FAST"),
                .init(code: .MX, accentHex: "FF7A00", count: nil, customs: "CARTA PORTE", hosLabel: "14h", certLabel: "SENTRI·Lic Fed"),
            ])
    }
    .padding()
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
