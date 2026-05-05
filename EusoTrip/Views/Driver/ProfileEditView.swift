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
            // without additional work.
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    await MainActor.run { draftAvatarData = data }
                }
            }
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
