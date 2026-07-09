//
//  699_RailBadOrderMonitor.swift
//  EusoTrip — Rail Engineer · Bad-Order Mechanical Defect Handoff.
//
//  The single-car defect dossier + handoff: enter a railcar, see its open
//  mechanical defect (from the latest failing inspection), the condemnable basis,
//  the AAR Interchange Rule 95 billing-responsibility verdict, and hand it off to
//  a certified RIP shop — or reinstate it after a single-car air-brake test pass.
//
//  Live wiring: railMechanical.getBadOrder (dossier), handoffBadOrder /
//  reinstateCar (irreversible, confirm-gated). Honest: no failing inspection →
//  "no open defect", never a fabricated bad-order.
//

import SwiftUI

struct RailBadOrderMonitorScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailBadOrderMonitorBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodable model (matches railMechanical.getBadOrder)

private struct BOCarSpec699: Decodable {
    let carType: String?
    let owner: String?
    let lessee: String?
    let aarClass: String?
    let dotSpec: String?
    let status: String?
}

private struct BODefect699: Decodable {
    let inspectionRef: String?
    let code: String?
    let headline: String?
    let severity: String?
    let foundAt: String?
    let notes: String?
}

private struct BORule95_699: Decodable {
    let responsibility: String
    let basis: String
}

private struct BOHandoff699: Decodable {
    let id: String
    let shopId: String?
    let ripTrack: String?
    let status: String
    let responsibility: String
    let backInServiceEta: String?
    let handedOffAt: String?
}

private struct BadOrder699: Decodable {
    let railcarNumber: String
    let carKnown: Bool
    let carSpec: BOCarSpec699?
    let verdict: String?     // "bad_order" | nil
    let asOf: String?
    let defect: BODefect699?
    let responsibility: BORule95_699?
    let existingHandoff: BOHandoff699?
}

// MARK: - Body

private struct RailBadOrderMonitorBody: View {
    @Environment(\.palette) private var palette
    @State private var railcar = ""
    @State private var dossier: BadOrder699? = nil
    @State private var loading = false
    @State private var loadError: String? = nil

    // Handoff / reinstate
    @State private var showHandoff = false
    @State private var shopId = ""
    @State private var ripTrack = ""
    @State private var showReinstate = false
    @State private var testId = ""
    @State private var submitting = false
    @State private var toast: String? = nil

    private func respColor(_ r: String?) -> Color {
        switch r {
        case "car_owner":     return Brand.info
        case "handling_line": return Brand.warning
        case "shared":        return Brand.warning
        default:               return palette.textTertiary   // undetermined
        }
    }
    private func respLabel(_ r: String?) -> String {
        switch r {
        case "car_owner":     return "CAR OWNER"
        case "handling_line": return "HANDLING LINE"
        case "shared":        return "SHARED"
        default:               return "UNDETERMINED"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                searchBar
                if loading {
                    LifecycleCard { Text("Pulling defect dossier…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let d = dossier {
                    verdictHero(d)
                    if let spec = d.carSpec { carSpecCard(spec) }
                    if let defect = d.defect { defectCard(defect, d) }
                    if let rule = d.responsibility { rule95Card(rule) }
                    repairRoutingCard(d)
                } else {
                    LifecycleCard { Text("Enter a railcar number to pull its bad-order dossier.").font(EType.caption).foregroundStyle(palette.textSecondary) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showHandoff) { handoffSheet }
        .sheet(isPresented: $showReinstate) { reinstateSheet }
    }

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · BAD-ORDER HANDOFF").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }
    private var headline: some View {
        Text("Bad-order handoff")
            .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
            .foregroundStyle(palette.textPrimary)
    }

    private var searchBar: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "number").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textTertiary)
            TextField("Railcar number", text: $railcar)
                .font(.system(size: 15, weight: .bold)).monospaced()
                .autocorrectionDisabled().textInputAutocapitalization(.characters)
                .foregroundStyle(palette.textPrimary)
                .onSubmit { Task { await load() } }
            Button { Task { await load() } } label: {
                Text("Pull").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(railcar.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func verdictHero(_ d: BadOrder699) -> some View {
        let bad = d.verdict == "bad_order"
        let color = bad ? Brand.danger : Brand.success
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(color.opacity(0.14)).frame(width: 52, height: 52)
                Image(systemName: bad ? "exclamationmark.octagon.fill" : "checkmark.seal.fill")
                    .font(.system(size: 24, weight: .heavy)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(d.railcarNumber).font(.system(size: 16, weight: .heavy)).monospaced().foregroundStyle(palette.textPrimary)
                Text(bad ? (d.defect?.headline ?? "Bad order") : "No open defect on file")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(color).lineLimit(2)
                if let code = d.defect?.code, bad {
                    Text("AAR defect \(code)").font(EType.caption).foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(color.opacity(0.4), lineWidth: 1.5))
    }

    private func carSpecCard(_ s: BOCarSpec699) -> some View {
        infoCard("EQUIPMENT", pairs: [
            ("Type", s.carType ?? "—"),
            ("Owner", s.owner ?? "—"),
            ("AAR class", s.aarClass ?? "—"),
            ("DOT spec", s.dotSpec ?? "—"),
            ("Status", (s.status ?? "—").replacingOccurrences(of: "_", with: " ")),
        ])
    }

    private func defectCard(_ defect: BODefect699, _ d: BadOrder699) -> some View {
        infoCard("DEFECT DOSSIER · 49 CFR 215", pairs: [
            ("Code", defect.code ?? "—"),
            ("Severity", defect.severity ?? "—"),
            ("Inspection", defect.inspectionRef ?? "—"),
            ("Found at", shortDate(defect.foundAt)),
        ], footnote: defect.notes)
    }

    private func rule95Card(_ rule: BORule95_699) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AAR INTERCHANGE RULE 95").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack {
                Text(respLabel(rule.responsibility))
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(respColor(rule.responsibility))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(respColor(rule.responsibility).opacity(0.14)))
                Spacer()
            }
            Text(rule.basis).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func repairRoutingCard(_ d: BadOrder699) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("REPAIR ROUTING").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if let h = d.existingHandoff {
                infoCard("HANDED OFF · \(h.status.replacingOccurrences(of: "_", with: " ").uppercased())", pairs: [
                    ("Shop", h.shopId ?? "—"),
                    ("RIP track", h.ripTrack ?? "—"),
                    ("Back in service", shortDate(h.backInServiceEta)),
                    ("Handed off", shortDate(h.handedOffAt)),
                ])
                CTAButton(title: "Reinstate car (single-car test)", action: { showReinstate = true }, leadingIcon: "arrow.uturn.up")
            } else if d.verdict == "bad_order" {
                CTAButton(title: "Hand off to RIP shop", action: { showHandoff = true }, leadingIcon: "arrow.right.circle")
            } else {
                Text("Car is in service — no handoff needed.").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func infoCard(_ title: String, pairs: [(String, String)], footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, kv in
                HStack {
                    Text(kv.0).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(kv.1).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                }
            }
            if let fn = footnote, !fn.isEmpty {
                Text(fn).font(EType.caption).foregroundStyle(palette.textTertiary).padding(.top, 2)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Sheets

    private var handoffSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Hand off \(dossier?.railcarNumber ?? "car")")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3).foregroundStyle(palette.textPrimary)
            Text("Irreversible — pulls the car from service to a certified repair shop.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            sheetField("RIP shop id", text: $shopId)
            sheetField("RIP track", text: $ripTrack)
            submitButton("Confirm handoff", enabled: !shopId.trimmingCharacters(in: .whitespaces).isEmpty) {
                await submitHandoff()
            }
            Spacer()
        }
        .padding(20).background(palette.bgSheet.ignoresSafeArea()).presentationDetents([.medium])
    }

    private var reinstateSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Reinstate \(dossier?.railcarNumber ?? "car")")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3).foregroundStyle(palette.textPrimary)
            Text("Irreversible — requires the single-car air-brake test pass reference (49 CFR 232 / AAR S-486).")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            sheetField("Single-car test id", text: $testId)
            submitButton("Confirm reinstatement", enabled: !testId.trimmingCharacters(in: .whitespaces).isEmpty) {
                await submitReinstate()
            }
            Spacer()
        }
        .padding(20).background(palette.bgSheet.ignoresSafeArea()).presentationDetents([.medium])
    }

    private func sheetField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 15, weight: .bold)).monospaced()
            .autocorrectionDisabled().textInputAutocapitalization(.characters)
            .foregroundStyle(palette.textPrimary)
            .padding(Space.s3).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func submitButton(_ title: String, enabled: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack { Spacer()
                if submitting { ProgressView().tint(.white) }
                else { Text(title).font(.system(size: 15, weight: .heavy)).foregroundStyle(.white) }
                Spacer() }
            .padding(.vertical, 14).background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(submitting || !enabled)
    }

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success)).padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func shortDate(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"; return f.string(from: d)
    }

    // MARK: Data

    private func load() async {
        let num = railcar.trimmingCharacters(in: .whitespaces)
        guard !num.isEmpty else { return }
        loading = true; loadError = nil
        struct Input: Encodable { let railcarNumber: String }
        do {
            self.dossier = try await EusoTripAPI.shared.query("railMechanical.getBadOrder", input: Input(railcarNumber: num))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func submitHandoff() async {
        guard let d = dossier else { return }
        struct Input: Encodable { let confirm: Bool; let railcarNumber: String; let defectCode: String; let shopId: String; let ripTrack: String? }
        struct Result: Decodable { let success: Bool? }
        submitting = true
        do {
            let _: Result = try await EusoTripAPI.shared.mutation("railMechanical.handoffBadOrder",
                input: Input(confirm: true, railcarNumber: d.railcarNumber, defectCode: d.defect?.code ?? "UNKNOWN", shopId: shopId, ripTrack: ripTrack.isEmpty ? nil : ripTrack))
            showHandoff = false; shopId = ""; ripTrack = ""
            await finishAction("Handed off \(d.railcarNumber)")
        } catch { await failAction(error) }
        submitting = false
    }

    private func submitReinstate() async {
        guard let d = dossier else { return }
        struct Input: Encodable { let confirm: Bool; let railcarNumber: String; let singleCarTestId: String }
        struct Result: Decodable { let success: Bool? }
        submitting = true
        do {
            let _: Result = try await EusoTripAPI.shared.mutation("railMechanical.reinstateCar",
                input: Input(confirm: true, railcarNumber: d.railcarNumber, singleCarTestId: testId))
            showReinstate = false; testId = ""
            await finishAction("Reinstated \(d.railcarNumber)")
        } catch { await failAction(error) }
        submitting = false
    }

    private func finishAction(_ msg: String) async {
        withAnimation(.easeOut(duration: 0.18)) { toast = msg }
        await load()
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        withAnimation(.easeOut(duration: 0.18)) { toast = nil }
    }
    private func failAction(_ error: Error) async {
        withAnimation(.easeOut(duration: 0.18)) { toast = (error as? EusoTripAPIError)?.errorDescription ?? "Action failed" }
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        withAnimation(.easeOut(duration: 0.18)) { toast = nil }
    }
}

#Preview("699 · Rail Bad-Order · Night") { RailBadOrderMonitorScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("699 · Rail Bad-Order · Light") { RailBadOrderMonitorScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
