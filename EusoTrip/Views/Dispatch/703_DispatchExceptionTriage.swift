// SHELVED 2026-05-01 — pre-existing build errors against an older
// design-system version (Theme.Palette.background, EType.h3,
// OrbESang.State.alert, etc.). Dispatch role currently routes to
// SFSafariViewController(app.eusotrip.com/dispatch) via
// RoleSurfaceRouter; this file ships the next time we knock down
// the Dispatch role per the founder's role-by-role cadence. Wrapped
// in `#if false` so the file references stay in the Xcode target
// (project.pbxproj) but the body doesn't enter compilation.
#if false
//
//  703_DispatchExceptionTriage.swift
//  EusoTrip — Dispatch · Exception triage (incidents queue + resolve).
//

import SwiftUI

struct DispatchExceptionTriageScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ExceptionBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .alert
            )
        }
    }
}

private struct ExceptionRow: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let severity: String?
    let driverName: String?
    let loadNumber: String?
    let location: String?
    let description: String?
    let createdAt: String?
    let status: String?
}

private struct ExceptionBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [ExceptionRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var resolvingId: String? = nil
    @State private var actionError: String? = nil
    @State private var lastResolved: String? = nil
    @State private var filter: String = "open"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                segmented
                if let m = lastResolved { LifecycleCard(accentGradient: true) { Text(m).font(EType.caption).foregroundStyle(palette.textPrimary) } }
                if let e = actionError { LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) } }
                content
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
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · TRIAGE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Exception triage").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Incidents that need a human decision — resolve to free the load.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var segmented: some View {
        HStack(spacing: 8) {
            ForEach([("open","OPEN"),("in_progress","IN PROGRESS"),("all","ALL")], id: \.0) { code, label in
                Button { filter = code; Task { await load() } } label: {
                    Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(filter == code ? .white : palette.textSecondary)
                        .background(filter == code ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.surface))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading exceptions…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty {
            EusoEmptyState(systemImage: "checkmark.seal.fill", title: "Queue is clear", subtitle: "No exceptions in this lens.")
        } else {
            ForEach(rows) { e in
                LifecycleCard(accentDanger: (e.severity?.lowercased() == "high" || e.severity?.lowercased() == "critical")) {
                    LifecycleSection(label: (e.type ?? "INCIDENT").uppercased(), icon: "exclamationmark.triangle")
                    LifecycleRow(label: "Severity", value: (e.severity ?? "—").uppercased())
                    LifecycleRow(label: "Driver",    value: dashIfEmpty(e.driverName))
                    LifecycleRow(label: "Load",      value: dashIfEmpty(e.loadNumber))
                    LifecycleRow(label: "Location",  value: dashIfEmpty(e.location))
                    LifecycleRow(label: "When",      value: humanISO(e.createdAt))
                    if let d = e.description, !d.isEmpty {
                        Text(d).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    }
                    Button { Task { await resolve(e.id) } } label: {
                        HStack(spacing: 6) {
                            if resolvingId == e.id { ProgressView().tint(.white) }
                            Text(resolvingId == e.id ? "Resolving…" : "Mark resolved").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain).disabled(resolvingId != nil).padding(.top, 6)
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let status: String? }
        do {
            let r: [ExceptionRow] = try await EusoTripAPI.shared.query("dispatch.getExceptions", input: In(status: filter == "all" ? nil : filter))
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func resolve(_ id: String) async {
        resolvingId = id; actionError = nil
        struct In: Encodable { let exceptionId: String; let resolution: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("dispatch.resolveException", input: In(exceptionId: id, resolution: "Triaged from mobile dispatch"))
            lastResolved = "Resolved exception \(id)."
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        resolvingId = nil
    }
}

#Preview("703 · Triage · Night") { DispatchExceptionTriageScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("703 · Triage · Afternoon") { DispatchExceptionTriageScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }

#endif
