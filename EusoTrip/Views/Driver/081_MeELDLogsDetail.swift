//
//  081_MeELDLogsDetail.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · ELD logs detail)
//
//  Screen 081 · Me · ELD Logs Detail — the driver's §395.8 Record of
//  Duty Status (RODS) drill-in. Gives drivers the compliance actions
//  they legally need to do daily — certify the log (§395.8(g)),
//  attach §395.8(j) remarks, review violations — without a laptop.
//
//  Distinct from 074 Me · HOS Logs (read-only cycle overview). 081
//  is the editable per-day surface: 7-day day-picker strip, full 24h
//  segment list per day, tap-to-add-remark on any entry, one-tap
//  certify with the driver's full name as the §395.8(g) signature.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Every segment comes from the live `hos.getLogHistory` and
//      `hos.getDailyLog` procedures via the existing `HOSLiveStore`
//      (MCP-verified at `frontend/server/routers/hos.ts`).
//
//    • Certify action round-trips through `hos.certifyLog` which
//      writes the `certified=true` + `certifiedAt` + signature hash
//      on the backing `hos_logs` row. No client-side sleight of
//      hand; the server is the source of truth.
//
//    • Remark action round-trips through `hos.addRemark` and attaches
//      the note to the active segment (or an explicit entry id when
//      the driver taps a specific row).
//
//    • Violations are surfaced server-authoritatively — the view
//      never computes new violations locally.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on certify CTA, certified seal,
//         remark banner. Brand.warning only for uncertified-but-
//         past-24hrs or open violations.
//    §4   Tokenized spacing, radii, type.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews compile — HOSLiveStore lands in `.isLoading` under
//         preview runtime. No fixtures.
//

import SwiftUI

// MARK: - Screen root

struct MeELDLogsDetail: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = HOSLiveStore()

    /// Currently-selected date (YYYY-MM-DD). Defaults to today.
    @State private var selectedDate: String = Self.todayISO()
    /// Segment tapped for the remark sheet.
    @State private var remarkTarget: HOSLogEntry?
    @State private var remarkText: String = ""
    /// Certify-signature sheet gate.
    @State private var showCertifySheet: Bool = false
    @State private var signatureText: String = ""
    @State private var lastToast: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                daysStrip
                if store.status == nil && store.isLoading {
                    skeleton
                } else if let log = logForSelection {
                    dailyHeader(log)
                    violationsStrip(log)
                    segmentsSection(log)
                    certifyActionRow(log)
                } else {
                    emptyHero
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.bootstrap() }
        .refreshable { await store.refreshAll() }
        .sheet(item: $remarkTarget, onDismiss: { remarkText = "" }) { entry in
            remarkSheet(for: entry)
                .eusoSheetX()
        }
        .sheet(isPresented: $showCertifySheet, onDismiss: { signatureText = "" }) {
            certifySheet
                .eusoSheetX()
        }
        .overlay(alignment: .bottom) {
            if let toast = lastToast {
                toastView(toast)
                    .padding(.bottom, Space.s6)
                    .padding(.horizontal, Space.s4)
                    .transition(.opacity)
            }
        }
    }

    // MARK: Data slicing

    /// Find the log for the selected date across today+history.
    private var logForSelection: HOSDailyLog? {
        if let today = store.today, today.date == selectedDate { return today }
        return store.history.first { $0.date == selectedDate }
    }

    /// The last 8 days (newest-first) — today prepended if missing.
    private var dayStripDates: [String] {
        let ordered = orderedHistoryDates()
        return Array(ordered.prefix(8))
    }

    private func orderedHistoryDates() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let today = store.today?.date ?? Self.todayISO()
        if !seen.contains(today) {
            seen.insert(today)
            result.append(today)
        }
        for log in store.history {
            if !seen.contains(log.date) {
                seen.insert(log.date)
                result.append(log.date)
            }
        }
        return result
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("ELD · RODS")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Certify · remark · review violations")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: (store.isLoading || store.isChangingStatus) ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Day strip

    private var daysStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(dayStripDates, id: \.self) { date in
                    dayPill(date)
                }
            }
        }
    }

    private func dayPill(_ date: String) -> some View {
        let selected = date == selectedDate
        let log = store.today?.date == date ? store.today : store.history.first { $0.date == date }
        let certified = log?.certified ?? false
        let label = shortDayLabel(date)
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 2) {
                Text(label.primary)
                    .font(EType.bodyStrong)
                    .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                Text(label.secondary)
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(selected ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(palette.textTertiary))
                if certified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(LinearGradient.diagonal))
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .frame(width: 76)
            .background(
                ZStack {
                    if selected {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCard.opacity(0.8))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty / skeleton

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "calendar.badge.clock",
            title: "No log for this day",
            subtitle: "Pick another day from the strip above, or pull to refresh."
        )
    }

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.45))
                .frame(height: 92)
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 56)
            }
        }
    }

    // MARK: Daily header

    private func dailyHeader(_ log: HOSDailyLog) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(longDayLabel(log.date))
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: Space.s2) {
                    metric("DRIVE", log.drivingDisplay)
                    metric("ON-DUTY", log.onDutyDisplay)
                    if let miles = log.milesDriven, miles > 0 {
                        metric("MILES", String(Int(miles.rounded())))
                    }
                }
            }
            Spacer()
            if log.certified {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("CERTIFIED")
                        .font(EType.micro).tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "exclamationmark.seal")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                    Text("PENDING")
                        .font(EType.micro).tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Violations strip

    @ViewBuilder
    private func violationsStrip(_ log: HOSDailyLog) -> some View {
        if !log.violations.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                    Text("VIOLATIONS · \(log.violations.count)")
                        .font(EType.micro).tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(spacing: Space.s2) {
                    ForEach(Array(log.violations.prefix(5).enumerated()), id: \.offset) { _, v in
                        violationRow(v)
                    }
                }
            }
        }
    }

    private func violationRow(_ v: HOSViolation) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.message ?? "Compliance violation")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if let ts = v.timestamp, let pretty = prettyTime(ts) {
                    Text(pretty)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: Space.s2)
            if let sev = v.severity {
                Text(sev.uppercased())
                    .font(EType.micro).tracking(1.1)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 2)
                    .background(Capsule().strokeBorder(Brand.warning.opacity(0.6), lineWidth: 1))
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: Segments

    @ViewBuilder
    private func segmentsSection(_ log: HOSDailyLog) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("SEGMENTS")
                    .font(EType.micro).tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(log.entries.count)")
                    .font(EType.micro).tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }
            if log.entries.isEmpty {
                HStack(spacing: Space.s3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                    Text("No duty segments on this day.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                .padding(Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(log.entries) { entry in
                        segmentRow(entry)
                    }
                }
            }
        }
    }

    private func segmentRow(_ e: HOSLogEntry) -> some View {
        Button {
            remarkTarget = e
        } label: {
            HStack(spacing: Space.s3) {
                dutyBadge(e.duty)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.s2) {
                        Text(timeRange(e))
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        if let m = e.durationMinutes {
                            Text("· \(HOSStatus.formatHours(Double(m) / 60.0))")
                                .font(EType.caption)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    if let loc = e.locationDescription, !loc.isEmpty {
                        Text(loc)
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let remark = e.remark, !remark.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(LinearGradient.diagonal)
                            Text(remark)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    if e.automaticEntry == true {
                        Text("AUTO")
                            .font(EType.micro).tracking(1.1)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(e.duty.shortLabel) segment \(timeRange(e))")
        .accessibilityHint("Opens remark editor")
    }

    @ViewBuilder
    private func dutyBadge(_ duty: HOSDutyCode) -> some View {
        Text(duty.shortLabel)
            .font(EType.micro)
            .tracking(1.3)
            .foregroundStyle(duty == .driving ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
            .frame(width: 40, height: 36)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(duty == .driving ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard.opacity(0.8)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
            )
    }

    // MARK: Certify CTA

    @ViewBuilder
    private func certifyActionRow(_ log: HOSDailyLog) -> some View {
        if log.certified {
            HStack(spacing: Space.s2) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log certified")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if let at = log.certifiedAt, let pretty = prettyTime(at) {
                        Text(pretty)
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "signature")
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .eusoCard(radius: Radius.lg)
        } else {
            Button {
                signatureText = session.user?.name ?? ""
                showCertifySheet = true
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "signature")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Certify this day · §395.8(g)")
                        .font(EType.bodyStrong)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Certify sheet

    private var certifySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("Your signature is your legal certification that this day's log is true and complete per 49 CFR §395.8(g).")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Type your full legal name", text: $signatureText)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Button {
                    Task {
                        let ok = await store.certify(
                            date: selectedDate,
                            signature: signatureText.trimmingCharacters(in: .whitespaces)
                        )
                        showCertifySheet = false
                        flashToast(ok ? "Log certified" : "Couldn't certify — try again")
                    }
                } label: {
                    Text("Certify \(longDayLabel(selectedDate))")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(signatureText.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(signatureText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
            }
            .padding(Space.s4)
            .navigationTitle("Certify log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { showCertifySheet = false }
                }
            }
            .background(palette.bgPage.ignoresSafeArea())
        }
        .presentationDetents([.medium])
    }

    // MARK: Remark sheet

    private func remarkSheet(for entry: HOSLogEntry) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("§395.8(j) remark")
                        .font(EType.micro).tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(entry.duty.shortLabel) · \(timeRange(entry))")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if let loc = entry.locationDescription, !loc.isEmpty {
                        Text(loc)
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if let existing = entry.remark, !existing.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("CURRENT REMARK")
                            .font(EType.micro).tracking(1.1)
                            .foregroundStyle(palette.textTertiary)
                        Text(existing)
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                    }
                    .padding(Space.s3)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCard.opacity(0.6))
                    )
                }
                Text("Add a remark")
                    .font(EType.micro).tracking(1.2)
                    .foregroundStyle(palette.textTertiary)
                TextEditor(text: $remarkText)
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
                Spacer()
                Button {
                    let text = remarkText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    Task {
                        let ok = await store.addRemark(text, entryId: entry.id)
                        remarkTarget = nil
                        flashToast(ok ? "Remark added" : "Couldn't add remark — try again")
                    }
                } label: {
                    Text("Save remark")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(remarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(remarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(Space.s4)
            .navigationTitle("Remark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { remarkTarget = nil }
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
                Image(systemName: "scroll")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("ELD-connected · §395.15 compliant")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Segments mirror the ELD feed verbatim. Certify the day's log before your next shift so the device carries the signature into roadside inspections. Remarks are timestamped and immutable once saved.")
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

    private struct DayStripLabel { let primary: String; let secondary: String }

    private func shortDayLabel(_ ymd: String) -> DayStripLabel {
        guard let d = Self.dateFrom(ymd) else { return .init(primary: ymd, secondary: "") }
        let cal = Calendar.current
        if cal.isDateInToday(d)    { return .init(primary: "Today",     secondary: relativeMonth(d)) }
        if cal.isDateInYesterday(d){ return .init(primary: "Yest.",     secondary: relativeMonth(d)) }
        let dow = DateFormatter()
        dow.dateFormat = "EEE"
        let md = DateFormatter()
        md.dateFormat = "MMM d"
        return .init(primary: dow.string(from: d), secondary: md.string(from: d))
    }

    private func longDayLabel(_ ymd: String) -> String {
        guard let d = Self.dateFrom(ymd) else { return ymd }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let out = DateFormatter()
        out.dateFormat = "EEEE, MMM d"
        return out.string(from: d)
    }

    private func relativeMonth(_ date: Date) -> String {
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: date)
    }

    private func timeRange(_ e: HOSLogEntry) -> String {
        let start = clockTime(e.startDate)
        if let end = e.endDate { return "\(start)–\(clockTime(end))" }
        return "\(start) · now"
    }

    private func clockTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func prettyTime(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM d · HH:mm"
        return out.string(from: d)
    }

    // MARK: Static date helpers

    private static let ymdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func todayISO() -> String {
        ymdFormatter.string(from: Date())
    }

    private static func dateFrom(_ ymd: String) -> Date? {
        ymdFormatter.date(from: ymd)
    }
}

// MARK: - Screen wrapper

struct MeELDLogsDetailScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeELDLogsDetail()
        } nav: {
            BottomNav(
                leading: driverNavLeading_081(),
                trailing: driverNavTrailing_081(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_081() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_081() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("081 · Me ELD Logs · Night") {
    MeELDLogsDetailScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("081 · Me ELD Logs · Afternoon") {
    MeELDLogsDetailScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
