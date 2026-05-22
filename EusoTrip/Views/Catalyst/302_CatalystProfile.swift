//
//  302_CatalystProfile.swift
//  EusoTrip — Catalyst · Profile (brick 302).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/302 Catalyst Profile.swift`.
//  Owner-op identity surface — name, USDOT/MC, verified+hazmat
//  endorsement badges, pool tier with B/S/G/P/D ladder, YTD KPIs.
//
//  Wire bindings:
//    profile.getCatalystProfile  — identity + role + verified flag
//    gamification.getProfile     — tier + XP toward next tier
//

import SwiftUI

private struct CatalystProfileData: Decodable, Hashable {
    let name: String?
    let email: String?
    let companyName: String?
    let dotNumber: String?
    let mcNumber: String?
    let verified: Bool?
    let hazmatAuthorized: Bool?
    let memberSinceYear: Int?
    let runsYTD: Int?
    let revenueYTD: Double?
}

private struct GamificationProfile: Decodable, Hashable {
    let tier: String?
    let totalXp: Int?
    let pointsToNextTier: Int?
    let nextTier: String?
    let tierProgress: Int?
}

struct CatalystProfileScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ProfileBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct ProfileBody: View {
    @Environment(\.palette) private var palette
    @State private var profile: CatalystProfileData?
    @State private var gam: GamificationProfile?
    @State private var loading: Bool = true
    @State private var editing: Bool = false
    @State private var editName: String = ""
    @State private var editPhone: String = ""
    @State private var editCompany: String = ""
    @State private var saveInFlight: Bool = false
    @State private var ack: String? = nil
    @State private var err: String? = nil

    private var tierIndex: Int {
        switch (gam?.tier ?? "").lowercased() {
        case "diamond":  return 4
        case "platinum": return 3
        case "gold":     return 2
        case "silver":   return 1
        default:         return 0
        }
    }
    private let tiers = ["B", "S", "G", "P", "D"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && profile == nil {
                    LifecycleCard { Text("Loading profile…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    identityCard
                    tierCard
                    ytdKPIRow
                }
                if let ack { LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(.green) } }
                if let err { LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) } }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Edit profile", isPresented: $editing) {
            TextField("Name", text: $editName)
            TextField("Company", text: $editCompany)
            Button("Cancel", role: .cancel) { editing = false }
            Button("Save") { Task { await saveProfile() } }
        } message: {
            Text("Update your display name and company on EusoTrip.")
        }
    }

    private func saveProfile() async {
        saveInFlight = true; ack = nil; err = nil
        defer { saveInFlight = false }
        struct In: Encodable { let name: String?; let company: String? }
        struct Out: Decodable { let success: Bool?; let userId: Int? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "users.updateProfile",
                input: In(
                    name: editName.isEmpty ? nil : editName,
                    company: editCompany.isEmpty ? nil : editCompany
                )
            )
            if resp.success != false {
                ack = "Profile updated."
                await load()
            } else {
                err = "Update returned no success flag."
            }
        } catch let e {
            err = (e as? LocalizedError)?.errorDescription ?? "Update failed: \(e)"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · ME · PROFILE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Button {
                    editName = profile?.name ?? ""
                    editCompany = profile?.companyName ?? ""
                    editing = true
                } label: {
                    Text("Edit").font(.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.4)))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }.buttonStyle(.plain)
            }
            Text("Profile").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            let tier = (gam?.tier ?? "—").uppercased()
            let year = profile?.memberSinceYear.map { String($0) } ?? "—"
            Text("TIER \(tier) · MEMBER \(year)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var identityCard: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(LinearGradient.diagonal).frame(width: 56, height: 56)
                        Text(initialsFor(profile?.name)).font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile?.name ?? "—")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text("\(profile?.companyName ?? "—") · owner-op")
                            .font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        if profile?.verified == true {
                            Text("VERIFIED")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                                .foregroundStyle(Color.green)
                        }
                        if profile?.hazmatAuthorized == true {
                            Text("HAZMAT · A+")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                                .foregroundStyle(Color.orange)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("USDOT \(profile?.dotNumber ?? "—") · MC-\(profile?.mcNumber ?? "—")")
                        .font(.caption.monospaced())
                        .foregroundStyle(palette.textTertiary)
                    Text(profile?.email ?? "—").font(.caption).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private var tierCard: some View {
        let progress = gam?.tierProgress ?? 0
        let next = gam?.nextTier ?? ""
        let pts = gam?.pointsToNextTier ?? 0
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("POOL TIER · \((gam?.tier ?? "—").uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    if pts > 0 {
                        Text("\(pts) pts to \(next.uppercased())")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                // B/S/G/P/D ladder
                HStack(spacing: 6) {
                    ForEach(Array(tiers.enumerated()), id: \.offset) { idx, letter in
                        let active = idx <= tierIndex
                        ZStack {
                            Circle()
                                .fill(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                                .frame(width: 32, height: 32)
                            Text(letter)
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(active ? .white : palette.textTertiary)
                        }
                        if idx < tiers.count - 1 {
                            Rectangle()
                                .fill(idx < tierIndex ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                                .frame(height: 2)
                        }
                    }
                }
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.bgCardSoft).frame(height: 6)
                        Capsule()
                            .fill(LinearGradient.diagonal)
                            .frame(width: CGFloat(max(0, min(100, progress))) / 100 * geo.size.width, height: 6)
                    }
                }
                .frame(height: 6)
                if pts > 0 {
                    Text("\(pts) more loads → top-billing in Catalyst auctions + 0.6% spot premium")
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var ytdKPIRow: some View {
        HStack(spacing: Space.s2) {
            kpi("RUNS YTD", "\(profile?.runsYTD ?? 0)", "+\(profile?.runsYTD ?? 0) this Q", .blue)
            kpi("REVENUE YTD", "$\(Int(profile?.revenueYTD ?? 0).formatted(.number))", "12-mo trailing", .green)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private func initialsFor(_ name: String?) -> String {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "—" }
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (first + last).uppercased()
    }

    private func load() async {
        loading = true
        async let p: Void = loadProfile()
        async let g: Void = loadGam()
        _ = await (p, g)
        loading = false
    }

    private func loadProfile() async {
        do { profile = try await EusoTripAPI.shared.queryNoInput("profile.getCatalystProfile") } catch { /* */ }
    }
    private func loadGam() async {
        do { gam = try await EusoTripAPI.shared.queryNoInput("gamification.getProfile") } catch { /* */ }
    }
}

#Preview("302 Profile · Dark")  { CatalystProfileScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("302 Profile · Light") { CatalystProfileScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
