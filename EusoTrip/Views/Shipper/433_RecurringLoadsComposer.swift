//
//  433_RecurringLoadsComposer.swift
//  EusoTrip — Shipper · Recurring loads composer (deeper than 221 list).
//

import SwiftUI

struct RecurringLoadsComposerScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RecurringComposerBody() } nav: { shipperLifecycleNav() }
    }
}

private struct RecurringComposerBody: View {
    @Environment(\.palette) private var palette
    @State private var lane: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(90 * 86400)
    @State private var cadence: String = "weekly"
    @State private var dayOfWeek: String = "monday"
    @State private var rate: Double? = nil
    @State private var sending = false
    @State private var saved = false
    @State private var actionError: String? = nil

    // Server (recurringLoads.create) accepts weekly | biweekly | monthly only;
    // "daily" was offered here but rejected at validation (silent failure).
    // Removed until the server gains a daily cadence + daily recurrence advance.
    private let cadences = ["weekly", "biweekly", "monthly"]
    private let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if saved { LifecycleCard(accentGradient: true) { Text("Recurring schedule saved.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                fieldsCard
                cadenceCard
                rateCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "repeat").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · RECURRING LOAD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Set a recurrence").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LANE + WINDOW", icon: "map")
            VStack(alignment: .leading, spacing: 4) {
                Text("LANE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                TextField("Houston, TX → Dallas, TX", text: $lane).textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack {
                DatePicker("From", selection: $startDate, displayedComponents: .date).labelsHidden()
                Text("→").foregroundStyle(palette.textTertiary)
                DatePicker("To", selection: $endDate, displayedComponents: .date).labelsHidden()
            }
        }
    }

    private var cadenceCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CADENCE", icon: "repeat.circle")
            HStack(spacing: 6) {
                ForEach(cadences, id: \.self) { c in
                    Button { cadence = c } label: {
                        Text(c.capitalized).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(cadence == c ? .white : palette.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(cadence == c ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            if cadence == "weekly" || cadence == "biweekly" {
                Text("DAY OF WEEK").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary).padding(.top, 6)
                Picker("", selection: $dayOfWeek) { ForEach(days, id: \.self) { Text($0.capitalized).tag($0) } }.pickerStyle(.menu).labelsHidden()
            }
        }
    }

    private var rateCard: some View {
        LifecycleCard {
            LifecycleSection(label: "RATE PER LOAD", icon: "dollarsign.circle")
            TextField("e.g. 1900", value: $rate, format: .number).keyboardType(.numberPad).textFieldStyle(.plain)
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
                Text(sending ? "Saving…" : "Save schedule").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || lane.isEmpty || rate == nil)
    }

    private func save() async {
        await MainActor.run { sending = true; saved = false; actionError = nil }
        struct In: Encodable { let lane: String; let startISO: String; let endISO: String; let cadence: String; let dayOfWeek: String?; let rate: Double }
        struct Out: Decodable { let success: Bool?; let scheduleId: String? }
        let f = ISO8601DateFormatter()
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "recurringLoads.create",
                input: In(lane: lane,
                          startISO: f.string(from: startDate),
                          endISO: f.string(from: endDate),
                          cadence: cadence,
                          dayOfWeek: cadence.contains("week") ? dayOfWeek : nil,
                          rate: rate ?? 0)
            )
            await MainActor.run { saved = true }
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { sending = false }
    }
}

#Preview("433 · Recurring · Night") { RecurringLoadsComposerScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("433 · Recurring · Afternoon") { RecurringLoadsComposerScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
