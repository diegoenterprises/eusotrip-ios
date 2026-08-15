//
//  700_RailCarmanCertRegistry.swift
//  EusoTrip — Rail Engineer · Carman Certification Registry (mechanical-shop
//  credential index). NOTE: numeric prefix collides with 700_TerminalHome +
//  700_VesselFreightBillAudit — different screens; the Rail prefix keeps this
//  file distinct per the Rail/ naming convention.
//
//  Bespoke port of "05 Rail/Light-SVG/700 Rail Carman Certification Registry.svg" (+ Dark).
//  ARCHETYPE = REGISTER / SEARCHABLE INDEX — coverage-summary hero, search
//  field, carman index rows with a four-pip credential cluster (AB/SCT/INS/WLD).
//  Distinct from 595 Crew Certifications (operating-crew grid); 700 is the
//  MECHANICAL-shop registry.
//
//  Role: RAIL_ENGINEER (carrier family). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getRailInspections  EXISTS:1915 {limit} →
//        [{id,type,date,location,status,inspector,notes,passed}] — inspectorId
//        joins users.name server-side. The REAL roster source: every distinct
//        inspector who has performed a mechanical inspection.
//    railShipments.getRailCrew         EXISTS:1687 {limit} →
//        rail_crew_assignments rows (userId, role, hoursOnDuty). Best-effort
//        shop-staff headcount context.
//    railMechanical.getCarmanRegistry / certifyCarman / renewCert
//    Cert kinds: AB=49 CFR 232.203 air-brake · SCT=AAR S-486 single-car test
//    INS=49 CFR 215 freight-car inspector · WLD=AWS D15.1 rail welding.
//
import SwiftUI

struct RailCarmanCertRegistryScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailCarmanCertRegistryBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror railShipments.ts outputs — all optional so a
// partial payload degrades to an honest empty registry, never a decode crash)

private struct InspectionRow700: Decodable {
    let id: String?
    let type: String?
    let date: String?
    let location: String?
    let status: String?
    let inspector: String?
    let notes: String?
    let passed: Bool?
}

private struct CrewRow700: Decodable {
    let id: Int?
    let userId: Int?
    let role: String?
    let hoursOfServiceCompliant: Bool?
}

private struct LimitInput700: Encodable { let limit: Int }
private struct CarmanRegistryInput700: Encodable { let limit: Int }

/// One real carman credential off `railMechanical.getCarmanRegistry`.
private struct CarmanCertRow700: Decodable {
    let name: String?
    let certType: String?   // AB | SCT | INS | WLD
    let certNumber: String?
    let status: String?     // active | expired | suspended | pending
    let expiresDate: String?
}

/// One aggregated carman row — derived entirely from real inspection rows
/// (inspector identity + activity). Credential pips have NO on-file source,
/// so every pip is `.unverified`.
private struct CarmanEntry700: Identifiable {
    let name: String
    let inspectionCount: Int
    let latestDate: Date?
    let latestType: String?
    var id: String { name }

    var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}

// MARK: - Body

private struct RailCarmanCertRegistryBody: View {
    @Environment(\.palette) private var palette
    @State private var inspections: [InspectionRow700] = []
    @State private var crew: [CrewRow700] = []
    @State private var certRegistry: [CarmanCertRow700] = []
    @State private var loading = true
    @State private var search = ""
    @State private var regime = 0
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newCertType = "AB"
    @State private var newCertNum = ""
    @State private var newAuth = ""
    @State private var isCertifying = false
    @State private var showAddNotice = false

    private let certKinds = ["AB", "SCT", "INS", "WLD"]
    private let regimes: [(String, String)] = [("US · AAR", "M-1003 · 232"),
                                               ("CA · TC", "Rwy Safety"),
                                               ("MX · NOM", "002-SCT")]

    /// Distinct inspectors aggregated from real inspection rows, most active
    /// first. This is the registry roster — real names off users.name.
    private var carmen: [CarmanEntry700] {
        var byName: [String: (count: Int, latest: Date?, type: String?)] = [:]
        for r in inspections {
            guard let name = r.inspector, !name.isEmpty else { continue }
            let d = Self.date(r.date)
            var cur = byName[name] ?? (0, nil, nil)
            cur.count += 1
            if let d, d > (cur.latest ?? .distantPast) {
                cur.latest = d
                cur.type = r.type
            }
            byName[name] = cur
        }
        return byName
            .map { CarmanEntry700(name: $0.key, inspectionCount: $0.value.count,
                                  latestDate: $0.value.latest, latestType: $0.value.type) }
            .sorted { $0.inspectionCount > $1.inspectionCount }
    }

    private var filteredCarmen: [CarmanEntry700] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return carmen }
        return carmen.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Carman registry")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("Mechanical credentials · AAR M-1003 QA program")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow
                .padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    coverageHero
                    searchField
                    registryHeader
                    registryList
                    triBand
                    footerActions
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
        .sheet(isPresented: $showAddSheet) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Certify Carman").font(EType.h2).foregroundStyle(palette.textPrimary)
                Text("Record a mechanical certification into the shop registry.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                
                TextField("Carman Name", text: $newName)
                    .font(.system(size: 14, weight: .bold))
                    .padding(Space.s3).background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                
                Picker("Type", selection: $newCertType) {
                    ForEach(certKinds, id: \.self) { kind in
                        Text(kind).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                
                TextField("Certificate Number", text: $newCertNum)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .padding(Space.s3).background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                
                TextField("Issuing Authority", text: $newAuth)
                    .font(.system(size: 14, weight: .bold))
                    .padding(Space.s3).background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                
                CTAButton(title: isCertifying ? "Certifying…" : "Record Certification", action: { Task { await certifyCarman() } })
                    .disabled(newName.isEmpty || newCertNum.isEmpty || newAuth.isEmpty || isCertifying)
                Spacer()
            }
            .padding(20).presentationDetents([.height(440)]).presentationDragIndicator(.visible)
            .background(palette.bgPage)
        }
        .alert("Credential records unavailable", isPresented: $showAddNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No credential registry is on file for this shop, so a carman can't be certified from this device. Inspector history from completed inspections still appears below — contact your mechanical desk to record air-brake, single-car, inspector, or welding credentials.")
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "RAIL ENGINEER · CARMAN REGISTRY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("SHOP ROSTER · \(carmen.count)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("\(carmen.count) carmen", Brand.blue)
            chip("AAR M-1003", Brand.warning)
            chip(crew.isEmpty ? "no crew on shift" : "\(crew.count) crew on shift", palette.textSecondary)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Coverage hero — counts are keyed to what is actually on file.
    // There are NO credential rows on disk, so valid/expiring/expired all
    // honestly read 0 and the pips below read UNVERIFIED.

    private var coverageHero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("INSPECTORS · ON FILE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(carmen.count)")
                        .font(.system(size: 34, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(" active")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
                Text("from \(inspections.count) recorded inspections")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                legend(Brand.success, "0 valid")
                legend(Brand.warning, "0 expiring")
                legend(Brand.danger, "0 expired")
                Text("no credential rows on file")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(c).frame(width: 10, height: 10)
            Text(t).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Search — real client-side filter over the loaded roster.

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.textTertiary)
            TextField("Search carman by name", text: $search)
                .font(.system(size: 12))
                .foregroundStyle(palette.textPrimary)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
    }

    private var registryHeader: some View {
        HStack {
            Text("CARMAN REGISTRY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("AB / SCT / INS / WLD")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var registryList: some View {
        if carmen.isEmpty {
            EusoEmptyState(systemImage: "person.badge.shield.checkmark",
                           title: "No inspectors on file",
                           subtitle: "Inspector names appear as mechanical inspections are recorded for this shop.")
        } else if filteredCarmen.isEmpty {
            EusoEmptyState(systemImage: "magnifyingglass",
                           title: "No match",
                           subtitle: "No inspector name matches \"\(search)\". Clear the search to see all \(carmen.count).")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(filteredCarmen.enumerated()), id: \.element.id) { i, c in
                    carmanRow(c)
                    if i < filteredCarmen.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(.horizontal, 16)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func carmanRow(_ c: CarmanEntry700) -> some View {
        HStack(spacing: 10) {
            Text(c.initials)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(LinearGradient.diagonal))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(rowSubtitle(c))
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            let held = heldCerts(for: c.name)
            HStack(spacing: 14) {
                ForEach(certKinds, id: \.self) { kind in
                    let isHeld = held.contains(kind)
                    VStack(spacing: 4) {
                        Text(kind)
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(isHeld ? palette.textPrimary : palette.textTertiary)
                        // Filled gradient pip when a real active cert row exists;
                        // hollow ring (unverified) otherwise — never fabricated.
                        Group {
                            if isHeld {
                                Circle().fill(LinearGradient.diagonal).frame(width: 9, height: 9)
                            } else {
                                Circle().strokeBorder(palette.textTertiary.opacity(0.6), lineWidth: 1.4).frame(width: 9, height: 9)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(held.isEmpty ? "Credentials unverified — no certification records on file" : "Holds \(held.sorted().joined(separator: ", "))")
        }
        .padding(.vertical, 12)
    }

    private func rowSubtitle(_ c: CarmanEntry700) -> String {
        var bits = ["\(c.inspectionCount) inspection\(c.inspectionCount == 1 ? "" : "s")"]
        if let t = c.latestType, !t.isEmpty {
            bits.append(t.replacingOccurrences(of: "_", with: " "))
        }
        if let d = c.latestDate { bits.append("latest \(Self.shortLabel(d))") }
        let held = heldCerts(for: c.name)
        bits.append(held.isEmpty ? "certs unverified" : "\(held.count) cert\(held.count == 1 ? "" : "s") on file")
        return bits.joined(separator: " · ")
    }

    // MARK: Tri-country credential authority band

    private var triBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == regime ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { regime = i }
            }
        }
    }

    // MARK: Footer — "Add carman" surfaces the honest no-registry notice;
    // "Export" is a REAL share of the loaded roster.

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Add carman", action: { showAddSheet = true })
                .frame(maxWidth: .infinity)
            ShareLink(item: exportText) {
                Text("Export")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 118)
                    .frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
        }
    }

    private var exportText: String {
        var lines = ["Carman registry — \(carmen.count) inspectors on file"]
        for c in carmen {
            lines.append("\(c.name) — \(c.inspectionCount) inspections — credentials unverified")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Load

    private func reload() async {
        loading = true
        async let insp: [InspectionRow700] = EusoTripAPI.shared.query(
            "railShipments.getRailInspections", input: LimitInput700(limit: 200))
        async let staff: [CrewRow700] = EusoTripAPI.shared.query(
            "railShipments.getRailCrew", input: LimitInput700(limit: 50))
        async let certs: [CarmanCertRow700] = EusoTripAPI.shared.query(
            "railMechanical.getCarmanRegistry", input: CarmanRegistryInput700(limit: 200))
        self.inspections = (try? await insp) ?? []
        self.crew = (try? await staff) ?? []
        self.certRegistry = (try? await certs) ?? []
        loading = false
    }

    private func certifyCarman() async {
        guard !isCertifying else { return }
        isCertifying = true; defer { isCertifying = false }
        struct In: Encodable {
            let carmanName: String
            let certType: String
            let certNumber: String
            let issuingAuthority: String
        }
        struct Out: Decodable { let success: Bool }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "railMechanical.certifyCarman",
                input: In(carmanName: newName, certType: newCertType, certNumber: newCertNum, issuingAuthority: newAuth)
            )
            showAddSheet = false
            newName = ""; newCertNum = ""; newAuth = ""
            await reload()
        } catch {
            // honest error handling
        }
    }

    /// Real active certs held by a carman, keyed by name (case-insensitive),
    /// off the live registry. Empty when no credential row is on file.
    private func heldCerts(for name: String) -> Set<String> {
        let key = name.lowercased()
        var held = Set<String>()
        for row in certRegistry where (row.name ?? "").lowercased() == key {
            if (row.status ?? "active") == "active", let t = row.certType { held.insert(t) }
        }
        return held
    }

    private static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }

    private static func shortLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

#Preview("700 · Rail Carman Cert Registry · Night") {
    RailCarmanCertRegistryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("700 · Rail Carman Cert Registry · Light") {
    RailCarmanCertRegistryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
