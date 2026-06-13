//
//  322_ProfileEdit.swift
//  EusoTrip — Shipper · Profile edit (Arc J).
//  Calls `shippers.updateProfile` (server gap §5 — surfaces honest
//  error if not yet wired).
//

import SwiftUI

struct ProfileEditScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ProfileEditBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ProfileEditBody: View {
    @Environment(\.palette) private var palette
    @State private var contactName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var address: String = ""
    @State private var website: String = ""
    // Location (companies.city/state/zipCode/country)
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var zipCode: String = ""
    @State private var country: String = "USA"
    // Company identity (companies.legalName/ein/description)
    @State private var legalName: String = ""
    @State private var ein: String = ""
    @State private var companyDescription: String = ""
    @State private var loading = true
    @State private var sending = false
    @State private var saved = false
    @State private var actionError: String? = nil

    // Dirty-check baseline — the exact values `load()` (or the last
    // successful `save()`) pulled from the server. `save()` diffs each
    // field against this snapshot and only sends the ones that actually
    // changed, so an untouched field is omitted from the request and the
    // server (which keys every column on `input.X !== undefined`) leaves
    // it alone. This prevents blank-overwrite at the source while still
    // letting an explicit clear ("" different from a non-empty baseline)
    // reach the server as a real value it can honor.
    @State private var loaded = LoadedProfile()
    private struct LoadedProfile {
        var contactName = ""; var email = ""; var phone = ""
        var address = ""; var website = ""
        var city = ""; var state = ""; var zipCode = ""; var country = ""
        var legalName = ""; var ein = ""; var description = ""
    }

    /// Allowed country codes for the picker. Kept in one place so the
    /// `Picker` options and the load-time normalization can't drift.
    private static let countryOptions = ["USA", "CA", "MX"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if saved { LifecycleCard(accentGradient: true) { Text("Profile updated.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                fieldsCard
                locationCard
                companyCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.circle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · EDIT PROFILE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Edit profile").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DETAILS", icon: "person")
            field("Contact name", text: $contactName)
            field("Email", text: $email)
            field("Phone", text: $phone)
            field("Address", text: $address)
            field("Website", text: $website)
        }
    }

    private var locationCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LOCATION", icon: "mappin.and.ellipse")
            field("City", text: $city)
            HStack(spacing: 10) {
                field("State", text: $state)
                field("ZIP code", text: $zipCode)
            }
            countryPicker
        }
    }

    private var companyCard: some View {
        LifecycleCard {
            LifecycleSection(label: "COMPANY", icon: "building.2")
            field("Legal name", text: $legalName)
            field("EIN", text: $ein)
            multilineField("Description", text: $companyDescription)
        }
    }

    private var countryPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COUNTRY").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Picker("Country", selection: $country) {
                ForEach(Self.countryOptions, id: \.self) { c in Text(c).tag(c) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(palette.bgCard.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func multilineField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField(label, text: text, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain).autocorrectionDisabled(false)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField(label, text: text)
                .textFieldStyle(.plain).autocorrectionDisabled(label != "Contact name")
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Saving…" : "Save profile").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending)
    }

    private func load() async {
        do {
            let p = try await EusoTripAPI.shared.shipper.getProfile()
            contactName = p.contactName; email = p.email; phone = p.phone
            address = p.address; website = p.website
            city = p.city; state = p.state; zipCode = p.zipCode
            // Normalize the server's country against the picker allowlist.
            // A value the picker can't render (legacy "United States",
            // a full name, or anything outside ["USA","CA","MX"]) would
            // leave the SwiftUI selection binding with no matching tag,
            // breaking the picker. Fall back to the current safe default
            // ("USA") rather than corrupt the control.
            if Self.countryOptions.contains(p.country) { country = p.country }
            legalName = p.legalName; ein = p.ein; companyDescription = p.description
            // Snapshot exactly what we just displayed (including the
            // normalized `country`) as the dirty-check baseline.
            loaded = LoadedProfile(
                contactName: contactName, email: email, phone: phone,
                address: address, website: website,
                city: city, state: state, zipCode: zipCode, country: country,
                legalName: legalName, ein: ein, description: companyDescription)
        } catch let apiErr as EusoTripAPIError {
            actionError = "Couldn't load profile: \(apiErr.errorDescription ?? "network error")"
        } catch {
            actionError = "Couldn't load profile: \(error.localizedDescription)"
        }
        loading = false
    }

    private func save() async {
        sending = true; actionError = nil
        // DIRTY-CHECK input. Every field is optional; a `nil` field is
        // omitted entirely from the encoded JSON (synthesized `Encodable`
        // uses `encodeIfPresent` for optionals), which the server reads as
        // `input.X === undefined` and leaves that column untouched. Only
        // fields whose current value differs from the loaded baseline are
        // sent — so we never blank-overwrite an untouched field, and a
        // field the user deliberately cleared ("" vs a non-empty baseline)
        // still reaches the server as an explicit value it can honor.
        struct In: Encodable {
            let contactName: String?; let email: String?; let phone: String?
            let address: String?; let website: String?
            let city: String?; let state: String?; let zipCode: String?; let country: String?
            let legalName: String?; let ein: String?; let description: String?
        }
        // Server echoes the persisted row back so we can re-confirm what landed.
        struct Out: Decodable {
            let success: Bool
            let contactName: String?; let email: String?; let phone: String?
            let address: String?; let website: String?
            let city: String?; let state: String?; let zipCode: String?; let country: String?
            let legalName: String?; let ein: String?; let description: String?
        }
        // Returns the new value only when it differs from the baseline,
        // otherwise nil (→ omitted from the request).
        func diff(_ current: String, _ base: String) -> String? {
            current == base ? nil : current
        }
        let input = In(
            contactName: diff(contactName, loaded.contactName),
            email:       diff(email, loaded.email),
            phone:       diff(phone, loaded.phone),
            address:     diff(address, loaded.address),
            website:     diff(website, loaded.website),
            city:        diff(city, loaded.city),
            state:       diff(state, loaded.state),
            zipCode:     diff(zipCode, loaded.zipCode),
            country:     diff(country, loaded.country),
            legalName:   diff(legalName, loaded.legalName),
            ein:         diff(ein, loaded.ein),
            description: diff(companyDescription, loaded.description))
        do {
            let out: Out = try await EusoTripAPI.shared.mutation("shippers.updateProfile", input: input)
            // Re-prefill from the authoritative persisted values…
            if let v = out.contactName { contactName = v }
            if let v = out.email { email = v }
            if let v = out.phone { phone = v }
            if let v = out.address { address = v }
            if let v = out.website { website = v }
            if let v = out.city { city = v }
            if let v = out.state { state = v }
            if let v = out.zipCode { zipCode = v }
            if let v = out.country, Self.countryOptions.contains(v) { country = v }
            if let v = out.legalName { legalName = v }
            if let v = out.ein { ein = v }
            if let v = out.description { companyDescription = v }
            // …and re-baseline so a second save in the same session only
            // sends the next set of edits (not the ones we just persisted).
            loaded = LoadedProfile(
                contactName: contactName, email: email, phone: phone,
                address: address, website: website,
                city: city, state: state, zipCode: zipCode, country: country,
                legalName: legalName, ein: ein, description: companyDescription)
            saved = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("322 · Profile edit · Night") { ProfileEditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("322 · Profile edit · Afternoon") { ProfileEditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
