//
//  253_PostLoadStep4Review.swift
//  EusoTrip — Shipper · Post-a-Load · Step 4 REVIEW.
//  Final wizard step. Renders the full draft summary and fires
//  `shippers.create` when the user taps Post.
//

import SwiftUI

struct PostLoadStep4ReviewScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { ReviewBody(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

private struct ReviewBody: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    @State private var showConfirmDialog: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                modeAndCountryCard
                laneCard
                equipmentCard
                documentsRequiredCard   // T-009 · 2026-05-20
                ePodLockCard            // T-011 · 2026-05-20
                pricingCard
                if draft.cargoType == .hazmat { hazmatCard }
                if draft.cargoType == .refrigerated { reeferCard }
                if !draft.stops.isEmpty { stopsCard }
                if let err = draft.postError { errorCard(err) }
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .onChange(of: draft.postedLoadNumber) { _, ln in
            if ln != nil {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "254"])
            }
        }
        // T-010 · 2026-05-20 — confirmation gate. Wraps draft.submit() so
        // a misclick on Post can't fire off an irreversible marketplace
        // post. Dialog body summarizes the lane + rate + ePOD-lock state
        // so the shipper sees exactly what they're committing to.
        .confirmationDialog(
            confirmTitle,
            isPresented: $showConfirmDialog,
            titleVisibility: .visible,
            actions: {
                Button("Post load", role: .destructive) {
                    Task { await draft.submit() }
                }
                Button("Cancel", role: .cancel) { }
            },
            message: { Text(confirmMessage) }
        )
    }

    private var confirmTitle: String {
        let lane = "\(dashIfEmpty(draft.origin)) → \(dashIfEmpty(draft.destination))"
        return "Post \(lane)?"
    }

    private var confirmMessage: String {
        var lines: [String] = []
        if let t = draft.trailer {
            lines.append("Equipment: \(t.displayName)")
        }
        if let v = draft.vertical {
            lines.append("Vertical: \(v.displayName)")
        }
        if let r = draft.rate {
            lines.append(String(format: "Rate: $%.0f", r))
        }
        if draft.ePodLockEnabled {
            lines.append("ePOD lock: ON (settlement waits for verified POD)")
        }
        if draft.isCrossBorder {
            lines.append(draft.isUSMCA ? "Cross-border · USMCA" : "Cross-border")
        }
        if draft.isHazmatComputed {
            lines.append("HAZMAT")
        }
        return lines.joined(separator: "\n")
    }

    // ── T-011 (ePOD lock initialization, 2026-05-20) ────────────────
    // Surfaces the ePOD-lock decision before the user posts. Auto-on
    // for cross-border / hazmat / rate > $5k / heavy haul; shipper can
    // toggle off (records as an explicit override). Banner explains
    // which trigger fired so the override decision is informed.
    private var ePodLockCard: some View {
        Group {
            if draft.requiresEpodLock || draft.ePodLockOverride != nil {
                LifecycleCard {
                    LifecycleSection(label: "ePOD LOCK", icon: "lock.shield")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Settlement holds for verified POD")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                        Toggle("", isOn: Binding(
                            get: { draft.ePodLockEnabled },
                            set: { draft.ePodLockOverride = $0 }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: Brand.blue))
                        .labelsHidden()
                    }
                    if draft.requiresEpodLock {
                        Text(ePodLockReason)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !draft.ePodLockEnabled && draft.requiresEpodLock {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Brand.warning)
                            Text("Lock disabled by override. Funds will release on POSTED → DELIVERED without ePOD verification.")
                                .font(.system(size: 10, weight: .heavy)).tracking(0.2)
                                .foregroundStyle(Brand.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// Human-readable reason the ePOD lock auto-engaged. Reads the
    /// strongest trigger first so the shipper sees the most relevant
    /// risk factor.
    private var ePodLockReason: String {
        var triggers: [String] = []
        if draft.isCrossBorder { triggers.append("cross-border (customs)") }
        if draft.isHazmatComputed { triggers.append("hazmat (regulatory)") }
        if let r = draft.rate, r > 5000 { triggers.append("rate > $5,000 (escrow)") }
        if draft.vertical == .heavyHaulSpecialized { triggers.append("heavy haul (escort + permits)") }
        return "Auto-engaged: \(triggers.joined(separator: " · ")). Disabling overrides the platform default — you'll be liable if settlement releases against an unverified POD."
    }

    // ── T-009 (canonical documents lock-in, 2026-05-20) ─────────────
    // Renders `DocumentRequirements.forShipment(vertical:isCrossBorder:)`.
    // Each row shows: document name, regulatory citation (49 CFR / USMCA /
    // etc.), the FSM state where it's required, a blocking pill, and a
    // checkbox to mark on-file. Documents needed at DRAFT / POSTED with
    // `blocking == true` gate the Post-load button below; later-state
    // docs (LOADED / DELIVERED) ride along for catalyst visibility but
    // don't block the marketplace post.
    private var documentsRequiredCard: some View {
        LifecycleCard {
            LifecycleSection(label: "REQUIRED DOCUMENTS", icon: "doc.text.fill")
            if draft.requiredDocuments.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text("Pick a vertical on Step 2 to see the canonical document checklist for this load.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                // Pre-flight gate summary header
                let total = draft.preFlightBlockingDocs.count
                let attached = draft.preFlightBlockingDocs.filter {
                    draft.attachedDocuments.contains($0.document)
                }.count
                HStack(spacing: 6) {
                    Image(systemName: draft.canPostMarketplace ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(draft.canPostMarketplace ? Brand.success : Brand.warning)
                    Text(draft.canPostMarketplace
                         ? "All pre-flight documents on file"
                         : "Pre-flight: \(attached) of \(total) blocking documents on file")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                }
                ForEach(draft.requiredDocuments, id: \.document) { req in
                    docRow(req)
                }
                Text("Pre-flight blockers must be uploaded before posting. Later-FSM docs (LOADED / DELIVERED) are enforced by the load lifecycle when the driver advances state.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func docRow(_ req: DocumentRequirement) -> some View {
        let on = draft.attachedDocuments.contains(req.document)
        let isPreFlight = req.requiredAt == .draft || req.requiredAt == .posted
        let isBlocker   = req.blocking && isPreFlight
        Button {
            if on {
                draft.attachedDocuments.remove(req.document)
            } else {
                draft.attachedDocuments.insert(req.document)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(on ? Brand.success : palette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(docLabel(req.document))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.85)
                    HStack(spacing: 4) {
                        Text("AT \(req.requiredAt.rawValue)")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        if req.blocking {
                            Text("BLOCKING")
                                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(isPreFlight ? Brand.warning : palette.textTertiary)
                                .clipShape(Capsule())
                        }
                        if let ref = req.regulatoryRef {
                            Text(ref)
                                .font(.system(size: 8, weight: .semibold)).tracking(0.4)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1).minimumScaleFactor(0.85)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isBlocker || on ? 1.0 : 0.85)
    }

    /// Human-readable label for the document type — keeps the canonical
    /// rawValue stable for the server while presenting a Title Case label.
    private func docLabel(_ d: DocumentType) -> String {
        switch d {
        case .billOfLading:                   return "Bill of Lading"
        case .rateConfirmation:               return "Rate Confirmation"
        case .commercialInvoice:              return "Commercial Invoice"
        case .packingList:                    return "Packing List"
        case .proofOfDelivery:                return "Proof of Delivery"
        case .insuranceCertificate:           return "Insurance Certificate"
        case .hazmatManifest:                 return "Hazmat Manifest (172.201)"
        case .shippingPapers:                 return "Shipping Papers"
        case .ergInfo:                        return "ERG Emergency Response Info"
        case .driverHazmatTrainingCert:       return "Driver Hazmat Training Cert"
        case .segregationVerification:        return "Segregation Verification (177.848)"
        case .tankWashCertificate:            return "Tank Wash Certificate"
        case .priorCommodityHistory:          return "Prior 3 Commodities"
        case .vaporRecoveryDeclaration:       return "Vapor Recovery Declaration"
        case .temperatureSetpoint:            return "Temperature Setpoint"
        case .fsmaCertificate:                return "FSMA Certificate"
        case .coldChainAttestation:           return "Cold Chain Attestation"
        case .foodGradeWashCert:              return "Food-Grade Wash Certificate"
        case .securementLog:                  return "Securement Log (393)"
        case .tarpInventory:                  return "Tarp Inventory"
        case .strapWLLLog:                    return "Strap WLL Log"
        case .vehicleConditionReport:         return "Vehicle Condition Report"
        case .uiiaInterchangeAgreement:       return "UIIA Interchange Agreement"
        case .equipmentInterchangeReceipt:    return "Equipment Interchange Receipt"
        case .containerSealLog:               return "Container Seal Log"
        case .nmfcFreightClassDeclaration:    return "NMFC Freight Class"
        case .osowPermits:                    return "OS/OW Permits"
        case .escortAgreement:                return "Escort Agreement"
        case .routeSurvey:                    return "Route Survey"
        case .bridgeClearanceDeclaration:     return "Bridge Clearance Declaration"
        case .usdaHealthCertificate:          return "USDA Health Certificate"
        case .animalWelfareCert:              return "Animal Welfare Cert"
        case .livestock28HrLog:               return "Livestock 28-Hour Log"
        case .kosherCertificate:              return "Kosher Certificate"
        case .halalCertificate:               return "Halal Certificate"
        case .hhgBillOfLading_375:            return "HHG Bill of Lading (49 CFR 375)"
        case .householdInventory:             return "Household Inventory"
        case .valuationDeclaration:           return "Valuation Declaration"
        case .customerReleaseAuthorization:   return "Customer Release Authorization"
        case .usmcaCertificateOfOrigin:       return "USMCA Certificate of Origin"
        case .pedimentoMx:                    return "Pedimento (MX)"
        case .cartaPorte:                     return "Carta Porte (MX SAT)"
        case .manifestUsAce:                  return "Manifest (US ACE)"
        case .rppCaCarm:                      return "RPP (CA CARM)"
        case .importExportLicense:            return "Import/Export License"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("POST A LOAD · STEP 4 · REVIEW")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("Confirm and post.")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.75)
        }
    }

    private var modeAndCountryCard: some View {
        LifecycleCard {
            LifecycleSection(label: "MODE + LANE", icon: "globe.americas.fill")
            LifecycleRow(label: "Mode",        value: draft.mode.label)
            LifecycleRow(label: "Origin",      value: "\(draft.originCountry.flag) \(draft.originCountry.label)")
            LifecycleRow(label: "Destination", value: "\(draft.destinationCountry.flag) \(draft.destinationCountry.label)")
            if draft.isCrossBorder {
                Text(draft.isUSMCA ? "Cross-border · USMCA-eligible" : "Cross-border")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
        }
    }

    private var laneCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LANE", icon: "map")
            LifecycleRow(label: "Origin",      value: dashIfEmpty(draft.origin))
            LifecycleRow(label: "Destination", value: dashIfEmpty(draft.destination))
            LifecycleRow(label: "Pickup",      value: draft.pickupDate.map(formatDate) ?? "—")
            LifecycleRow(label: "Delivery",    value: draft.deliveryDate.map(formatDate) ?? "—")
        }
    }

    private var equipmentCard: some View {
        LifecycleCard {
            LifecycleSection(label: "EQUIPMENT", icon: "shippingbox")
            LifecycleRow(label: "Cargo type",  value: draft.cargoType.label)
            LifecycleRow(label: "Equipment",   value: dashIfEmpty(draft.equipmentType))
            LifecycleRow(label: "Weight",      value: draft.weight.map { "\(Int($0)) lb" } ?? "—")
            LifecycleRow(label: "Commodity",   value: dashIfEmpty(draft.commodity))
        }
    }

    private var pricingCard: some View {
        LifecycleCard {
            LifecycleSection(label: "PRICING", icon: "dollarsign.circle")
            LifecycleRow(label: "Target rate", value: usd(draft.rate))
            LifecycleRow(label: "FSC %",       value: draft.fuelSurchargeRate.map { String(format: "%.1f%%", $0) } ?? "—")
            if !draft.accessorialsAllowed.isEmpty {
                LifecycleRow(label: "Accessorials", value: draft.accessorialsAllowed.joined(separator: ", "))
            }
            if !draft.notes.isEmpty {
                LifecycleRow(label: "Notes", value: draft.notes)
            }
        }
    }

    private var hazmatCard: some View {
        LifecycleCard(accentWarning: true) {
            LifecycleSection(label: "HAZMAT", icon: "triangle.fill")
            LifecycleRow(label: "UN",       value: dashIfEmpty(draft.unNumber))
            LifecycleRow(label: "Class",    value: dashIfEmpty(draft.hazmatClass))
            LifecycleRow(label: "PG",       value: dashIfEmpty(draft.packingGroup))
            LifecycleRow(label: "PSN",      value: dashIfEmpty(draft.properShippingName))
            LifecycleRow(label: "ERG",      value: draft.ergGuide.map { "#\($0)" } ?? "—")
            LifecycleRow(label: "CHEMTREC", value: dashIfEmpty(draft.chemtrecPhone))
            // Country-specific regulatory frames
            switch (draft.originCountry, draft.destinationCountry) {
            case (.US, _), (_, .US): LifecycleRow(label: "US 49 CFR", value: "Required")
            case (.MX, _), (_, .MX): LifecycleRow(label: "MX NOM",    value: "Required")
            case (.EU, _), (_, .EU): LifecycleRow(label: "EU ADR",    value: "Required")
            default: EmptyView()
            }
            if draft.mode == .vessel {
                LifecycleRow(label: "IMDG", value: "Required")
            }
        }
    }

    private var reeferCard: some View {
        LifecycleCard {
            LifecycleSection(label: "REEFER", icon: "thermometer")
            if let lo = draft.reeferTempLow, let hi = draft.reeferTempHigh {
                LifecycleRow(label: "Setpoint", value: "\(Int(lo))–\(Int(hi))°F")
            } else {
                LifecycleRow(label: "Setpoint", value: "—")
            }
            LifecycleRow(label: "Pre-cool", value: draft.preCoolRequired ? "Required" : "Not required")
            LifecycleRow(label: "Mode",     value: draft.continuousMode ? "Continuous" : "Cycle-sentry")
        }
    }

    private var stopsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "STOPS", icon: "list.number")
            ForEach(draft.stops) { stop in
                LifecycleRow(label: "\(stop.sequence). \(stop.address)", value: stop.appointmentISO ?? "—")
            }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
                Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
                Spacer(minLength: 0)
            }
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "252"])
            } label: {
                Text("Back").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                // T-010 · 2026-05-20 — confirmation gate. Trigger the
                // .confirmationDialog on the outer ScrollView instead of
                // firing draft.submit() directly. The dialog's "Post load"
                // action runs the submit; "Cancel" is a no-op.
                showConfirmDialog = true
            } label: {
                HStack(spacing: 6) {
                    if draft.isPosting { ProgressView().tint(.white) }
                    Text(postButtonLabel)
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(draft.canPostMarketplace
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.textTertiary))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(draft.isPosting || !draft.canPostMarketplace)
        }
    }

    /// T-009 (2026-05-20) — Post-load button copy reflects which gate is
    /// stopping the submit so the user knows what to fix. Order of
    /// precedence: in-flight network call → missing pre-flight docs →
    /// vertical not picked → ready.
    private var postButtonLabel: String {
        if draft.isPosting { return "Posting…" }
        if draft.vertical == nil { return "Pick vertical on Step 2" }
        if !draft.canPostMarketplace {
            let missing = draft.preFlightBlockingDocs.filter {
                !draft.attachedDocuments.contains($0.document)
            }.count
            return "Attach \(missing) blocking doc\(missing == 1 ? "" : "s")"
        }
        return "Post load"
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · HH:mm"
        return f.string(from: d)
    }
}

#Preview("253 · Review · Night") {
    PostLoadStep4ReviewScreen(theme: Theme.dark, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("253 · Review · Afternoon") {
    PostLoadStep4ReviewScreen(theme: Theme.light, draft: PostLoadDraft())
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
