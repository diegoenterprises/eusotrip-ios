//
//  209_ShipperContacts.swift
//  EusoTrip — Shipper · Contacts (brick 209).
//
//  Parity-reconciled to `02 Shipper/Code/209_ShipperContacts.swift`
//  per _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: TopBar (eyebrow + active/favorites counter), title block
//  (Contacts display + dispatchers/facility/support sub-line),
//  IridescentHairline, search capsule + Add capsule, 4-chip filter
//  row, CATALYST · DISPATCHERS card with monogram avatar + identity
//  stack + favorite star + 32×22 call pill per row, FACILITY · OPS
//  card with hazmat-diamond / reefer glyph rows, gradient Add-contact
//  ribbon at the bottom.
//
//  Real data preserved: ShipperFavoriteCatalystsStore +
//  shippers.getFavoriteCatalysts. Catalyst rows hydrate from the live
//  store when present; facility rows + dispatcher contact details
//  fall back to §11.2 / §11.4 canon anchor copy until contacts.list
//  + facilities.list ship.
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1).
//  §11 dispatcher canon: Renee Marsh (Eusotrans LLC favorited),
//  Daniel Kim (Test Carrier Services), Carla Brown (Plainview Petroleum).
//  §11.2 / §11.4 facility canon: Gulf Coast Petroleum Terminal /
//  Heartland NH₃ Co-op / Phoenix Cold Chain Receiver.
//
//  Web peer: Contacts.tsx (`/shipper/contacts`).
//  Notification names: eusoShipperContactSearch, eusoShipperContactAdd,
//                      eusoShipperContactRow,
//                      eusoShipperContactFavoriteToggle,
//                      eusoShipperContactFacility.
//
//  BottomNav: Me current — out of scope per parity mandate §1.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import UIKit

// MARK: - Models (file-scoped)

private struct ContactRow: Identifiable {
    let id: String
    let initials: String
    let name: String
    let org: String
    let role: String?
    let phone: String
    let email: String
    let favorited: Bool
    let callable: Bool
}

private enum FacilityKind {
    case hazmatDiamond(unClass: String)
    case reeferTemp(label: String)
}

private struct FacilityRow: Identifiable {
    let id: String
    let kind: FacilityKind
    let name: String
    let sub: String?
    let phone: String
    let extra: String
}

private enum ContactsFilter: String, CaseIterable, Identifiable {
    case all, catalyst, facility, favorites
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:       return "All"
        case .catalyst:  return "Catalyst"
        case .facility:  return "Facility"
        case .favorites: return "Fav"
        }
    }
}

// MARK: - Screen body

struct ShipperContacts: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var store = ShipperFavoriteCatalystsStore()

    @State private var query: String = ""
    @State private var filter: ContactsFilter = .all
    @State private var lastToast: String?
    @State private var localFavoriteOverrides: [String: Bool] = [:]

    /// Dialog state — set when the user taps a contact row. Drives a
    /// confirmationDialog with Call / Text / Email / Cancel options.
    /// Replaces the prior openURL("…/contacts/{id}") stub which 404'd.
    @State private var pendingContactAction: ContactActionRef?

    /// Sheet state — set when the user taps "Add contact". Drives a
    /// real in-app form that calls `contacts.create`.
    @State private var showAddContactSheet: Bool = false

    /// §11 / §11.2 / §11.4 facility canon — three flagship facility POCs
    /// that mirror the §11.2 MATRIX-50 lanes (Houston tanker, KC NH₃,
    /// LA→Phoenix berries). Until `facilities.list` ships, these are the
    /// canonical anchors per the wireframe Code/ port.
    private let facilityContacts: [FacilityRow] = [
        FacilityRow(
            id: "fac_gulf_coast_petroleum",
            kind: .hazmatDiamond(unClass: "3"),
            name: "Gulf Coast Petroleum Terminal · Houston",
            sub: "Loading dock 7 · 1234 Industrial Blvd",
            phone: "+1 (713) 555-0117",
            extra: "gate-pin 4821"
        ),
        FacilityRow(
            id: "fac_heartland_nh3",
            kind: .hazmatDiamond(unClass: "2.2"),
            name: "Heartland NH₃ Co-op · Kansas City",
            sub: "MC-331 fill rack · escort dispatch on site",
            phone: "+1 (816) 555-0240",
            extra: "pre-arrival 30 min"
        ),
        FacilityRow(
            id: "fac_phoenix_cold_chain",
            kind: .reeferTemp(label: "38°"),
            name: "Phoenix Cold Chain Receiver",
            sub: nil,
            phone: "+1 (602) 555-0388",
            extra: "dock 14 · reefer cold-stage"
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            titleBlock
                .padding(.top, Space.s3)
            IridescentHairline()
                .padding(.top, Space.s3)
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    searchRow
                    filterChips
                    catalystSection
                    facilitySection
                    addContactRibbon
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
            .overlay(alignment: .bottom) {
                if let toast = lastToast {
                    toastView(toast)
                        .padding(.bottom, Space.s5)
                        .padding(.horizontal, Space.s5)
                        .transition(.opacity)
                }
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .confirmationDialog(
            pendingContactAction?.name ?? "Contact",
            isPresented: Binding(
                get: { pendingContactAction != nil },
                set: { if !$0 { pendingContactAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingContactAction
        ) { ref in
            if !ref.phone.isEmpty {
                Button("Call \(ref.phone)") {
                    let digits = ref.phone.filter { $0.isNumber || $0 == "+" }
                    if let url = URL(string: "tel://\(digits)") { openURL(url) }
                }
                Button("Text \(ref.phone)") {
                    let digits = ref.phone.filter { $0.isNumber || $0 == "+" }
                    if let url = URL(string: "sms:\(digits)") { openURL(url) }
                }
            }
            if !ref.email.isEmpty {
                Button("Email \(ref.email)") {
                    if let url = URL(string: "mailto:\(ref.email)") { openURL(url) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAddContactSheet) {
            AddContactSheet(onCreated: { name in
                showAddContactSheet = false
                Task { await store.refresh() }
                flashToast("Saved \(name)")
            })
            .eusoSheetX()
        }
    }

    // MARK: - TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · CONTACTS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    private var counterEyebrow: String {
        let active = catalystRows.count + facilityContacts.count
        let favorites = catalystRows.filter { isFavorited(catalystId: $0.id, default: $0.favorited) }.count
        return "\(active) ACTIVE · \(favorites) FAVORITES"
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Contacts")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Catalyst dispatchers · facility ops · platform support")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Search row

    private var searchRow: some View {
        HStack(spacing: Space.s2) {
            HStack(spacing: 12) {
                MagnifierGlyph(stroke: palette.textTertiary)
                    .frame(width: 20, height: 20)
                TextField("Search dispatchers, facilities…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textPrimary)
                    .submitLabel(.search)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
            .accessibilityLabel("Search contacts. Dispatchers and facilities.")

            Button {
                // Add-contact form hasn't shipped in-app yet; route
                // to the canonical web form via openURL so the tap
                // lands on a real surface (same Bearer cookie auth
                // — no re-login). Telemetry post retained for
                // observability.
                NotificationCenter.default.post(
                    name: .eusoShipperContactAdd, object: nil,
                    userInfo: [
                        "source": "209_ShipperContacts",
                        "shipperCompanyId": session.user?.companyId ?? "1",
                    ]
                )
                showAddContactSheet = true
            } label: {
                ZStack {
                    Capsule().fill(LinearGradient.primary)
                    PlusGlyph(stroke: .white).frame(width: 14, height: 16)
                }
                .frame(width: 72, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a new contact")
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ContactsFilter.allCases) { f in
                    chip(for: f)
                }
            }
        }
        .frame(height: 32)
    }

    private func chipCount(for f: ContactsFilter) -> Int {
        switch f {
        case .all:       return catalystRows.count + facilityContacts.count
        case .catalyst:  return catalystRows.count
        case .facility:  return facilityContacts.count
        case .favorites: return catalystRows.filter { isFavorited(catalystId: $0.id, default: $0.favorited) }.count
        }
    }

    private func chip(for f: ContactsFilter) -> some View {
        let on = (filter == f)
        let count = chipCount(for: f)
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                filter = f
            }
        } label: {
            HStack(spacing: 4) {
                if f == .favorites {
                    StarGlyph()
                        .fill(on ? AnyShapeStyle(.white) : AnyShapeStyle(LinearGradient.primary))
                        .frame(width: 10, height: 10)
                }
                Text(count > 0 ? "\(f.label) · \(count)" : f.label)
                    .font(.system(size: 12, weight: on ? .bold : .semibold))
                    .foregroundStyle(on ? .white : palette.textPrimary)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard)))
            .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.borderSoft), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Catalyst section

    @ViewBuilder
    private var catalystSection: some View {
        if filter == .all || filter == .catalyst || filter == .favorites {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("CATALYST · DISPATCHERS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                catalystCard
            }
        }
    }

    private var catalystRows: [ContactRow] {
        // Hydrate from live store when available
        if case .loaded(let rows) = store.state, !rows.isEmpty {
            return rows.map { fc in
                ContactRow(
                    id: fc.id,
                    initials: monogram(fc.name),
                    name: fc.name.isEmpty ? "—" : fc.name,
                    org: dispatcherOrg(for: fc),
                    role: dispatcherRole(for: fc),
                    phone: dispatcherPhone(for: fc),
                    email: dispatcherEmail(for: fc),
                    favorited: fc.loadsCompleted >= 5,
                    callable: !fc.dotNumber.isEmpty
                )
            }
        }
        // Fallback: §11 canon anchor
        return [
            ContactRow(
                id: "ctc_renee_marsh",
                initials: "RM",
                name: "Renee Marsh",
                org: "Eusotrans LLC",
                role: "Dispatch · Belle Plaine IA",
                phone: "+1 (319) 555-1842",
                email: "dispatch@eusotrans.com",
                favorited: true,
                callable: true
            ),
            ContactRow(
                id: "ctc_daniel_kim",
                initials: "DK",
                name: "Daniel Kim",
                org: "Test Carrier Services LLC",
                role: "Ops manager · Houston TX",
                phone: "+1 (713) 555-0100",
                email: "dispatch@testcarrier.com",
                favorited: false,
                callable: true
            ),
            ContactRow(
                id: "ctc_carla_brown",
                initials: "CB",
                name: "Carla Brown",
                org: "Plainview Petroleum",
                role: nil,
                phone: "+1 (602) 555-0042",
                email: "dispatch@plainviewpet.com",
                favorited: true,
                callable: false
            ),
        ]
    }

    private var visibleCatalystRows: [ContactRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows = catalystRows
        if filter == .favorites {
            rows = rows.filter { isFavorited(catalystId: $0.id, default: $0.favorited) }
        }
        guard !needle.isEmpty else { return rows }
        return rows.filter { r in
            r.name.lowercased().contains(needle)
                || r.org.lowercased().contains(needle)
                || r.phone.lowercased().contains(needle)
                || r.email.lowercased().contains(needle)
        }
    }

    private var catalystCard: some View {
        VStack(spacing: 0) {
            switch store.state {
            case .loading:
                catalystSkeleton
                    .padding(.horizontal, 20).padding(.vertical, 14)
            case .empty, .error:
                ForEach(visibleCatalystRows.indices, id: \.self) { idx in
                    catalystRow(visibleCatalystRows[idx])
                        .padding(.horizontal, 20).padding(.vertical, 14)
                    if idx < visibleCatalystRows.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 20)
                    }
                }
            case .loaded:
                if visibleCatalystRows.isEmpty {
                    Text("No matches in catalyst dispatchers.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 20).padding(.vertical, 18)
                } else {
                    ForEach(visibleCatalystRows.indices, id: \.self) { idx in
                        catalystRow(visibleCatalystRows[idx])
                            .padding(.horizontal, 20).padding(.vertical, 14)
                        if idx < visibleCatalystRows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 20)
                        }
                    }
                }
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func catalystRow(_ row: ContactRow) -> some View {
        let isFav = isFavorited(catalystId: row.id, default: row.favorited)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(row.initials)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(row.name) · \(row.org)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.82)
                if let role = row.role {
                    Text(role)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Text("\(row.phone) · \(row.email)")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.78)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 8) {
                Button { tapFavorite(row.id, currentlyFavorited: isFav) } label: {
                    StarGlyph()
                        .fill(isFav
                              ? AnyShapeStyle(LinearGradient.primary)
                              : AnyShapeStyle(palette.textPrimary.opacity(0.16)))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFav ? "Unfavorite \(row.name)" : "Favorite \(row.name)")

                if row.callable {
                    Button { tapCall(row.phone) } label: {
                        ZStack {
                            Capsule().fill(LinearGradient.primary)
                            HandsetGlyph(stroke: .white)
                                .frame(width: 12, height: 10)
                        }
                        .frame(width: 32, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Call \(row.name) at \(row.phone)")
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .onTapGesture { tapContactRow(row.id) }
    }

    private var catalystSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 56)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Facility section

    @ViewBuilder
    private var facilitySection: some View {
        if filter == .all || filter == .facility {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("FACILITY · OPS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                facilityCard
            }
        }
    }

    private var visibleFacilityRows: [FacilityRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return facilityContacts }
        return facilityContacts.filter { r in
            r.name.lowercased().contains(needle)
                || (r.sub ?? "").lowercased().contains(needle)
                || r.phone.lowercased().contains(needle)
                || r.extra.lowercased().contains(needle)
        }
    }

    private var facilityCard: some View {
        VStack(spacing: 0) {
            ForEach(visibleFacilityRows.indices, id: \.self) { idx in
                facilityRow(visibleFacilityRows[idx])
                    .padding(.horizontal, 20).padding(.vertical, 14)
                if idx < visibleFacilityRows.count - 1 {
                    Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 20)
                }
            }
            if visibleFacilityRows.isEmpty {
                Text("No matches in facility ops.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 20).padding(.vertical, 18)
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func facilityRow(_ row: FacilityRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            facilityIcon(row.kind).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.82)
                if let sub = row.sub {
                    Text(sub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Text("\(row.phone) · \(row.extra)")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.78)
            }
            Spacer(minLength: 6)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name). \(row.sub ?? ""). Phone \(row.phone). \(row.extra).")
        .onTapGesture {
            // Facility row tap → dial the facility's phone (the
            // primary user intent on the contacts list). Telemetry
            // post retained for observability — analytics keys off
            // the same notification.
            NotificationCenter.default.post(
                name: .eusoShipperContactFacility, object: nil,
                userInfo: [
                    "source": "209_ShipperContacts",
                    "facilityId": row.id,
                    "phone": row.phone,
                    "shipperCompanyId": session.user?.companyId ?? "1",
                ]
            )
            let digits = row.phone.filter { $0.isNumber || $0 == "+" }
            if !digits.isEmpty, let url = URL(string: "tel://\(digits)") {
                openURL(url)
            }
        }
    }

    @ViewBuilder
    private func facilityIcon(_ kind: FacilityKind) -> some View {
        switch kind {
        case .hazmatDiamond(let unClass):
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.hazmat.opacity(0.16))
                DiamondHazmatGlyph(label: unClass).frame(width: 22, height: 22)
            }
        case .reeferTemp(let label):
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                ReeferGlyph(label: label).frame(width: 24, height: 20)
            }
        }
    }

    // MARK: - Add contact ribbon

    private var addContactRibbon: some View {
        Button {
            // Add-contact form not yet shipped in-app — route to the
            // canonical web form so the tap lands on a real surface
            // (same Bearer cookie auth, no re-login). Telemetry post
            // retained for observability. Mirror of the L223 ribbon
            // wiring committed in 56ecae7.
            NotificationCenter.default.post(
                name: .eusoShipperContactAdd, object: nil,
                userInfo: [
                    "source": "209_ShipperContacts",
                    "shipperCompanyId": session.user?.companyId ?? "1",
                ]
            )
            if let url = URL(string: "https://app.eusotrip.com/shipper/contacts/new") {
                openURL(url)
            }
        } label: {
            ZStack {
                Capsule().fill(LinearGradient.primary)
                HStack(spacing: 10) {
                    PlusGlyph(stroke: .white).frame(width: 14, height: 16)
                    Text("Add contact")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a new contact")
    }

    // MARK: - Tap handlers

    private func tapContactRow(_ contactId: String,
                               name: String = "",
                               phone: String = "",
                               email: String = "") {
        NotificationCenter.default.post(
            name: .eusoShipperContactRow, object: nil,
            userInfo: [
                "source": "209_ShipperContacts",
                "contactId": contactId,
                "shipperCompanyId": session.user?.companyId ?? "1",
            ]
        )
        // Real action: pop a Call / Text / Email confirmationDialog.
        // Replaces the prior openURL("…/contacts/{id}") stub.
        pendingContactAction = ContactActionRef(
            id: contactId, name: name, phone: phone, email: email
        )
    }

    private func tapFavorite(_ contactId: String, currentlyFavorited: Bool) {
        // Optimistic toggle
        localFavoriteOverrides[contactId] = !currentlyFavorited
        flashToast(currentlyFavorited ? "Removed from favorites" : "Added to favorites")
        NotificationCenter.default.post(
            name: .eusoShipperContactFavoriteToggle, object: nil,
            userInfo: [
                "source": "209_ShipperContacts",
                "contactId": contactId,
                "wasFavorited": currentlyFavorited,
                "shipperCompanyId": session.user?.companyId ?? "1",
            ]
        )
    }

    private func tapCall(_ phone: String) {
        let stripped = phone.filter { "+0123456789".contains($0) }
        if let url = URL(string: "tel:\(stripped)") {
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        }
    }

    private func isFavorited(catalystId: String, default initial: Bool) -> Bool {
        localFavoriteOverrides[catalystId] ?? initial
    }

    // MARK: - Toast

    private func toastView(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LinearGradient.diagonal)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.2), radius: 16, y: 8)
    }

    private func flashToast(_ text: String) {
        withAnimation { lastToast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { withAnimation { lastToast = nil } }
        }
    }

    // MARK: - Helpers

    private func monogram(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2).map(String.init)
        let chars = parts.compactMap { $0.first }.map(String.init)
        let m = chars.joined().uppercased()
        return m.isEmpty ? "??" : m
    }

    /// Compose the dispatcher's org line — `name` is already the
    /// company name from `getFavoriteCatalysts`. Until contacts.list
    /// ships per-dispatcher rows, treat the catalyst record as the
    /// dispatcher row, with the company echoed as the org.
    private func dispatcherOrg(for fc: ShipperAPI.FavoriteCatalyst) -> String {
        fc.name.isEmpty ? "—" : fc.name
    }

    private func dispatcherRole(for fc: ShipperAPI.FavoriteCatalyst) -> String? {
        let dot = fc.dotNumber.isEmpty ? nil : "USDOT \(fc.dotNumber)"
        let loads = fc.loadsCompleted > 0 ? "\(fc.loadsCompleted) delivered" : nil
        let parts = [dot, loads].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func dispatcherPhone(for fc: ShipperAPI.FavoriteCatalyst) -> String {
        // contacts.list will surface phone — em-dash for now
        "—"
    }

    private func dispatcherEmail(for fc: ShipperAPI.FavoriteCatalyst) -> String {
        // contacts.list will surface email — em-dash for now
        "—"
    }

    private func formatCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

// MARK: - Glyphs (lifted verbatim from wireframe Code/ port)

private struct StarGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = CGAffineTransform(scaleX: rect.width / 10, y: rect.height / 10)
        var p = Path()
        p.move(to: CGPoint(x: 5, y: 0))
        p.addLine(to: CGPoint(x: 6.2, y: 3.6))
        p.addLine(to: CGPoint(x: 10, y: 3.6))
        p.addLine(to: CGPoint(x: 7, y: 5.8))
        p.addLine(to: CGPoint(x: 8.2, y: 9.4))
        p.addLine(to: CGPoint(x: 5, y: 7.2))
        p.addLine(to: CGPoint(x: 1.8, y: 9.4))
        p.addLine(to: CGPoint(x: 3, y: 5.8))
        p.addLine(to: CGPoint(x: 0, y: 3.6))
        p.addLine(to: CGPoint(x: 3.8, y: 3.6))
        p.closeSubpath()
        return p.applying(s)
    }
}

private struct DiamondHazmatGlyph: View {
    let label: String
    var body: some View {
        ZStack {
            Rectangle()
                .stroke(Brand.hazmat, lineWidth: 2)
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(45))
            Text(label)
                .font(.system(size: label.count > 1 ? 8 : 9, weight: .heavy))
                .foregroundStyle(Brand.hazmat)
        }
    }
}

private struct ReeferGlyph: View {
    let label: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(Brand.info, lineWidth: 1.8)
                .frame(width: 22, height: 16)
            Rectangle()
                .fill(Brand.info)
                .frame(width: 1.8, height: 16)
                .offset(x: -7)
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Brand.info)
                .offset(x: 3)
        }
    }
}

private struct HandsetGlyph: View {
    let stroke: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 10, geo.size.height / 8)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 4 * s))
                p.addLine(to: CGPoint(x: 4 * s, y: 0))
                p.addLine(to: CGPoint(x: 10 * s, y: 4 * s))
                p.addLine(to: CGPoint(x: 10 * s, y: 8 * s))
                p.addLine(to: CGPoint(x: 0, y: 8 * s))
                p.closeSubpath()
            }
            .stroke(stroke, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct PlusGlyph: View {
    let stroke: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 14, geo.size.height / 16)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 8 * s))
                p.addLine(to: CGPoint(x: 14 * s, y: 8 * s))
                p.move(to: CGPoint(x: 7 * s, y: 0))
                p.addLine(to: CGPoint(x: 7 * s, y: 16 * s))
            }
            .stroke(stroke, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }
}

private struct MagnifierGlyph: View {
    let stroke: Color
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 20
            ZStack {
                Circle()
                    .stroke(stroke, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 14 * s, height: 14 * s)
                    .position(x: 9 * s, y: 9 * s)
                Path { p in
                    p.move(to: CGPoint(x: 14 * s, y: 14 * s))
                    p.addLine(to: CGPoint(x: 20 * s, y: 20 * s))
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperContactSearch         = Notification.Name("eusoShipperContactSearch")
    static let eusoShipperContactAdd            = Notification.Name("eusoShipperContactAdd")
    static let eusoShipperContactRow            = Notification.Name("eusoShipperContactRow")
    static let eusoShipperContactFavoriteToggle = Notification.Name("eusoShipperContactFavoriteToggle")
    static let eusoShipperContactFacility       = Notification.Name("eusoShipperContactFacility")
}

// MARK: - Screen wrapper

struct ShipperContactsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperContacts()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_209(),
                trailing: shipperNavTrailing_209(),
                orbState: .idle
            )
        }
    }
}

// Out of scope per parity mandate §1.
private func shipperNavLeading_209() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_209() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("209 · Shipper · Contacts · Night") {
    ShipperContactsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("209 · Shipper · Contacts · Afternoon") {
    ShipperContactsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

/// Identifier wrapper used by the row-tap confirmationDialog so the
/// caller can stash name + phone + email in one shot. The dialog
/// renders Call / Text / Email / Cancel against these fields.
private struct ContactActionRef: Identifiable, Hashable {
    let id: String
    let name: String
    let phone: String
    let email: String
}

/// In-app contact-creation sheet — replaces the prior openURL hand-off
/// to a non-existent web `/shipper/contacts/new` route. Calls
/// `contacts.create` directly so the row lands in the contacts list
/// on the next refresh.
private struct AddContactSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onCreated: (String) -> Void

    @State private var contactType: String = "shipper"
    @State private var name: String = ""
    @State private var company: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var saving: Bool = false
    @State private var saveError: String? = nil

    private let typeOptions: [(id: String, label: String)] = [
        ("shipper", "Shipper"),
        ("catalyst", "Catalyst"),
        ("broker", "Broker"),
        ("driver", "Driver"),
        ("terminal", "Terminal / Facility"),
        ("vendor", "Vendor"),
        ("other", "Other"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Type", selection: $contactType) {
                        ForEach(typeOptions, id: \.id) { opt in
                            Text(opt.label).tag(opt.id)
                        }
                    }
                    TextField("Company (optional)", text: $company)
                }
                Section("Reach") {
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let err = saveError {
                    Section {
                        Text(err).foregroundStyle(Brand.danger).font(EType.caption)
                    }
                }
            }
            .navigationTitle("Add contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        saveError = nil
        struct In: Encodable {
            let type: String
            let name: String
            let company: String?
            let email: String?
            let phone: String?
        }
        struct Out: Decodable { let id: String }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedCompany = company.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "contacts.create",
                input: In(
                    type: contactType,
                    name: trimmedName,
                    company: trimmedCompany.isEmpty ? nil : trimmedCompany,
                    email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                    phone: trimmedPhone.isEmpty ? nil : trimmedPhone
                )
            )
            onCreated(trimmedName)
        } catch {
            saveError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        saving = false
    }
}
