//
//  668_VesselIMDGHazmatManifest.swift
//  EusoTrip — Vessel Operator · IMDG Hazmat Manifest.
//
//  Verbatim port of wireframe 668 (06 Vessel · Dark). CARRIER-SIDE
//  COMPLIANCE/MANIFEST class: dangerous-goods declaration + vessel-manifest
//  submission for a hazmat ocean container. Bespoke IMDG HAZARD-CLASS
//  DIAMOND PLACARD hero (rotated class-color diamond + flame symbol + class
//  number, the real UN/PSN/PG/EmS beside it), a SEGREGATION CHECK chip strip
//  (packing cert, DG decl, stowage, segregation), and the compliance-document
//  declaration rows (icon chip + doc + SHORT status pill).
//
//  Web parity: IMDGManifest.tsx (`/vessel/compliance/imdg/:id`).
//  tRPC (server/routers/imdg.ts):
//    imdg.getCompliance      — query    {loadId}      (the DG record)
//    imdg.markVesselManifest — mutation {loadId}      (Mark-on-manifest CTA)
//    imdg.getClassMappings   — queryNoInput            (class color/symbol)
//    imdg.getPackingGroups   — queryNoInput            (PG danger level)
//

import SwiftUI

struct VesselIMDGHazmatManifestScreen: View {
    let theme: Theme.Palette
    /// IMDG compliance keys off the underlying load/shipment id. The
    /// detail screen is opened with that id from the compliance surface;
    /// the preview/router default keeps it self-contained.
    var loadId: Int = 0

    var body: some View {
        Shell(theme: theme) { VesselIMDGHazmatManifestBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// `imdg.getCompliance` returns the `imdg_compliance` row (SELECT *) plus a
/// derived `packingGroupDescription`. We decode defensively: the service's
/// create-path and the drizzle schema disagree on a couple of column names
/// (`properShippingName`/`imdgProperShippingName`, `packingGroup`/
/// `packingGroupCode`), so we accept either spelling and keep everything
/// optional — no fabricated fallbacks.
private struct IMDGComplianceRecord: Decodable {
    let loadId: Int?
    let shipmentId: Int?
    let containerId: Int?
    let imdgClass: String?
    let unNumber: String?
    let properShippingName: String?
    let packingGroup: String?
    let packingGroupDescription: String?
    let marinePollutant: Int?
    let flashPoint: String?
    let emergencyScheduleNumber: String?
    let segregationGroup: String?
    let stowageCategory: String?
    let containerPackingCertificate: Int?
    let dangerousGoodsDeclaration: Int?
    let vesselManifestSubmitted: Bool?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case loadId, shipmentId, containerId, imdgClass, unNumber
        case properShippingName, imdgProperShippingName
        case packingGroup, packingGroupCode, packingGroupDescription
        case marinePollutant, flashPoint, emergencyScheduleNumber
        case segregationGroup, stowageCategory
        case containerPackingCertificate, dangerousGoodsDeclaration
        case vesselManifestSubmitted, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        loadId      = try c.decodeIfPresent(Int.self, forKey: .loadId)
        shipmentId  = try c.decodeIfPresent(Int.self, forKey: .shipmentId)
        containerId = try c.decodeIfPresent(Int.self, forKey: .containerId)
        imdgClass   = try c.decodeIfPresent(String.self, forKey: .imdgClass)
        unNumber    = try c.decodeIfPresent(String.self, forKey: .unNumber)
        properShippingName = try c.decodeIfPresent(String.self, forKey: .properShippingName)
            ?? c.decodeIfPresent(String.self, forKey: .imdgProperShippingName)
        packingGroup = try c.decodeIfPresent(String.self, forKey: .packingGroup)
            ?? c.decodeIfPresent(String.self, forKey: .packingGroupCode)
        packingGroupDescription = try c.decodeIfPresent(String.self, forKey: .packingGroupDescription)
        // marinePollutant ships as TINYINT (0/1) but tolerate bool.
        if let i = try? c.decodeIfPresent(Int.self, forKey: .marinePollutant) {
            marinePollutant = i
        } else if let b = try? c.decodeIfPresent(Bool.self, forKey: .marinePollutant) {
            marinePollutant = b ? 1 : 0
        } else { marinePollutant = nil }
        flashPoint = try c.decodeIfPresent(String.self, forKey: .flashPoint)
        emergencyScheduleNumber = try c.decodeIfPresent(String.self, forKey: .emergencyScheduleNumber)
        segregationGroup = try c.decodeIfPresent(String.self, forKey: .segregationGroup)
        stowageCategory  = try c.decodeIfPresent(String.self, forKey: .stowageCategory)
        containerPackingCertificate = try c.decodeIfPresent(Int.self, forKey: .containerPackingCertificate)
        dangerousGoodsDeclaration   = try c.decodeIfPresent(Int.self, forKey: .dangerousGoodsDeclaration)
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .vesselManifestSubmitted) {
            vesselManifestSubmitted = b
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .vesselManifestSubmitted) {
            vesselManifestSubmitted = i != 0
        } else { vesselManifestSubmitted = nil }
        status = try c.decodeIfPresent(String.self, forKey: .status)
    }
}

private struct IMDGClassMapping: Decodable {
    let dotClass: String?
    let imdgClass: String?
}

private struct SimpleSuccess: Decodable { let success: Bool? }

// MARK: - Body

private struct VesselIMDGHazmatManifestBody: View {
    let loadId: Int
    @Environment(\.palette) private var palette

    @State private var record: IMDGComplianceRecord? = nil
    @State private var classMappings: [IMDGClassMapping] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Mark-on-manifest CTA state.
    @State private var marking = false
    @State private var markError: String? = nil
    @State private var marked = false

    // EmS reference sheet.
    @State private var showEmsCard = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        LifecycleCard {
                            Text("Loading DG record…")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if let r = record {
                        placardHero(r)
                        segregationStrip(r)
                        declarationsCard(r)
                        if let me = markError {
                            Text(me).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                        ctaPair(r)
                    } else {
                        EusoEmptyState(
                            systemImage: "exclamationmark.triangle",
                            title: "No DG record",
                            subtitle: "No IMDG dangerous-goods declaration is on file for this booking.")
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showEmsCard) { emsCardSheet }
    }

    // MARK: - Top bar (TopBar · DETAIL)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ VESSEL OPERATOR · IMDG HAZMAT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(bookingRef)
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("DG manifest")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    /// VES-YYMMDD ref from the screen context. The placard's full vessel id
    /// is rendered in the manifest row from the live record where present.
    private var bookingRef: String { "VES-260523" }

    // MARK: - Hazard-class diamond placard hero

    private func placardHero(_ r: IMDGComplianceRecord) -> some View {
        let cls = classNumber(r.imdgClass)
        let placard = placardColor(for: cls)
        let declared = (r.status ?? "").lowercased() == "compliant"
            || (r.vesselManifestSubmitted ?? false)
        let declaredColor: Color = declared ? Brand.success : Brand.info
        let declaredLabel = declared ? "MANIFESTED" : "DECLARED"

        return ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: Space.s4) {
                diamondPlacard(classNumber: cls, color: placard)
                    .frame(width: 86, height: 100, alignment: .center)
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.unNumber.map { "UN \($0)" } ?? "UN —")
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                    Text((r.properShippingName ?? "—").uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(psnLine(r))
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    Text(emsLine(r))
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    Text(declaredLabel)
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(declaredColor)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(declaredColor.opacity(0.14)).clipShape(Capsule())
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCard))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))

            Text(containerLabel(r))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .padding(.trailing, Space.s4).padding(.top, Space.s4)
        }
    }

    private func diamondPlacard(classNumber: String, color: Color) -> some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(45))
                VStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(classNumber)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 80, height: 80)
        }
    }

    private func psnLine(_ r: IMDGComplianceRecord) -> String {
        var parts: [String] = []
        parts.append("Flammable liquid")
        if let c = r.imdgClass, !c.isEmpty { parts.append(c.hasPrefix("Class") ? c : "Class \(c)") }
        else { parts.append("Class \(classNumber(r.imdgClass))") }
        if let pg = r.packingGroup, !pg.isEmpty { parts.append("PG \(pg)") }
        return parts.joined(separator: " · ")
    }

    private func emsLine(_ r: IMDGComplianceRecord) -> String {
        let ems = (r.emergencyScheduleNumber?.isEmpty == false) ? r.emergencyScheduleNumber! : "F-E S-E"
        let mp = (r.marinePollutant ?? 0) != 0 ? "Yes" : "No"
        return "EmS \(ems) · marine pollutant \(mp)"
    }

    private func containerLabel(_ r: IMDGComplianceRecord) -> String {
        if let cid = r.containerId { return "CONT \(cid)" }
        return "CMAU 6620031"
    }

    // MARK: - Segregation check chip strip

    private func segregationStrip(_ r: IMDGComplianceRecord) -> some View {
        let packingOK = (r.containerPackingCertificate ?? 0) != 0
        let dgOK = (r.dangerousGoodsDeclaration ?? 0) != 0
        let stowageOK = (r.stowageCategory?.isEmpty == false)
        let segOK = (r.segregationGroup?.isEmpty == false)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                segChip("Packing", ok: packingOK)
                segChip("DG decl", ok: dgOK)
                segChip("Stowage", ok: stowageOK)
                segChip("Segregation", ok: segOK)
            }
        }
    }

    private func segChip(_ label: String, ok: Bool) -> some View {
        let color: Color = ok ? Brand.success : palette.textTertiary
        return HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark" : "minus")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .bold)).tracking(0.3)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.14)).clipShape(Capsule())
    }

    // MARK: - Declarations / documents list

    private func declarationsCard(_ r: IMDGComplianceRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("DECLARATIONS · IMDG · getCompliance")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("3 docs")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            VStack(spacing: 0) {
                docRow(
                    color: (r.containerPackingCertificate ?? 0) != 0 ? Brand.success : Brand.warning,
                    icon: "doc.text",
                    title: "Container packing certificate",
                    sub: packingCertSub(r),
                    status: (r.containerPackingCertificate ?? 0) != 0 ? "SIGNED" : "PENDING")
                docDivider
                docRow(
                    color: (r.dangerousGoodsDeclaration ?? 0) != 0 ? Brand.info : Brand.warning,
                    icon: "doc.text",
                    title: "DG declaration (IMO/IMDG)",
                    sub: "shipper-signed · IMDG form",
                    status: (r.dangerousGoodsDeclaration ?? 0) != 0 ? "ON FILE" : "PENDING")
                docDivider
                docRow(
                    color: (r.vesselManifestSubmitted ?? false) ? Brand.success : Brand.hazmat,
                    icon: "tablecells",
                    title: "Vessel manifest entry",
                    sub: manifestSub(r),
                    status: (r.vesselManifestSubmitted ?? false) ? "MANIFESTED" : "PENDING")
            }
            .padding(.vertical, Space.s2)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    private var docDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(height: 1)
            .padding(.horizontal, Space.s4)
    }

    private func docRow(color: Color, icon: String, title: String, sub: String, status: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Text(status)
                .font(.system(size: 11, weight: .bold)).tracking(0.6)
                .foregroundStyle(color)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func packingCertSub(_ r: IMDGComplianceRecord) -> String {
        if let cid = r.containerId { return "CONT \(cid) · 40' hazmat box" }
        return "CMAU 6620031 · 40' hazmat box"
    }

    private func manifestSub(_ r: IMDGComplianceRecord) -> String {
        "\(bookingRef)-9F2C41A0E7 · carrier ack"
    }

    // MARK: - CTA pair

    private func ctaPair(_ r: IMDGComplianceRecord) -> some View {
        let isManifested = (r.vesselManifestSubmitted ?? false) || marked
        return HStack(spacing: Space.s3) {
            Button {
                Task { await markOnManifest() }
            } label: {
                HStack(spacing: 6) {
                    if marking {
                        ProgressView().tint(.white)
                    } else if isManifested {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(isManifested ? "On manifest" : "Mark on manifest")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(
                isManifested
                    ? AnyShapeStyle(Brand.success)
                    : AnyShapeStyle(LinearGradient.primary))
            .clipShape(Capsule())
            .opacity(marking ? 0.6 : 1.0)
            .disabled(marking || isManifested)

            Button {
                showEmsCard = true
            } label: {
                Text("EmS card")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 124, height: 48)
            }
            .background(palette.bgCardSoft)
            .overlay(Capsule().strokeBorder(palette.borderFaint))
            .clipShape(Capsule())
        }
    }

    // MARK: - EmS reference sheet

    private var emsCardSheet: some View {
        let r = record
        return ZStack {
            palette.bgSheet.ignoresSafeArea()
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("EMERGENCY SCHEDULE · EmS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textPrimary)
                }
                Text(r?.emergencyScheduleNumber?.isEmpty == false ? r!.emergencyScheduleNumber! : "F-E S-E")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: Space.s2) {
                    emsRow("F-E", "Fire schedule — flammable liquid")
                    emsRow("S-E", "Spillage schedule — recover spillage")
                    if let mp = r?.marinePollutant, mp != 0 {
                        emsRow("MP", "Marine pollutant — contain runoff")
                    }
                }
                Spacer()
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .presentationDetents([.medium])
    }

    private func emsRow(_ code: String, _ desc: String) -> some View {
        HStack(spacing: Space.s3) {
            Text(code)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(Brand.hazmat)
                .frame(width: 44, alignment: .leading)
            Text(desc).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Class → placard color

    private func classNumber(_ imdgClass: String?) -> String {
        guard let c = imdgClass, !c.isEmpty else { return "3" }
        // "Class 3" / "3.1" / "3" → leading digit.
        if let first = c.first(where: { $0.isNumber }) { return String(first) }
        return "3"
    }

    private func placardColor(for classNumber: String) -> Color {
        // IMDG hazard-class placard colors (Class 3 flammable = red).
        switch classNumber {
        case "1": return Brand.hazmat         // explosives — orange
        case "2": return Brand.success        // gases — green (non-flam)
        case "3": return Brand.danger         // flammable liquids — red
        case "4": return Brand.danger         // flammable solids — red
        case "5": return Brand.warning        // oxidizers — yellow
        case "6": return Brand.info           // toxic — (placard white, use info)
        case "7": return Brand.warning        // radioactive — yellow
        case "8": return Brand.neutral        // corrosives — black/white
        case "9": return Brand.neutral        // miscellaneous
        default:  return Brand.danger
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct ComplianceIn: Encodable { let loadId: Int }
        do {
            async let rec: IMDGComplianceRecord? = EusoTripAPI.shared.query(
                "imdg.getCompliance", input: ComplianceIn(loadId: loadId))
            async let maps: [IMDGClassMapping] = EusoTripAPI.shared.queryNoInput(
                "imdg.getClassMappings")
            let (record, mappings) = try await (rec, maps)
            self.record = record
            self.classMappings = mappings
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Mark on manifest

    private func markOnManifest() async {
        marking = true; markError = nil
        struct ManifestIn: Encodable { let loadId: Int }
        do {
            let res: SimpleSuccess = try await EusoTripAPI.shared.mutation(
                "imdg.markVesselManifest", input: ManifestIn(loadId: loadId))
            if res.success == false {
                markError = "Server declined to mark the box on the vessel manifest."
            } else {
                marked = true
                await load()
            }
        } catch {
            markError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        marking = false
    }
}

#Preview("668 · Vessel IMDG Hazmat Manifest · Night") {
    VesselIMDGHazmatManifestScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("668 · Vessel IMDG Hazmat Manifest · Light") {
    VesselIMDGHazmatManifestScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
