//
//  RegistrationViewModel.swift
//  EusoTrip — Role-aware sign-up state machine.
//
//  Single view-model drives all six primary signup roles (Driver / Carrier /
//  Shipper / Broker / Dispatch / Escort).  Each role exposes only the fields
//  required by its backend zod schema.
//

import Foundation
import SwiftUI
import CoreLocation

@MainActor
final class RegistrationViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case submitting
        case error(String)
        case success(message: String)   // "Check your email to verify."
    }

    // MARK: Wizard taxonomy (country + mode + role)

    /// Countries the operator serves (multi-select — step 1 of the wizard).
    @Published var selectedCountries: Set<RegistrationCountry> = []

    /// Transport modes the operator works in (multi-select — step 2).
    @Published var selectedModes: Set<TransportMode> = []

    /// Selected role (chosen on step 3).
    @Published var role: EusoRole = .driver

    /// Roles filtered by selected modes. If no modes are selected, all roles.
    var rolesForSelectedModes: [EusoRole] {
        guard !selectedModes.isEmpty else { return EusoRole.allSignupRoles }
        return EusoRole.allSignupRoles.filter { r in
            !r.modes.isDisjoint(with: selectedModes)
        }
    }

    func toggleCountry(_ c: RegistrationCountry) {
        if selectedCountries.contains(c) { selectedCountries.remove(c) }
        else { selectedCountries.insert(c) }
    }

    func toggleMode(_ m: TransportMode) {
        if selectedModes.contains(m) { selectedModes.remove(m) }
        else { selectedModes.insert(m) }
    }

    // MARK: Shared identity fields

    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var email: String = ""
    @Published var phone: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""

    // MARK: Agreements

    @Published var acceptsTerms: Bool = false
    @Published var acceptsPrivacy: Bool = false

    // MARK: Role-specific

    // Driver
    @Published var cdlNumber: String = ""
    @Published var cdlState: String = ""
    @Published var cdlClass: String = "A"
    @Published var dateOfBirth: String = ""
    @Published var companyCode: String = ""     // driver & dispatch

    // Shipper / Catalyst / Broker
    @Published var companyName: String = ""
    @Published var address: String = ""
    @Published var city: String = ""
    @Published var state: String = ""
    @Published var zip: String = ""

    /// Resolved-address shadow for the company street address. The
    /// `EusoAddressField` drives this; we mirror its `.text` onto `address`
    /// on change so the registration payload stays identical to the old
    /// plain-string world. Coords are held here and can optionally ride
    /// along in a future payload field without breaking the current one.
    @Published var companyResolvedAddress: ResolvedAddress = ResolvedAddress()

    // Catalyst
    @Published var mcNumber: String = ""
    @Published var dotNumber: String = ""
    @Published var ein: String = ""

    // Broker
    @Published var brokerMcNumber: String = ""
    @Published var bondProvider: String = ""
    @Published var bondAmount: String = ""

    // Escort
    @Published var escortCertState: String = ""
    @Published var certificationExpires: String = ""

    // Terminal Manager
    @Published var facilityName: String = ""
    @Published var epaFacilityId: String = ""

    // Compliance Officer
    @Published var certificationNumber: String = ""
    @Published var trainingProvider: String = ""
    @Published var trainingCompletionDate: String = ""

    // Safety Manager
    @Published var csaSpecialistCert: String = ""
    @Published var yearsOfExperience: String = ""  // parsed to Int on submit

    // Admin (invite-only)
    @Published var inviteCode: String = ""

    // ─── Rail ─────────────────────────────────────────────────────
    //
    // All rail fields are optional on the server except the FRA
    // certification numbers for RAIL_ENGINEER / RAIL_CONDUCTOR. The
    // iOS form collects the identity-level + key-cert subset so
    // sign-up completes in under a minute; richer compliance data
    // (PTC system, insurance, drug-testing program) is captured
    // post-signup in the role's in-app onboarding flow.
    @Published var stbRegistration: String = ""        // shipper / broker
    @Published var stbDocket: String = ""              // catalyst
    @Published var fraCertification: String = ""       // catalyst
    @Published var fraCertificationNumber: String = "" // engineer / conductor (required)
    @Published var fraCertificationExpires: String = ""
    @Published var employerRailroad: String = ""
    @Published var dispatcherCertification: String = ""
    @Published var locomotiveCount: String = ""        // parsed to Int
    @Published var railcarCount: String = ""
    @Published var imcRegistration: String = ""

    // ─── Vessel ───────────────────────────────────────────────────
    @Published var fmcRegistration: String = ""        // shipper
    @Published var fmcLicenseNumber: String = ""       // operator / broker
    @Published var uscgDocumentNumber: String = ""     // operator
    @Published var vesselCount: String = ""            // parsed to Int
    @Published var mmcLicenseNumber: String = ""       // captain (required)
    @Published var mmcExpires: String = ""
    @Published var stcwCertification: String = ""
    @Published var stcwExpires: String = ""
    @Published var yearsAtSea: String = ""
    @Published var portName: String = ""               // port master
    @Published var portAuthority: String = ""
    @Published var mtsaFacilityPlan: String = ""
    @Published var uscgFacilityId: String = ""
    @Published var cbpLicenseNumber: String = ""       // customs broker (required)
    @Published var cbpLicenseExpires: String = ""
    @Published var bondNumber: String = ""             // customs broker bond

    // ─── Factoring ─────────────────────────────────────────────────
    @Published var stateLenderLicense: String = ""
    @Published var yearsInBusiness: String = ""
    @Published var advanceRate: String = ""            // parsed to Double
    @Published var factoringFeeRate: String = ""

    // ─── Super-Admin (invite-only) ────────────────────────────────
    // Uses the existing `inviteCode` + a new `reason` field.
    @Published var superAdminReason: String = ""

    // MARK: Phase

    @Published var phase: Phase = .idle

    // MARK: Validation

    var passwordStrengthMessage: String? {
        guard !password.isEmpty else { return nil }
        if password.count < 8 { return "Minimum 8 characters" }
        return nil
    }

    var confirmPasswordMessage: String? {
        guard !confirmPassword.isEmpty else { return nil }
        return confirmPassword == password ? nil : "Passwords don't match"
    }

    var emailError: String? {
        guard !email.isEmpty else { return nil }
        return email.contains("@") && email.contains(".") ? nil : "Enter a valid email"
    }

    var canSubmit: Bool {
        guard !firstName.isEmpty, !lastName.isEmpty,
              !email.isEmpty, emailError == nil,
              password.count >= 8, confirmPassword == password,
              acceptsTerms, acceptsPrivacy else { return false }

        switch role {
        case .catalyst, .shipper, .broker:
            return !companyName.isEmpty
        case .compliance, .safety:
            // Company-bound roles — backend rejects without a
            // companyCode tying the new account to a registered
            // Catalyst / Shipper. Parity with the web
            // `/register/compliance` + `/register/safety` forms.
            return !companyCode.isEmpty
        case .admin, .superAdmin:
            // Invite-only — server gates both roles behind an
            // invite token. Block submit locally too so the form
            // doesn't round-trip a failure the user can't interpret.
            return !inviteCode.isEmpty
        case .railShipper, .railCatalyst, .railBroker,
             .vesselShipper, .vesselOperator, .vesselBroker,
             .factoring:
            return !companyName.isEmpty
        case .customsBroker:
            // Customs brokers need both their company affiliation and
            // a CBP license # under 19 CFR 111.
            return !companyName.isEmpty && !cbpLicenseNumber.isEmpty
        case .railEngineer, .railConductor:
            // FRA certification number is required per §49 CFR 240 /
            // §49 CFR 242. Locks the picker until the driver types it.
            return !fraCertificationNumber.isEmpty
        case .shipCaptain:
            // MMC (Merchant Mariner Credential) number is required
            // under 46 CFR 10.201.
            return !mmcLicenseNumber.isEmpty
        case .railDispatch:
            return !employerRailroad.isEmpty
        case .portMaster:
            return !portName.isEmpty
        default:
            return true
        }
    }

    // MARK: Submit

    func submit(api: EusoTripAPI = .shared) async {
        phase = .submitting
        do {
            let successMessage: String
            switch role {
            case .driver:
                _ = try await api.registration.registerDriver(.init(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone.nilIfEmpty,
                    cdlNumber: cdlNumber.nilIfEmpty,
                    cdlState: cdlState.nilIfEmpty,
                    cdlClass: cdlClass.nilIfEmpty,
                    dateOfBirth: dateOfBirth.nilIfEmpty,
                    companyCode: companyCode.nilIfEmpty
                ))
                successMessage = "Driver account created. Verify email to continue."

            case .shipper:
                _ = try await api.registration.registerShipper(.init(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone.nilIfEmpty,
                    companyName: companyName,
                    address: address.nilIfEmpty,
                    city: city.nilIfEmpty,
                    state: state.nilIfEmpty,
                    zip: zip.nilIfEmpty
                ))
                successMessage = "Shipper account created. Verify email to continue."

            case .catalyst:
                _ = try await api.registration.registerCatalyst(.init(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone.nilIfEmpty,
                    companyName: companyName,
                    mcNumber: mcNumber.nilIfEmpty,
                    dotNumber: dotNumber.nilIfEmpty,
                    ein: ein.nilIfEmpty
                ))
                successMessage = "Carrier account created. Verify email to continue."

            case .broker:
                _ = try await api.registration.registerBroker(.init(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone.nilIfEmpty,
                    companyName: companyName,
                    brokerMcNumber: brokerMcNumber.nilIfEmpty,
                    bondProvider: bondProvider.nilIfEmpty,
                    bondAmount: Double(bondAmount)
                ))
                successMessage = "Broker account created. Verify email to continue."

            case .dispatch:
                _ = try await api.registration.registerDispatch(.init(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone.nilIfEmpty,
                    companyCode: companyCode.nilIfEmpty
                ))
                successMessage = "Dispatch account created. Verify email to continue."

            case .escort:
                _ = try await api.registration.registerEscort(.init(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone.nilIfEmpty,
                    escortCertState: escortCertState.nilIfEmpty,
                    certificationExpires: certificationExpires.nilIfEmpty
                ))
                successMessage = "Escort account created. Verify email to continue."

            case .terminal:
                _ = try await api.registration.registerTerminalManager(.init(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone.nilIfEmpty,
                    companyName: companyName.nilIfEmpty,
                    facilityName: facilityName.nilIfEmpty,
                    epaFacilityId: epaFacilityId.nilIfEmpty,
                    companyCode: companyCode.nilIfEmpty
                ))
                successMessage = "Terminal Manager account created. Verify email to continue."

            case .compliance:
                _ = try await api.registration.registerComplianceOfficer(.init(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone.nilIfEmpty,
                    certificationNumber: certificationNumber.nilIfEmpty,
                    trainingProvider: trainingProvider.nilIfEmpty,
                    trainingCompletionDate: trainingCompletionDate.nilIfEmpty,
                    companyCode: companyCode.nilIfEmpty
                ))
                successMessage = "Compliance Officer account created. Verify email to continue."

            case .safety:
                _ = try await api.registration.registerSafetyManager(.init(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone.nilIfEmpty,
                    csaSpecialistCert: csaSpecialistCert.nilIfEmpty,
                    yearsOfExperience: Int(yearsOfExperience),
                    companyCode: companyCode.nilIfEmpty
                ))
                successMessage = "Safety Manager account created. Verify email to continue."

            case .admin:
                // Invite-only — backend rejects requests without a
                // SUPER_ADMIN-issued token, which is what makes this
                // form safe to ship on consumer App Store builds.
                _ = try await api.registration.registerAdmin(.init(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone.nilIfEmpty,
                    inviteCode: inviteCode
                ))
                successMessage = "Admin account created. Verify email to continue."

            // ─── Rail (6) ─────────────────────────────────────────
            case .railShipper:
                _ = try await api.registration.registerRailShipper(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    companyName: companyName, dba: nil, ein: ein.nilIfEmpty,
                    stbRegistration: stbRegistration.nilIfEmpty,
                    streetAddress: address.nilIfEmpty, city: city.nilIfEmpty,
                    state: state.nilIfEmpty, zipCode: zip.nilIfEmpty
                ))
                successMessage = "Rail Shipper account created. Verify email to continue."

            case .railCatalyst:
                _ = try await api.registration.registerRailCatalyst(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    companyName: companyName, dba: nil, ein: ein.nilIfEmpty,
                    stbDocket: stbDocket.nilIfEmpty,
                    fraCertification: fraCertification.nilIfEmpty,
                    locomotiveCount: Int(locomotiveCount),
                    railcarCount: Int(railcarCount),
                    operatingStates: nil
                ))
                successMessage = "Rail Catalyst account created. Verify email to continue."

            case .railDispatch:
                _ = try await api.registration.registerRailDispatcher(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    employerRailroad: employerRailroad,
                    dispatcherCertification: dispatcherCertification.nilIfEmpty,
                    yearsExperience: yearsOfExperience.nilIfEmpty,
                    companyCode: companyCode.nilIfEmpty
                ))
                successMessage = "Rail Dispatcher account created. Verify email to continue."

            case .railEngineer:
                _ = try await api.registration.registerRailEngineer(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    dateOfBirth: dateOfBirth.nilIfEmpty,
                    fraCertificationNumber: fraCertificationNumber,
                    fraCertificationExpires: fraCertificationExpires.nilIfEmpty,
                    employerRailroad: employerRailroad.nilIfEmpty,
                    yearsExperience: yearsOfExperience.nilIfEmpty,
                    medicalCardNumber: nil, medicalCardExpires: nil
                ))
                successMessage = "Rail Engineer account created. Verify email to continue."

            case .railConductor:
                _ = try await api.registration.registerRailConductor(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    dateOfBirth: dateOfBirth.nilIfEmpty,
                    fraCertificationNumber: fraCertificationNumber,
                    fraCertificationExpires: fraCertificationExpires.nilIfEmpty,
                    employerRailroad: employerRailroad.nilIfEmpty,
                    yearsExperience: yearsOfExperience.nilIfEmpty,
                    medicalCardNumber: nil, medicalCardExpires: nil
                ))
                successMessage = "Rail Conductor account created. Verify email to continue."

            case .railBroker:
                _ = try await api.registration.registerRailBroker(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    companyName: companyName, dba: nil,
                    imcRegistration: imcRegistration.nilIfEmpty,
                    stbRegistration: stbRegistration.nilIfEmpty,
                    ein: ein.nilIfEmpty,
                    bondProvider: bondProvider.nilIfEmpty,
                    bondAmount: Double(bondAmount)
                ))
                successMessage = "Rail Broker account created. Verify email to continue."

            // ─── Vessel (6) ───────────────────────────────────────
            case .vesselShipper:
                _ = try await api.registration.registerVesselShipper(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    companyName: companyName, dba: nil, ein: ein.nilIfEmpty,
                    fmcRegistration: fmcRegistration.nilIfEmpty,
                    cargoTypes: nil
                ))
                successMessage = "Vessel Shipper account created. Verify email to continue."

            case .vesselOperator:
                _ = try await api.registration.registerVesselOperator(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    companyName: companyName,
                    fmcLicenseNumber: fmcLicenseNumber.nilIfEmpty,
                    uscgDocumentNumber: uscgDocumentNumber.nilIfEmpty,
                    vesselCount: Int(vesselCount),
                    operatingPorts: nil
                ))
                successMessage = "Vessel Operator account created. Verify email to continue."

            case .shipCaptain:
                _ = try await api.registration.registerShipCaptain(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    dateOfBirth: dateOfBirth.nilIfEmpty,
                    mmcLicenseNumber: mmcLicenseNumber,
                    mmcExpires: mmcExpires.nilIfEmpty,
                    stcwCertification: stcwCertification.nilIfEmpty,
                    stcwExpires: stcwExpires.nilIfEmpty,
                    vesselClassEndorsements: nil,
                    yearsAtSea: yearsAtSea.nilIfEmpty,
                    medicalCertificateNumber: nil, medicalCertificateExpires: nil
                ))
                successMessage = "Ship Captain account created. Verify email to continue."

            case .vesselBroker:
                _ = try await api.registration.registerVesselBroker(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    companyName: companyName, dba: nil,
                    fmcLicenseNumber: fmcLicenseNumber.nilIfEmpty,
                    ein: ein.nilIfEmpty,
                    bondProvider: bondProvider.nilIfEmpty,
                    bondAmount: Double(bondAmount)
                ))
                successMessage = "Vessel Broker account created. Verify email to continue."

            case .portMaster:
                _ = try await api.registration.registerPortMaster(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    portName: portName,
                    portAuthority: portAuthority.nilIfEmpty,
                    mtsaFacilityPlan: mtsaFacilityPlan.nilIfEmpty,
                    uscgFacilityId: uscgFacilityId.nilIfEmpty,
                    jobTitle: nil,
                    yearsExperience: yearsOfExperience.nilIfEmpty
                ))
                successMessage = "Port Master account created. Verify email to continue."

            case .customsBroker:
                _ = try await api.registration.registerCustomsBroker(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    companyName: companyName, dba: nil,
                    cbpLicenseNumber: cbpLicenseNumber,
                    cbpLicenseExpires: cbpLicenseExpires.nilIfEmpty,
                    bondNumber: bondNumber.nilIfEmpty,
                    bondAmount: Double(bondAmount),
                    bondProvider: bondProvider.nilIfEmpty,
                    ein: ein.nilIfEmpty,
                    portsOfEntry: nil
                ))
                successMessage = "Customs Broker account created. Verify email to continue."

            // ─── Financial / platform (2) ─────────────────────────
            case .factoring:
                _ = try await api.registration.registerFactoring(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    companyName: companyName, dba: nil, ein: ein.nilIfEmpty,
                    stateLenderLicense: stateLenderLicense.nilIfEmpty,
                    yearsInBusiness: yearsInBusiness.nilIfEmpty,
                    operatingStates: nil, serviceCommodities: nil,
                    advanceRate: Double(advanceRate),
                    factoringFeeRate: Double(factoringFeeRate)
                ))
                successMessage = "Factoring account created. Verify email to continue."

            case .superAdmin:
                _ = try await api.registration.registerSuperAdmin(.init(
                    email: email, password: password,
                    firstName: firstName, lastName: lastName,
                    phone: phone,
                    inviteCode: inviteCode,
                    reason: superAdminReason.nilIfEmpty
                ))
                successMessage = "Super-Admin account created. Verify email to continue."
            }

            phase = .success(message: successMessage)
        } catch EusoTripAPIError.trpcError(let msg) {
            phase = .error(msg)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
