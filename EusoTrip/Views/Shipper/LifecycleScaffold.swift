//
//  LifecycleScaffold.swift
//  EusoTrip — Shipper · Round 4 / Arc E shared lifecycle scaffold.
//
//  Every 260–279 lifecycle brick consumes
//  `shippers.getLifecycleSnapshot(loadId)` through this scaffold so the
//  20 surfaces share one snapshot store, one RemoteState machine, one
//  header recipe, and one bottom-nav slot wiring. Per-stage content is
//  injected via a `body:` closure that receives the live snapshot.
//
//  Doctrine:
//    • No fabricated runtime data — every field surfaces from the
//      server. Missing rows render em-dash sentinels via `dashIfEmpty`.
//    • Shipper bottom nav: Home · Loads · [ESang] · Bids · Me. Lifecycle
//      screens drilled from Loads keep Loads `isCurrent: true`.
//    • Live updates: socket subscription on
//      `LOAD_STATUS_CHANGED`/`LOAD_GEOFENCE_ENTER`/`LOAD_BOL_SIGNED`/
//      `LOAD_POD_SUBMITTED` refresh the snapshot.
//

import SwiftUI

// MARK: - Em-dash sentinels (no fabricated values per Cohort B doctrine)

@inlinable
func dashIfEmpty(_ s: String?) -> String { (s?.isEmpty == false ? s! : "—") }

@inlinable
func dashIfNil<T: Numeric>(_ n: T?) -> String {
    guard let v = n else { return "—" }
    return "\(v)"
}

@inlinable
func usd(_ amount: Double?) -> String {
    guard let v = amount, v > 0 else { return "—" }
    let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
}

@inlinable
func usd0(_ amount: Double?) -> String {
    guard let v = amount, v > 0 else { return "—" }
    return "$\(Int(v))"
}

@inlinable
func humanISO(_ iso: String?, format: String = "MMM d · HH:mm") -> String {
    guard let iso = iso, !iso.isEmpty else { return "—" }
    let isoFmt = ISO8601DateFormatter()
    isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = isoFmt.date(from: iso)
    if date == nil {
        isoFmt.formatOptions = [.withInternetDateTime]
        date = isoFmt.date(from: iso)
    }
    guard let d = date else { return iso }
    let fmt = DateFormatter()
    fmt.dateFormat = format
    return fmt.string(from: d)
}

@inlinable
func relativeETA(from iso: String?) -> String {
    guard let iso = iso, !iso.isEmpty else { return "—" }
    let isoFmt = ISO8601DateFormatter()
    isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = isoFmt.date(from: iso)
    if date == nil {
        isoFmt.formatOptions = [.withInternetDateTime]
        date = isoFmt.date(from: iso)
    }
    guard let d = date else { return iso }
    let secs = d.timeIntervalSinceNow
    if secs <= 0 { return "now" }
    let m = Int(secs / 60); let h = m / 60; let mm = m % 60
    if h == 0 { return "\(m) min" }
    return "\(h)h \(mm)m"
}

@inlinable
func laneDisplay(_ snap: ShipperAPI.LifecycleSnapshot) -> String {
    let p = snap.pickup
    let d = snap.delivery
    let from = [p?.city, p?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    let to   = [d?.city, d?.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    if from.isEmpty && to.isEmpty { return "—" }
    if from.isEmpty { return "— → \(to)" }
    if to.isEmpty { return "\(from) → —" }
    return "\(from) → \(to)"
}

@inlinable
func resolveProduct(_ snap: ShipperAPI.LifecycleSnapshot, role: String?) -> TripProduct {
    TripProduct.resolveDirect(
        cargoType: snap.load.cargoType,
        hazmatClass: snap.load.hazmatClass,
        vertical: TripVertical(role: role)
    )
}

// MARK: - Shipper bottom nav (Round 4 doctrine)

@inlinable
func shipperLifecycleNav() -> BottomNav {
    BottomNav(
        leading: [
            NavSlot(label: "Home", systemImage: "house", isCurrent: false),
            NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
        ],
        trailing: [
            NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
            NavSlot(label: "Me", systemImage: "person", isCurrent: false),
        ],
        orbState: .idle
    )
}

// MARK: - Section header + helpers (used by every lifecycle screen)

struct LifecycleSection: View {
    @Environment(\.palette) private var palette
    let label: String
    let icon: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }
}

struct LifecycleRow: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer(minLength: Space.s2)
            Text(value).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
        }
    }
}

struct LifecycleStatTile: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let icon: String
    var danger: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(danger ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.diagonal))
                Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            }
            Text(value).font(.system(size: 15, weight: .heavy)).foregroundStyle(danger ? Brand.danger : palette.textPrimary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(danger ? Brand.danger.opacity(0.4) : palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

struct LifecycleCard<Content: View>: View {
    @Environment(\.palette) private var palette
    let content: Content
    var accentDanger: Bool = false
    var accentWarning: Bool = false
    var accentGradient: Bool = false
    init(accentDanger: Bool = false, accentWarning: Bool = false, accentGradient: Bool = false, @ViewBuilder content: () -> Content) {
        self.accentDanger = accentDanger
        self.accentWarning = accentWarning
        self.accentGradient = accentGradient
        self.content = content()
    }
    var body: some View {
        let strokeStyle: AnyShapeStyle = {
            if accentDanger { return AnyShapeStyle(Brand.danger.opacity(0.55)) }
            if accentWarning { return AnyShapeStyle(Brand.warning.opacity(0.55)) }
            if accentGradient {
                return AnyShapeStyle(LinearGradient(colors: [Brand.gradientStart.opacity(0.7), Brand.gradientEnd.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            return AnyShapeStyle(palette.borderFaint)
        }()
        return VStack(alignment: .leading, spacing: Space.s2) { content }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(strokeStyle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - Lifecycle scaffold view

struct LifecycleScaffold<Body: View>: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    let loadId: String
    /// Eyebrow chip text. e.g. "SHIPPER · POSTED · STAGE 1 OF 8".
    let eyebrow: String
    /// Stage value passed to ShipperLoadCycleView. Use the canonical
    /// loads.status enum string ("posted", "bidding", "in_transit", …).
    let cycleStatus: String
    /// Per-stage body content — receives the live snapshot.
    let bodyContent: (ShipperAPI.LifecycleSnapshot) -> Body

    @StateObject private var snap = ShipperLifecycleSnapshotStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                contentBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            snap.loadId = loadId
            await snap.refresh()
        }
        .refreshable { await snap.refresh() }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch snap.state {
        case .loading:
            loadingHeader
            ProgressView().padding()
        case .loaded(let optionalSnapshot):
            if let live = optionalSnapshot {
                header(snapshot: live)
                ShipperLoadCycleView(
                    status: cycleStatus,
                    product: resolveProduct(live, role: session.user?.role),
                    vertical: TripVertical(role: session.user?.role)
                )
                bodyContent(live)
            } else {
                emptyHeader
            }
        case .empty:
            emptyHeader
        case .error(let err):
            errorHeader(err)
        }
    }

    private func header(snapshot live: ShipperAPI.LifecycleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(live.load.loadNumber).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(laneDisplay(live)).font(EType.body).foregroundStyle(palette.textSecondary)
        }
    }

    private var loadingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Loading…").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Pulling the latest from the load record.").font(EType.body).foregroundStyle(palette.textSecondary)
        }
    }

    private var emptyHeader: some View {
        EusoEmptyState(
            systemImage: "doc.text",
            title: "Load not found",
            subtitle: "The load you tapped is no longer in the system. Pull to refresh or pick another load from the list."
        )
    }

    private func errorHeader(_ err: Error) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.danger)
            }
            Text(err.localizedDescription).font(EType.caption).foregroundStyle(palette.textSecondary)
            Button { Task { await snap.refresh() } } label: {
                Text("Retry").font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
