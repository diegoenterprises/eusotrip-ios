//
//  FacilityProfileSheet.swift
//  EusoTrip — Universal facility profile (port of web FacilityProfile.tsx).
//
//  Role-agnostic facility intelligence surface. Used by Shipper /
//  Catalyst / Dispatch / Driver — any role that opens a load detail
//  with a known facilityId. Pulls real data off
//  `facilityIntelligence.{getById, getRequirements, getRatings, rate,
//  getPipelineTariffs}` — all real server endpoints (no stubs).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

struct FacilityRecord: Decodable, Hashable {
    let id: Int
    let facilityType: String?
    let facilitySubtype: String?
    let facilityName: String
    let operatorName: String?
    let ownerName: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let latitude: String?
    let longitude: String?
    let storageCapacityBbl: Int?
    let processingCapacityBpd: Int?
    let receivesPipeline: Bool?
    let receivesTanker: Bool?
    let receivesBarge: Bool?
    let receivesTruck: Bool?
    let receivesRail: Bool?
}

struct FacilityRatingsSummary: Decodable, Hashable {
    let avgRating: Double?
    let totalRatings: Int?
    let categories: [String: Double]?
}

struct FacilityRequirement: Decodable, Hashable, Identifiable {
    let id: Int
    let category: String?
    let label: String?
    let description: String?
    let isMandatory: Bool?
}

// MARK: - Sheet

public struct FacilityProfileSheet: View {
    public let facilityId: Int
    public init(facilityId: Int) { self.facilityId = facilityId }

    @Environment(\.dismiss) private var dismiss
    @State private var facility: FacilityRecord?
    @State private var ratings: FacilityRatingsSummary?
    @State private var requirements: [FacilityRequirement] = []
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var myRating: Int = 0
    @State private var submittingRating: Bool = false
    @State private var rateError: String?
    @State private var rateAck: String?

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if loading {
                        HStack { ProgressView().controlSize(.small); Text("Loading facility…").font(.callout).foregroundStyle(.secondary) }
                    } else if let err = error {
                        Text(err).font(.callout).foregroundStyle(.red)
                    } else if let f = facility {
                        identityCard(f)
                        connectivityCard(f)
                        if (f.storageCapacityBbl ?? 0) > 0 || (f.processingCapacityBpd ?? 0) > 0 {
                            capacityCard(f)
                        }
                        if let r = ratings { ratingsCard(r) }
                        ratingPanel
                        if !requirements.isEmpty { requirementsSection }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Facility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadAll() }
            .refreshable { await loadAll() }
        }
    }

    // MARK: subviews

    private func identityCard(_ f: FacilityRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: facilityIcon(f.facilityType))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.facilityName)
                        .font(.title3.weight(.bold))
                    HStack(spacing: 6) {
                        if let t = f.facilityType {
                            Text(t).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                        }
                        if let s = f.facilitySubtype {
                            Text("· \(s)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if let op = f.operatorName, !op.isEmpty {
                row(label: "OPERATOR", value: op)
            }
            if let ow = f.ownerName, !ow.isEmpty, f.ownerName != f.operatorName {
                row(label: "OWNER", value: ow)
            }
            let addr = [f.address, f.city, f.state, f.zip].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            if !addr.isEmpty {
                row(label: "ADDRESS", value: addr)
            }
            if let lat = f.latitude, let lng = f.longitude {
                row(label: "COORDS", value: "\(lat), \(lng)")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func connectivityCard(_ f: FacilityRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONNECTIVITY").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                if f.receivesPipeline == true { chip("Pipeline",  systemImage: "pipe.and.drop.fill", color: .blue) }
                if f.receivesTruck    == true { chip("Truck",     systemImage: "truck.box.fill",      color: .green) }
                if f.receivesRail     == true { chip("Rail",      systemImage: "tram.fill",           color: .purple) }
                if f.receivesBarge    == true { chip("Barge",     systemImage: "ferry.fill",          color: .cyan) }
                if f.receivesTanker   == true { chip("Tanker",    systemImage: "drop.triangle.fill",  color: .orange) }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func capacityCard(_ f: FacilityRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CAPACITY").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
            HStack(spacing: 14) {
                if let bbl = f.storageCapacityBbl, bbl > 0 {
                    stat(label: "STORAGE", value: "\(bbl.formatted(.number)) bbl")
                }
                if let bpd = f.processingCapacityBpd, bpd > 0 {
                    stat(label: "PROCESSING", value: "\(bpd.formatted(.number)) bpd")
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func ratingsCard(_ r: FacilityRatingsSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RATINGS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
                Spacer()
                Text("\(r.totalRatings ?? 0) reviews").font(.caption2).foregroundStyle(.tertiary)
            }
            if let avg = r.avgRating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text(String(format: "%.1f", avg))
                        .font(.title3.weight(.bold).monospacedDigit())
                }
            }
            if let cats = r.categories, !cats.isEmpty {
                ForEach(cats.keys.sorted(), id: \.self) { k in
                    HStack {
                        Text(k.capitalized).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f", cats[k] ?? 0))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var ratingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RATE THIS FACILITY").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        myRating = i
                    } label: {
                        Image(systemName: i <= myRating ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(i <= myRating ? Color.yellow : Color.secondary)
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            if myRating > 0 {
                Button {
                    Task { await submitRating() }
                } label: {
                    HStack(spacing: 6) {
                        if submittingRating { ProgressView().controlSize(.mini) }
                        Text(submittingRating ? "Submitting…" : "Submit \(myRating)-star rating")
                            .font(.callout.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(submittingRating)
            }
            if let ack = rateAck { Text(ack).font(.caption).foregroundStyle(.green) }
            if let err = rateError { Text(err).font(.caption).foregroundStyle(.red) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REQUIREMENTS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
            ForEach(requirements) { r in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: r.isMandatory == true ? "exclamationmark.shield.fill" : "info.circle.fill")
                        .foregroundStyle(r.isMandatory == true ? .red : .blue)
                        .font(.callout)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.label ?? r.category ?? "Requirement").font(.callout.weight(.semibold))
                        if let d = r.description, !d.isEmpty {
                            Text(d).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.secondarySystemBackground)))
            }
        }
    }

    // MARK: helpers

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary).frame(width: 80, alignment: .leading)
            Text(value).font(.footnote).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
            Text(value).font(.body.weight(.heavy).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func facilityIcon(_ raw: String?) -> String {
        switch (raw ?? "").uppercased() {
        case "TERMINAL":     return "building.columns.fill"
        case "REFINERY":     return "flame.fill"
        case "WELL":         return "drop.fill"
        case "RACK":         return "rectangle.stack.fill"
        case "TANK_BATTERY": return "cylinder.fill"
        case "TRANSLOAD":    return "arrow.left.arrow.right"
        case "BULK_PLANT":   return "building.2.fill"
        default:             return "building.fill"
        }
    }

    // MARK: pipeline

    private func loadAll() async {
        loading = true; error = nil
        async let a: Void = loadFacility()
        async let b: Void = loadRatings()
        async let c: Void = loadRequirements()
        _ = await (a, b, c)
        loading = false
    }

    private func loadFacility() async {
        struct In: Encodable { let facilityId: Int }
        do {
            let f: FacilityRecord = try await EusoTripAPI.shared.query(
                "facilityIntelligence.getById", input: In(facilityId: facilityId)
            )
            facility = f
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadRatings() async {
        struct In: Encodable { let facilityId: Int }
        do {
            let r: FacilityRatingsSummary = try await EusoTripAPI.shared.query(
                "facilityIntelligence.getRatings", input: In(facilityId: facilityId)
            )
            ratings = r
        } catch { /* optional */ }
    }

    private func loadRequirements() async {
        struct In: Encodable { let facilityId: Int }
        do {
            let r: [FacilityRequirement] = try await EusoTripAPI.shared.query(
                "facilityIntelligence.getRequirements", input: In(facilityId: facilityId)
            )
            requirements = r
        } catch { /* optional */ }
    }

    private func submitRating() async {
        submittingRating = true; rateError = nil
        struct In: Encodable { let facilityId: Int; let rating: Int }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "facilityIntelligence.rate",
                input: In(facilityId: facilityId, rating: myRating)
            )
            rateAck = "Rating submitted."
            myRating = 0
            await loadRatings()
        } catch {
            rateError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        submittingRating = false
    }
}

#Preview("Facility · Dark") {
    FacilityProfileSheet(facilityId: 1)
        .preferredColorScheme(.dark)
}

#Preview("Facility · Light") {
    FacilityProfileSheet(facilityId: 1)
        .preferredColorScheme(.light)
}
