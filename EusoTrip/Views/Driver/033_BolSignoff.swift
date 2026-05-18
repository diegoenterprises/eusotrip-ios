//
//  033_BolSignoff.swift
//  EusoTrip — Lifecycle screen 033 · BOL Sign-off (release the rig).
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `033 BOL Sign-off.png`. Final step before rolling — driver reviews
//  the Bill of Lading, Spectra-Match cert line, EusoShield activation
//  chip, certification statement, and signs their name. "Sign and
//  release rig" arms the gate-open and transitions the lifecycle to
//  in-transit.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct BolSignoff: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isSigning: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .afternoon) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Live-load facet helpers (141st firing M3 sweep)
    //
    // Replaces the prior `fallbackXxx` literal block. Every visible
    // string on this BOL screen now flows through a `ctx.facets.*`
    // accessor with a clean neutral fallback when the backend hasn't
    // shipped the column. Regulatory universals (CHEMTREC, 49 CFR
    // 177.823 placard, 49 CFR 172 cert statement) ride on the
    // hazmat-class presence check inside `LiveLoadFacets` itself —
    // they collapse to em-dash automatically when the load is
    // non-hazmat. Driver name is sourced from the live session user.

    /// Current local time HH:mm. Not a fixture — derived from the
    /// device clock at render time.
    private var currentClockHHmm: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    /// "BOL #44912" or em-dash when the load isn't hydrated yet.
    private var bolLoadIdLine: String {
        guard let n = activeLoad?.loadNumber, !n.isEmpty else { return LiveLoadFacets.dash }
        return "BOL #\(n)"
    }

    /// MC/DOT chip — `facets.tankSpec` when shipped, em-dash
    /// otherwise. Visible in the BOL header strip.
    private var tankSpecChip: String { ctx.facets.tankSpec }

    /// Shipper name — backend-gap → em-dash. (Per §16 loads-lifecycle
    /// slice, the shipper envelope isn't joined onto `loads.getById`.)
    private var shipperName: String { LiveLoadFacets.dash }

    /// Shipper address — falls through to `pickupFacility` (live
    /// address line on the load envelope) when shipped, em-dash
    /// otherwise.
    private var shipperAddress: String { ctx.facets.pickupFacility }

    /// Consignee name — backend gap → em-dash.
    private var consigneeName: String { LiveLoadFacets.dash }

    /// Consignee address — falls through to `deliveryFacility`.
    private var consigneeAddress: String { ctx.facets.deliveryFacility }

    /// Commodity descriptor: `commodityWithUN` (live) joined with the
    /// hazard class when present. Em-dash falls through cleanly.
    private var commodityLine: String {
        let parts = [ctx.facets.commodityWithUN, ctx.facets.hazardClass]
            .filter { $0 != LiveLoadFacets.dash }
        return parts.isEmpty ? LiveLoadFacets.dash : parts.joined(separator: " · ")
    }

    /// Sub-line under the commodity row. Carries CHEMTREC (universal
    /// regulatory constant; auto-presents only when hazmat) — joined
    /// segments drop cleanly when the class is empty.
    private var commoditySubLine: String {
        let parts = [ctx.facets.chemtrecLine]
            .filter { $0 != LiveLoadFacets.dash }
        return parts.isEmpty ? LiveLoadFacets.dash : parts.joined(separator: " · ")
    }

    /// 49 CFR 177.823 placard confirmation — auto-presents only when
    /// hazmat. Em-dash for non-hazmat loads.
    private var placardLine: String { ctx.facets.placardConfirmation }

    /// Net gallons display — falls through to `loadedGallons` when
    /// shipped, em-dash otherwise.
    private var netGallonsCell: String { ctx.facets.loadedGallons }

    /// Liquid fill temperature display — `liquidFillTempDisplay`
    /// when shipped, em-dash otherwise.
    private var fillTempCell: String { ctx.facets.liquidFillTempDisplay }

    /// Fill-completed-at HH:mm — `liquidFillCompletedAt` when shipped,
    /// em-dash otherwise.
    private var fillCompletedAtCell: String { ctx.facets.liquidFillCompletedAt }

    /// Spectra-Match cert chip identifier. Em-dash falls through to
    /// the screen's own neutral fallback ("Spectra cert").
    private var spectraCertLabel: String {
        let id = ctx.facets.spectraMatchSampleId
        return id == LiveLoadFacets.dash ? "Spectra cert" : id
    }

    /// Spectra-Match cert sub-line — purity readout joined with the
    /// universal ESANG-AI lineage stamp. Em-dash drops the purity
    /// segment cleanly.
    private var spectraCertSub: String {
        let purity = ctx.facets.spectraMatchPurity
        let lineage = "SIGNED BY ESANG AI LINEAGE"
        return purity == LiveLoadFacets.dash
            ? lineage
            : "\(purity) · \(lineage)"
    }

    /// EusoShield binder line — universal copy describing the
    /// in-transit binder activation behavior. Not per-load data.
    private var binderLine: String {
        "On sign, EusoShield in-transit binder activates · consignee gets ETA"
    }

    /// BOL certification statement — hazmat (49 CFR 172) when the
    /// load carries a hazmat class, generic carrier-certification
    /// otherwise. Both bodies live on `LiveLoadFacets` as
    /// regulatory-constant accessors.
    private var certStatementBody: String {
        let h = ctx.facets.hazmatCertStatement
        return h == LiveLoadFacets.dash ? ctx.facets.generalCertStatement : h
    }

    /// Driver signature display name — sourced from the live session
    /// user (`AuthUser.name`). Em-dash when no user is hydrated
    /// (preview / pre-auth) or when the name field is empty.
    private var driverSignatureName: String {
        let s = (session.user?.name ?? "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? LiveLoadFacets.dash : s
    }

    /// Driver credential line — `driverCredentialLine` when shipped,
    /// em-dash otherwise.
    private var driverCredentialLine: String { ctx.facets.driverCredentialLine }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                bolCard
                certRow
                binderRow
                statementCard
                signatureBlock
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { navBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("STEP 6 / 6")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· SIGN TO RELEASE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("Sign BOL + Spectra cert")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Last step before you roll — review then sign · ~30 sec")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(currentClockHHmm)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var bolCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("Bill of Lading")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(tankSpecChip)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Text(bolLoadIdLine)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)

            HStack(alignment: .top, spacing: Space.s3) {
                partyBlock(label: "SHIPPER", name: shipperName, address: shipperAddress)
                partyBlock(label: "CONSIGNEE", name: consigneeName, address: consigneeAddress)
            }

            Divider().overlay(palette.borderFaint)

            Text(commodityLine)
                .font(EType.body.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(commoditySubLine)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
            if placardLine != LiveLoadFacets.dash {
                Text(placardLine)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Brand.warning.opacity(0.5), lineWidth: 1))
            }

            HStack(spacing: Space.s2) {
                factCell(label: "NET", value: netGallonsCell)
                factCell(label: "TEMP AT FILL", value: fillTempCell)
                factCell(label: "PS", value: fillCompletedAtCell)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func partyBlock(label: String, name: String, address: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(name)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(address)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func factCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var certRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "waveform.path")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text(spectraCertLabel)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text(spectraCertSub)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text("ATTACHED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var binderRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.success)
            Text(binderLine)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text("ACTIVATE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().stroke(Brand.warning.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var statementCard: some View {
        Text(certStatementBody)
            .font(EType.body)
            .foregroundStyle(palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var signatureBlock: some View {
        VStack(alignment: .center, spacing: Space.s2) {
            Text(driverSignatureName)
                .font(.custom("SnellRoundhand", size: 34))
                .foregroundStyle(LinearGradient.diagonal)
            Divider().overlay(palette.borderSoft).padding(.horizontal, Space.s3)
            VStack(spacing: 2) {
                Text(driverSignatureName)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(driverCredentialLine)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Text("STORED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { navBack?() } label: {
                Text("Reject")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            CTAButton(
                title: "Sign and release rig",
                action: { Task { await signAndRelease() } },
                isLoading: isSigning
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func signAndRelease() async {
        isSigning = true
        defer { isSigning = false }
        let keys = ["departing", "in_transit", "loaded", "rolling"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

struct BolSignoffScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            BolSignoff(register: .afternoon)
        } nav: {
            BottomNav(leading: driverNavLeading_033(),
                      trailing: driverNavTrailing_033(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_033() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_033() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("033 · BOL Sign-off · Dark") {
    BolSignoffScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("033 · BOL Sign-off · Light") {
    BolSignoffScreen(theme: Theme.light).preferredColorScheme(.light)
}
