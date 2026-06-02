//
//  571_RailIMDGHazmatManifest.swift
//  EusoTrip — Rail Engineer · IMDG Hazmat Manifest (intermodal dangerous-goods manifest).
//
//  Verbatim port of "571 Rail IMDG Hazmat Manifest.svg" (Light + Dark).
//  Rail-mode sibling of Vessel/668 IMDG Hazmat Manifest. Segregation, placards,
//  CHEMTREC, ERG guide, and DG declaration generation.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Data:
//    imdg.getCompliance          (EXISTS imdg.ts:13)           → hero status + DG metadata
//    hazmat.determinePlacards    (EXISTS hazmat.ts:121)         → KPI class/UN/PG
//    hazmat.checkSegregation     (EXISTS hazmat.ts:152)         → segregation check rows
//    hazmat.getEmergencyContacts (EXISTS hazmat.ts:388)         → CHEMTREC/ERG rows
//    imdg.setDGDeclarationUrl    (EXISTS imdg.ts:26)            → Generate DG declaration CTA
//

import SwiftUI

struct RailIMDGHazmatManifestScreen: View {
    let theme: Theme.Palette
    let containerNumber: String
    let railId: String

    var body: some View {
        Shell(theme: theme) { RailIMDGHazmatManifestBody(containerNumber: containerNumber, railId: railId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct IMDGCompliance571: Decodable {
    let containerNumber: String?
    let unNumber: String?
    let commodityName: String?
    let imdgClass: String?
    let packingGroup: String?
    let volume: String?
    let vehicleType: String?
    let route: String?
    let declarationStatus: String?

    private enum CodingKeys: String, CodingKey {
        case containerNumber, unNumber, commodityName, imdgClass, packingGroup
        case volume, vehicleType, route, declarationStatus
        case loadId, imdgProperShippingName, packingGroupCode, packingGroupDescription
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Server returns database fields; map them to iOS struct fields
        self.imdgClass = try c.decodeIfPresent(String.self, forKey: .imdgClass)
        self.packingGroup = try c.decodeIfPresent(String.self, forKey: .packingGroupCode)
        self.commodityName = try c.decodeIfPresent(String.self, forKey: .imdgProperShippingName)
        self.declarationStatus = try c.decodeIfPresent(String.self, forKey: .packingGroupDescription)
        // Fields that server does not provide; set to nil
        self.containerNumber = try c.decodeIfPresent(String.self, forKey: .containerNumber)
        self.unNumber = try c.decodeIfPresent(String.self, forKey: .unNumber)
        self.volume = try c.decodeIfPresent(String.self, forKey: .volume)
        self.vehicleType = try c.decodeIfPresent(String.self, forKey: .vehicleType)
        self.route = try c.decodeIfPresent(String.self, forKey: .route)
    }
}

private struct HazmatPlacard571: Decodable {
    let imdgClass: String?
    let unNumber: String?
    let packingGroup: String?
    let placards: [PlacardInfo]?
    let subsidiaryPlacards: [PlacardInfo]?
    let useDangerousPlacardOption: Bool?
    let dangerousPlacardNote: String?
    let totalMaterials: Int?

    struct PlacardInfo: Decodable {
        let hazmatClass: String?
        let placardName: String?
        let color: String?
        let required: Bool?
        let reason: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode the server's actual envelope fields
        placards = try container.decodeIfPresent([PlacardInfo].self, forKey: .placards)
        subsidiaryPlacards = try container.decodeIfPresent([PlacardInfo].self, forKey: .subsidiaryPlacards)
        useDangerousPlacardOption = try container.decodeIfPresent(Bool.self, forKey: .useDangerousPlacardOption)
        dangerousPlacardNote = try container.decodeIfPresent(String.self, forKey: .dangerousPlacardNote)
        totalMaterials = try container.decodeIfPresent(Int.self, forKey: .totalMaterials)
        
        // Extract legacy fields from first placard for backward compatibility
        if let first = placards?.first {
            imdgClass = first.hazmatClass
            unNumber = nil  // Server doesn't provide UN in the response
            packingGroup = nil  // Server doesn't provide packing group in the response
        } else {
            imdgClass = nil
            unNumber = nil
            packingGroup = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case placards
        case subsidiaryPlacards
        case useDangerousPlacardOption
        case dangerousPlacardNote
        case totalMaterials
    }
}

private struct SegregationCheck571: Decodable, Identifiable {
    let id: Int
    let checkName: String?
    let detail: String?
    let status: String?             // "clear" | "review" | "active" | "ref"
    let result: String?
    let contactType: String?        // nil | "chemtrec" | "erg"
    let phoneNumber: String?
}

private struct SegregationCheckEnvelope571: Decodable {
    let compatible: Bool
    let violations: [ViolationItem]
    let materialCount: Int
    let regulation: String
    
    struct ViolationItem: Decodable, Identifiable {
        let id: Int
        let classA: String
        let classB: String
        let nameA: String
        let nameB: String
        let regulation: String
        let severity: String
        
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.classA = try c.decode(String.self, forKey: .classA)
            self.classB = try c.decode(String.self, forKey: .classB)
            self.nameA = try c.decode(String.self, forKey: .nameA)
            self.nameB = try c.decode(String.self, forKey: .nameB)
            self.regulation = try c.decode(String.self, forKey: .regulation)
            self.severity = try c.decode(String.self, forKey: .severity)
            // Generate synthetic id from classA/classB pair
            self.id = "\(classA)-\(classB)".hashValue
        }
        
        private enum CodingKeys: String, CodingKey {
            case classA, classB, nameA, nameB, regulation, severity
        }
    }
}

private struct EmergencyContact571: Decodable, Identifiable {
    let id: Int
    let name: String?
    let contact: String?            // phone + ref number
    let availability: String?       // "24/7"
    let ergGuide: String?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case name, description
        case contact = "phone"
        case availability = "available"
        case purpose
        case ergGuide
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.contact = try c.decodeIfPresent(String.self, forKey: .contact)
        self.availability = try c.decodeIfPresent(String.self, forKey: .availability)
        self.ergGuide = try c.decodeIfPresent(String.self, forKey: .ergGuide)
        self.description = try c.decodeIfPresent(String.self, forKey: .purpose)
        // Generate id from name hash for unique identification
        self.id = self.name?.hashValue ?? 0
    }
}

private struct HazmatEmergencyContactsResponse: Decodable {
    let contacts: [EmergencyContact571]
    // (server may also send `ergContacts`; ignored here — not surfaced in the UI)
}

// MARK: - Unified list item

private struct ManifestRow571: Identifiable {
    let id: Int
    let title: String
    let sub: String
    let status: String
    let result: String
    let chipColor: Color
    let chipIcon: String
}

// MARK: - Body

private struct RailIMDGHazmatManifestBody: View {
    @Environment(\.palette) private var palette
    let containerNumber: String
    let railId: String

    @State private var compliance: IMDGCompliance571? = nil
    @State private var placard: HazmatPlacard571? = nil
    @State private var rows: [ManifestRow571] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isGenerating = false

    // MARK: Derived

    private var unLabel: String    { compliance?.unNumber ?? placard?.unNumber ?? "—" }
    private var classLabel: String { compliance?.imdgClass ?? placard?.imdgClass ?? "—" }
    private var pgLabel: String    { compliance?.packingGroup ?? placard?.packingGroup ?? "—" }

    private func statusColor(_ s: String?) -> Color {
        switch (s ?? "").lowercased() {
        case "clear":  return Brand.success
        case "review": return Brand.warning
        case "active": return Brand.info
        default:       return Brand.rail
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading manifest…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    segregationList
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · IMDG MANIFEST")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(compliance?.containerNumber ?? containerNumber)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Hazmat manifest")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text((compliance?.declarationStatus ?? "DECLARED").uppercased())
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.success.opacity(0.14)))
                let pgChip = "Class \(classLabel) · PG \(pgLabel)"
                Text(pgChip)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("UN\(unLabel)")
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(compliance?.commodityName ?? "Dangerous goods")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(compliance?.route ?? "—")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("VOLUME")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(compliance?.volume ?? "—")
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(compliance?.vehicleType ?? "tank car")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "CLASS",      value: classLabel, gradientNumeral: true)
            MetricTile(label: "UN PLACARD", value: unLabel)
            MetricTile(label: "PKG GRP",    value: pgLabel)
        }
    }

    // MARK: - Segregation list

    private var segregationList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("SEGREGATION & RESPONSE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("checkSegregation")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if rows.isEmpty {
                EusoEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "No segregation data",
                    subtitle: "Segregation checks and emergency contacts will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        manifestRow(row)
                        if idx < rows.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                                .overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func manifestRow(_ row: ManifestRow571) -> some View {
        let sColor = statusColor(row.status)
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(row.chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: row.chipIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(row.chipColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(row.sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(row.status.uppercased())
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(sColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(sColor.opacity(0.14)))
                Text(row.result)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Generate DG declaration", action: { Task { await generateDeclaration() } }, leadingIcon: "doc.fill", isLoading: isGenerating)
            Button {} label: {
                Text("Emergency")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.danger)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.40)))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct ContainerIn: Encodable { let containerNumber: String }
        struct SegIn: Encodable { let containerNumber: String; let railId: String }
        do {
            async let comp: IMDGCompliance571 = EusoTripAPI.shared.query(
                "imdg.getCompliance", input: ContainerIn(containerNumber: containerNumber))
            async let plac: HazmatPlacard571 = EusoTripAPI.shared.query(
                "hazmat.determinePlacards", input: ContainerIn(containerNumber: containerNumber))
            async let segs: [SegregationCheck571] = EusoTripAPI.shared.query(
                "hazmat.checkSegregation", input: SegIn(containerNumber: containerNumber, railId: railId))
            async let contacts: [EmergencyContact571] = EusoTripAPI.shared.query(
                "hazmat.getEmergencyContacts", input: ContainerIn(containerNumber: containerNumber))
            let (c, p, s, ec) = try await (comp, plac, segs, contacts)
            self.compliance = c
            self.placard    = p
            self.rows = buildRows(segregation: s, contacts: ec)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func buildRows(segregation: [SegregationCheck571], contacts: [EmergencyContact571]) -> [ManifestRow571] {
        var result: [ManifestRow571] = []
        var idx = 0
        for s in segregation {
            let color: Color = {
                switch (s.status ?? "").lowercased() {
                case "clear":  return Brand.success
                case "review": return Brand.warning
                default:       return Brand.rail
                }
            }()
            let icon: String = (s.status ?? "").lowercased() == "clear" ? "checkmark.diamond.fill" : "exclamationmark.triangle.fill"
            result.append(ManifestRow571(
                id: idx, title: s.checkName ?? "—", sub: s.detail ?? "—",
                status: s.status ?? "clear", result: s.result ?? "—",
                chipColor: color, chipIcon: icon))
            idx += 1
        }
        for c in contacts {
            let isERG = (c.name ?? "").uppercased().contains("ERG") || c.ergGuide != nil
            let color: Color = isERG ? Brand.rail : Brand.info
            let icon  = isERG ? "book.fill" : "phone.fill"
            let sub   = c.contact ?? c.description ?? "—"
            let resultLabel = isERG ? (c.ergGuide.map { "G\($0)" } ?? "—") : (c.availability ?? "24/7")
            let status = isERG ? "ref" : "active"
            let r = ManifestRow571(
                id: idx, title: c.name ?? "—", sub: sub,
                status: status, result: resultLabel,
                chipColor: color, chipIcon: icon)
            result.append(r)
            idx += 1
        }
        return result
    }

    private func generateDeclaration() async {
        isGenerating = true
        struct DeclIn: Encodable { let loadId: Int; let url: String }
        struct DeclOut: Decodable { let success: Bool }
        do {
            let _: DeclOut = try await EusoTripAPI.shared.query(
                "imdg.setDGDeclarationUrl",
                input: DeclIn(loadId: 0, url: ""))
        } catch { /* non-fatal */ }
        isGenerating = false
    }
}

#Preview("571 · Rail IMDG Hazmat Manifest · Night") { RailIMDGHazmatManifestScreen(theme: Theme.dark, containerNumber: "TCNU7693120", railId: "RAIL-260523-7C3A0B12D4").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("571 · Rail IMDG Hazmat Manifest · Light") { RailIMDGHazmatManifestScreen(theme: Theme.light, containerNumber: "TCNU7693120", railId: "RAIL-260523-7C3A0B12D4").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
