//
//  ProfileEditView.swift
//  EusoTrip — Editable driver profile (avatar + name + email + CDL + phone).
//
//  Entry points:
//    • MeSettingsView ACCOUNT card (tap) → sheet
//    • DriverTabPanes Me tab header card (tap) → sheet
//
//  What it wires up (Wave-5, 2026-04-20):
//    • PhotosPicker for avatar swap. Writes JPEG bytes into the shared
//      DriverProfileStore so the Home greeting "Hey, {firstName}" and the
//      Me header card pick up the change live the moment the user saves.
//    • TextField binding for firstName / lastName / email / licenseClass /
//      phone. All local drafts until the user taps "Save" — this keeps
//      the Home header from flickering through every keystroke.
//    • Remove Photo option so the driver can drop a bad crop without
//      having to pick a replacement first.
//
//  Why a sheet and not a push:
//    The Settings surface is itself already presented as a sheet via
//    `MeDetailContainer`. Nesting a push NavigationLink inside a sheet
//    introduces a second nav stack and breaks swipe-down-to-dismiss on
//    the outer sheet. A sheet-over-sheet presentation keeps both layers
//    independently dismissable with a clean drag handle.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileEditView: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var profile: DriverProfileStore

    // MARK: - Draft state (commits to the store only on Save)

    @State private var draftFirstName: String = ""
    @State private var draftLastName: String = ""
    @State private var draftEmail: String = ""
    @State private var draftLicenseClass: String = ""
    @State private var draftPhone: String = ""
    @State private var draftAvatarData: Data? = nil

    // Driver-specific compliance fields — written via
    // `DriverProfileStore.commitDriver(...)` which fires the
    // `profile.updateDriverProfile` mutation. Server persists into
    // `users.metadata.driver` JSON; web /profile and any other
    // logged-in device repaint via the realtime `profile:updated`
    // broadcast.
    @State private var draftCdlNumber: String = ""
    @State private var draftCdlState: String = ""
    @State private var draftCdlExpDate: String = ""
    @State private var draftMedExpDate: String = ""
    @State private var draftMedExaminer: String = ""
    @State private var draftTwicNumber: String = ""
    @State private var draftTwicExpDate: String = ""
    @State private var draftHazmat: Bool = false
    @State private var draftTanker: Bool = false
    @State private var draftHomeTerminal: String = ""

    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var isSaving: Bool = false

    // MARK: - Driver-license capture (document-intelligence spine)
    //
    // Registration identity is load-bearing — the CDL fields above feed
    // FMCSA / Motus identity checks, so we do NOT let the driver upload a
    // raw image and hope it's a license. The picked photo is routed
    // through `documentRouter.classifyAndRoute` (Gemini + NVIDIA vision
    // spine) FIRST so the capture point KNOWS the document is a CDL /
    // driver license before we trust any of its numbers. On a confident
    // match we auto-fill CDL # / state / class / expiry into the drafts
    // above; on a mismatch / low confidence we say so honestly and fill
    // nothing.
    @State private var licensePickerItem: PhotosPickerItem? = nil
    @State private var licenseScanning: Bool = false
    @State private var licenseScan: LicenseScanResult? = nil
    @State private var licenseScanError: String? = nil

    // MARK: - Body

    var body: some View {
        ZStack {
            palette.bgPage.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    titleBar
                    avatarCard
                    identityCard
                    contactCard
                    licenseCard
                    licenseScanCard
                    complianceCard
                    endorsementsCard
                    saveButton

                    // Reserve bottom inset so the Save button isn't hidden
                    // behind the home indicator on devices without a
                    // physical home button.
                    Color.clear.frame(height: Device.safeBottom + Space.s4)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear(perform: hydrateDrafts)
        .onChange(of: pickerItem) { _, newValue in
            // A PhotosPicker selection gives us a `PhotosPickerItem` —
            // async-load its bytes into the draft so Save can commit
            // without additional work. (Avatar stays a RAW image — it's a
            // photo, not a document, so it never touches the classifier.)
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await MainActor.run { draftAvatarData = data }
                }
            }
        }
        .onChange(of: licensePickerItem) { _, newValue in
            // The license photo is a DOCUMENT — route it through the
            // vision spine to confirm it really is a CDL / driver license
            // and pull the identity fields, instead of trusting a raw
            // upload.
            guard let newValue else { return }
            Task { await classifyLicense(item: newValue) }
        }
        // Uniform cafe-door entrance matches every other sheet — the
        // profile edit surface used to land statically which broke the
        // visual rhythm across the Me section.
        .screenTileRoot()
    }

    // MARK: - Title bar (Back / "Edit profile" / Save shortcut)

    private var titleBar: some View {
        HStack(alignment: .center) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text("Edit profile")
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            // Invisible spacer mirror so the title stays visually
            // centered regardless of the left close button's width.
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.clear)
        }
    }

    // MARK: - Avatar card (PhotosPicker + Remove)

    private var avatarCard: some View {
        ActiveCard {
            VStack(spacing: Space.s3) {
                avatarPreview
                    .frame(width: 112, height: 112)

                HStack(spacing: Space.s2) {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Text(draftAvatarData == nil ? "Add photo" : "Change photo")
                            .font(EType.bodyStrong)
                            .foregroundStyle(LinearGradient.diagonal)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s2)
                            .background(
                                Capsule().strokeBorder(palette.borderFaint)
                            )
                    }

                    if draftAvatarData != nil {
                        Button(role: .destructive) {
                            draftAvatarData = nil
                            pickerItem = nil
                        } label: {
                            Text("Remove")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textSecondary)
                                .padding(.horizontal, Space.s4)
                                .padding(.vertical, Space.s2)
                                .background(
                                    Capsule().strokeBorder(palette.borderFaint)
                                )
                        }
                    }
                }

                Text("JPEG or PNG · shown as a circle throughout the app")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var avatarPreview: some View {
        ZStack {
            if let data = draftAvatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 112, height: 112)
                    .clipShape(Circle())
            } else {
                // Fallback gradient monogram — matches the Home greeting
                // "Hey, <FirstName>" color treatment so the ProfileEdit
                // sheet reads as the same person the header greets.
                Circle()
                    .fill(LinearGradient.diagonal)
                    .overlay(
                        Text(initials)
                            .font(.system(size: 40, weight: .heavy))
                            .foregroundStyle(.white)
                    )
            }
        }
        .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var initials: String {
        let f = draftFirstName.first.map { String($0) } ?? ""
        let l = draftLastName.first.map { String($0) } ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "ME" : s
    }

    // MARK: - Identity / contact / license cards

    private var identityCard: some View {
        sectionCard(title: "Identity") {
            fieldRow(label: "First name",
                     placeholder: "Michael",
                     text: $draftFirstName,
                     keyboard: .default,
                     capitalization: .words)
            Divider().overlay(palette.borderFaint)
            fieldRow(label: "Last name",
                     placeholder: "Eusorone",
                     text: $draftLastName,
                     keyboard: .default,
                     capitalization: .words)
        }
    }

    private var contactCard: some View {
        sectionCard(title: "Contact") {
            fieldRow(label: "Email",
                     placeholder: "you@example.com",
                     text: $draftEmail,
                     keyboard: .emailAddress,
                     capitalization: .never)
            Divider().overlay(palette.borderFaint)
            fieldRow(label: "Phone",
                     placeholder: "+1 (555) 000-0000",
                     text: $draftPhone,
                     keyboard: .phonePad,
                     capitalization: .never)
        }
    }

    private var licenseCard: some View {
        sectionCard(title: "License") {
            fieldRow(label: "CDL class",
                     placeholder: "CDL-A",
                     text: $draftLicenseClass,
                     keyboard: .default,
                     capitalization: .characters)
            Divider().overlay(palette.borderFaint)
            // Read-only row for memberSinceYear — driver cannot backdate
            // when they joined.
            HStack(alignment: .center) {
                Text("Member since")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 110, alignment: .leading)
                Text(profile.memberSinceYear)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
    }

    // MARK: - Driver-license scan card (classify + extract before trust)

    private var licenseScanCard: some View {
        sectionCard(title: "Verify license photo") {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Scan your CDL so we can confirm it's a real driver license and auto-fill the fields below.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                HStack(spacing: Space.s2) {
                    PhotosPicker(selection: $licensePickerItem, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.viewfinder")
                                .font(.system(size: 12, weight: .heavy))
                            Text(licenseScan == nil ? "Scan license" : "Rescan")
                                .font(EType.bodyStrong)
                        }
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .background(Capsule().strokeBorder(palette.borderFaint))
                    }
                    .disabled(licenseScanning)

                    if licenseScanning {
                        ProgressView().scaleEffect(0.7).tint(palette.textPrimary)
                        Text("Reading…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }

                if let err = licenseScanError {
                    Text(err)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let scan = licenseScan {
                    licenseResultBlock(scan)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
    }

    @ViewBuilder
    private func licenseResultBlock(_ scan: LicenseScanResult) -> some View {
        let confPct = Int((scan.confidence * 100).rounded())
        VStack(alignment: .leading, spacing: Space.s2) {
            // Detected-type verdict — green when it's confidently a
            // license, amber when it's a license but low-confidence,
            // red when it is NOT a license at all. We never claim a
            // type the classifier didn't return.
            HStack(spacing: 6) {
                Image(systemName: scan.verdict.icon)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(scan.verdict.tint)
                Text(scan.verdict.headline)
                    .font(EType.caption.weight(.heavy))
                    .foregroundStyle(scan.verdict.tint)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            Text("Detected: \(scan.detectedLabel) · \(confPct)% confidence")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)

            // Surfaced identity fields — show only what the classifier
            // actually extracted, so the driver can confirm before save.
            if !scan.fieldRows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(scan.fieldRows, id: \.0) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.0)
                                .font(EType.micro)
                                .foregroundStyle(palette.textTertiary)
                                .frame(width: 96, alignment: .leading)
                            Text(row.1)
                                .font(EType.caption.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }

            if scan.verdict.didAutofill {
                Text("Auto-filled the CDL fields above — please double-check them before saving.")
                    .font(EType.micro)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(scan.warnings, id: \.self) { w in
                Text("⚠ " + w)
                    .font(EType.micro)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Compliance card (CDL number / state / expiry, medical, TWIC)

    private var complianceCard: some View {
        sectionCard(title: "CDL & medical") {
            fieldRow(label: "CDL #",
                     placeholder: "T-12345678",
                     text: $draftCdlNumber,
                     keyboard: .default,
                     capitalization: .characters)
            Divider().overlay(palette.borderFaint)
            fieldRow(label: "State",
                     placeholder: "TX",
                     text: $draftCdlState,
                     keyboard: .default,
                     capitalization: .characters)
            Divider().overlay(palette.borderFaint)
            fieldRow(label: "CDL expires",
                     placeholder: "YYYY-MM-DD",
                     text: $draftCdlExpDate,
                     keyboard: .numbersAndPunctuation,
                     capitalization: .never)
            Divider().overlay(palette.borderFaint)
            fieldRow(label: "Medical exp",
                     placeholder: "YYYY-MM-DD",
                     text: $draftMedExpDate,
                     keyboard: .numbersAndPunctuation,
                     capitalization: .never)
            Divider().overlay(palette.borderFaint)
            fieldRow(label: "Examiner",
                     placeholder: "Dr. Smith",
                     text: $draftMedExaminer,
                     keyboard: .default,
                     capitalization: .words)
            Divider().overlay(palette.borderFaint)
            fieldRow(label: "TWIC #",
                     placeholder: "Optional",
                     text: $draftTwicNumber,
                     keyboard: .default,
                     capitalization: .characters)
            Divider().overlay(palette.borderFaint)
            fieldRow(label: "TWIC exp",
                     placeholder: "YYYY-MM-DD",
                     text: $draftTwicExpDate,
                     keyboard: .numbersAndPunctuation,
                     capitalization: .never)
            Divider().overlay(palette.borderFaint)
            fieldRow(label: "Home terminal",
                     placeholder: "Houston, TX",
                     text: $draftHomeTerminal,
                     keyboard: .default,
                     capitalization: .words)
        }
    }

    // MARK: - Endorsements card (hazmat / tanker toggles)

    private var endorsementsCard: some View {
        sectionCard(title: "Endorsements") {
            HStack(alignment: .center) {
                Text("Hazmat")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 110, alignment: .leading)
                Text(draftHazmat ? "H endorsed" : "Not endorsed")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Toggle("", isOn: $draftHazmat).labelsHidden()
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            Divider().overlay(palette.borderFaint)
            HStack(alignment: .center) {
                Text("Tanker")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 110, alignment: .leading)
                Text(draftTanker ? "N endorsed" : "Not endorsed")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Toggle("", isOn: $draftTanker).labelsHidden()
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
    }

    // MARK: - Save CTA

    private var saveButton: some View {
        CTAButton(title: isSaving ? "Saving…" : "Save changes") {
            guard !isSaving else { return }
            isSaving = true
            profile.commit(
                firstName: draftFirstName,
                lastName: draftLastName,
                email: draftEmail,
                licenseClass: draftLicenseClass,
                phone: draftPhone,
                avatarData: draftAvatarData
            )
            // Compliance fields ride the same Save CTA — fired through
            // `commitDriver(...)` which posts `profile.updateDriverProfile`
            // and the server broadcasts `profile:updated` so other
            // devices repaint these fields too.
            profile.commitDriver(
                cdlNumber:             draftCdlNumber,
                cdlClass:              draftLicenseClass,
                cdlState:              draftCdlState,
                cdlEndorsements:       (draftHazmat ? ["H"] : []) + (draftTanker ? ["N"] : []),
                cdlExpirationDate:     draftCdlExpDate,
                medicalExpirationDate: draftMedExpDate,
                medicalExaminerName:   draftMedExaminer,
                twicNumber:            draftTwicNumber,
                twicExpirationDate:    draftTwicExpDate,
                hazmatEndorsement:     draftHazmat,
                tankerEndorsement:     draftTanker,
                homeTerminal:          draftHomeTerminal,
                hireDate:              profile.hireDate,
                yearsExperience:       profile.yearsExperience
            )
            // Short delay so the CTA's "Saving…" flash is visible for
            // at least 120 ms. Purely cosmetic — the commits above are
            // fire-and-forget at the network layer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isSaving = false
                dismiss()
            }
        }
        .disabled(isSaving || draftFirstName.isEmpty || draftLastName.isEmpty)
        .opacity((isSaving || draftFirstName.isEmpty || draftLastName.isEmpty) ? 0.6 : 1.0)
    }

    // MARK: - Section card + field row builders

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) { content() }
                .eusoCard(radius: Radius.lg)
        }
    }

    @ViewBuilder
    private func fieldRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        capitalization: TextInputAutocapitalization
    ) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 110, alignment: .leading)
            TextField(placeholder, text: text)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(keyboard == .emailAddress || keyboard == .phonePad)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: - Draft hydration

    /// Pulls the current store values into the local @State drafts so
    /// every opening of the sheet starts from the latest saved state
    /// and not whatever the drafts were on the last close.
    private func hydrateDrafts() {
        draftFirstName    = profile.firstName
        draftLastName     = profile.lastName
        draftEmail        = profile.email
        draftLicenseClass = profile.licenseClass
        draftPhone        = profile.phone
        draftAvatarData   = profile.avatarData

        // Compliance / endorsements drafts pull from the same store —
        // server-hydrated on launch via `profile.getDriverProfile`
        // which reads `users.metadata.driver`.
        draftCdlNumber    = profile.cdlNumber
        draftCdlState     = profile.cdlState
        draftCdlExpDate   = profile.cdlExpirationDate
        draftMedExpDate   = profile.medicalExpirationDate
        draftMedExaminer  = profile.medicalExaminerName
        draftTwicNumber   = profile.twicNumber
        draftTwicExpDate  = profile.twicExpirationDate
        draftHazmat       = profile.hazmatEndorsement
        draftTanker       = profile.tankerEndorsement
        draftHomeTerminal = profile.homeTerminal
    }

    // MARK: - License classify → extract pipeline

    /// Loads the picked photo, routes it through the document-intelligence
    /// spine to CONFIRM it's a driver license, and (only on a confident
    /// match) auto-fills the CDL drafts. Honest at every branch: a
    /// non-license, an `unknown`, or a low-confidence result fills nothing
    /// and says exactly what was (or wasn't) detected.
    @MainActor
    private func classifyLicense(item: PhotosPickerItem) async {
        guard !licenseScanning else { return }
        licenseScanError = nil
        licenseScan = nil
        licenseScanning = true
        defer { licenseScanning = false; licensePickerItem = nil }

        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
            licenseScanError = "Couldn't read that photo. Try another."
            return
        }

        // Compress so the Gemini payload stays under ~900KB, mirroring the
        // registration CredentialScanCard / Me·Docs capture handling.
        var jpeg = data
        if data.count > 900_000, let img = UIImage(data: data) {
            for q in [CGFloat(0.85), 0.75, 0.65, 0.55, 0.45] {
                if let d = img.jpegData(compressionQuality: q), d.count <= 900_000 {
                    jpeg = d
                    break
                }
            }
        }
        let base64 = jpeg.base64EncodedString()

        do {
            let resp = try await EusoTripAPI.shared.documentRouter.classifyAndRoute(
                documentBase64: base64,
                mimeType: .jpeg,
                callerContext: "driver license"
            )
            licenseScan = makeLicenseResult(from: resp)
        } catch let apiErr as EusoTripAPIError {
            licenseScanError = "Couldn't read the license: \(apiErr.errorDescription ?? "classification failed")"
        } catch {
            licenseScanError = "Couldn't read the license: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    /// Turns a raw `ClassifyResponse` into a verdict + the fields we show,
    /// and auto-fills the CDL drafts only when the document is confidently
    /// a driver license. Never fabricates a type.
    private func makeLicenseResult(
        from resp: DocumentRouterAPI.ClassifyResponse
    ) -> LicenseScanResult {
        let fields = resp.extractedFields.compactMapValues { $0.asString }
        let isLicense = Self.isDriverLicenseType(resp.classifiedType)
        let confident = resp.confidence >= 0.6

        // Pull the identity fields by the keys the CDL parser emits
        // (`identifier`/`issuingJurisdiction`/`licenseClass`/
        // `expirationDate`), tolerating the common aliases Gemini may
        // return for each.
        let number = firstField(fields, ["identifier", "licenseNumber", "cdlNumber", "documentNumber"])
        let state  = firstField(fields, ["issuingJurisdiction", "state", "jurisdiction", "issuingState"])
        let cls    = firstField(fields, ["licenseClass", "class", "cdlClass"])
        let expiry = firstField(fields, ["expirationDate", "expiry", "expires", "dateOfExpiry"])

        var rows: [(String, String)] = []
        if let v = number, !v.isEmpty { rows.append(("License #", v)) }
        if let v = state,  !v.isEmpty { rows.append(("State", v)) }
        if let v = cls,    !v.isEmpty { rows.append(("Class", v)) }
        if let v = expiry, !v.isEmpty { rows.append(("Expires", v)) }

        let verdict: LicenseVerdict
        var didAutofill = false
        if isLicense && confident {
            // Confident license → auto-fill the drafts (only the fields we
            // actually got back).
            if let v = number, !v.isEmpty { draftCdlNumber = v }
            if let v = state,  !v.isEmpty { draftCdlState  = v.uppercased() }
            if let v = cls,    !v.isEmpty {
                let stripped = v.replacingOccurrences(of: "Class ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if ["A", "B", "C"].contains(stripped.uppercased()) {
                    draftLicenseClass = "CDL-" + stripped.uppercased()
                }
            }
            if let v = expiry, !v.isEmpty { draftCdlExpDate = v }
            didAutofill = !rows.isEmpty
            verdict = .confirmed(didAutofill: didAutofill)
        } else if isLicense {
            // It's a license, but the classifier isn't confident — show the
            // fields for the driver to confirm, but don't silently overwrite.
            verdict = .lowConfidence
        } else if resp.classifiedType.isEmpty || resp.classifiedType.lowercased() == "unknown" {
            verdict = .unknown
        } else {
            // It's confidently something else — refuse to call it a license.
            verdict = .mismatch
        }

        return LicenseScanResult(
            classifiedType: resp.classifiedType,
            confidence: resp.confidence,
            verdict: verdict,
            fieldRows: rows,
            warnings: resp.warnings
        )
    }

    private func firstField(_ fields: [String: String], _ keys: [String]) -> String? {
        for k in keys {
            if let v = fields[k]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                return v
            }
        }
        return nil
    }

    /// True for any of the server's driver-license / CDL classified types
    /// across US / CA / MX (mirrors `documentRouter.DocumentTypes`).
    private static func isDriverLicenseType(_ raw: String) -> Bool {
        let t = raw.lowercased()
        if ["us_cdl", "ca_cdl", "mx_cdl", "ca_class1_license", "mx_licencia_federal"].contains(t) {
            return true
        }
        // Defensive: catch generic "drivers_license" / "*_driver_license"
        // shapes the classifier may emit for a non-commercial license.
        return t.contains("driver") && t.contains("licen")
    }
}

// MARK: - License scan view model

/// Verdict for a single license classification — drives the honest
/// headline / tint / icon shown to the driver.
private enum LicenseVerdict {
    case confirmed(didAutofill: Bool)
    case lowConfidence
    case mismatch
    case unknown

    var headline: String {
        switch self {
        case .confirmed:     return "Driver license confirmed"
        case .lowConfidence: return "Looks like a license — please confirm"
        case .mismatch:      return "That doesn't look like a driver license"
        case .unknown:       return "Couldn't confidently identify this document"
        }
    }

    var tint: Color {
        switch self {
        case .confirmed:     return Brand.success
        case .lowConfidence: return Brand.warning
        case .mismatch:      return Brand.danger
        case .unknown:       return Brand.warning
        }
    }

    var icon: String {
        switch self {
        case .confirmed:     return "checkmark.seal.fill"
        case .lowConfidence: return "exclamationmark.triangle.fill"
        case .mismatch:      return "xmark.octagon.fill"
        case .unknown:       return "questionmark.circle.fill"
        }
    }

    var didAutofill: Bool {
        if case .confirmed(let f) = self { return f }
        return false
    }
}

/// Rendered result of a license classification.
private struct LicenseScanResult {
    let classifiedType: String
    let confidence: Double
    let verdict: LicenseVerdict
    let fieldRows: [(String, String)]
    let warnings: [String]

    /// Human label for the detected type — never invents one; falls back
    /// to a de-snaked rendering of whatever the server returned.
    var detectedLabel: String {
        switch classifiedType.lowercased() {
        case "us_cdl":              return "US CDL"
        case "ca_cdl", "ca_class1_license": return "Canada Class 1"
        case "mx_cdl", "mx_licencia_federal": return "Licencia Federal"
        case "", "unknown":         return "Unknown document"
        default:
            return classifiedType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Preview

#Preview("Edit profile · Dark") {
    ProfileEditView()
        .environmentObject(DriverProfileStore())
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("Edit profile · Light") {
    ProfileEditView()
        .environmentObject(DriverProfileStore())
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
