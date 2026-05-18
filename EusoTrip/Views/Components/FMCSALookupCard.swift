//
//  FMCSALookupCard.swift
//  EusoTrip — registration-time SAFER autofill.
//
//  iOS parity for the web `FMCSALookup` component
//  (`frontend/client/src/components/registration/FMCSALookup.tsx`).
//
//  Drops into a carrier / broker registration form. Renders a
//  DOT / MC input pair with a "Verify" button that fires
//  `fmcsa.lookupByDOT` or `fmcsa.lookupByMC`, then shows the
//  verified envelope: legal name, fleet size, authority status,
//  hazmat flag, insurance posture, safety rating, plus any
//  warnings or block reasons.
//
//  The host form passes an `onDataLoaded` callback so it can
//  apply each field to its view-model (companyName, dotNumber,
//  mcNumber, address, hazmatAuthorized, etc.).
//

import SwiftUI

public struct FMCSALookupCard: View {
    public enum Mode: String { case dot, mc, both }

    public let mode: Mode
    @Binding public var dotNumber: String
    @Binding public var mcNumber: String
    public let onDataLoaded: (FMCSACarrierLookup) -> Void
    /// Compact rendering for forms that already have their own
    /// section header. Hides the eyebrow + tip card.
    public var compact: Bool = false

    @Environment(\.palette) private var palette

    @State private var phase: Phase = .idle
    @State private var lookup: FMCSACarrierLookup? = nil

    private enum Phase: Equatable {
        case idle, loading, success, error(String), notFound
    }

    public init(
        mode: Mode,
        dotNumber: Binding<String>,
        mcNumber: Binding<String>,
        compact: Bool = false,
        onDataLoaded: @escaping (FMCSACarrierLookup) -> Void
    ) {
        self.mode = mode
        self._dotNumber = dotNumber
        self._mcNumber = mcNumber
        self.compact = compact
        self.onDataLoaded = onDataLoaded
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if !compact { header }
            inputRow
            if case .error(let msg) = phase {
                errorRow(msg)
            }
            if phase == .notFound {
                notFoundRow
            }
            if let l = lookup, phase == .success { resultBlock(l) }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft.opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: — Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("FMCSA SAFER VERIFY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("One number, 30+ fields auto-filled")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("We pull legal name, addresses, fleet size, authority, hazmat, and insurance straight from FMCSA QCMobile.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: — Input row

    @ViewBuilder
    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if mode == .dot || mode == .both {
                VStack(alignment: .leading, spacing: 4) {
                    Text("USDOT").font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                    TextField("1234567", text: $dotNumber)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(palette.borderSoft)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .font(.system(size: 14, design: .monospaced))
                }
            }
            if mode == .mc || mode == .both {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MC #").font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                    TextField("123456", text: $mcNumber)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(palette.borderSoft)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .font(.system(size: 14, design: .monospaced))
                }
            }
            verifyButton
        }
    }

    private var verifyButton: some View {
        Button { Task { await verify() } } label: {
            HStack(spacing: 6) {
                if phase == .loading {
                    ProgressView().scaleEffect(0.55).tint(.white)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .heavy))
                }
                Text(phase == .loading ? "Looking up…" : "Verify")
                    .font(.system(size: 12, weight: .heavy))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(canVerify ? AnyView(LinearGradient.diagonal) : AnyView(Color.gray.opacity(0.4)))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canVerify || phase == .loading)
        .opacity((canVerify && phase != .loading) ? 1.0 : 0.6)
    }

    private var canVerify: Bool {
        let dot = dotNumber.trimmingCharacters(in: .whitespaces)
        let mc = mcNumber.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "MC", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-", with: "")
        switch mode {
        case .dot: return !dot.isEmpty && dot.allSatisfy(\.isNumber)
        case .mc:  return !mc.isEmpty && mc.allSatisfy(\.isNumber)
        case .both: return (!dot.isEmpty && dot.allSatisfy(\.isNumber))
                       || (!mc.isEmpty && mc.allSatisfy(\.isNumber))
        }
    }

    // MARK: — Result block

    private func resultBlock(_ l: FMCSACarrierLookup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow(l)
            if let p = l.companyProfile { profileRow(p) }
            if let a = l.authority { authorityRow(a) }
            if let s = l.safety { safetyRow(s) }
            if let ins = l.insurance { insuranceRow(ins) }
            if let h = l.hazmat, h.authorized {
                Text("⚑ Hazmat authorized")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.4)))
            }
            if let w = l.warnings, !w.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(w, id: \.self) { msg in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Brand.warning)
                            Text(msg).font(EType.caption).foregroundStyle(Brand.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if l.isBlocked == true, let r = l.blockReason {
                Text(r)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.danger.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Brand.danger.opacity(0.5))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.top, 6)
    }

    private func statusRow(_ l: FMCSACarrierLookup) -> some View {
        let blocked = l.isBlocked == true
        return HStack(spacing: 6) {
            Image(systemName: blocked ? "xmark.octagon.fill" : "checkmark.seal.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(blocked ? Brand.danger : Brand.success)
            Text(blocked ? "FMCSA · NOT AUTHORIZED" : "FMCSA · VERIFIED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(blocked ? Brand.danger : Brand.success)
            if l.fromCache == true {
                Text("CACHED")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(palette.bgCardSoft))
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private func profileRow(_ p: FMCSACarrierLookup.CompanyProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(p.legalName)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            if let dba = p.dba, !dba.isEmpty {
                Text("DBA \(dba)").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            let addr = "\(p.physicalAddress.street) · \(p.physicalAddress.city), \(p.physicalAddress.state) \(p.physicalAddress.zip)"
            Text(addr).font(EType.caption).foregroundStyle(palette.textSecondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                pill("\(p.fleetSize)", "PU")
                pill("\(p.driverCount)", "DRIVERS")
            }
        }
    }

    private func authorityRow(_ a: FMCSACarrierLookup.Authority) -> some View {
        HStack(spacing: 6) {
            pill("DOT \(a.dotNumber)", nil)
            pill(a.operatingStatus, nil,
                 color: a.allowedToOperate ? Brand.success : Brand.danger)
            if a.commonAuthority == "Y" { pill("COMMON", nil, color: Brand.info) }
            if a.contractAuthority == "Y" { pill("CONTRACT", nil, color: Brand.info) }
            if a.brokerAuthority == "Y" { pill("BROKER", nil, color: Brand.info) }
            Spacer(minLength: 0)
        }
    }

    private func safetyRow(_ s: FMCSACarrierLookup.Safety) -> some View {
        let color: Color = {
            switch s.rating.uppercased() {
            case "SATISFACTORY": return Brand.success
            case "CONDITIONAL": return Brand.warning
            case "UNSATISFACTORY": return Brand.danger
            default: return palette.textTertiary
            }
        }()
        return HStack(spacing: 6) {
            pill("SAFETY: \(s.rating)", nil, color: color)
            pill("OOS DRV \(formatRate(s.inspections.driver.rate))%", nil,
                 color: s.inspections.driver.rate > 25 ? Brand.warning : palette.textTertiary)
            pill("OOS VEH \(formatRate(s.inspections.vehicle.rate))%", nil,
                 color: s.inspections.vehicle.rate > 25 ? Brand.warning : palette.textTertiary)
            Spacer(minLength: 0)
        }
    }

    private func insuranceRow(_ ins: FMCSACarrierLookup.Insurance) -> some View {
        HStack(spacing: 6) {
            pill(ins.bipdOnFile ? "BIPD ✓" : "BIPD ✗", nil,
                 color: ins.bipdOnFile ? Brand.success : (ins.bipdRequired ? Brand.danger : palette.textTertiary))
            pill(ins.cargoOnFile ? "CARGO ✓" : "CARGO ✗", nil,
                 color: ins.cargoOnFile ? Brand.success : (ins.cargoRequired ? Brand.danger : palette.textTertiary))
            pill(ins.bondOnFile ? "BOND ✓" : "BOND ✗", nil,
                 color: ins.bondOnFile ? Brand.success : (ins.bondRequired ? Brand.danger : palette.textTertiary))
            Spacer(minLength: 0)
        }
    }

    private func pill(_ label: String, _ caption: String?, color: Color? = nil) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
            if let caption {
                Text(caption)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill((color ?? palette.textPrimary).opacity(0.12)))
        .overlay(Capsule().strokeBorder((color ?? palette.textPrimary).opacity(0.3)))
        .foregroundStyle(color ?? palette.textPrimary)
    }

    private func formatRate(_ r: Double) -> String {
        r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r)
    }

    private func errorRow(_ msg: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Brand.warning)
            Text(msg).font(EType.caption).foregroundStyle(Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notFoundRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No SAFER record for that number — you can still enter the rest manually.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: — Behavior

    @MainActor
    private func verify() async {
        let dot = dotNumber.trimmingCharacters(in: .whitespaces)
        let mc = mcNumber.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "MC", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "-", with: "")

        phase = .loading
        do {
            let result: FMCSACarrierLookup
            if mode == .mc || (mode == .both && dot.isEmpty && !mc.isEmpty) {
                result = try await EusoTripAPI.shared.fmcsa.lookupByMC(mc)
            } else {
                result = try await EusoTripAPI.shared.fmcsa.lookupByDOT(dot)
            }

            if result.verified {
                lookup = result
                phase = .success
                onDataLoaded(result)
            } else if result.noApiKey == true {
                phase = .error(result.error ?? "FMCSA API key not configured on server")
            } else if result.error != nil {
                phase = .notFound
            } else {
                phase = .notFound
            }
        } catch {
            phase = .error("Couldn't reach FMCSA. Try again or enter manually.")
        }
    }
}

// MARK: - Previews

private struct _DotMcHost: View {
    @State var dot: String = ""
    @State var mc: String = ""
    var body: some View {
        FMCSALookupCard(
            mode: .both,
            dotNumber: $dot,
            mcNumber: $mc
        ) { _ in }
    }
}

#Preview("FMCSALookupCard · Dark") {
    _DotMcHost()
        .padding(16)
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("FMCSALookupCard · Light") {
    _DotMcHost()
        .padding(16)
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
