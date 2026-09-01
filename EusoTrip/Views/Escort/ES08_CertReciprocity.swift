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
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire contracts (mirror server/routers/escorts.ts ESC-08 spine)

private struct CertSummary: Decodable, Identifiable {
    let id: String
    let certificationId: String
    let certType: String
    let certNumber: String?
    let issuingState: String
    let issuingAuthority: String?
    let status: String
    let displayStatus: String
    let issueDate: String?
    let expirationDate: String?
    let verificationStatus: String?
    let verificationMethod: String?
    let verificationSourceReference: String?
    let verificationSourceObservedAt: String?
    let heightPoleCertified: Bool
    let hazmatEscortCertified: Bool
    let nightOperationsCertified: Bool
    let documentUrl: String?
    let notes: String?
}
private struct CertStatus: Decodable {
    let total: Int
    let active: Int
    let valid: Int
    let expiringSoon: Int
    let expired: Int
    let pending: Int
    let suspended: Int
    let revoked: Int
    let unverified: Int
    let statesCleared: [String]
    let reciprocalStatesCleared: [String]
    let states: [CertStateRow]
    let certifications: [CertSummary]
    let tracking: EscortCertificationTracking
}
private struct CertStateRow: Decodable {
    let code: String
    let name: String
    let status: String
    let expirationDate: String?
}
private struct ReciprocityCell: Decodable, Identifiable {
    let state: String
    let clearance: String
    var id: String { state }
}
private struct EligibilityInput: Encodable { let state: String }
private struct EligibilityResult: Decodable { let eligible: Bool; let reason: String }

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
                    // Section order mirrors the ES-08 SVG twins: map → summary → wallet → gate.
                    reciprocityCard
                    summaryStrip
                    walletCard
                    eligibilityCard
                }
                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { uploadBar }
        .sheet(isPresented: $showUpload) {
            EscortAddCertificationSheet { submission in
                await upload(submission)
            }
            .environment(\.palette, palette)
        }
        .eusoRefreshTask { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · CERT RECIPROCITY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Cert Reciprocity").font(.system(size: 24, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            summaryTile("ACTIVE", "\(status?.active ?? 0)", Brand.success)
            summaryTile("EXPIRING", "\(status?.expiringSoon ?? 0)", Brand.warning)
            summaryTile("EXPIRED", "\(status?.expired ?? 0)", Brand.danger)
            // Cleared = held + reciprocal (matches the twins' "13 states" figure).
            summaryTile("CLEARED", "\((status?.statesCleared.count ?? 0) + (status?.reciprocalStatesCleared.count ?? 0))", Brand.blue)
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
        HStack(spacing: 8) {
            legendDot("Held", .held)
            legendDot("Recip.", .reciprocal)
            legendDot("Expired", .expired)
            legendDot("Blocked", .blocked)
            legendDot("Needs", .needsCert)
            legendDot("No req", Clearance.none)
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
                if let authority = c.issuingAuthority {
                    Text(authority).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                HStack(spacing: 5) {
                    if c.heightPoleCertified { tag("HIGH POLE") }
                    if c.hazmatEscortCertified { tag("HAZMAT") }
                    if c.nightOperationsCertified { tag("NIGHT") }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(c.displayStatus.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(c.displayStatus == "valid" ? Brand.success : (c.displayStatus == "expired" ? Brand.danger : Brand.warning))
                if c.verificationStatus != "verified" {
                    Text("UNVERIFIED").font(EType.mono(.micro)).foregroundStyle(Brand.warning)
                }
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
            // Hues mirror the ES-08 SVG twins: held = brand blue, reciprocal = escort purple.
            case .held: return Brand.blue
            case .reciprocal: return Brand.escort
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
        errorMessage = nil
        do {
            async let statusRequest: CertStatus = EusoTripAPI.shared.query(
                "escorts.getCertificationStatus", input: EmptyInput())
            async let mapRequest: [ReciprocityCell] = EusoTripAPI.shared.query(
                "escorts.getReciprocityMap", input: EmptyInput())
            let (freshStatus, freshMap) = try await (statusRequest, mapRequest)
            status = freshStatus
            map = freshMap
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription
                ?? "Certification records are unavailable. Pull to retry."
        }
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

    private func upload(_ submission: EscortCertificationSubmissionInput) async -> Bool {
        do {
            let receipt: EscortCertificationSubmissionResult = try await EusoTripAPI.shared.mutation(
                "escorts.uploadCertification", input: submission)
            guard receipt.success,
                  receipt.status == "pending",
                  receipt.verificationStatus == "unverified",
                  receipt.requiresVerification,
                  receipt.evidenceAttached else {
                errorMessage = "Certification evidence wasn't submitted. Review the file and certification details, then try again."
                return false
            }
            await load()
            return true
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't upload the certification. Try again."
            return false
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

// MARK: - Registered surface wrapper (id 610)

struct EscortCertReciprocityScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortCertReciprocity()
        } nav: {
            // Escort role enum TRIP·COMMS·PERMIT·ME — mirrors ES-01/ES-02 (ESC-07 axis-I precedent).
            BottomNav(
                leading: EscortNavRoute.leading(current: .me),
                trailing: EscortNavRoute.trailing(current: .me),
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
