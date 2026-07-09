//
//  ES08_CertReciprocity.swift
//  EusoTrip — Escort · ES-08 Cert Reciprocity (iOS peer of the live web page).
//
//  The escort's certification wallet + 50-state reciprocity clearance map +
//  eligibility checker. Wired to the SAME live procs the web page consumes
//  (fix pack L10-6; spine already on the escort branch):
//    REAL  escorts.getCertificationStatus → cert wallet + summary counts
//    REAL  escorts.getReciprocityMap      → per-state clearance choropleth
//    REAL  escorts.checkStateEligibility  → pick a state → verdict
//    REAL  escorts.uploadCertification    → add a certification
//
//  Clearance legend (held beats blocked): held · reciprocal · needs_cert ·
//  expired · blocked · none.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire contracts (mirror server/routers/escorts.ts ESC-08 spine)

private struct CertSummary: Decodable, Identifiable {
    let id: String
    let certType: String
    let issuingState: String
    let issuingAuthority: String
    let status: String
    let expirationDate: String?
    let heightPoleCertified: Bool
    let hazmatEscortCertified: Bool
    let nightOperationsCertified: Bool
}
private struct CertStatus: Decodable {
    let total: Int
    let active: Int
    let expiringSoon: Int
    let expired: Int
    let statesCleared: [String]
    let reciprocalStatesCleared: [String]
    let certifications: [CertSummary]
}
private struct ReciprocityCell: Decodable, Identifiable {
    let state: String
    let clearance: String
    var id: String { state }
}
private struct EligibilityInput: Encodable { let state: String }
private struct EligibilityResult: Decodable { let eligible: Bool; let reason: String }
private struct UploadInput: Encodable { let state: String; let type: String; let expirationDate: String }
private struct UploadResult: Decodable { let success: Bool; let certId: String }

// MARK: - Screen

struct EscortCertReciprocity: View {
    @Environment(\.palette) private var palette

    @State private var status: CertStatus? = nil
    @State private var map: [ReciprocityCell] = []
    @State private var loading = true
    @State private var checkState = ""
    @State private var checkResult: EligibilityResult? = nil
    @State private var showUpload = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading certifications…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    if let err = errorMessage { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                    summaryStrip
                    eligibilityCard
                    reciprocityCard
                    walletCard
                }
                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { uploadBar }
        .sheet(isPresented: $showUpload) {
            UploadCertSheet(onUpload: { state, type, expiry in
                Task { await upload(state: state, type: type, expiry: expiry) }
            })
            .environment(\.palette, palette)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · CERT RECIPROCITY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Certification wallet").font(.system(size: 24, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            summaryTile("ACTIVE", "\(status?.active ?? 0)", Brand.success)
            summaryTile("EXPIRING", "\(status?.expiringSoon ?? 0)", Brand.warning)
            summaryTile("EXPIRED", "\(status?.expired ?? 0)", Brand.danger)
            summaryTile("CLEARED", "\(status?.statesCleared.count ?? 0)", Brand.blue)
        }
    }

    private func summaryTile(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 20, weight: .heavy).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.system(size: 8.5, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(tint.opacity(0.3)))
    }

    // Eligibility checker: pick a 2-letter state → verdict.
    private var eligibilityCard: some View {
        LifecycleCard {
            sectionEyebrow("ELIGIBILITY CHECK", icon: "magnifyingglass")
            HStack(spacing: 10) {
                TextField("State (e.g. OK)", text: $checkState)
                    .font(EType.body).textInputAutocapitalization(.characters)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .frame(width: 130)
                Button { Task { await checkEligibility() } } label: {
                    Text("Check").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(checkState.count == 2 ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain).disabled(checkState.count != 2)
                Spacer(minLength: 0)
            }
            if let r = checkResult {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: r.eligible ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(r.eligible ? Brand.success : Brand.danger)
                    Text(r.reason).font(EType.caption).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
    }

    // 50-state reciprocity — a compact grid choropleth (held beats blocked).
    private var reciprocityCard: some View {
        LifecycleCard {
            sectionEyebrow("50-STATE RECIPROCITY", icon: "map")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6), spacing: 5) {
                ForEach(map) { cell in
                    Text(cell.state)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(clearanceFg(cell.clearance))
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(clearanceBg(cell.clearance))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .padding(.top, 2)
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendDot("Held", .held)
            legendDot("Recip.", .reciprocal)
            legendDot("Needs", .needsCert)
            legendDot("Blocked", .blocked)
        }
        .padding(.top, 6)
    }

    private func legendDot(_ label: String, _ c: Clearance) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(c.bg).frame(width: 12, height: 12)
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    private var walletCard: some View {
        LifecycleCard {
            sectionEyebrow("CERT WALLET", icon: "wallet.pass")
            if let certs = status?.certifications, !certs.isEmpty {
                VStack(spacing: 8) { ForEach(certs) { certRow($0) } }
            } else {
                Text("No certifications on file. Add one with Upload below.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).padding(.vertical, 4)
            }
        }
    }

    private func certRow(_ c: CertSummary) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                Text(c.issuingState).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.certType).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                HStack(spacing: 5) {
                    if c.heightPoleCertified { tag("HIGH POLE") }
                    if c.hazmatEscortCertified { tag("HAZMAT") }
                    if c.nightOperationsCertified { tag("NIGHT") }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(c.status.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(c.status == "active" ? Brand.success : (c.status == "expired" ? Brand.danger : palette.textTertiary))
                if let exp = c.expirationDate { Text(shortDate(exp)).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary) }
            }
        }
        .padding(.vertical, 2)
    }

    private func tag(_ t: String) -> some View {
        Text(t).font(.system(size: 8, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(palette.bgCardSoft))
    }

    private var uploadBar: some View {
        Button { showUpload = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.doc.fill").font(.system(size: 13, weight: .heavy))
                Text("Upload certification").font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(.white)
            .background(LinearGradient.diagonal).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func sectionEyebrow(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }.padding(.bottom, 2)
    }

    // MARK: Clearance styling

    private enum Clearance {
        case held, reciprocal, needsCert, expired, blocked, none
        init(_ s: String) {
            switch s {
            case "held": self = .held
            case "reciprocal": self = .reciprocal
            case "needs_cert": self = .needsCert
            case "expired": self = .expired
            case "blocked": self = .blocked
            default: self = .none
            }
        }
        var bg: Color {
            switch self {
            case .held: return Brand.success
            case .reciprocal: return Brand.blue
            case .needsCert: return Brand.warning
            case .expired: return Brand.danger.opacity(0.7)
            case .blocked: return Brand.danger
            case .none: return .gray.opacity(0.25)
            }
        }
    }
    private func clearanceBg(_ s: String) -> Color { Clearance(s).bg.opacity(0.22) }
    private func clearanceFg(_ s: String) -> Color {
        let c = Clearance(s); return (c == .none) ? palette.textSecondary : c.bg
    }

    // MARK: Data

    private func load() async {
        loading = true
        defer { loading = false }
        async let st: CertStatus? = try? await EusoTripAPI.shared.query("escorts.getCertificationStatus", input: EmptyInput())
        async let mp: [ReciprocityCell]? = try? await EusoTripAPI.shared.query("escorts.getReciprocityMap", input: EmptyInput())
        status = await st
        map = await mp ?? []
    }

    private func checkEligibility() async {
        guard checkState.count == 2 else { return }
        do {
            checkResult = try await EusoTripAPI.shared.query(
                "escorts.checkStateEligibility", input: EligibilityInput(state: checkState.uppercased()))
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't check eligibility. Try again."
        }
    }

    private func upload(state: String, type: String, expiry: String) async {
        do {
            let _: UploadResult = try await EusoTripAPI.shared.mutation(
                "escorts.uploadCertification", input: UploadInput(state: state, type: type, expirationDate: expiry))
            await load()
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't upload the certification. Try again."
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMM yyyy"
        return out.string(from: d)
    }
}

/// Empty input for the no-arg queries.
private struct EmptyInput: Encodable {}

// MARK: - Upload sheet

private struct UploadCertSheet: View {
    let onUpload: (_ state: String, _ type: String, _ expiry: String) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var state = ""
    @State private var type = "Pilot/Escort"
    @State private var expiry = Date().addingTimeInterval(60 * 60 * 24 * 365)

    private var valid: Bool { state.count == 2 && !type.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Upload certification").font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                labeled("ISSUING STATE") {
                    TextField("e.g. TX", text: $state).textInputAutocapitalization(.characters)
                        .font(EType.body).padding(.horizontal, 10).padding(.vertical, 9)
                        .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                labeled("CERT TYPE") {
                    TextField("e.g. Pilot/Escort", text: $type)
                        .font(EType.body).padding(.horizontal, 10).padding(.vertical, 9)
                        .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                labeled("EXPIRATION") {
                    DatePicker("", selection: $expiry, displayedComponents: .date).labelsHidden()
                }
                Button {
                    let iso = ISO8601DateFormatter().string(from: expiry)
                    onUpload(state.uppercased(), type, iso)
                    dismiss()
                } label: {
                    Text("Upload").font(.system(size: 14, weight: .heavy))
                        .frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(.white)
                        .background(valid ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).disabled(!valid)
            }
            .padding(16)
        }
        .presentationDetents([.medium])
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            content()
        }
    }
}

// MARK: - Registered surface wrapper (id 610)

struct EscortCertReciprocityScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortCertReciprocity()
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home",        systemImage: "house",                  isCurrent: false),
                    NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled", isCurrent: false),
                ],
                trailing: [
                    NavSlot(label: "Corridor", systemImage: "map",    isCurrent: false),
                    NavSlot(label: "Me",       systemImage: "person", isCurrent: true),
                ],
                orbState: .idle
            )
        }
    }
}

#Preview("ES-08 · Cert Reciprocity · Dark") {
    EscortCertReciprocityScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("ES-08 · Cert Reciprocity · Light") {
    EscortCertReciprocityScreen(theme: Theme.light).preferredColorScheme(.light)
}
