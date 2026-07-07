//
//  VesselLandfallRegimeRail.swift
//  EusoTrip 2027 · 06 Vessel · VISIBILITY/TRACKING COUNTRY-DONE staging
//
//  Scope: takes the 3-country landfall spine and re-keys it for the
//  active destination regime (US/CA/MX).
//

import SwiftUI

// MARK: - Data model

struct LandfallRegime: Hashable, Identifiable {
    let id = UUID()
    let code: String            // US / CA / MX
    let port: String            // display name: US · LONG BEACH
    let portShort: String       // e.g. US·LGB
    let regimeLine: String      // per-screen: arrival instrument / release instrument / free-time basis
    let flag: Flag              // which flag glyph to draw
    let active: Bool

    enum Flag: String, Codable { case us, ca, mx }
}

extension LandfallRegime {
    /// Default static values as fallbacks or for previews.
    static let arrival: [LandfallRegime] = [
        .init(code: "US", port: "US · LONG BEACH", portShort: "US·LGB", regimeLine: "USCG eNOA · USD", flag: .us, active: true),
        .init(code: "CA", port: "CA · VANCOUVER",  portShort: "CA·VAN", regimeLine: "TC PAIR · CAD",   flag: .ca, active: false),
        .init(code: "MX", port: "MX · MANZANILLO", portShort: "MX·ZLO", regimeLine: "SEMAR · MXN",     flag: .mx, active: false),
    ]
    static let release: [LandfallRegime] = [
        .init(code: "US", port: "US · LONG BEACH", portShort: "US·LGB · CBP ACE",  regimeLine: "release on discharge", flag: .us, active: true),
        .init(code: "CA", port: "CA · VANCOUVER",  portShort: "CA·VAN · CBSA ACI", regimeLine: "RNS release",          flag: .ca, active: false),
        .init(code: "MX", port: "MX · MANZANILLO", portShort: "MX·ZLO · SAT PED",  regimeLine: "VUCEM · previo",       flag: .mx, active: false),
    ]
    static let terminalFreeTime: [LandfallRegime] = [
        .init(code: "US", port: "US · LBCT",  portShort: "US·LBCT", regimeLine: "FMC 46 CFR 541 · USD", flag: .us, active: true),
        .init(code: "CA", port: "CA · VFPA",  portShort: "CA·VFPA", regimeLine: "CTA tariff · CAD",     flag: .ca, active: false),
        .init(code: "MX", port: "MX · API",   portShort: "MX·ZLO",  regimeLine: "SAT estadías · MXN",   flag: .mx, active: false),
    ]
}

// MARK: - Flag glyph

struct LandfallFlag: View {
    let kind: LandfallRegime.Flag
    var muted: Bool = false
    var body: some View {
        ZStack {
            switch kind {
            case .us:
                Color.white
                Rectangle().fill(Color(red: 0.235, green: 0.231, blue: 0.431)) // #3C3B6E
                    .frame(width: 8, height: 6).offset(x: -5, y: -3)
                VStack(spacing: 1.5) {
                    Spacer()
                    Rectangle().fill(Color(red: 0.698, green: 0.133, blue: 0.204)).frame(height: 1.6) // #B22234
                    Rectangle().fill(Color(red: 0.698, green: 0.133, blue: 0.204)).frame(height: 1.6)
                }
            case .ca:
                Color.white
                HStack {
                    Rectangle().fill(Color(red: 0.835, green: 0.169, blue: 0.118)).frame(width: 4) // #D52B1E
                    Spacer()
                    Rectangle().fill(Color(red: 0.835, green: 0.169, blue: 0.118)).frame(width: 4)
                }
                Circle().fill(Color(red: 0.835, green: 0.169, blue: 0.118)).frame(width: 4.4, height: 4.4)
            case .mx:
                HStack(spacing: 0) {
                    Rectangle().fill(Color(red: 0.0, green: 0.408, blue: 0.278))   // #006847
                    Rectangle().fill(Color.white)
                    Rectangle().fill(Color(red: 0.808, green: 0.067, blue: 0.149)) // #CE1126
                }
                Circle().fill(Color(red: 0.549, green: 0.384, blue: 0.224)).frame(width: 3, height: 3)
            }
        }
        .frame(width: 18, height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 1))
        .opacity(muted ? 0.6 : 1)
    }
}

// MARK: - The rail

struct LandfallRegimeRail: View {
    @Environment(\.palette) private var palette
    enum Variant { case evenWaypoints, selectorCaption }

    let eyebrow: String
    let trailingEyebrow: String?
    let regimes: [LandfallRegime]
    let variant: Variant
    var captionLines: [CaptionLine] = []
    var onSelect: (String) -> Void = { _ in }

    struct CaptionLine: Identifiable { let id = UUID(); let text: String; let tone: Tone
        enum Tone { case primary, secondary, success, warning } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(eyebrow).font(.system(size: 9, weight: .heavy)).kerning(0.9)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if let t = trailingEyebrow {
                    Text(t).font(.system(size: 8, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.bottom, 10)

            switch variant {
            case .evenWaypoints:   evenWaypoints
            case .selectorCaption: selectorCaption
            }
        }
    }

    private var evenWaypoints: some View {
        HStack(spacing: 0) {
            ForEach(Array(regimes.enumerated()), id: \.element.id) { idx, r in
                waypoint(r)
                if idx < regimes.count - 1 {
                    Rectangle().fill(palette.borderFaint).frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                        .offset(y: -10)
                }
            }
        }
    }

    private func waypoint(_ r: LandfallRegime) -> some View {
        VStack(spacing: 6) {
            LandfallFlag(kind: r.flag, muted: !r.active)
            Text(r.portShort).font(EType.mono(.micro)).foregroundStyle(r.active ? palette.textPrimary : palette.textTertiary)
        }
    }

    private var selectorCaption: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(regimes) { r in
                    Button { onSelect(r.code) } label: {
                        LandfallFlag(kind: r.flag, muted: !r.active)
                            .padding(4)
                            .background(r.active ? palette.bgCard : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(r.active ? palette.borderStrong : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(captionLines) { line in
                    Text(line.text)
                        .font(EType.caption.weight(.bold))
                        .foregroundStyle(toneColor(line.tone))
                }
            }
        }
    }

    private func toneColor(_ t: CaptionLine.Tone) -> Color {
        switch t {
        case .primary:   return palette.textPrimary
        case .secondary: return palette.textSecondary
        case .success:   return Brand.success
        case .warning:   return Brand.warning
        }
    }
}

// MARK: - Factory methods

extension LandfallRegimeRail {
    /// 003 Vessel Live Tracking (Shipper) — selector + status caption.
    static func liveTracking003(captionLines: [CaptionLine],
                                onSelect: @escaping (String) -> Void) -> LandfallRegimeRail {
        .init(eyebrow: "LANDFALL REGIME · DESTINATION PORT", trailingEyebrow: "STATUS",
              regimes: LandfallRegime.arrival, variant: .selectorCaption,
              captionLines: captionLines, onSelect: onSelect)
    }
    /// 660 Vessel Live Position (Operator) — even waypoints, arrival regime.
    static func livePosition660(onSelect: @escaping (String) -> Void) -> LandfallRegimeRail {
        .init(eyebrow: "ARRIVAL LANDFALL · GATES ON DISCHARGE PORT", trailingEyebrow: nil,
              regimes: LandfallRegime.arrival, variant: .evenWaypoints, onSelect: onSelect)
    }
    /// 666 Vessel Container Timeline (Operator) — even waypoints, destination-release regime.
    static func containerTimeline666(onSelect: @escaping (String) -> Void) -> LandfallRegimeRail {
        .init(eyebrow: "DESTINATION RELEASE · GATES ON DISCHARGE COUNTRY", trailingEyebrow: nil,
              regimes: LandfallRegime.release, variant: .evenWaypoints, onSelect: onSelect)
    }
    /// 707 Vessel Container Movement Log (Operator) — selector + free-time caption; re-keys the dwell clock.
    static func movementLog707(captionLines: [CaptionLine],
                               onSelect: @escaping (String) -> Void) -> LandfallRegimeRail {
        .init(eyebrow: "TERMINAL FREE-TIME", trailingEyebrow: "DWELL CLOCK GATES ON TERMINAL",
              regimes: LandfallRegime.terminalFreeTime, variant: .selectorCaption,
              captionLines: captionLines, onSelect: onSelect)
    }
}
