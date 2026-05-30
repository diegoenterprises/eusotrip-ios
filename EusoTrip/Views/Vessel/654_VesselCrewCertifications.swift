//
//  654_VesselCrewCertifications.swift
//  EusoTrip — Vessel Operator · Crew & Certifications (carrier vantage).
//
//  Drill-down from the carrier Home / Compliance surface. Verbatim port of
//  "654 Vessel Crew Certifications.svg" (Light + Dark). Nav anchored to
//  VesselOperatorNavController.swift; Compliance tab current (filled symbol).
//
//  Crew identities are NOT yet canonized (Vessel Operator/Captain/Port-Master/
//  Customs-Broker need founder canonization per SKILL); rows render STCW rank +
//  crew-ID + cert status. Real names arrive from the users rows at runtime.
//  Data shape mirrors vesselShipments.getVesselCrew → { crew, certifications,
//  expiringCount } (server/routers/vesselShipments.ts:742).
//

import SwiftUI

struct VesselCrewCertificationsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselCrewCertificationsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                  isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
        // Real top back affordance (replaces the old decorative chevron in
        // the body header). Fixed leading slot → never overlaps the title;
        // posts the shared NavBack the VesselOperatorSurface pops on.
        .injectBespokeBackBar(title: nil) {
            NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
        }
    }
}

// MARK: - Data shapes (mirror getVesselCrew return)

private struct VesselCrewMember: Decodable, Identifiable {
    let id: Int
    let name: String?
    let role: String?           // STCW rank
    let crewId: String?
    let isActive: Bool?
}

private struct CrewCertification: Decodable, Identifiable {
    let id: Int
    let userId: Int?
    let title: String?
    let expiryDate: String?
}

private struct VesselCrewResponse: Decodable {
    let crew: [VesselCrewMember]
    let certifications: [CrewCertification]
    let expiringCount: Int?
}

// MARK: - Body

private struct VesselCrewCertificationsBody: View {
    @Environment(\.palette) private var palette
    @State private var response: VesselCrewResponse? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var crew: [VesselCrewMember] { response?.crew ?? [] }
    private var validCount: Int { (response?.certifications.count ?? 0) - (response?.expiringCount ?? 0) }

    // Days until expiry for a crew member's earliest-expiring cert.
    private func certStatus(for userId: Int) -> (label: String, days: Int?, expiring: Bool) {
        let certs = (response?.certifications ?? []).filter { $0.userId == userId }
        let formatter = ISO8601DateFormatter()
        let soonest = certs.compactMap { c -> (CrewCertification, Date)? in
            guard let s = c.expiryDate, let d = formatter.date(from: s) else { return nil }
            return (c, d)
        }.min { $0.1 < $1.1 }
        guard let (_, date) = soonest else { return ("VALID", nil, false) }
        let days = Int(date.timeIntervalSinceNow / 86_400)
        let expiring = days >= 0 && days <= 90
        return (expiring ? "EXPIRING" : "VALID", days, expiring)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading crew…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    summaryTiles
                    Text("CREW · getVesselCrew")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    VStack(spacing: Space.s2) { ForEach(crew) { crewRow($0) } }
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
                Image(systemName: "person.2.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · CREW & CERTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Crew & certs").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("\(crew.count) crew · STCW certificates · \(response?.expiringCount ?? 0) expiring within 90 days")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var summaryTiles: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ON ARTICLES", value: "\(crew.count)",      icon: "person.2")
            LifecycleStatTile(label: "CERTS VALID", value: "\(max(validCount, 0))", icon: "checkmark.seal")
            LifecycleStatTile(label: "EXPIRING",    value: "\(response?.expiringCount ?? 0)", icon: "exclamationmark.triangle",
                              danger: (response?.expiringCount ?? 0) > 0)
        }
    }

    private func crewRow(_ m: VesselCrewMember) -> some View {
        let status = certStatus(for: m.id)
        let tone = status.expiring ? Brand.warning : Brand.success
        return HStack(spacing: Space.s3) {
            Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                .overlay(Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(m.role ?? "Crew") · \(m.crewId ?? "—")").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(status.days.map { "STCW cert · expires in \($0) days" } ?? "STCW cert · valid")
                    .font(.system(size: 11)).monospaced().foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(status.label).font(.system(size: 8.5, weight: .heavy)).tracking(0.5).foregroundStyle(tone)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(tone.opacity(0.14)).clipShape(Capsule())
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func load() async {
        loading = true; loadError = nil
        struct CrewIn: Encodable { let search: String? }
        do {
            let result: VesselCrewResponse = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCrew", input: CrewIn(search: nil))
            self.response = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("654 · Vessel Crew & Certs · Night") { VesselCrewCertificationsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("654 · Vessel Crew & Certs · Light") { VesselCrewCertificationsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
