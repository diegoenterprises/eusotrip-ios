//
//  096_MeErg.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · ERG Hazmat Lookup)
//
//  Screen 096 · Me · ERG Lookup — the driver's in-app Emergency
//  Response Guidebook. This digital lookup supplements required
//  emergency-response information; PHMSA does not permit an
//  electronic ERG to replace the required hard-copy document.
//
//  Flow:
//    1. Emergency contact strip — CHEMTREC + National Response
//       Center + Poison + 911, all tappable to dial.
//    2. Search by UN number or material name. Results show guide
//       number + hazard class + TIH/WR flags.
//    3. Tap result → full detail sheet with the ERG guide page
//       (potential hazards / public safety / emergency response)
//       plus TIH initial isolation / protective action distances.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • All material rows + guide text + protective distances ship
//      from `erg.search` / `erg.searchByUN` — MCP-verified at
//      `frontend/server/routers/erg.ts`. Server is backed by the
//      canonical ERG material table + guide pages.
//    • Emergency contacts ship from `erg.getEmergencyContacts` —
//      server-authoritative phone numbers. We do NOT hard-code
//      1-800-424-9300 client-side; the driver sees whatever the
//      server shipped (which matches the current ERG printing).
//    • No fabricated UN numbers, no placeholder guide text.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on CHEMTREC CTA (it's the one the
//         driver calls on an actual release). Brand.warning on TIH
//         flag. Brand.magenta on WR flag.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeErg: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL
    @StateObject private var store = ErgStore()

    @State private var detailPresented: String?
    @AppStorage("ergIncidentCountry") private var incidentCountry = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                searchBar
                emergencyStrip
                resultsSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await refreshContacts() }
        .refreshable {
            await store.refresh(
                countryCode: selectedIncidentCountry,
                force: true
            )
        }
        .sheet(
            isPresented: Binding(
                get: { detailPresented != nil },
                set: { if !$0 { detailPresented = nil; store.clearDetail() } }
            )
        ) {
            if let un = detailPresented {
                ErgDetailSheet(unNumber: un, store: store)
                    .eusoSheetX()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("ERG Lookup")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ERG 2024 · Emergency response reference")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.textTertiary)
            TextField("UN number or material name", text: $store.query)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .onChange(of: store.query) { _, _ in
                    store.scheduleSearch()
                }
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                    store.scheduleSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.45))
        )
    }

    // MARK: Emergency contacts

    @ViewBuilder
    private var emergencyStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("EMERGENCY CONTACTS")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                incidentCountryPicker
            }

            if store.isLoading && store.contacts == nil {
                HStack(spacing: Space.s2) {
                    ProgressView()
                    Text("Loading verified contacts…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(Space.s3)
            } else if let response = store.contacts {
                if response.status == "available" {
                    if let phone = response.localEmergencyServices.phone {
                        localEmergencyCard(
                            response.localEmergencyServices,
                            phone: phone
                        )
                    }
                    ForEach(response.contacts) { contact in
                        contactCard(contact)
                    }
                } else {
                    EusoEmptyState(
                        systemImage: "globe.americas.fill",
                        title: "Select the incident country",
                        subtitle: "Emergency references are jurisdiction-specific."
                    )
                }

                Text(response.warning)
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.s1)
            } else if let error = store.lastError {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(ergFailureCopy_096(error, noun: "emergency contact list"))
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                    Button {
                        Task {
                            await store.refresh(
                                countryCode: selectedIncidentCountry,
                                force: true
                            )
                        }
                    } label: {
                        Label("Retry contacts", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var incidentCountryPicker: some View {
        Picker(
            "Incident country",
            selection: Binding(
                get: { incidentCountry },
                set: { country in
                    incidentCountry = country
                    Task {
                        await store.refresh(
                            countryCode: country.isEmpty ? nil : country,
                            force: true
                        )
                    }
                }
            )
        ) {
            Text("Select").tag("")
            Text("US").tag("US")
            Text("Canada").tag("CA")
            Text("México").tag("MX")
        }
        .pickerStyle(.menu)
        .font(EType.caption)
    }

    private func localEmergencyCard(
        _ contact: ErgAPI.LocalEmergencyServices,
        phone: String
    ) -> some View {
        Button { callNumber(phone) } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: "phone.fill.arrow.up.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                    Text("Police · Fire · EMS")
                        .font(EType.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(phone)
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("TAP TO CALL")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(LinearGradient.diagonal)
            )
        }
        .buttonStyle(.plain)
    }

    private func contactCard(_ contact: ErgAPI.EmergencyContact) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Button { callNumber(contact.phone) } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text(contact.description)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.leading)
                        Text(([contact.phone] + contact.alternatePhones).joined(separator: " · "))
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "phone.arrow.up.right")
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if let restriction = contact.usageRestriction {
                Text(restriction)
                    .font(EType.micro)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let source = URL(string: contact.sourceUrl) {
                Link(destination: source) {
                    Label("Official source · verified \(contact.verifiedAt)", systemImage: "checkmark.seal")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md)
    }

    private func callNumber(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel:\(digits)") else { return }
        openURL(url)
    }

    @MainActor
    private func refreshContacts() async {
        await store.refresh(countryCode: selectedIncidentCountry)
        if incidentCountry.isEmpty, let resolved = store.contacts?.countryCode {
            incidentCountry = resolved
        }
    }

    private var selectedIncidentCountry: String? {
        let normalized = incidentCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    // MARK: Results

    @ViewBuilder
    private var resultsSection: some View {
        if store.query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("RESULTS")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                if store.results.isEmpty {
                    EusoEmptyState(
                        systemImage: "magnifyingglass",
                        title: "No match",
                        subtitle: "Try a UN number (e.g. 1203 for gasoline) or a partial material name."
                    )
                } else {
                    ForEach(store.results) { hit in
                        Button {
                            detailPresented = hit.unNumber
                        } label: {
                            resultRow(hit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else if !store.isLoading {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("START TYPING")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Text("Search the official ERG 2024 response reference by UN number or material name. Verify legal classification and required shipping-paper information from the controlling transport documents.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .eusoCard(radius: Radius.md)
            }
        }
    }

    private func resultRow(_ hit: ErgAPI.SearchHit) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.22))
                Text("\(hit.guide)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text("UN\(hit.unNumber)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
                Text(hit.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if hit.classificationEvidence?.eligibleAsClassificationSource == true,
                   let hazardClass = hit.hazardClass,
                   !hazardClass.isEmpty {
                    HStack(spacing: 4) {
                        Text("Class \(hazardClass)")
                        if let placardName = hit.placardName, !placardName.isEmpty {
                            Text("·")
                            Text(placardName)
                        }
                    }
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                } else {
                    Text("Response reference only · classification verified separately")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if hit.isTIH == true {
                    flagChip("TIH", color: Brand.warning)
                }
                if hit.isWR == true {
                    flagChip("WR", color: Brand.magenta)
                }
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    private func flagChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(EType.micro)
            .tracking(1.2)
            .foregroundStyle(color)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .center, spacing: 4) {
            Text("TIH · Toxic by Inhalation · requires greater protective distances")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
            Text("WR · Dangerous When Wet")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
            Text("Digital ERG is supplemental. Keep the required printed emergency-response information with the shipping paper.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, Space.s1)
        }
        .padding(.horizontal, Space.s2)
    }
}

// MARK: - Detail sheet

private struct ErgDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) var palette
    let unNumber: String
    @ObservedObject var store: ErgStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if let d = store.detail, d.found == true {
                        heroCard(d)
                        // Full structured handbook layout when the
                        // server emits guideFull (every UN since
                        // 2026-05-05 deploy). Falls through to the
                        // flat guide view for older legacy entries.
                        if let g = d.guideFull {
                            healthSection(g)
                            fireExplosionSection(g)
                            isolationSection(g)
                            evacuationSection(g)
                            fireResponseSection(g)
                            spillResponseSection(g)
                            firstAidSection(g)
                        } else if let guide = d.guide {
                            guideSection(guide)
                        }
                        if let pd = d.protectiveDistance {
                            protectiveSection(pd)
                        }
                    } else if store.isDetailLoading {
                        loadingState
                    } else if let error = store.lastError {
                        detailErrorState(error)
                    } else {
                        EusoEmptyState(
                            systemImage: "questionmark.circle",
                            title: "UN\(unNumber) not in ERG",
                            subtitle: "Double-check the number on the shipping paper / placard."
                        )
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s4)
            }
            .navigationTitle("UN\(unNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: unNumber) {
                if store.detail == nil && !store.isDetailLoading {
                    await store.loadDetail(unNumber: unNumber)
                }
            }
        }
    }

    private func heroCard(_ d: ErgAPI.MaterialDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(d.name ?? "UN\(unNumber)")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    if let alt = d.alternateNames, !alt.isEmpty {
                        Text(alt.joined(separator: " · "))
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                if let guide = d.guideNumber {
                    VStack(spacing: 2) {
                        Text("GUIDE")
                            .font(EType.micro)
                            .tracking(1.3)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(guide)")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                    }
                }
            }
            HStack(spacing: Space.s2) {
                if d.classificationEvidence?.eligibleAsClassificationSource == true,
                   let cls = d.hazardClass {
                    chip("Class \(cls)", color: palette.textSecondary, stroked: true)
                }
                if d.classificationEvidence?.eligibleAsClassificationSource == true,
                   let placard = d.placard,
                   !placard.isEmpty {
                    chip(placard, color: palette.textSecondary, stroked: true)
                }
                if d.isTIH == true {
                    chip("TIH", color: Brand.warning, stroked: true)
                }
                if d.isWR == true {
                    chip("WR", color: Brand.magenta, stroked: true)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    @ViewBuilder
    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
            Text("Loading UN\(unNumber) from the ERG handbook…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
    }

    private func detailErrorState(_ error: Error) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Brand.warning)
            Text("ERG lookup unavailable")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text(ergFailureCopy_096(error, noun: "ERG entry"))
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.loadDetail(unNumber: unNumber) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
    }

    // MARK: - Full ERG handbook sections

    @ViewBuilder
    private func healthSection(_ g: ErgAPI.GuideFull) -> some View {
        if !g.health.isEmpty {
            ergSection(
                label: "HEALTH HAZARDS",
                icon: "cross.case.fill",
                tint: Brand.magenta,
                bullets: g.health
            )
        }
    }

    @ViewBuilder
    private func fireExplosionSection(_ g: ErgAPI.GuideFull) -> some View {
        if !g.fireExplosion.isEmpty {
            ergSection(
                label: "FIRE / EXPLOSION",
                icon: "flame.fill",
                tint: Brand.warning,
                bullets: g.fireExplosion
            )
        }
    }

    @ViewBuilder
    private func isolationSection(_ g: ErgAPI.GuideFull) -> some View {
        let hasIso = (g.isolationDistanceMeters ?? 0) > 0
        let hasFire = (g.fireIsolationMeters ?? 0) > 0
        if hasIso || hasFire {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("ISOLATION DISTANCES")
                        .font(EType.micro).tracking(1.3)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                HStack(spacing: Space.s2) {
                    if hasIso {
                        isoTile(
                            label: "INITIAL",
                            meters: g.isolationDistanceMeters ?? 0,
                            feet: g.isolationDistanceFeet ?? 0,
                            color: Brand.warning
                        )
                    }
                    if hasFire {
                        isoTile(
                            label: "FIRE",
                            meters: g.fireIsolationMeters ?? 0,
                            feet: g.fireIsolationFeet ?? 0,
                            color: Brand.danger
                        )
                    }
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md)
        }
    }

    private func isoTile(label: String, meters: Int, feet: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(color)
            Text("\(meters)m")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text("\(feet) ft")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(color.opacity(0.3))
        )
    }

    @ViewBuilder
    private func evacuationSection(_ g: ErgAPI.GuideFull) -> some View {
        if g.protectiveClothing != nil || g.evacuationNotes != nil {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "person.line.dotted.person.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                    Text("PUBLIC SAFETY")
                        .font(EType.micro).tracking(1.3)
                        .foregroundStyle(Brand.warning)
                }
                if let pc = g.protectiveClothing, !pc.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protective clothing")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(pc)
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let ev = g.evacuationNotes, !ev.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Evacuation")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(ev)
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md)
        }
    }

    @ViewBuilder
    private func fireResponseSection(_ g: ErgAPI.GuideFull) -> some View {
        if !g.fireSmall.isEmpty || !g.fireLarge.isEmpty || !g.fireTank.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "flame")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                    Text("FIRE RESPONSE")
                        .font(EType.micro).tracking(1.3)
                        .foregroundStyle(Brand.danger)
                }
                if !g.fireSmall.isEmpty { responseBlock(title: "SMALL FIRE", bullets: g.fireSmall) }
                if !g.fireLarge.isEmpty { responseBlock(title: "LARGE FIRE", bullets: g.fireLarge) }
                if !g.fireTank.isEmpty  { responseBlock(title: "TANK FIRE",  bullets: g.fireTank) }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md)
        }
    }

    @ViewBuilder
    private func spillResponseSection(_ g: ErgAPI.GuideFull) -> some View {
        if !g.spillGeneral.isEmpty || !g.spillSmall.isEmpty || !g.spillLarge.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.info)
                    Text("SPILL / LEAK")
                        .font(EType.micro).tracking(1.3)
                        .foregroundStyle(Brand.info)
                }
                if !g.spillGeneral.isEmpty { responseBlock(title: "GENERAL", bullets: g.spillGeneral) }
                if !g.spillSmall.isEmpty   { responseBlock(title: "SMALL",   bullets: g.spillSmall) }
                if !g.spillLarge.isEmpty   { responseBlock(title: "LARGE",   bullets: g.spillLarge) }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md)
        }
    }

    @ViewBuilder
    private func firstAidSection(_ g: ErgAPI.GuideFull) -> some View {
        if !g.firstAid.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "cross.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.success)
                    Text("FIRST AID")
                        .font(EType.micro).tracking(1.3)
                        .foregroundStyle(Brand.success)
                }
                ForEach(Array(g.firstAid.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.md)
        }
    }

    private func responseBlock(title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, b in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundStyle(palette.textSecondary)
                    Text(b)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Shared section frame used by health + fire/explosion (single
    /// bullet list with colored accent stripe).
    private func ergSection(
        label: String,
        icon: String,
        tint: Color,
        bullets: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(tint)
                Text(label)
                    .font(EType.micro).tracking(1.3)
                    .foregroundStyle(tint)
            }
            ForEach(Array(bullets.enumerated()), id: \.offset) { _, b in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(tint)
                    Text(b)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md)
    }

    private func guideSection(_ g: ErgAPI.GuideDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let title = g.title, !title.isEmpty {
                Text(title.uppercased())
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
            }
            if let items = g.potentialHazards, !items.isEmpty {
                guideBlock(title: "POTENTIAL HAZARDS", items: items, tint: Brand.magenta)
            }
            if let items = g.publicSafety, !items.isEmpty {
                guideBlock(title: "PUBLIC SAFETY", items: items, tint: Brand.warning)
            }
            if let items = g.emergencyResponse, !items.isEmpty {
                guideBlock(title: "EMERGENCY RESPONSE", items: items, tint: .green)
            }
        }
    }

    private func guideBlock(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 4) {
                Rectangle().fill(tint).frame(width: 3, height: 14)
                Text(title)
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(tint)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(tint)
                    Text(item)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md)
    }

    @ViewBuilder
    private func protectiveSection(_ pd: ErgAPI.ProtectiveDistance) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PROTECTIVE DISTANCES (TIH)")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            protectiveRow(label: "Small spill", row: pd.smallSpill)
            if pd.refTable3 == true {
                Text("Large spill distances require the actual Table 3 container type and current wind conditions.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .padding(Space.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .eusoCard(radius: Radius.md)
            } else {
                protectiveRow(label: "Large spill", row: pd.largeSpill)
            }
        }
    }

    private func protectiveRow(
        label: String,
        row: ErgAPI.ProtectiveDistance.SpillRow
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: Space.s3) {
                pdValue(title: "ISOLATE", value: "\(row.day.isolateMeters) m")
                pdValue(title: "DAY DOWNWIND", value: formatProtectiveDistance(row.day))
                pdValue(title: "NIGHT DOWNWIND", value: formatProtectiveDistance(row.night))
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.md)
    }

    private func formatProtectiveDistance(
        _ value: ErgAPI.ProtectiveDistance.DistanceValue
    ) -> String {
        let kilometers = value.protectKm.formatted(
            .number.precision(.fractionLength(0...1))
        )
        return "\(kilometers)\(value.mayBeLarger == true ? "+" : "") km"
    }

    private func pdValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
        }
    }

    private func chip(_ text: String, color: Color, stroked: Bool) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.1)
            .foregroundStyle(color)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(color.opacity(0.7), lineWidth: 1))
    }
}

// MARK: - Screen wrapper

struct MeErgScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeErg()
        } nav: {
            BottomNav(
                leading: driverNavLeading_096(),
                trailing: driverNavTrailing_096(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_096() -> [NavSlot] {
    RoleNav.driverLeading(current: .none)
}
private func driverNavTrailing_096() -> [NavSlot] {
    RoleNav.driverTrailing(current: .me)
}

// MARK: - Previews

#Preview("096 · ERG · Night") {
    MeErgScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("096 · ERG · Afternoon") {
    MeErgScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}

// MARK: - Operator-facing failure copy

/// Operator-language reason an emergency-response lookup failed.
///
/// This screen is used at the roadside during a hazmat incident, so the
/// copy never dead-ends: every branch names the fallback the driver
/// should use right now. The caught error stays available for logging;
/// the driver never sees a raw `NSError` description. `noun` names what
/// failed ("ERG entry", "emergency contact list").
fileprivate func ergFailureCopy_096(_ error: Error, noun: String) -> String {
    let fallback = "If this is an active incident, call 911 first, then CHEMTREC at +1-800-424-9300."
    if let api = error as? EusoTripAPIError {
        switch api {
        case .unauthenticated:
            return "Your session expired, so the \(noun) couldn't load. Sign in again. \(fallback)"
        case .forbidden(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "This account can't open the \(noun). \(fallback)"
                : "\(trimmed) \(fallback)"
        case .trpcError(let reason):
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "The \(noun) couldn't be retrieved. Retry. \(fallback)"
                : "\(trimmed) \(fallback)"
        case .httpStatus(let code, _):
            return "The \(noun) didn't load (code \(code)). Retry. \(fallback)"
        case .decodingFailed:
            return "The \(noun) came back in a form this build can't read, so nothing here is verified. Update the app. \(fallback)"
        case .empty:
            return "No \(noun) came back for this selection. Retry. \(fallback)"
        case .notConfigured, .badURL:
            return "This device isn't set up for live emergency references yet. Restart the app. \(fallback)"
        case .queuedForOfflineReplay:
            return "You're offline, so the \(noun) isn't verified right now. \(fallback)"
        }
    }
    if (error as NSError).domain == NSURLErrorDomain {
        return "No connection, so the \(noun) couldn't be verified. \(fallback)"
    }
    return "The \(noun) didn't load. Retry. \(fallback)"
}
