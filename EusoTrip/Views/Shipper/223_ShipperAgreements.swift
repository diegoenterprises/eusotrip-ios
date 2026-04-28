//
//  223_ShipperAgreements.swift
//  EusoTrip 2027 UI — brick 223 (shipper · agreements)
//
//  Agreements list + detail + Gradient-Ink sign flow. Mirrors the
//  shipper-relevant slice of the web `/agreements` list and the
//  inline `Sign` modal from `ShipperAgreementWizard.tsx`.
//
//  The web wizard (mode → parties → financial → lanes → review →
//  sign → complete) is multi-form-heavy; this brick surfaces the
//  high-frequency RUN-state actions an iOS shipper actually does
//  in the field — read existing agreements + sign one when prompted.
//  Wizard CREATION is deferred to web via the
//  `MeAction.fire("shipper.agreement.create")` CTA.
//
//  Wires:
//    • `agreements.list` — `ShipperAgreementsAPI.list()`.
//    • `agreements.sign` — `ShipperAgreementsAPI.sign(...)`.
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperAgreementsStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded([ShipperAgreementsAPI.Agreement])
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var statusFilter: String? = nil
    @Published var lastSigned: String? = nil
    @Published var lastError: String? = nil

    static let statusFilters: [(String?, String)] = [
        (nil, "All"),
        ("draft", "Draft"),
        ("pending_signature", "To sign"),
        ("active", "Active"),
        ("expired", "Expired"),
    ]

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let r = try await api.shipperAgreements.list(limit: 100, offset: 0)
            var rows = r.agreements ?? []
            if let f = statusFilter {
                rows = rows.filter { ($0.status ?? "").lowercased() == f }
            }
            phase = .loaded(rows)
        } catch {
            phase = .error("Couldn't load agreements.")
        }
    }

    func sign(_ row: ShipperAgreementsAPI.Agreement, signerName: String, signerTitle: String) async {
        let payload = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        do {
            let ack = try await api.shipperAgreements.sign(
                agreementId: row.id,
                signatureData: payload,
                signatureRole: "SHIPPER",
                signerName: signerName.isEmpty ? nil : signerName,
                signerTitle: signerTitle.isEmpty ? nil : signerTitle
            )
            lastSigned = row.agreementNumber ?? "#\(row.id)"
            lastError = nil
            if ack.fullyExecuted == true {
                lastSigned = (lastSigned ?? "Agreement") + " · ACTIVATED"
            }
            await load()
        } catch {
            lastError = "Couldn't sign agreement."
        }
    }
}

// MARK: - Brick

struct ShipperAgreements: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperAgreementsStore()
    @State private var detail: ShipperAgreementsAPI.Agreement? = nil
    @State private var showSignedToast: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                statsHero
                filterRow
                listSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.load() }
        .onChange(of: store.statusFilter) { _, _ in Task { await store.load() } }
        .onChange(of: store.lastSigned ?? "") { _, v in if !v.isEmpty { showSignedToast = true } }
        .sheet(item: $detail) { ShipperAgreementDetailSheet(row: $0).environmentObject(store) }
        .alert("Signed", isPresented: $showSignedToast, actions: {
            Button("OK") { store.lastSigned = nil }
        }, message: {
            if let s = store.lastSigned { Text(s) }
        })
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text.fill").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · AGREEMENTS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Contracts").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("Active rate sheets · pending signatures · Gradient-Ink audit trail.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                MeAction.fire("shipper.agreement.create", userInfo: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 11, weight: .heavy))
                    Text("New").font(.system(size: 11, weight: .heavy))
                }.foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }.padding(.top, 4)
    }

    private var statsHero: some View {
        let rows: [ShipperAgreementsAPI.Agreement] = {
            if case .loaded(let r) = store.phase { return r } else { return [] }
        }()
        let active = rows.filter { ($0.status ?? "").lowercased() == "active" }.count
        let pending = rows.filter { ($0.status ?? "").lowercased() == "pending_signature" }.count
        let expired = rows.filter { ($0.status ?? "").lowercased() == "expired" }.count
        return HStack(spacing: Space.s2) {
            statTile(label: "ACTIVE", value: "\(active)", color: Brand.success)
            statTile(label: "PENDING", value: "\(pending)", color: Brand.warning)
            statTile(label: "EXPIRED", value: "\(expired)", color: Brand.danger)
        }
    }

    private func statTile(label: String, value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient.diagonal))
                .monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ShipperAgreementsStore.statusFilters, id: \.1) { item in
                    chip(label: item.1, active: store.statusFilter == item.0) {
                        store.statusFilter = item.0
                    }
                }
            }
        }
    }

    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, Space.s3).padding(.vertical, 7)
                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                .background(Capsule().fill(active ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)) : AnyShapeStyle(palette.bgCard)))
                .overlay(Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var listSection: some View {
        switch store.phase {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Loading agreements…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded(let rows):
            if rows.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        Button { detail = row } label: { agreementRow(row) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func agreementRow(_ a: ShipperAgreementsAPI.Agreement) -> some View {
        let style = AgreementStatusStyle.from(a.status)
        return HStack(alignment: .top, spacing: 10) {
            statusDot(color: style.color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(a.agreementNumber ?? "#\(a.id)").font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary).lineLimit(1)
                    statusPill(style.label, color: style.color)
                }
                if let t = a.agreementType {
                    Text(t.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let r = a.baseRate, !r.isEmpty {
                        Label("$\(r)", systemImage: "dollarsign.circle.fill")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    }
                    if let d = a.effectiveDate { dateChip("Effective", d) }
                    if let d = a.expirationDate { dateChip("Expires", d) }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func statusDot(color: Color) -> some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(color.opacity(0.4), lineWidth: 2).scaleEffect(1.6))
            .padding(.top, 6)
    }

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private func dateChip(_ k: String, _ d: String) -> some View {
        let display = String(d.prefix(10))
        return HStack(spacing: 3) {
            Text(k.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(display).font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Capsule().fill(palette.bgCardSoft))
        .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No agreements yet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Send a counter-party an agreement from the web wizard. It'll appear here for sign-off.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4).frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - status style

private struct AgreementStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String?) -> AgreementStatusStyle {
        switch (raw ?? "").lowercased() {
        case "active":             return .init(label: "Active",   color: Brand.success)
        case "pending_signature":  return .init(label: "To sign",  color: Brand.warning)
        case "draft":              return .init(label: "Draft",    color: Brand.info)
        case "negotiating":        return .init(label: "Negotiating", color: Brand.info)
        case "expired":            return .init(label: "Expired",  color: Brand.danger)
        case "terminated":         return .init(label: "Terminated", color: Brand.danger)
        default:                   return .init(label: (raw ?? "Unknown").capitalized, color: .gray)
        }
    }
}

// MARK: - Detail sheet

struct ShipperAgreementDetailSheet: View {
    let row: ShipperAgreementsAPI.Agreement
    @EnvironmentObject private var store: ShipperAgreementsStore
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var signerName: String = ""
    @State private var signerTitle: String = ""
    @State private var signing: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                hero
                fields
                if (row.status ?? "").lowercased() == "pending_signature" {
                    signCard
                }
                viewOnWeb
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
    }

    private var hero: some View {
        let style = AgreementStatusStyle.from(row.status)
        return VStack(alignment: .leading, spacing: 6) {
            Text("AGREEMENT").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text(row.agreementNumber ?? "#\(row.id)")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(palette.textPrimary)
            HStack(spacing: 6) {
                Text(style.label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(style.color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(style.color.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(style.color.opacity(0.5)))
                if let t = row.agreementType {
                    Text(t.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = row.baseRate { kv("Base rate", "$\(r)") }
            if let d = row.effectiveDate { kv("Effective", String(d.prefix(10))) }
            if let d = row.expirationDate { kv("Expires", String(d.prefix(10))) }
            if let a = row.partyAUserId { kv("Party A user #", "\(a)") }
            if let b = row.partyBUserId { kv("Party B user #", "\(b)") }
            if let c = row.createdAt { kv("Created", String(c.prefix(10))) }
            if let n = row.notes { kv("Notes", n) }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary).frame(width: 110, alignment: .leading)
            Text(v).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var signCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("GRADIENT INK · SIGN").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            Text("Tapping sign appends a SHA-256 audit row tied to your account, IP, and timestamp. Both parties must sign to activate.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("FULL NAME").font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
                TextField("e.g. Diego Usoro", text: $signerName)
                    .textFieldStyle(.plain).padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("TITLE").font(.system(size: 8, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
                TextField("e.g. Founder & CEO", text: $signerTitle)
                    .textFieldStyle(.plain).padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            Button {
                signing = true
                Task {
                    await store.sign(row, signerName: signerName, signerTitle: signerTitle)
                    signing = false
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if signing {
                        ProgressView().scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: "signature").font(.system(size: 13, weight: .heavy))
                    }
                    Text(signing ? "Signing…" : "Sign agreement")
                        .font(.system(size: 14, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(signing || signerName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var viewOnWeb: some View {
        Button {
            MeAction.fire("shipper.agreement.openOnWeb", userInfo: ["agreementId": row.id])
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 12, weight: .heavy))
                Text("Open full contract on web").font(.system(size: 12, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .foregroundStyle(palette.textPrimary).background(palette.bgCard)
            .overlay(Capsule().strokeBorder(palette.borderFaint))
            .clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Agreements · Dark") {
    ShipperAgreements().preferredColorScheme(.dark)
}

#Preview("Agreements · Light") {
    ShipperAgreements().preferredColorScheme(.light)
}
