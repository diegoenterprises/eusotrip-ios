//
//  418_TenderAcceptCountdown.swift
//  EusoTrip — Shipper · Tender accept countdown (Arc C deepening).
//

import SwiftUI

struct TenderAcceptCountdownScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var deadlineISO: String?
    var body: some View {
        Shell(theme: theme) { TenderCountdownBody(loadId: loadId, deadlineISO: deadlineISO) } nav: { shipperLifecycleNav() }
    }
}

private struct TenderCountdownBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    let deadlineISO: String?
    @State private var now: Date = Date()
    @State private var deadline: Date = Date().addingTimeInterval(15 * 60)
    @State private var processing: String? = nil
    @State private var actionError: String? = nil

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var remainingSeconds: TimeInterval { max(0, deadline.timeIntervalSince(now)) }
    private var fraction: Double {
        let total = max(1, deadline.timeIntervalSince(deadline.addingTimeInterval(-15 * 60)))
        return min(1, max(0, remainingSeconds / total))
    }

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            countdownHero
            ctaRow
            Spacer()
            if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }.padding(.horizontal, 14) }
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 14).padding(.top, 8)
        .onReceive(timer) { _ in now = Date() }
        .onAppear { hydrateDeadline() }
    }

    private var countdownHero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 8).frame(width: 180, height: 180)
                Circle().trim(from: 0, to: fraction).stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 180, height: 180)
                VStack(spacing: 4) {
                    Text(timerLabel).font(.system(size: 32, weight: .heavy)).foregroundStyle(.white).monospacedDigit()
                    Text("TO ACCEPT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                }
            }
            Text("Tender expires soon").font(.system(size: 17, weight: .heavy)).foregroundStyle(.white)
            Text("Accept, counter, or reject before the timer hits zero. After expiry the load re-enters bidding.").font(EType.caption).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.horizontal, 14)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var ctaRow: some View {
        VStack(spacing: 10) {
            Button { Task { await accept() } } label: {
                HStack(spacing: 6) {
                    if processing == "accept" { ProgressView().tint(.white) }
                    Text(processing == "accept" ? "Accepting…" : "Accept tender").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(processing != nil)
            HStack(spacing: 10) {
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "415", "loadId": loadId, "bidId": "tender"])
                } label: {
                    Text("Counter").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(palette.tintNeutral)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "416", "loadId": loadId, "bidId": "tender"])
                } label: {
                    Text("Reject").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Brand.danger)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private var timerLabel: String {
        let m = Int(remainingSeconds) / 60
        let s = Int(remainingSeconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func hydrateDeadline() {
        guard let iso = deadlineISO else { return }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { deadline = d }
    }

    private func accept() async {
        processing = "accept"; actionError = nil
        struct In: Encodable { let loadId: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("shippers.acceptTender", input: In(loadId: loadId))
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "262", "loadId": loadId])
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        processing = nil
    }
}

#Preview("418 · Tender · Night") { TenderAcceptCountdownScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("418 · Tender · Afternoon") { TenderAcceptCountdownScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
