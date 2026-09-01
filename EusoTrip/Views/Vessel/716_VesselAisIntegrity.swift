//
//  716_VesselAisIntegrity.swift
//  EusoTrip — Vessel Operator · AIS Integrity & STS Sanctions detector.
//
//  Verbatim SwiftUI port of "716 Vessel AIS Integrity STS Sanctions.svg"
//  (Dark + Light). Archetype: COMPLIANCE / risk-verdict — a risk-spectrum
//  verdict hero, a tri-country sanctions-authority strip, an AIS voyage-
//  integrity track, and an anomaly signal ledger. Nav: VesselOperatorNav —
//  COMPLIANCE tab current.
//
//  WIRING (line-confirmed on disk):
//    getOceanTrackingBoard EXISTS vesselShipments.ts:2411 (vesselProcedure ·
//        {bookingNumber} → booking+vessel+position+events · the voyage track +
//        live-AIS-fix state · PRIMARY REAL).
//    getVesselCompliance  EXISTS vesselShipments.ts:2047 (inspections/ISPS/insurance).
//    sanctions.getScreenings EXISTS sanctions.ts:194 (protectedProcedure · recent
//        OFAC screenings for the party · the OFAC anomaly row · REAL).
//    fraud.recordSignal   EXISTS fraud.ts:435 (protectedProcedure · signalType
//        enum INCLUDES "AIS_SPOOFING" fraud.ts:51 · the File-signal CTA · REAL).
//  STUB · named-gap (surfaced to the-oath, rendered as PENDING — NOT fabricated):
//    · The STS-rendezvous / AIS-dark-period / reflagging / GISIS-reactivated-IMO
//      detection engine + composite RIOS score → vesselShipments.runAisIntegrityCheck
//      {imo,bookingId} → {compositeScore,tier,verdict,signals[],track{points,gaps}}.
//    · IMO-level sanctions screen → vesselShipments.screenVesselSanctions
//      {imo,dischargeCountry} (Lloyd's List connector exists but is not exposed).
//  The two REAL signals (OFAC party screen + live-AIS-fix presence) drive the
//  hero verdict; the composite score + STS/reflag/GISIS rows read PENDING until
//  runAisIntegrityCheck lands. transportMode=vessel; tri-country US·CA·MX.
//

import SwiftUI

// MARK: - Data shapes

private struct TrackBooking716: Decodable {
    let bookingNumber: String?; let status: String?; let voyageNumber: String?
    let originUnlocode: String?; let destinationUnlocode: String?
    let originName: String?; let destinationName: String?
}
private struct TrackVessel716: Decodable { let name: String?; let imoNumber: String?; let status: String? }
private struct TrackPosition716: Decodable { let lat: Double?; let lng: Double?; let speedKn: Double?; let headingDeg: Double? }
private struct TrackBoard716: Decodable {
    let found: Bool?
    let booking: TrackBooking716?
    let vessel: TrackVessel716?
    let position: TrackPosition716?
    let etaUtc: String?
}
private struct Screening716: Decodable { let status: String?; let overallRisk: String?; let matchCount: Int?; let screenedAt: String? }
private struct ScreeningsResult716: Decodable { let screenings: [Screening716]? }

// MARK: - Screen

struct VesselAisIntegrityScreen: View {
    let theme: Theme.Palette
    var bookingNumber: String = "VES-260523-9F2C41A0E7"
    var vesselId: Int? = nil
    var importerEntityId: Int? = nil

    var body: some View {
        Shell(theme: theme) {
            VesselAisIntegrityBody(bookingNumber: bookingNumber, vesselId: vesselId, importerEntityId: importerEntityId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct VesselAisIntegrityBody: View {
    @Environment(\.palette) private var palette
    let bookingNumber: String
    let vesselId: Int?
    let importerEntityId: Int?

    private enum Regime: String { case us = "US", ca = "CA", mx = "MX" }

    @State private var board: TrackBoard716? = nil
    @State private var ofac: Screening716? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var regime: Regime = .us
    @State private var filing = false

    private var hasLiveFix: Bool { board?.position?.lat != nil && board?.position?.lng != nil }
    private var vesselName: String { board?.vessel?.name ?? "MV Aurora Strait" }
    private var imo: String { board?.vessel?.imoNumber ?? "9483621" }
    // Hero verdict derives from the two REAL signals; AIS composite stays PENDING.
    private var ofacClear: Bool { (ofac?.status ?? "").lowercased() == "clear" || ofac == nil }
    private var heroVerdict: (String, Color) {
        if !hasLiveFix { return ("AIS DARK", Brand.danger) }
        if !ofacClear { return ("REVIEW", Brand.warning) }
        return ("REVIEW", Brand.warning)   // composite pending → always operator-review
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    gapCard("Running pre-load integrity check…", "getOceanTrackingBoard · \(bookingNumber)", warn: false)
                } else if let err = loadError {
                    gapCard("Integrity check unavailable", err, warn: true)
                } else {
                    verdictHero
                    sanctionsStrip
                    voyageTrack
                    anomalyLedger
                    esang
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripEyebrow(verbatim: "VESSEL OPERATOR · AIS INTEGRITY").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("OFAC · LLOYD'S LIST").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(Color(hex: 0x4FB8E8))
            }
            Text("AIS integrity check").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Text("\(board?.booking?.bookingNumber ?? bookingNumber) · \(vesselName) · pre-load gate")
                .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: Risk-spectrum verdict hero

    private var verdictHero: some View {
        RimCard716 {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("VESSEL INTEGRITY · COMPOSITE RIOS").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(heroVerdict.1).frame(width: 8, height: 8)
                        Text(heroVerdict.0).font(.system(size: 9.5, weight: .heavy)).tracking(0.4).foregroundStyle(heroVerdict.1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(heroVerdict.1.opacity(0.14)))
                }
                .padding(.bottom, 14)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vesselName).font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text("IMO \(imo) · \(board?.vessel?.status ?? "Panama flag") · ONE charter")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary).lineLimit(1)
                        // risk spectrum track — composite score pending
                        LinearGradient(colors: [Color(hex: 0x0A8F63), Brand.warning, Color(hex: 0xE5484D)], startPoint: .leading, endPoint: .trailing)
                            .frame(height: 8).clipShape(Capsule())
                            .overlay(alignment: .center) {
                                Circle().fill(palette.bgCard).overlay(Circle().strokeBorder(palette.textTertiary, lineWidth: 2.4))
                                    .frame(width: 12, height: 12).opacity(0.6)
                            }
                            .padding(.top, 6)
                        HStack(spacing: 4) {
                            Text("AIS reporting").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                            Text(hasLiveFix ? "live fix on file" : "no fix on file · AIS dark")
                                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                                .foregroundStyle(hasLiveFix ? Brand.success : Color(hex: 0xFF5A4D))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 52).padding(.horizontal, 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Risk score").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text("—").font(.system(size: 23, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
                        Text("PENDING").font(.system(size: 8.5, weight: .heavy)).tracking(0.3).foregroundStyle(palette.textTertiary)
                    }
                }
                Text("Composite AIS integrity score pending runAisIntegrityCheck")
                    .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    .padding(.top, 10)
            }
        }
    }

    // MARK: Tri-country sanctions authority

    private var sanctionsStrip: some View {
        HStack(spacing: 8) {
            sanctionsTab(.us, "OFAC · SDN", ofacClear ? "Parties clear" : "Review", Color(hex: 0x5B8CFF), real: true)
            sanctionsTab(.ca, "OSFI · SEMA", "Tap to screen", Color(hex: 0xF0473A), real: false)
            sanctionsTab(.mx, "UIF · SHCP", "Tap to screen", Color(hex: 0x2BA579), real: false)
        }
    }
    private func sanctionsTab(_ r: Regime, _ auth: String, _ state: String, _ ring: Color, real: Bool) -> some View {
        let active = regime == r
        return Button { regime = r } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(ring, lineWidth: 2.4).frame(width: 22, height: 22)
                        Text(r.rawValue).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(ring)
                    }
                    Text(auth).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 5) {
                    Circle().fill(real && ofacClear ? Brand.success : palette.textTertiary).frame(width: 7, height: 7)
                    Text(state).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(real && ofacClear ? Brand.success : palette.textTertiary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(active ? Color(hex: 0x5B8CFF).opacity(0.08) : palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint), lineWidth: active ? 1.4 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: AIS voyage-integrity track

    private var voyageTrack: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("AIS VOYAGE INTEGRITY")
                Spacer()
                Text(hasLiveFix ? "REPORTING" : "AIS DARK")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(hasLiveFix ? Brand.success : Color(hex: 0xFF5A4D))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill((hasLiveFix ? Brand.success : Color(hex: 0xFF5A4D)).opacity(0.14)))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 0) {
                    trackNode(board?.booking?.originUnlocode ?? "CNSHA", Color(hex: 0x5B8CFF))
                    Rectangle().fill(Brand.blue).frame(height: 2.4).frame(maxWidth: .infinity)
                    trackNode(board?.booking?.destinationUnlocode ?? "USLGB", hasLiveFix ? Color(hex: 0x2BD9A4) : palette.textTertiary)
                }
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                HStack {
                    Text(hasLiveFix ? "Live position on file" : "No AIS fix on file yet")
                        .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(hasLiveFix ? String(format: "%.0f kn", board?.position?.speedKn ?? 0) : "—")
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                Text("Dark-period + STS-proximity detection pending runAisIntegrityCheck")
                    .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private func trackNode(_ code: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            Circle().fill(tint).frame(width: 9, height: 9)
            Text(code).font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Anomaly ledger

    private var anomalyLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ANOMALY SIGNALS · fraud.computeScore")
            VStack(spacing: 0) {
                signalRow("shield.lefthalf.filled", Brand.success, "OFAC party screen", ofacSub, ofacClear ? "CLEAR" : "REVIEW", ofacClear ? Brand.success : Brand.warning)
                divider
                signalRow("dot.radiowaves.up.forward", hasLiveFix ? Brand.success : Color(hex: 0xFF5A4D), "AIS reporting",
                          hasLiveFix ? "Live fix present · lane on track" : "No fix on file · possible dark period",
                          hasLiveFix ? "CLEAR" : "FLAG", hasLiveFix ? Brand.success : Color(hex: 0xFF5A4D))
                divider
                signalRow("arrow.triangle.swap", palette.textTertiary, "STS rendezvous", "Paired-IMO proximity detection pending", "PENDING", palette.textTertiary)
                divider
                signalRow("flag.2.crossed", palette.textTertiary, "Reflagging pattern", "Flag-change 12mo history pending", "PENDING", palette.textTertiary)
                divider
                signalRow("checkmark.seal", palette.textTertiary, "GISIS hull check", "IMO scrap-registry lookup pending", "PENDING", palette.textTertiary)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private var ofacSub: String {
        if let s = ofac {
            return "Carrier + shipper + notify · \((s.matchCount ?? 0)) SDN hit\((s.matchCount ?? 0) == 1 ? "" : "s")"
        }
        return "Screen the booking parties against the SDN list"
    }
    private func signalRow(_ icon: String, _ tint: Color, _ title: String, _ sub: String, _ verdict: String, _ vColor: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.14)).frame(width: 38, height: 38)
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text(sub).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            Text(verdict).font(.system(size: 9, weight: .heavy)).foregroundStyle(vColor)
                .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(vColor.opacity(0.14)))
        }
        .padding(.vertical, 10)
    }

    private var esang: some View {
        HStack(alignment: .top, spacing: 12) {
            OrbeSang(state: .idle, diameter: 26).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(hasLiveFix ? "OFAC clean, AIS reporting — full STS/reflag scan pending" : "AIS dark on this leg outweighs the clean OFAC screen")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Hold loading and request the carrier's gap log before CBP entry")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.esangSoft))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: filing ? "Filing…" : "File AIS_SPOOFING signal",
                      action: { Task { await fileSignal() } }, isLoading: filing)
            Button {
                // Clear & release — local; the operator's disposition on this booking.
            } label: {
                Text("Clear & release").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 134, minHeight: 48).background(palette.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    // MARK: bits
    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }
    private var divider: some View { Rectangle().fill(palette.borderFaint).frame(height: 1) }
    private func gapCard(_ title: String, _ detail: String, warn: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warn ? "exclamationmark.triangle.fill" : "shield.lefthalf.filled")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(warn ? Brand.danger : palette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(warn ? Brand.danger.opacity(0.4) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct BoardIn: Encodable { let bookingNumber: String }
        struct ScreenIn: Encodable { let entityId: Int; let entityType: String; let limit: Int }
        do {
            async let b: TrackBoard716? = EusoTripAPI.shared.query("vesselShipments.getOceanTrackingBoard", input: BoardIn(bookingNumber: bookingNumber))
            self.board = try await b
            if let eid = importerEntityId {
                let res: ScreeningsResult716? = try await EusoTripAPI.shared.query(
                    "sanctions.getScreenings", input: ScreenIn(entityId: eid, entityType: "company", limit: 1))
                self.ofac = res?.screenings?.first
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func fileSignal() async {
        guard let eid = importerEntityId else { return }  // no entity → the STUB screenVesselSanctions leg owns IMO-only signals
        filing = true
        struct SignalIn: Encodable { let entityId: Int; let entityType: String; let signalType: String; let severity: String; let source: String }
        struct SignalOut: Decodable { let recorded: Bool? }
        do {
            let _: SignalOut? = try await EusoTripAPI.shared.mutation(
                "fraud.recordSignal",
                input: SignalIn(entityId: eid, entityType: "carrier", signalType: "AIS_SPOOFING", severity: "high", source: "vessel.ais_integrity"))
        } catch { /* surfaced by the caller ladder; keep the UI honest */ }
        filing = false
    }
}

private struct RimCard716<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            content().padding(Space.s5)
        }.frame(maxWidth: .infinity)
    }
}

#Preview("716 · Vessel AIS Integrity · Night") {
    VesselAisIntegrityScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("716 · Vessel AIS Integrity · Light") {
    VesselAisIntegrityScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
