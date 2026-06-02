//
//  1109_VerticalEndorsementSheet.swift
//  EusoTrip — Compliance · Vertical overlay endorsement (RIOS §11).
//
//  A .sheet-content View (capture/confirm sheet precedent, 1100–1110) that
//  attaches a vertical-specific overlay endorsement to an entity:
//
//      HAZMAT · FSMA · LIVESTOCK · OVERSIZE · INTERMODAL · HHG · AUTO
//
//  The officer picks a vertical from a MetricTile grid, fills the optional
//  endorsement type / value / expiry, and commits via
//  `registration.attachVerticalEndorsement`. The server's AttachResult.status
//  is rendered VERBATIM — we only paint green/"Verified" when status reads
//  as a clear/verified/active state; "pending" / "provider_unavailable" /
//  unknown all surface a neutral Brand.warning "Pending review" state, never
//  a fabricated success. Thrown errors surface their LocalizedError text.
//
//  Presented as sheet content (NOT slide-up navigation): hosts its own
//  header + dismiss affordance. The Tier wizard (1111) is the pushed full
//  Shell screen; this is its companion capture sheet.
//

import SwiftUI

// MARK: - Vertical catalog

/// The seven overlay verticals the endorsement endpoint accepts. The
/// `code` is the exact token sent to `registration.attachVerticalEndorsement`
/// (server-side enum); the rest is presentation only.
private struct EndorsementVertical: Identifiable, Hashable {
    let code: String          // wire value, e.g. "HAZMAT"
    let title: String         // grid tile label
    let icon: String          // SF Symbol
    let accent: Color
    let typeHint: String      // placeholder for the endorsement-type field
    let valueHint: String     // placeholder for the value field

    var id: String { code }
}

private let kEndorsementVerticals: [EndorsementVertical] = [
    EndorsementVertical(code: "HAZMAT", title: "Hazmat", icon: "exclamationmark.triangle.fill",
                        accent: Brand.hazmat, typeHint: "e.g. H endorsement", valueHint: "e.g. Classes 3, 8"),
    EndorsementVertical(code: "FSMA", title: "FSMA", icon: "leaf.fill",
                        accent: Brand.success, typeHint: "e.g. Sanitary transport", valueHint: "e.g. Reefer SOP ref"),
    EndorsementVertical(code: "LIVESTOCK", title: "Livestock", icon: "hare.fill",
                        accent: Brand.info, typeHint: "e.g. Animal welfare", valueHint: "e.g. Cert / handler ID"),
    EndorsementVertical(code: "OVERSIZE", title: "Oversize", icon: "arrow.left.and.right",
                        accent: Brand.escort, typeHint: "e.g. Superload permit", valueHint: "e.g. Permit number"),
    EndorsementVertical(code: "INTERMODAL", title: "Intermodal", icon: "shippingbox.fill",
                        accent: Brand.rail, typeHint: "e.g. UIIA interchange", valueHint: "e.g. SCAC"),
    EndorsementVertical(code: "HHG", title: "Household", icon: "house.fill",
                        accent: Brand.magenta, typeHint: "e.g. HHG authority", valueHint: "e.g. MC number"),
    EndorsementVertical(code: "AUTO", title: "Auto", icon: "car.fill",
                        accent: Brand.blue, typeHint: "e.g. Auto-hauler bond", valueHint: "e.g. Bond / cargo limit"),
]

// MARK: - Honest endorsement state

/// Maps an AttachResult into the three honest presentation states the
/// doctrine allows. Never reports success from a pending / unavailable /
/// unknown server status.
private enum EndorsementOutcome {
    case verified(status: String, expiresAt: String?)   // green — server said clear/verified/active
    case pending(status: String)                        // amber — pending / provider_unavailable / unknown
    case failed(message: String)                        // red — thrown error

    init(result: RegistrationAPI.AttachResult) {
        let raw = (result.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = raw.lowercased()
        let clearStates: Set<String> = ["verified", "clear", "active", "approved", "attached", "valid"]
        if clearStates.contains(normalized) {
            self = .verified(status: raw.isEmpty ? "verified" : raw, expiresAt: result.expiresAt)
        } else {
            // pending / provider_unavailable / manual_review / null / anything
            // unrecognized → neutral pending, NEVER a fake success.
            self = .pending(status: raw.isEmpty ? "pending review" : raw)
        }
    }
}

// MARK: - Sheet

struct VerticalEndorsementSheet: View {
    /// Active theme (Night / Afternoon) injected by the presenter so the
    /// sheet matches the host surface even though it isn't wrapped in Shell.
    let theme: Theme.Palette

    /// Entity the endorsement is attached to. Defaults match the API's own
    /// default `entityType` so a company-scoped officer can present this
    /// with just an id.
    let entityId: Int
    var entityType: String = "company"

    /// Optional pre-selected vertical (e.g. when opened from a hazmat-load
    /// flow). When nil the officer picks from the grid.
    var initialVertical: String? = nil

    /// Fired after a successful (server-confirmed clear/verified) attach so
    /// the presenter can refresh its gate board. Pending outcomes do NOT
    /// fire this — they aren't a confirmed success.
    var onAttached: ((RegistrationAPI.AttachResult) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var selected: EndorsementVertical?
    @State private var endorsementType: String = ""
    @State private var value: String = ""
    @State private var expiresAt: String = ""   // ISO-ish free text (YYYY-MM-DD); optional
    @State private var sending = false
    @State private var outcome: EndorsementOutcome?

    var body: some View {
        ZStack(alignment: .top) {
            theme.bgSheet.ignoresSafeArea()
            theme.bgPage.opacity(scheme == .dark ? 0.6 : 0.0).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    outcomeBanner
                    verticalGrid
                    if selected != nil {
                        detailFields
                    }
                    ctaRow
                    Color.clear.frame(height: Space.s8)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s5)
            }
        }
        .environment(\.palette, theme)
        .presentationDragIndicator(.visible)
        .onAppear {
            if selected == nil, let code = initialVertical {
                selected = kEndorsementVerticals.first { $0.code == code }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("COMPLIANCE · VERTICAL ENDORSEMENT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Attach overlay endorsement")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(theme.textPrimary)
                Text("\(entityType.capitalized) #\(entityId)")
                    .font(EType.mono(.caption))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: Space.s2)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(theme.bgCardSoft))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: Outcome banner (honest states)

    @ViewBuilder
    private var outcomeBanner: some View {
        switch outcome {
        case .verified(let status, let expiry):
            LifecycleCard(accentGradient: true) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Endorsement \(status).")
                            .font(EType.bodyStrong).foregroundStyle(theme.textPrimary)
                        if let expiry, !expiry.isEmpty {
                            Text("Valid until \(expiry)")
                                .font(EType.caption).foregroundStyle(theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        case .pending(let status):
            LifecycleCard(accentWarning: true) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "clock.badge.questionmark").foregroundStyle(Brand.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pendingHeadline(for: status))
                            .font(EType.bodyStrong).foregroundStyle(theme.textPrimary)
                        Text("Server status: \(status). This is not a confirmed approval — it will be reviewed.")
                            .font(EType.caption).foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        case .failed(let message):
            LifecycleCard(accentDanger: true) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(Brand.danger)
                    Text(message)
                        .font(EType.caption).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        case .none:
            EmptyView()
        }
    }

    private func pendingHeadline(for status: String) -> String {
        let s = status.lowercased()
        if s.contains("unavailable") { return "Provider unavailable — manual review" }
        return "Pending review"
    }

    // MARK: Vertical grid (MetricTile-based picker)

    private var verticalGrid: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            LifecycleSection(label: "VERTICAL", icon: "square.grid.2x2.fill")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                                GridItem(.flexible(), spacing: Space.s2)],
                      spacing: Space.s2) {
                ForEach(kEndorsementVerticals) { v in
                    Button {
                        selectVertical(v)
                    } label: {
                        verticalTile(v)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(v.title)
                    .accessibilityAddTraits(selected == v ? .isSelected : [])
                }
            }
        }
    }

    private func verticalTile(_ v: EndorsementVertical) -> some View {
        let isSel = (selected == v)
        return VStack(alignment: .leading, spacing: Space.s1) {
            HStack {
                Image(systemName: v.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(v.accent)
                Spacer(minLength: 0)
                if isSel {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(v.accent)
                }
            }
            Text(v.title.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(isSel ? v.accent.opacity(0.9) : theme.textTertiary)
            Text(v.code)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSel ? v.accent : theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(v.accent.opacity(isSel ? 0.16 : 0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(v.accent.opacity(isSel ? 0.7 : 0.25),
                              lineWidth: isSel ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func selectVertical(_ v: EndorsementVertical) {
        selected = v
        // A new vertical invalidates a prior outcome banner so the officer
        // never reads a stale "verified" against a different vertical.
        outcome = nil
    }

    // MARK: Detail fields

    private var detailFields: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            LifecycleSection(label: "ENDORSEMENT DETAIL", icon: "doc.text.fill")
            GlassField(label: "Endorsement type",
                       placeholder: selected?.typeHint ?? "Type",
                       icon: "tag",
                       text: $endorsementType,
                       autocapitalization: .words)
            GlassField(label: "Value",
                       placeholder: selected?.valueHint ?? "Value",
                       icon: "number",
                       text: $value,
                       autocapitalization: .characters)
            GlassField(label: "Expires (YYYY-MM-DD)",
                       placeholder: "Optional",
                       icon: "calendar",
                       text: $expiresAt,
                       keyboardType: .numbersAndPunctuation,
                       autocapitalization: .never,
                       error: expiryError)
            Text("Type, value and expiry are optional — the server records what you provide and flags the rest for review.")
                .font(EType.caption)
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Lightweight, non-blocking format hint for the expiry field. Empty is
    /// valid (the field is optional); a malformed non-empty entry shows a
    /// hint but does not hard-block submit (server is source of truth).
    private var expiryError: String? {
        let s = expiresAt.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let ok = s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        return ok ? nil : "Use YYYY-MM-DD"
    }

    // MARK: CTA

    private var ctaRow: some View {
        VStack(spacing: Space.s2) {
            CTAButton(
                title: sending ? "Attaching…" : "Attach endorsement",
                action: { Task { await submit() } },
                trailingIcon: sending ? nil : "checkmark.seal",
                isLoading: sending
            )
            .opacity(selected == nil ? 0.5 : 1.0)
            .disabled(selected == nil || sending)

            if selected == nil {
                Text("Pick a vertical to continue.")
                    .font(EType.caption).foregroundStyle(theme.textTertiary)
            }
        }
    }

    // MARK: Submit

    private func submit() async {
        guard let v = selected, !sending else { return }
        sending = true
        outcome = nil

        let trimmedType = endorsementType.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpiry = expiresAt.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let result = try await EusoTripAPI.shared.registration.attachVerticalEndorsement(
                entityId: entityId,
                entityType: entityType,
                vertical: v.code,
                endorsementType: trimmedType.isEmpty ? nil : trimmedType,
                value: trimmedValue.isEmpty ? nil : trimmedValue,
                expiresAt: trimmedExpiry.isEmpty ? nil : trimmedExpiry
            )
            let resolved = EndorsementOutcome(result: result)
            outcome = resolved
            // Only a server-confirmed clear/verified outcome counts as an
            // attach worth bubbling up to the presenter.
            if case .verified = resolved {
                onAttached?(result)
            }
        } catch let err as LocalizedError {
            outcome = .failed(message: err.errorDescription ?? "Couldn't attach the endorsement.")
        } catch {
            outcome = .failed(message: error.localizedDescription)
        }
        sending = false
    }
}

// MARK: - Previews

#Preview("1109 · Vertical endorsement · Night") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            VerticalEndorsementSheet(theme: Theme.dark, entityId: 4021)
                .environmentObject(EusoTripSession())
                .preferredColorScheme(.dark)
        }
}

#Preview("1109 · Vertical endorsement · Afternoon") {
    Color.white
        .sheet(isPresented: .constant(true)) {
            VerticalEndorsementSheet(theme: Theme.light, entityId: 4021, initialVertical: "HAZMAT")
                .environmentObject(EusoTripSession())
                .preferredColorScheme(.light)
        }
}
