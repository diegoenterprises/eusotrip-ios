//
//  110_MeAutoAcceptRules.swift
//  EusoTrip 2027 UI — brick 110 (driver/shipper · auto-accept rules)
//
//  Set rules so qualifying bids auto-accept without manual review.
//  E.g. "rate ≥$2.85/mi from carriers with safety rating ≥
//  Satisfactory and ≥$1M insurance gets auto-accepted." Server
//  evaluates ALL criteria server-side at bid-submit time and flips
//  matching bids to `auto_accepted` before the recipient ever sees
//  them.
//
//  Single brick serves both lenses (driver receiving counter-offers,
//  shipper receiving driver bids) since the
//  `bidAutoAcceptRules` table is keyed on userId — server pulls the
//  rules for the load owner at evaluation time.
//
//  Wires:
//    • `loadBidding.listAutoAcceptRules`
//    • `loadBidding.createAutoAcceptRule`
//    • `loadBidding.toggleAutoAcceptRule(id:isActive:)`
//    • `loadBidding.deleteAutoAcceptRule(id:)`
//

import SwiftUI

// MARK: - Store

@MainActor
final class AutoAcceptRulesStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded([LoadBiddingAPI.AutoAcceptRule])
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var working: Set<Int> = []
    @Published var lastAck: String? = nil
    @Published var lastError: String? = nil

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let rules = try await api.loadBidding.listAutoAcceptRules()
            phase = .loaded(rules)
        } catch {
            phase = .error("Couldn't load rules.")
        }
    }

    func create(name: String,
                maxRate: Double?,
                maxRatePerMile: Double?,
                minCatalystRating: Double?,
                requiredInsuranceMin: Double?,
                requiredHazmat: Bool?,
                maxTransitDays: Int?) async {
        do {
            _ = try await api.loadBidding.createAutoAcceptRule(
                name: name,
                maxRate: maxRate,
                maxRatePerMile: maxRatePerMile,
                minCatalystRating: minCatalystRating,
                requiredInsuranceMin: requiredInsuranceMin,
                requiredEquipmentTypes: nil,
                requiredHazmat: requiredHazmat,
                maxTransitDays: maxTransitDays,
                preferredCatalystIds: nil,
                originStates: nil,
                destinationStates: nil
            )
            lastAck = "Rule created."
            await load()
        } catch {
            lastError = "Couldn't create rule."
        }
    }

    func toggle(_ rule: LoadBiddingAPI.AutoAcceptRule) async {
        working.insert(rule.id)
        defer { working.remove(rule.id) }
        let next = !(rule.isActive ?? false)
        do {
            _ = try await api.loadBidding.toggleAutoAcceptRule(id: rule.id, isActive: next)
            await load()
        } catch {
            lastError = "Couldn't toggle rule."
        }
    }

    func delete(_ rule: LoadBiddingAPI.AutoAcceptRule) async {
        working.insert(rule.id)
        defer { working.remove(rule.id) }
        do {
            _ = try await api.loadBidding.deleteAutoAcceptRule(id: rule.id)
            await load()
        } catch {
            lastError = "Couldn't delete rule."
        }
    }
}

// MARK: - Brick

struct MeAutoAcceptRulesView: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = AutoAcceptRulesStore()
    @State private var showCreateSheet: Bool = false
    @State private var showAck: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                explainerCard
                listSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(isPresented: $showCreateSheet) {
            CreateRuleSheet().environmentObject(store)
        }
        .onChange(of: store.lastAck ?? "") { _, v in if !v.isEmpty { showAck = true } }
        .alert("Done", isPresented: $showAck, actions: {
            Button("OK") { store.lastAck = nil }
        }, message: {
            if let s = store.lastAck { Text(s) }
        })
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("ME · AUTO-ACCEPT").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Auto-accept rules").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("When a bid matches ALL criteria, server auto-flips it. Faster deals, fewer push notifications.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                showCreateSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 11, weight: .heavy))
                    Text("New").font(.system(size: 11, weight: .heavy))
                }.foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }.padding(.top, 4)
    }

    private var explainerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill").font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("ALL criteria must match for the rule to fire. Inactive rules stay on file but don't evaluate.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private var listSection: some View {
        switch store.phase {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Loading rules…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded(let rules):
            if rules.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(rules) { rule in ruleRow(rule) }
                }
            }
        }
    }

    private func ruleRow(_ r: LoadBiddingAPI.AutoAcceptRule) -> some View {
        let active = r.isActive ?? false
        let busy = store.working.contains(r.id)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                .frame(width: 32, height: 32)
                .background(palette.bgCardSoft).clipShape(Circle())
                .overlay(Circle().strokeBorder(palette.borderFaint))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(r.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                    statusPill(active ? "Active" : "Paused", color: active ? Brand.success : .gray)
                }
                criteriaList(for: r)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { active },
                    set: { _ in Task { await store.toggle(r) } }
                ))
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: Brand.success))
                .disabled(busy)

                Button {
                    Task { await store.delete(r) }
                } label: {
                    Image(systemName: "trash").font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger.opacity(0.7))
                }.buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func criteriaList(for r: LoadBiddingAPI.AutoAcceptRule) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let v = r.maxRate, !v.isEmpty {
                criteriaPill(icon: "dollarsign.circle.fill", text: "Max rate $\(v)")
            }
            if let v = r.maxRatePerMile, !v.isEmpty {
                criteriaPill(icon: "speedometer", text: "Max $\(v)/mi")
            }
            if let v = r.minCatalystRating, !v.isEmpty {
                criteriaPill(icon: "star.fill", text: "Min carrier rating \(v)")
            }
            if let v = r.requiredInsuranceMin, !v.isEmpty {
                criteriaPill(icon: "shield.fill", text: "Min insurance $\(v)")
            }
            if r.requiredHazmat == true {
                criteriaPill(icon: "exclamationmark.triangle.fill", text: "Hazmat required", tint: Brand.danger)
            }
            if let v = r.maxTransitDays, v > 0 {
                criteriaPill(icon: "clock.fill", text: "Max \(v)d transit")
            }
            if let arr = r.requiredEquipmentTypes, !arr.isEmpty {
                criteriaPill(icon: "shippingbox.fill",
                             text: arr.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", "))
            }
            if let arr = r.originStates, !arr.isEmpty {
                criteriaPill(icon: "location.fill",
                             text: "Origin: " + arr.joined(separator: " · "))
            }
            if let arr = r.destinationStates, !arr.isEmpty {
                criteriaPill(icon: "flag.fill",
                             text: "Dest: " + arr.joined(separator: " · "))
            }
        }
    }

    private func criteriaPill(icon: String, text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(tint ?? palette.textTertiary)
            Text(text).font(.system(size: 10, weight: .heavy))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No rules yet").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Tap New to create your first rule. Set thresholds for rate / per-mile / safety / insurance — bids matching all criteria auto-accept.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                showCreateSheet = true
            } label: {
                Text("Create rule").font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(Space.s4).frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Create rule sheet

private struct CreateRuleSheet: View {
    @EnvironmentObject private var store: AutoAcceptRulesStore
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var maxRate: String = ""
    @State private var maxRatePerMile: String = ""
    @State private var minCatalystRating: String = ""
    @State private var requiredInsuranceMin: String = ""
    @State private var requireHazmat: Bool = false
    @State private var maxTransitDays: String = ""
    @State private var creating: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                hero
                fieldStack
                createButton
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NEW RULE").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text("Auto-accept criteria").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Leave a field blank to ignore that criterion. ALL non-blank criteria must match for the rule to fire.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var fieldStack: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            field(label: "Rule name", placeholder: "e.g. \"Reefer Texas runs\"", text: $name, keyboard: .default)
            field(label: "Max total rate ($)", placeholder: "e.g. 3500", text: $maxRate, keyboard: .decimalPad)
            field(label: "Max per-mile rate ($/mi)", placeholder: "e.g. 2.85", text: $maxRatePerMile, keyboard: .decimalPad)
            field(label: "Min carrier rating (0-5)", placeholder: "e.g. 4.2", text: $minCatalystRating, keyboard: .decimalPad)
            field(label: "Min insurance ($)", placeholder: "e.g. 1000000", text: $requiredInsuranceMin, keyboard: .decimalPad)
            field(label: "Max transit days", placeholder: "e.g. 3", text: $maxTransitDays, keyboard: .numberPad)
            HStack {
                Toggle(isOn: $requireHazmat) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.danger)
                        Text("Require hazmat-certified carrier")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: Brand.danger))
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func field(label: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.plain).padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .font(EType.body).foregroundStyle(palette.textPrimary)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
    }

    private var createButton: some View {
        Button {
            creating = true
            Task {
                await store.create(
                    name: name.trimmingCharacters(in: .whitespaces),
                    maxRate: Double(maxRate),
                    maxRatePerMile: Double(maxRatePerMile),
                    minCatalystRating: Double(minCatalystRating),
                    requiredInsuranceMin: Double(requiredInsuranceMin),
                    requiredHazmat: requireHazmat ? true : nil,
                    maxTransitDays: Int(maxTransitDays)
                )
                creating = false
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if creating {
                    ProgressView().scaleEffect(0.6).tint(.white)
                } else {
                    Image(systemName: "plus.circle.fill").font(.system(size: 13, weight: .heavy))
                }
                Text(creating ? "Creating…" : "Create rule").font(.system(size: 14, weight: .heavy))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(creating || name.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

// MARK: - Screen wrapper

struct MeAutoAcceptRulesScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeAutoAcceptRulesView()
        } nav: {
            BottomNav(
                leading: driverNavLeading_110(),
                trailing: driverNavTrailing_110(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_110() -> [NavSlot] {
    [NavSlot(label: "Home", systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul", systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_110() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("110 · Me · Auto-Accept · Night") {
    MeAutoAcceptRulesScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("110 · Me · Auto-Accept · Afternoon") {
    MeAutoAcceptRulesScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
