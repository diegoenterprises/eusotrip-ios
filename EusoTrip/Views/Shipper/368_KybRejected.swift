//
//  368_KybRejected.swift
//  EusoTrip — Shipper · KYB rejected (Arc M).
//

import SwiftUI

struct KybRejectedScreen: View {
    let theme: Theme.Palette
    var reasons: [String] = []
    var body: some View {
        Shell(theme: theme) { KybRejectedBody(reasons: reasons) } nav: { shipperLifecycleNav() }
    }
}

private struct KybRejectedBody: View {
    @Environment(\.palette) private var palette
    let reasons: [String]
    @State private var rs: [String] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading review feedback…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else { reasonsCard; ctaRow }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.below.ecg").font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                Text("SHIPPER · KYB · ATTENTION NEEDED").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(Brand.warning)
            }
            Text("KYB needs more info").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Resolve the items below, then resubmit. Existing loads stay paused until KYB clears.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reasonsCard: some View {
        LifecycleCard(accentWarning: true) {
            LifecycleSection(label: "WHAT'S MISSING", icon: "exclamationmark.triangle.fill")
            if rs.isEmpty {
                Text("No specific items returned by review. Email support@eusotrip.com.").font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(Array(rs.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Brand.warning).padding(.top, 6)
                        Text(r).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var ctaRow: some View {
        Button { NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "322"]) } label: {
            Text("Update profile").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        if !reasons.isEmpty { rs = reasons; loading = false; return }
        struct Out: Decodable { let reasons: [String] }
        do {
            let r: Out = try await EusoTripAPI.shared.queryNoInput("auth.kybRejectionReasons")
            rs = r.reasons
        } catch {
            // Empty list surfaces the email-support fallback.
            rs = []
        }
        loading = false
    }
}

#Preview("368 · KYB rejected · Night") { KybRejectedScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("368 · KYB rejected · Afternoon") { KybRejectedScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
