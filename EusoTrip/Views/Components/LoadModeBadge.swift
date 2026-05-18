//
//  LoadModeBadge.swift
//  EusoTrip
//
//  2026-05-17 — Shared mode badge surfaced on every load row across
//  all 24 role surfaces (shipper loads list, catalyst board, broker
//  bid screen, dispatch lane board, driver available-loads, etc.).
//  Replaces the implicit truck-only assumption: rail / vessel / barge
//  loads now read distinctly in every list.
//
//  Doctrine reference (memory):
//  • "Full-parity doctrine — all 24 roles + 3 verticals ship at equal
//    depth" — the badge appears identically wherever a load row renders.
//  • "Cross-role action chain — every endpoint/screen/mutation must
//    have its counter-party endpoint on the other role(s)" — surfacing
//    transport mode on every counter-party's load row is the read-side
//    half of the chain we just opened on the write side (shipper
//    Post-a-Load wizard Step-1 mode picker).
//
//  Visual: one capsule with an SF symbol + 2-letter code. Colors are
//  pulled from the existing Brand palette (rail = Brand.rail, vessel
//  = Brand.vessel, truck/barge = Brand.blue) so the badge inherits the
//  same theming as every other branded surface.
//

import SwiftUI

struct LoadModeBadge: View {
    /// Raw transport mode string from the wire (truck / rail / vessel
    /// / barge). Lenient: anything that doesn't match a known mode
    /// renders as Truck so the badge never goes blank.
    let modeRaw: String?
    /// Optional vehicle count. When >1 the badge prepends "Nx" so the
    /// reader sees "3x · RAIL" without opening the detail screen.
    let multiVehicleCount: Int?
    /// Optional compact variant (e.g. tiny chips on cramped rows).
    var compact: Bool = false

    private var resolvedMode: String {
        switch (modeRaw ?? "truck").lowercased() {
        case "rail":   return "rail"
        case "vessel": return "vessel"
        case "barge":  return "barge"
        default:       return "truck"
        }
    }

    private var symbol: String {
        switch resolvedMode {
        case "rail":   return "tram.fill"
        case "vessel": return "ferry.fill"
        case "barge":  return "sailboat.fill"
        default:       return "truck.box.fill"
        }
    }

    private var label: String {
        switch resolvedMode {
        case "rail":   return "RAIL"
        case "vessel": return "VESSEL"
        case "barge":  return "BARGE"
        default:       return "TRUCK"
        }
    }

    private var tint: Color {
        switch resolvedMode {
        case "rail":   return Brand.rail
        case "vessel": return Brand.vessel
        case "barge":  return Brand.info
        default:       return Brand.blue
        }
    }

    var body: some View {
        // Hide entirely for the default truck single-vehicle case so
        // we don't add chrome to the common case. Founder doctrine:
        // surface what's *different* about the row, don't restate the
        // default everywhere.
        if resolvedMode == "truck" && (multiVehicleCount ?? 1) <= 1 {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                if let count = multiVehicleCount, count > 1 {
                    Text("\(count)×")
                        .font(.system(size: compact ? 8 : 9, weight: .heavy, design: .monospaced))
                        .tracking(0.4)
                }
                Image(systemName: symbol)
                    .font(.system(size: compact ? 8 : 9, weight: .heavy))
                Text(label)
                    .font(.system(size: compact ? 8 : 9, weight: .heavy))
                    .tracking(0.6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 2 : 3)
            .background(Capsule().fill(tint))
        }
    }
}

#Preview("Dark") {
    HStack(spacing: 8) {
        LoadModeBadge(modeRaw: "truck", multiVehicleCount: 1)
        LoadModeBadge(modeRaw: "rail", multiVehicleCount: 100)
        LoadModeBadge(modeRaw: "vessel", multiVehicleCount: 1)
        LoadModeBadge(modeRaw: "barge", multiVehicleCount: 6)
        LoadModeBadge(modeRaw: "truck", multiVehicleCount: 3)
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    HStack(spacing: 8) {
        LoadModeBadge(modeRaw: "truck", multiVehicleCount: 1)
        LoadModeBadge(modeRaw: "rail", multiVehicleCount: 100)
        LoadModeBadge(modeRaw: "vessel", multiVehicleCount: 1)
        LoadModeBadge(modeRaw: "barge", multiVehicleCount: 6)
        LoadModeBadge(modeRaw: "truck", multiVehicleCount: 3)
    }
    .padding()
    .background(Color.white)
    .preferredColorScheme(.light)
}
