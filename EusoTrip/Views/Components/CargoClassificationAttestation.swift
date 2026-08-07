//
//  CargoClassificationAttestation.swift
//  EusoTrip — shared cargo-classification attestation primitive.
//
//  ONE type + ONE control for every surface that posts a load. Same
//  convention as ESangChatKit (chat), TransportLexicon (mode terms) and
//  FlipTile (cards): the attestation is never re-implemented per screen.
//
//  WHY THIS EXISTS
//  ---------------
//  The server made the cargo classification a first-class REQUIRED input on
//  every load-creating procedure:
//
//    • loads.create               → assessCargoClassification →
//    • shippers.create              cargoClassificationFailures →
//    • loadTemplates.useTemplate    TRPCError PRECONDITION_FAILED
//    • loads.createFromTemplate
//    • industryVerticals.assessDraft (same three attestation fields)
//
//  (frontend/server/services/cargoClassification.ts)
//
//  DOCTRINE — non-negotiable on a regulated-industry platform:
//    • The USER attests; the app RECORDS. Nothing is defaulted, guessed or
//      pre-selected. There is no "sensible default" for a legal
//      classification.
//    • Regulated status is NEVER inferred from the trailer, the equipment,
//      the vertical, the cargo-type chip or an ERG lookup. ERG may SUGGEST
//      an identity; it can never ESTABLISH a legal classification.
//    • A saved template may SUGGEST an identity but can never ESTABLISH one
//      — it carries no attestation, no evidence reference and no confirming
//      user. Every materialization needs a fresh attestation from whoever
//      is posting THAT occurrence.
//    • No fabricated evidence references, no placeholder strings, no silent
//      fallbacks. When the poster has not attested, the load is a clearly
//      labelled DRAFT and the refusal names exactly what is missing.
//
//  `.undetermined` IS A REAL STATE. It is the absence of a determination and
//  it is storable on a draft. It is NOT a way to post: the server always
//  pushes a required input for it, so an undetermined load can never post.
//  The control therefore offers exactly TWO determinations and treats "no
//  selection" as `.undetermined` — that is why nothing is pre-selected.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Value type

/// The poster's cargo-classification attestation for ONE posting.
///
/// Mirrors the server wire contract verbatim
/// (`cargoClassification.ts` · `CargoClassificationInput`). The rules in
/// `failures(context:)` mirror `assessCargoClassification` — they are not a
/// looser local convenience rule. Where the server can check something this
/// client cannot (the dangerous-goods ↔ equipment compatibility table lives
/// in `_core/hazmatConstants` and is server-only), the client does not guess:
/// the server remains the authority and its refusal is surfaced verbatim.
struct CargoClassificationAttestation: Codable, Hashable {

    // MARK: Server vocabularies (raw values are the wire values)

    /// `DANGEROUS_GOODS_STATUSES`.
    enum DangerousGoodsStatus: String, Codable, Hashable, CaseIterable, Identifiable {
        case undetermined
        case notDangerousGoods = "not_dangerous_goods"
        case dangerousGoods    = "dangerous_goods"

        var id: String { rawValue }

        /// What the poster is actually attesting to. Written as a claim,
        /// because that is what it is.
        var label: String {
            switch self {
            case .undetermined:      return "No determination"
            case .notDangerousGoods: return "Not dangerous goods"
            case .dangerousGoods:    return "Dangerous goods"
            }
        }

        var detail: String {
            switch self {
            case .undetermined:
                return "No classification has been made for this cargo."
            case .notDangerousGoods:
                return "This cargo is not regulated as dangerous goods, and I hold documentation that says so."
            case .dangerousGoods:
                return "This cargo is regulated as dangerous goods, and I hold the classification evidence."
            }
        }

        var symbol: String {
            switch self {
            case .undetermined:      return "questionmark.circle"
            case .notDangerousGoods: return "checkmark.shield"
            case .dangerousGoods:    return "exclamationmark.triangle.fill"
            }
        }
    }

    /// `CARGO_CLASSIFICATION_SOURCES`.
    ///
    /// `regulatoryLookup` exists in the server enum but is deliberately never
    /// offered by the control: it is reference evidence only. It is in
    /// neither `AUTHORITATIVE_REGULATED_SOURCES` nor
    /// `AUTHORITATIVE_NON_REGULATED_SOURCES`, so selecting it can only ever
    /// produce a required-input failure plus a warning. Offering a choice
    /// that can never post would be dishonest UI.
    enum CargoClassificationSource: String, Codable, Hashable, CaseIterable, Identifiable {
        case sds
        case shipperMasterData        = "shipper_master_data"
        case providerVerified         = "provider_verified"
        case regulatoryLookup         = "regulatory_lookup"
        case notRegulatedDocumentation = "not_regulated_documentation"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sds:                      return "Safety data sheet"
            case .shipperMasterData:        return "Shipper master data"
            case .providerVerified:         return "Verified provider"
            case .regulatoryLookup:         return "Regulatory lookup"
            case .notRegulatedDocumentation: return "Non-regulated documentation"
            }
        }

        /// What the evidence reference must point at for this source. Used as
        /// the field placeholder — it is a prompt, never a pre-filled value.
        var evidencePrompt: String {
            switch self {
            case .sds:                      return "SDS document number"
            case .shipperMasterData:        return "Master-data record identifier"
            case .providerVerified:         return "Provider verification identifier"
            case .regulatoryLookup:         return "Regulation or CFR citation"
            case .notRegulatedDocumentation: return "Non-regulated document reference"
            }
        }
    }

    /// `PACKING_GROUP_STATUSES`.
    enum PackingGroupStatus: String, Codable, Hashable, CaseIterable, Identifiable {
        case undetermined
        case assigned
        case notAssigned = "not_assigned"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .undetermined: return "Not answered"
            case .assigned:     return "Packing group assigned"
            case .notAssigned:  return "No packing group"
            }
        }
    }

    enum PackingGroup: String, Codable, Hashable, CaseIterable, Identifiable {
        case I, II, III
        var id: String { rawValue }
    }

    // MARK: Stored state

    /// The determination itself. Starts `.undetermined` — the ABSENCE of an
    /// attestation, never a default answer.
    var dangerousGoodsStatus: DangerousGoodsStatus = .undetermined
    /// Always required by the server; its absence alone fails the post.
    var classificationSource: CargoClassificationSource? = nil
    /// Required whenever the status is not `.undetermined`. A pointer to the
    /// ACTUAL evidence. Never auto-filled.
    var classificationEvidenceRef: String = ""

    // Dangerous-goods detail (49 CFR 172.200-204 / IMDG / TDG identity).
    var unNumber: String = ""
    var properShippingName: String = ""
    var hazmatClass: String = ""
    var technicalName: String = ""
    var emergencyPhone: String = ""
    var packagingType: String = ""
    var packingGroupStatus: PackingGroupStatus? = nil
    var packingGroup: PackingGroup? = nil
    var subsidiaryHazards: [String] = []

    init() {}

    // MARK: Wire projection (nil = field omitted, never an empty placeholder)

    var wireStatus: String { dangerousGoodsStatus.rawValue }
    var wireSource: String? { classificationSource?.rawValue }
    var wireEvidenceRef: String? { Self.nonBlank(classificationEvidenceRef) }
    var wireUnNumber: String? { Self.nonBlank(unNumber) }
    var wireProperShippingName: String? { Self.nonBlank(properShippingName) }
    var wireHazmatClass: String? { Self.nonBlank(hazmatClass) }
    var wireTechnicalName: String? { Self.nonBlank(technicalName) }
    var wireEmergencyPhone: String? { Self.nonBlank(emergencyPhone) }
    var wirePackagingType: String? { Self.nonBlank(packagingType) }
    var wirePackingGroupStatus: String? { packingGroupStatus?.rawValue }
    var wirePackingGroup: String? { packingGroup?.rawValue }
    var wireSubsidiaryHazards: [String]? {
        let cleaned = subsidiaryHazards.compactMap(Self.nonBlank)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func nonBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Sources valid for the current branch

    /// Only the sources that can actually establish the selected
    /// determination. Mirrors `AUTHORITATIVE_REGULATED_SOURCES` /
    /// `AUTHORITATIVE_NON_REGULATED_SOURCES`.
    static func sources(for status: DangerousGoodsStatus) -> [CargoClassificationSource] {
        switch status {
        case .undetermined:
            // No determination → no evidence question to answer yet.
            return []
        case .notDangerousGoods:
            return [.sds, .shipperMasterData, .providerVerified, .notRegulatedDocumentation]
        case .dangerousGoods:
            return [.sds, .shipperMasterData, .providerVerified]
        }
    }

    /// Applies a determination and drops anything that the new branch cannot
    /// carry. Never invents a replacement — it clears, so the poster answers
    /// again.
    mutating func setDetermination(_ status: DangerousGoodsStatus) {
        dangerousGoodsStatus = status
        if let source = classificationSource,
           !Self.sources(for: status).contains(source) {
            classificationSource = nil
        }
        if status != .dangerousGoods {
            packingGroupStatus = nil
            packingGroup = nil
        }
        if status == .notDangerousGoods {
            // A not-regulated load cannot carry regulated-material
            // identifiers — the server blocks exactly this combination. The
            // identifiers here were only ever a suggestion (a template
            // pre-fill, or a mirror of the host screen's hazmat card), so
            // they are dropped rather than sent alongside a contradicting
            // attestation. Hosts that mirror their own fields in will
            // re-populate them, which correctly re-raises the contradiction
            // when the poster really did type a UN number.
            unNumber = ""
            properShippingName = ""
            hazmatClass = ""
            technicalName = ""
            subsidiaryHazards = []
        }
        if status == .undetermined {
            classificationEvidenceRef = ""
        }
    }

    /// Seed the regulated IDENTITY from something that may SUGGEST it (the
    /// poster's own typed hazmat fields on the host screen, or a saved
    /// template). Only fills blanks — it never overwrites what the poster
    /// attested, and it never touches the determination, the source or the
    /// evidence reference, because none of those can be suggested by anything.
    mutating func seedRegulatedIdentity(
        unNumber: String? = nil,
        hazmatClass: String? = nil,
        properShippingName: String? = nil,
        packingGroup: String? = nil
    ) {
        if self.unNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let seed = Self.nonBlank(unNumber ?? "") {
            self.unNumber = seed
        }
        if self.hazmatClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let seed = Self.nonBlank(hazmatClass ?? "") {
            self.hazmatClass = seed
        }
        if self.properShippingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let seed = Self.nonBlank(properShippingName ?? "") {
            self.properShippingName = seed
        }
        if self.packingGroup == nil,
           let raw = Self.nonBlank(packingGroup ?? ""),
           let parsed = PackingGroup(rawValue: raw.uppercased()) {
            self.packingGroup = parsed
        }
    }

    // MARK: - Server mirror

    /// The load facts the classification assessor needs that this attestation
    /// does NOT own — they belong to the posting screen (commodity, equipment,
    /// mode, quantity). Supplying them lets the client name every missing
    /// input before the round trip instead of after it.
    struct CargoContext: Hashable {
        var productName: String = ""
        var equipmentType: String = ""
        var transportMode: String = ""
        var quantity: Double? = nil
        var quantityUnit: String = ""

        /// Use when the caller genuinely has none of this context yet.
        ///
        /// 2026-08-07 — this is NOT an exemption. An empty context used to
        /// skip the host-owned checks entirely, so a dangerous-goods
        /// attestation with no product, no equipment and no quantity reported
        /// "ready", lit the Post button green, and was then refused by
        /// `assessCargoClassification`. The server requires those facts for
        /// every regulated post, so their absence IS a missing input and is
        /// now reported as one. Fail closed: a screen that cannot supply them
        /// cannot post regulated cargo.
        static let unknown = CargoContext()

        var isEmpty: Bool {
            productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && equipmentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && transportMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && quantity == nil
                && quantityUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// True when the server's `hasRegulatedIdentity` would be true.
    var hasRegulatedIdentity: Bool {
        wireUnNumber != nil
            || wireProperShippingName != nil
            || wireHazmatClass != nil
            || wirePackingGroup != nil
            || wireTechnicalName != nil
            || wireSubsidiaryHazards != nil
    }

    /// Everything `cargoClassificationFailures` would return, minus the two
    /// checks that are structurally server-only (the dangerous-goods ↔
    /// equipment compatibility table). Strings are the SERVER's strings so
    /// the client and the server never say different things about the same
    /// load.
    func failures(context: CargoContext = .unknown) -> [String] {
        var required: [String] = []
        var blocking: [String] = []
        let isDangerousGoods = dangerousGoodsStatus == .dangerousGoods

        if dangerousGoodsStatus == .undetermined {
            required.append("dangerous-goods determination")
        }
        if classificationSource == nil {
            required.append("classification evidence source")
        }
        if dangerousGoodsStatus != .undetermined, wireEvidenceRef == nil {
            required.append("classification evidence reference")
        }

        if dangerousGoodsStatus == .notDangerousGoods {
            if let source = classificationSource,
               !Self.sources(for: .notDangerousGoods).contains(source) {
                required.append("shipper, SDS, provider, or documented non-regulated confirmation")
            }
            if hasRegulatedIdentity {
                blocking.append(
                    "The cargo is marked not regulated but regulated-material identifiers are present"
                )
            }
        }

        if isDangerousGoods {
            // Host-owned facts. Evaluated unconditionally: the server requires
            // every one of them for a regulated post, so an empty context is a
            // context with all of them missing — not a reason to stay silent.
            if context.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                required.append("exact regulated product")
            }
            if context.equipmentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                required.append("transport equipment type")
            }
            if context.transportMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                required.append("transport mode")
            }
            if !(context.quantity.map { $0.isFinite && $0 > 0 } ?? false) {
                required.append("regulated-material quantity")
            }
            if context.quantityUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                required.append("regulated-material quantity unit")
            }
            if wireUnNumber == nil { required.append("UN or NA identification number") }
            if wireProperShippingName == nil { required.append("proper shipping name") }
            if wireHazmatClass == nil { required.append("primary hazard class or division") }
            if wireEmergencyPhone == nil { required.append("emergency response phone") }
            if wirePackagingType == nil { required.append("packaging or containment type") }

            if packingGroupStatus == nil || packingGroupStatus == .undetermined {
                required.append("packing-group applicability")
            } else if packingGroupStatus == .assigned && packingGroup == nil {
                required.append("assigned packing group")
            } else if packingGroupStatus == .notAssigned && packingGroup != nil {
                blocking.append(
                    "A packing group value is present even though the material is marked not assigned"
                )
            }

            if let source = classificationSource,
               !Self.sources(for: .dangerousGoods).contains(source) {
                required.append("shipper, SDS, or verified-provider classification confirmation")
            }

            if let un = wireUnNumber {
                let normalized = un.replacingOccurrences(
                    of: "\\s+", with: "", options: .regularExpression
                ).uppercased()
                if normalized.range(of: "^(UN|NA)?[0-9]{4}$", options: .regularExpression) == nil {
                    blocking.append("The UN or NA identification number must contain four digits")
                }
            }
            if let phone = wireEmergencyPhone {
                let digits = phone.filter(\.isNumber).count
                if digits < 7 || digits > 15 {
                    blocking.append("The emergency response phone must contain 7 to 15 digits")
                }
            }
            let shippingName = (wireProperShippingName ?? "").lowercased()
            if (shippingName.contains("n.o.s.") || shippingName.contains("not otherwise specified")),
               wireTechnicalName == nil {
                required.append("technical name for the N.O.S. shipping description")
            }
        }

        var seen = Set<String>()
        return (blocking + required).filter { seen.insert($0).inserted }
    }

    /// Warnings the server would attach. Reference-only evidence is called out
    /// as reference-only.
    var warnings: [String] {
        classificationSource == .regulatoryLookup
            ? ["Regulatory lookup is reference evidence and does not replace shipper classification"]
            : []
    }

    /// The attestation-only completeness gate: true when nothing this value
    /// type owns is missing. Host screens that also own the commodity /
    /// equipment / mode / quantity should gate on
    /// `failures(context:).isEmpty` instead, which is the full mirror.
    var isComplete: Bool { failures().isEmpty }

    /// One honest sentence for a blocked Post button. Nil when complete.
    func blockReason(context: CargoContext = .unknown) -> String? {
        let missing = failures(context: context)
        guard !missing.isEmpty else { return nil }
        if dangerousGoodsStatus == .undetermined {
            return "This load stays a draft until you attest to its cargo classification."
        }
        return "Cargo classification is incomplete — \(missing.joined(separator: "; "))."
    }
}

// MARK: - Control

/// The one attestation control. Same card chrome as every other review /
/// lifecycle surface (`LifecycleCard` / `LifecycleSection` / `LifecycleRow`).
///
/// Nothing is pre-selected: the determination row starts with neither chip
/// lit, which IS `.undetermined`. Tapping the lit chip clears back to it.
struct CargoClassificationAttestationCard: View {
    @Environment(\.palette) private var palette

    @Binding var attestation: CargoClassificationAttestation

    /// Load facts owned by the host screen, so the missing-input list is the
    /// complete one. Pass `.unknown` when the screen genuinely has none.
    var context: CargoClassificationAttestation.CargoContext = .unknown

    /// Regulated-identity fields the HOST screen already asks for. Those are
    /// not asked twice here; the host feeds them in via
    /// `seedRegulatedIdentity`, so the attestation stays the single wire
    /// source of truth without double-asking the poster.
    var hostCaptures: IdentityFields = []

    /// Optional eyebrow suffix, e.g. "· FIRST OCCURRENCE".
    var titleSuffix: String? = nil

    struct IdentityFields: OptionSet {
        let rawValue: Int
        static let unNumber           = IdentityFields(rawValue: 1 << 0)
        static let hazmatClass        = IdentityFields(rawValue: 1 << 1)
        static let properShippingName = IdentityFields(rawValue: 1 << 2)
        static let packingGroup       = IdentityFields(rawValue: 1 << 3)
    }

    private var status: CargoClassificationAttestation.DangerousGoodsStatus {
        attestation.dangerousGoodsStatus
    }

    private var missing: [String] { attestation.failures(context: context) }

    var body: some View {
        LifecycleCard(
            accentDanger: status != .undetermined && !missing.isEmpty,
            accentWarning: status == .undetermined
        ) {
            LifecycleSection(
                label: ["CARGO CLASSIFICATION · ATTESTATION", titleSuffix]
                    .compactMap { $0 }.joined(separator: " "),
                icon: "checkmark.shield.fill"
            )

            Text("You attest to this classification and EusoTrip records it. Reference tools may suggest an identity — only your evidence establishes it.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            determinationRow

            if status == .undetermined {
                draftNotice
            } else {
                LifecycleRow(label: "Determination", value: status.label)
                Text(status.detail)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                sourceRow
                evidenceRow
                if status == .dangerousGoods {
                    dangerousGoodsDetail
                }
                ForEach(attestation.warnings, id: \.self) { warning in
                    noticeLine(warning, icon: "info.circle.fill", tint: Brand.warning)
                }
            }

            if !missing.isEmpty {
                missingList
            } else {
                noticeLine(
                    "Attested. The server re-checks this classification and the equipment compatibility table before the load posts.",
                    icon: "checkmark.seal.fill",
                    tint: Brand.success
                )
            }
        }
    }

    // MARK: Determination

    private var determinationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DETERMINATION")
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 6) {
                determinationChip(.notDangerousGoods)
                determinationChip(.dangerousGoods)
            }
        }
    }

    private func determinationChip(
        _ candidate: CargoClassificationAttestation.DangerousGoodsStatus
    ) -> some View {
        let selected = status == candidate
        return Button {
            // Tapping the lit chip withdraws the attestation back to
            // "no determination" — a poster must be able to un-attest.
            attestation.setDetermination(selected ? .undetermined : candidate)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: candidate.symbol)
                    .font(.system(size: 10, weight: .heavy))
                Text(candidate.label)
                    .font(.system(size: 11, weight: .heavy))
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(selected
                ? AnyShapeStyle(LinearGradient.diagonal)
                : AnyShapeStyle(palette.bgCardSoft)))
            .foregroundStyle(selected
                ? AnyShapeStyle(Color.white)
                : AnyShapeStyle(palette.textPrimary))
            .overlay(Capsule().strokeBorder(selected
                ? AnyShapeStyle(Color.clear)
                : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(candidate.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var draftNotice: some View {
        noticeLine(
            "No determination recorded. This load stays a draft until you attest — EusoTrip will not choose for you.",
            icon: "questionmark.circle.fill",
            tint: Brand.warning
        )
    }

    // MARK: Evidence source

    private var sourceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EVIDENCE SOURCE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: 6)],
                alignment: .leading, spacing: 6
            ) {
                ForEach(CargoClassificationAttestation.sources(for: status)) { source in
                    sourceChip(source)
                }
            }
        }
    }

    private func sourceChip(
        _ source: CargoClassificationAttestation.CargoClassificationSource
    ) -> some View {
        let selected = attestation.classificationSource == source
        return Button {
            attestation.classificationSource = selected ? nil : source
        } label: {
            Text(source.label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2).minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Capsule().fill(selected
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.bgCardSoft)))
                .foregroundStyle(selected
                    ? AnyShapeStyle(Color.white)
                    : AnyShapeStyle(palette.textPrimary))
                .overlay(Capsule().strokeBorder(selected
                    ? AnyShapeStyle(Color.clear)
                    : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var evidenceRow: some View {
        field(
            "Evidence reference",
            text: $attestation.classificationEvidenceRef,
            placeholder: attestation.classificationSource?.evidencePrompt
                ?? "Select an evidence source first",
            autocapitalization: .characters
        )
        .disabled(attestation.classificationSource == nil)
        .opacity(attestation.classificationSource == nil ? 0.55 : 1)
        Text("Point at the real record. A reference that does not exist is worse than no post.")
            .font(.system(size: 9))
            .foregroundStyle(palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Dangerous-goods detail

    @ViewBuilder
    private var dangerousGoodsDetail: some View {
        Divider().background(palette.borderFaint).padding(.vertical, 2)
        Text("REGULATED IDENTITY · 49 CFR 172.200-204")
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(palette.textSecondary)

        if !hostCaptures.contains(.unNumber) || !hostCaptures.contains(.hazmatClass) {
            HStack(spacing: 8) {
                if !hostCaptures.contains(.unNumber) {
                    field("UN / NA", text: $attestation.unNumber,
                          placeholder: "UN1267", autocapitalization: .characters)
                }
                if !hostCaptures.contains(.hazmatClass) {
                    field("Class", text: $attestation.hazmatClass,
                          placeholder: "3", autocapitalization: .characters)
                }
            }
        }
        if !hostCaptures.contains(.properShippingName) {
            field("Proper shipping name", text: $attestation.properShippingName,
                  placeholder: "Petroleum crude oil", autocapitalization: .words)
        }
        field("Technical name", text: $attestation.technicalName,
              placeholder: "Required for an N.O.S. shipping description",
              autocapitalization: .words)
        field("Packaging or containment", text: $attestation.packagingType,
              placeholder: "UN 1A1 steel drum · MC-307 cargo tank",
              autocapitalization: .characters)
        field("Emergency response phone", text: $attestation.emergencyPhone,
              placeholder: "24-hour number, 7-15 digits",
              autocapitalization: .never)
        field("Subsidiary hazards", text: subsidiaryHazardsBinding,
              placeholder: "Comma-separated, e.g. 6.1, 8",
              autocapitalization: .characters)

        packingGroupRow
    }

    private var subsidiaryHazardsBinding: Binding<String> {
        Binding(
            get: { attestation.subsidiaryHazards.joined(separator: ", ") },
            set: { raw in
                attestation.subsidiaryHazards = raw
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    @ViewBuilder
    private var packingGroupRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PACKING GROUP")
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: 6) {
                packingStatusChip(.assigned)
                packingStatusChip(.notAssigned)
            }
            if attestation.packingGroupStatus == .assigned,
               !hostCaptures.contains(.packingGroup) {
                HStack(spacing: 6) {
                    ForEach(CargoClassificationAttestation.PackingGroup.allCases) { group in
                        packingGroupChip(group)
                    }
                }
            }
        }
    }

    private func packingStatusChip(
        _ candidate: CargoClassificationAttestation.PackingGroupStatus
    ) -> some View {
        let selected = attestation.packingGroupStatus == candidate
        return Button {
            if selected {
                attestation.packingGroupStatus = nil
            } else {
                attestation.packingGroupStatus = candidate
                if candidate == .notAssigned { attestation.packingGroup = nil }
            }
        } label: {
            Text(candidate.label)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2).minimumScaleFactor(0.8)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Capsule().fill(selected
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.bgCardSoft)))
                .foregroundStyle(selected
                    ? AnyShapeStyle(Color.white)
                    : AnyShapeStyle(palette.textPrimary))
                .overlay(Capsule().strokeBorder(selected
                    ? AnyShapeStyle(Color.clear)
                    : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func packingGroupChip(
        _ candidate: CargoClassificationAttestation.PackingGroup
    ) -> some View {
        let selected = attestation.packingGroup == candidate
        return Button {
            attestation.packingGroup = selected ? nil : candidate
        } label: {
            Text(candidate.rawValue)
                .font(.system(size: 11, weight: .heavy))
                .frame(width: 44)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.bgCardSoft)))
                .foregroundStyle(selected
                    ? AnyShapeStyle(Color.white)
                    : AnyShapeStyle(palette.textPrimary))
                .overlay(Capsule().strokeBorder(selected
                    ? AnyShapeStyle(Color.clear)
                    : AnyShapeStyle(palette.borderFaint), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared bits

    /// Labelled text input in the house idiom (same recipe as 204's
    /// `hazmatTextField`).
    private func field(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        autocapitalization: TextInputAutocapitalization
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .tint(LinearGradient.diagonal)
                .autocorrectionDisabled()
                .textInputAutocapitalization(autocapitalization)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var missingList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STILL REQUIRED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                .foregroundStyle(Brand.warning)
            ForEach(missing, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                        .foregroundStyle(Brand.warning)
                        .padding(.top, 6)
                    Text(item)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func noticeLine(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(tint)
                .padding(.top, 2)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Previews

#Preview("Cargo classification · undetermined · Dark") {
    StatefulPreviewWrapper(CargoClassificationAttestation()) { binding in
        ScrollView {
            CargoClassificationAttestationCard(attestation: binding)
                .padding(14)
        }
        .background(Theme.dark.bgPrimary)
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Cargo classification · dangerous goods · Light") {
    StatefulPreviewWrapper({
        var value = CargoClassificationAttestation()
        value.setDetermination(.dangerousGoods)
        value.classificationSource = .sds
        return value
    }()) { binding in
        ScrollView {
            CargoClassificationAttestationCard(attestation: binding)
                .padding(14)
        }
        .background(Theme.light.bgPrimary)
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}

/// Minimal binding host so the previews can drive the control.
private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View { content($value) }
}
