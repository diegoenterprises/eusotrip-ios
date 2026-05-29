//
//  555_RailConsistBoard.swift
//  EusoTrip — Rail Engineer · Consist Board (carrier vantage).
//

import SwiftUI

struct RailConsistBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailConsistBoardBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct TrainConsist: Decodable, Identifiable {
    let id: Int
    let consistNumber: String?
    let originYard: String?
    let destinationYard: String?
    let totalCars: Int?
    let assignedCars: Int?
    let hazmatCars: Int?
    let status: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id, consistNumber, totalCars, status
        case originYardId, destinationYardId
        case locomotiveUnits, totalWeight, totalLengthFeet, trainType
        case departureTime, arrivalTime, engineerId, conductorId, railroadId, ptcActive
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.consistNumber = try c.decodeIfPresent(String.self, forKey: .consistNumber)
        self.totalCars = try c.decodeIfPresent(Int.self, forKey: .totalCars)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        // Server returns IDs; iOS struct expects display strings. Default to nil if ID missing.
        let originYardId = try c.decodeIfPresent(Int.self, forKey: .originYardId)
        let destYardId = try c.decodeIfPresent(Int.self, forKey: .destinationYardId)
        self.originYard = originYardId.map { "Yard #\($0)" }
        self.destinationYard = destYardId.map { "Yard #\($0)" }
        // Server doesn't provide assignedCars or hazmatCars; default to nil.
        self.assignedCars = nil
        self.hazmatCars = nil
        self.note = nil
    }
}

private struct ConsistsResponse: Decodable {
    let consists: [TrainConsist]
    let total: Int
}

private struct RailConsistBoardBody: View {
    @Environment(\.palette) private var palette
    @State private var consists: [TrainConsist] = []
    @State private var totalCars = 0
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var building = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading consists…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if consists.isEmpty {
                    EusoEmptyState(systemImage: "tram.fill", title: "No consists",
                                   subtitle: "Building and rolling consists will appear here.")
                } else {
                    VStack(spacing: Space.s2) { ForEach(consists) { consistCard($0) } }
                    CTAButton(title: building ? "Building…" : "Build new consist", leadingIcon: "plus",
                              action: { Task { await buildConsist() } })
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Image(systemName: "tram.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · CONSISTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Consist board").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("\(consists.count) consists building / rolling · \(totalCars) cars total")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func consistCard(_ c: TrainConsist) -> some View {
        let rolling = (c.status ?? "").lowercased() == "rolling"
        let total = c.totalCars ?? 0
        let assigned = c.assignedCars ?? total
        let hazmat = c.hazmatCars ?? 0
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(c.consistNumber ?? "—").font(.system(size: 15, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: (c.status ?? "—").uppercased(), kind: rolling ? .info : .neutral)
            }
            Text("\(c.originYard ?? "—") → \(c.destinationYard ?? "—") · \(total) cars\(c.note.map { " · \($0)" } ?? "")")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(idx >= assigned ? AnyShapeStyle(Color.clear)
                              : (idx >= total - hazmat ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(Brand.success)))
                        .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(idx >= assigned ? palette.textTertiary : Color.clear, lineWidth: 1.2))
                        .frame(width: 11, height: 14)
                }
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func load() async {
        loading = true; loadError = nil
        struct ConsistsIn: Encodable { let limit: Int; let offset: Int }
        do {
            let result: ConsistsResponse = try await EusoTripAPI.shared.query(
                "railShipments.getTrainConsists", input: ConsistsIn(limit: 20, offset: 0))
            self.consists = result.consists
            self.totalCars = result.consists.reduce(0) { $0 + ($1.totalCars ?? 0) }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func buildConsist() async {
        building = true
        building = false
    }
}

#Preview("555 · Rail Consist Board · Night") { RailConsistBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("555 · Rail Consist Board · Light") { RailConsistBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
