//
//  419_ExceptionResponse.swift
//  EusoTrip — Shipper · Exception response routing (Arc C deepening).
//

import SwiftUI

struct ExceptionResponseScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var exceptionType: String = "detention"
    var body: some View {
        Shell(theme: theme) { ExceptionRoutingBody(loadId: loadId, exceptionType: exceptionType) } nav: { shipperLifecycleNav() }
    }
}

private struct ExceptionRoutingBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    let exceptionType: String

    private var routes: [(icon: String, title: String, subtitle: String, screen: String, claim: String?)] {
        switch exceptionType.lowercased() {
        case "detention":
            return [
                ("dollarsign.circle", "File detention claim", "$75/hr × hours captured by ELD", "386", "detention"),
                ("phone.fill", "Escalate to dispatch", "Page Eusorone ops dispatcher", "318", nil),
                ("text.bubble", "Message driver", "Direct chat thread", "311", nil),
            ]
        case "breakdown":
            return [
                ("wrench.fill", "Open Zeun breakdown ticket", "Mechanical accident routes through Zeun", "318", nil),
                ("phone.fill", "Call carrier ops", "Carrier dispatch line", "262", nil),
                ("doc.text", "File freight claim (cargo)", "Cargo damage / spoilage", "386", "damage"),
            ]
        case "contamination", "reefer_excursion":
            return [
                ("thermometer.transmission", "File reefer excursion claim", "Auto-attaches temp log", "386", "reefer_excursion"),
                ("phone.fill", "Notify insurer", "Carrier insurance contact", "262", nil),
                ("xmark.octagon", "Refuse cargo at receiver", "Halts unload, opens claim", "278", nil),
            ]
        case "un1203_delayed", "delay":
            return [
                ("clock.arrow.2.circlepath", "Re-route", "Find nearest secure parking", "278", nil),
                ("dollarsign.circle", "File detention claim", "Triggers carrier insurance", "386", "delay"),
                ("phone.fill", "Escalate to dispatch", "Page Eusorone ops", "318", nil),
            ]
        default:
            return [
                ("phone.fill", "Escalate to dispatch", "Page Eusorone ops", "318", nil),
                ("doc.text", "File freight claim", "Catch-all claim flow", "386", "other"),
            ]
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                LifecycleCard(accentDanger: true) {
                    LifecycleSection(label: "EXCEPTION TYPE", icon: "exclamationmark.triangle.fill")
                    LifecycleRow(label: "Type", value: exceptionType.replacingOccurrences(of: "_", with: " ").uppercased())
                    LifecycleRow(label: "Load", value: loadId)
                }
                ForEach(Array(routes.enumerated()), id: \.offset) { i, route in
                    Button {
                        var info: [String: Any] = ["screenId": route.screen, "loadId": loadId]
                        if let c = route.claim { info["claimType"] = c }
                        NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: info)
                    } label: {
                        LifecycleCard {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: route.icon).font(.system(size: 22, weight: .heavy)).foregroundStyle(LinearGradient.diagonal).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                    Text(route.subtitle).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.bubble").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("SHIPPER · EXCEPTION RESPONSE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.warning)
            }
            Text("How do you want to respond?").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }
}

#Preview("419 · Exception · Night") { ExceptionResponseScreen(theme: Theme.dark, loadId: "1", exceptionType: "detention").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("419 · Exception · Afternoon") { ExceptionResponseScreen(theme: Theme.light, loadId: "1", exceptionType: "detention").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
