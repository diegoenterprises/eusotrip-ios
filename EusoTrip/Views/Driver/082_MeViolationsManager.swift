//
//  082_MeViolationsManager.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · violations manager)
//
//  Screen 082 · Me · Violations Manager — the driver's single pane
//  for every open violation the carrier owes resolution on. Combines
//  HOS (cycle / break / driving-limit) + inspection / DVIR defects
//  in one severity-ordered list, with per-row acknowledge + note
//  + resolve actions for the inspection-backed rows.
//
//  Pairs with 081 ELD Logs Detail — a certified day can still leave
//  carrier-side resolution work open (e.g. a roadside inspection
//  with defects found), and 082 is where that work gets cleared.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Inspection violations + stats come from the live
//      `compliance.getViolations` + `compliance.getViolationStats`
//      tRPC procedures — MCP-verified at
//      `frontend/server/routers/compliance.ts:1055, 1142`.
//
//    • HOS violations come from the live `hos.getViolations`
//      procedure (ELD-aware; falls back to the engine's in-memory
//      state when no ELD is connected).
//
//    • Resolve mutation round-trips through
//      `compliance.resolveViolation` which marks the backing
//      `inspections` row `status = passed` and records the resolver.
//      HOS violations are not individually resolvable — they clear
//      naturally as the driver rests back into compliance — so
//      those rows render without the resolve action.
//
//    • Empty state is server-confirmed. A driver with zero open
//      rows sees a quiet "All clear" hero, not a mock list of
//      fake "warning" placeholders.
//
//  Doctrine refs:
//    §2   Brand.warning on critical chip only. Gradient on resolve
//         CTA + success state. No Brand.info flats.
//    §4   Tokenized spacing, radii, type.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews land in `.error` under the preview runtime. No
//         fixtures.
//

import SwiftUI

// MARK: - Severity filter

private enum SeverityFilter: String, Hashable, Identifiable, CaseIterable {
    case all, critical, major, minor
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:      return "All"
        case .critical: return "Critical"
        case .major:    return "Major"
        case .minor:    return "Minor"
        }
    }
    /// Server value — "all" becomes nil (no filter).
    var serverValue: String? {
        self == .all ? nil : rawValue
    }
}

// MARK: - Screen root

struct MeViolationsManager: View {
    @Environment(\.palette) var palette
    @StateObject private var store = ViolationsStore()

    @State private var severityFilter: SeverityFilter = .all
    @State private var showResolvedToo: Bool = false
    @State private var resolveTarget: UnifiedViolation?
    @State private var resolveNote: String = ""
    @State private var lastToast: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                statsStrip
                filters
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let rows):
                    violationsList(rows)
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .onChange(of: severityFilter) { _, newValue in
            store.severity = newValue.serverValue
        }
        .onChange(of: showResolvedToo) { _, newValue in
            store.status = newValue ? nil : "open"
        }
        .sheet(item: $resolveTarget, onDismiss: { resolveNote = "" }) { row in
            resolveSheet(for: row)
                .eusoSheetX()
        }
        .overlay(alignment: .bottom) {
            if let toast = lastToast {
                toastView(toast)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s6)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Violations")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("HOS · DVIR · roadside inspections")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Stats strip

    @ViewBuilder
    private var statsStrip: some View {
        if let s = store.stats {
            HStack(spacing: Space.s2) {
                statTile(label: "OPEN",      value: "\(s.open)",       emphasis: s.open > 0)
                statTile(label: "CRITICAL",  value: "\(s.critical)",   warn: s.critical > 0)
                statTile(label: "RESOLVED",  value: "\(s.resolved)",   emphasis: false)
            }
        }
    }

    private func statTile(label: String, value: String, emphasis: Bool = false, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .monospacedDigit()
                .foregroundStyle(
                    warn
                        ? AnyShapeStyle(Brand.warning)
                        : (emphasis
                           ? AnyShapeStyle(LinearGradient.diagonal)
                           : AnyShapeStyle(palette.textPrimary))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(warn ? Brand.warning.opacity(0.4) : palette.borderFaint.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: Filters

    private var filters: some View {
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                ForEach(SeverityFilter.allCases) { filter in
                    severityPill(filter)
                }
            }
            Toggle(isOn: $showResolvedToo) {
                Text("Show resolved too")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .toggleStyle(GradientToggleStyle())
        }
    }

    private func severityPill(_ filter: SeverityFilter) -> some View {
        let on = filter == severityFilter
        return Button {
            severityFilter = filter
        } label: {
            Text(filter.label)
                .font(EType.caption)
                .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    ZStack {
                        if on {
                            Capsule().fill(LinearGradient.diagonal)
                        } else {
                            Capsule().fill(palette.bgCard.opacity(0.85))
                        }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(on ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 76)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "checkmark.shield",
            title: showResolvedToo ? "No violations in your file" : "All clear",
            subtitle: showResolvedToo
                ? "Nothing on record. When HOS or inspection events land they'll show up here."
                : "No open HOS, DVIR, or inspection violations to resolve. Flip the toggle above to see resolved history."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load violations")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: List

    @ViewBuilder
    private func violationsList(_ rows: [UnifiedViolation]) -> some View {
        if rows.isEmpty {
            emptyHero
        } else {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("VIOLATIONS")
                        .font(EType.micro).tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(rows.count)")
                        .font(EType.micro).tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        violationRow(row)
                    }
                }
            }
        }
    }

    private func violationRow(_ v: UnifiedViolation) -> some View {
        let mutating = store.resolvingId == v.id
        return HStack(alignment: .top, spacing: Space.s3) {
            severityBadge(v.severity)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.s2) {
                    Text(v.kindLabel)
                        .font(EType.micro).tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
                        )
                    if let pretty = shortDate(v.date) {
                        Text(pretty)
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }
                Text(v.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(v.subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2)

                if v.isResolvable {
                    HStack(spacing: Space.s2) {
                        Button {
                            resolveTarget = v
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("RESOLVE")
                                    .font(EType.micro).tracking(1.2)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(LinearGradient.diagonal))
                        }
                        .buttonStyle(.plain)
                        .disabled(mutating)
                        .opacity(mutating ? 0.6 : 1.0)

                        if mutating {
                            ProgressView().progressViewStyle(.circular).controlSize(.small)
                        }
                    }
                    .padding(.top, 2)
                } else if v.isResolved {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("RESOLVED")
                            .font(EType.micro).tracking(1.2)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: Space.s2)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(rowBorder(for: v.severity), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func severityBadge(_ severity: String) -> some View {
        let (icon, tint): (String, Color) = {
            switch severity {
            case "critical": return ("exclamationmark.octagon.fill", Brand.warning)
            case "major":    return ("exclamationmark.triangle.fill", Brand.warning)
            default:         return ("exclamationmark.circle", palette.textSecondary)
            }
        }()
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(palette.bgCard.opacity(0.8))
            )
    }

    private func rowBorder(for severity: String) -> Color {
        severity == "critical" ? Brand.warning.opacity(0.45) : palette.borderFaint
    }

    // MARK: Resolve sheet

    private func resolveSheet(for v: UnifiedViolation) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RESOLVING")
                        .font(EType.micro).tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                    Text(v.title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(v.subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }

                Text("What corrective action did you take? (Optional)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                TextEditor(text: $resolveNote)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )

                Text("Resolving acknowledges that the corrective action was performed and closes this violation in the carrier's compliance record. A resolved-by stamp with your name + timestamp is written to the audit trail.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    Task {
                        let note = resolveNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        let ok = await store.resolve(id: v.id, notes: note.isEmpty ? nil : note)
                        resolveTarget = nil
                        flashToast(ok ? "Violation resolved" : "Couldn't resolve — try again")
                    }
                } label: {
                    Text("Mark resolved")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(Space.s4)
            .navigationTitle("Resolve violation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { resolveTarget = nil }
                }
            }
            .background(palette.bgPage.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "scale.3d")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("How resolution flows to FMCSA")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Resolutions close the carrier's compliance record but do not overwrite the underlying CSA event. DataQs challenges (49 CFR §386) remain the canonical path to correct an FMCSA-reported violation — the corrective note here is the carrier's internal audit trail.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Toast

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
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 14, y: 6)
    }

    private func flashToast(_ text: String) {
        withAnimation { lastToast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            await MainActor.run { withAnimation { lastToast = nil } }
        }
    }

    // MARK: Date helpers

    private func shortDate(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        // YYYY-MM-DD first
        let ymd = DateFormatter()
        ymd.calendar = Calendar(identifier: .gregorian)
        ymd.locale = Locale(identifier: "en_US_POSIX")
        ymd.dateFormat = "yyyy-MM-dd"
        if let d = ymd.date(from: raw) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: d)
        }
        // Fallback ISO-8601 for HOS timestamps
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
            let out = DateFormatter()
            out.dateFormat = "MMM d · HH:mm"
            return out.string(from: d)
        }
        return raw
    }
}

// MARK: - Screen wrapper

struct MeViolationsManagerScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeViolationsManager()
        } nav: {
            BottomNav(
                leading: driverNavLeading_082(),
                trailing: driverNavTrailing_082(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_082() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_082() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("082 · Me Violations · Night") {
    MeViolationsManagerScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("082 · Me Violations · Afternoon") {
    MeViolationsManagerScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
