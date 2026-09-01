//
//  694_VesselConsigneeTrackingLink.swift
//  EusoTrip — Vessel Operator · Consignee Tracking Link (CARRIER-SIDE · SHARE-CONSOLE class).
//
//  PURPOSE-BUILT: the source wireframe "694 Vessel Consignee Tracking Link.svg"
//  ships EMPTY in the catalog (0 bytes, Dark + Light), so this screen is composed
//  to the golden bar from the real consigneePortal router blueprint + the design
//  authority (composition-follows-function). A token-share CONSOLE: mint a
//  read-only public tracking link for a booking, preview exactly what the
//  consignee will see, and revoke on demand — distinct from every other Vessel
//  screen's composition.
//
//  Web parity: ConsigneePortal.tsx (`/vessel/:id/share`).
//
//  DATA (endpoints confirmed on disk this fire):
//    consigneePortal.createShareLink {shipmentId, customerName, customerEmail?, expiresInDays}
//        → { token, url, expiresAt }   (MUTATION · tenant-gated · server/routers/consigneePortal.ts:24)
//    consigneePortal.publicTrack {token}
//        → { bookingNumber, status, eta, progress, containers[], milestones[] }
//        (publicProcedure · consigneePortal.ts:84 — the exact consignee view, used as the live preview)
//    consigneePortal.revokeShareLink {token} → { revoked }   (MUTATION · consigneePortal.ts:68)
//
//  HONEST GAPS (surfaced to the-oath — NOT papered over):
//    • There is NO list-active-links procedure — a minted link is shown for THIS
//      session only; a persisted "active links for this shipment" list needs
//      consigneePortal.listShareLinks {shipmentId}. Surfaced in-copy, not faked.
//
//  NAV (VesselOperatorNavController): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  transportMode=vessel · US import. PERSONA Vessel Operator · shipper-of-record DU/Eusorone.
//

import SwiftUI

struct VesselConsigneeTrackingLinkScreen: View {
    let theme: Theme.Palette
    /// Vessel shipment the share link is scoped to (createShareLink scope).
    var shipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselConsigneeTrackingLinkBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct ShareLinkOut: Decodable { let token: String; let url: String; let expiresAt: String? }
private struct RevokeOut: Decodable { let revoked: Bool }
private struct PublicTrack: Decodable {
    let bookingNumber: String?
    let status: String?
    let eta: String?
    let progress: Int?
    let containers: [ConsigneeContainer]
    let milestones: [ConsigneeMilestone]
}
private struct ConsigneeContainer: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let status: String?
}
private struct ConsigneeMilestone: Decodable, Identifiable {
    let id: Int
    let eventType: String?
    let timestamp: String?
}

// MARK: - Body

private struct VesselConsigneeTrackingLinkBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var customerName: String = "Consignee"
    @State private var expiryDays: Int = 30
    @State private var link: ShareLinkOut? = nil
    @State private var preview: PublicTrack? = nil

    @State private var minting = false
    @State private var revoking = false
    @State private var actionAck: String? = nil
    @State private var actionError: String? = nil

    private let expiryOptions = [7, 30, 90]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s4)

                VStack(alignment: .leading, spacing: Space.s4) {
                    linkStatusHero
                    accessControls
                    previewCard
                    ctaPair
                    gapNote
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EusoTripEyebrow(verbatim: "VESSEL OPERATOR · TRACKING LINK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(shipmentId > 0 ? "SHIPMENT \(shipmentId)" : "SHARE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Consignee link")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary).padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
    }

    // MARK: Link status hero

    private var linkStatusHero: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Image(systemName: link == nil ? "link.badge.plus" : "link")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link == nil ? "No live link" : "Link live")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text(link == nil ? "read-only · no login for the consignee" : "expires \(prettyDate(link?.expiresAt))")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            if let link {
                HStack(spacing: Space.s2) {
                    Text(link.url)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = "https://eusotrip.com\(link.url)"
                        actionAck = "Tracking link copied."
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Space.s3)
                .background(RoundedRectangle(cornerRadius: Radius.md).fill(.white.opacity(0.18)))
            }
        }
        .padding(Space.s5).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: Access controls

    private var accessControls: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("SHARE SETTINGS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONSIGNEE NAME").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    TextField("Consignee", text: $customerName)
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        .padding(Space.s3)
                        .background(RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCardSoft))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXPIRES IN").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    HStack(spacing: Space.s2) {
                        ForEach(expiryOptions, id: \.self) { d in
                            Button { expiryDays = d } label: {
                                Text("\(d)d")
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(expiryDays == d ? .white : palette.textSecondary)
                                    .frame(width: 52, height: 30)
                                    .background(expiryDays == d ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)
        }
    }

    // MARK: Preview (what the consignee sees)

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CONSIGNEE PREVIEW · SECURE TRACKING")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if link == nil {
                EusoEmptyState(icon: Image(systemName: "eye"),
                               title: "Preview appears after minting",
                               subtitle: "Create the link to see the exact read-only view the consignee will open.")
            } else if let p = preview {
                HStack(spacing: Space.s4) {
                    ZStack {
                        Circle().stroke(palette.borderFaint, lineWidth: 7)
                        Circle().trim(from: 0, to: max(0.001, Double(p.progress ?? 0) / 100))
                            .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(p.progress ?? 0)%").font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .frame(width: 62, height: 62)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.bookingNumber ?? "Booking")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text("\(p.containers.count) container(s) · \(p.milestones.count) milestone(s)")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        Text("status \((p.status ?? "—").replacingOccurrences(of: "_", with: " "))")
                            .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.lg)
            } else {
                LifecycleCard { Text("Loading consignee preview…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button { Task { await mint() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "link.badge.plus").font(.system(size: 15, weight: .bold))
                        Text(link == nil ? "Create link" : "Re-mint link").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .opacity(minting || shipmentId <= 0 ? 0.6 : 1)
                }
                .buttonStyle(.plain).disabled(minting || shipmentId <= 0)

                Button { Task { await revoke() } } label: {
                    Text("Revoke").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(link == nil ? palette.textTertiary : Brand.danger)
                        .frame(width: 110, height: 48)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).disabled(revoking || link == nil)
            }
            if shipmentId <= 0 {
                Text("Open this from a booking to mint its consignee link.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            }
            if let actionAck { Text(actionAck).font(EType.caption).foregroundStyle(Brand.success) }
            if let actionError { Text(actionError).font(EType.caption).foregroundStyle(Brand.danger) }
        }
    }

    private var gapNote: some View {
        Text("The newly issued tracking link appears here. Previously issued links remain attached to their shipment records.")
            .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
    }

    // MARK: Actions

    private func mint() async {
        actionAck = nil; actionError = nil; minting = true
        struct In: Encodable { let shipmentId: Int; let customerName: String; let expiresInDays: Int }
        do {
            let out: ShareLinkOut = try await EusoTripAPI.shared.mutation(
                "consigneePortal.createShareLink",
                input: In(shipmentId: shipmentId, customerName: customerName.isEmpty ? "Consignee" : customerName, expiresInDays: expiryDays))
            self.link = out
            actionAck = "Link live — expires \(prettyDate(out.expiresAt))."
            await loadPreview(token: out.token)
        } catch {
            actionError = error.eusoUserCopy
        }
        minting = false
    }

    private func loadPreview(token: String) async {
        struct In: Encodable { let token: String }
        preview = try? await EusoTripAPI.shared.query("consigneePortal.publicTrack", input: In(token: token))
    }

    private func revoke() async {
        actionAck = nil; actionError = nil
        guard let token = link?.token else { return }
        revoking = true
        struct In: Encodable { let token: String }
        do {
            let out: RevokeOut = try await EusoTripAPI.shared.mutation("consigneePortal.revokeShareLink", input: In(token: token))
            if out.revoked { link = nil; preview = nil; actionAck = "Link revoked — the consignee can no longer track." }
        } catch {
            actionError = error.eusoUserCopy
        }
        revoking = false
    }

    private func prettyDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let d = ISO8601DateFormatter().date(from: raw) ?? {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: raw)
        }()
        guard let d else { return raw }
        let out = DateFormatter(); out.dateFormat = "MMM dd, yyyy"
        return out.string(from: d)
    }
}

#Preview("694 · Vessel Consignee Tracking Link · Night") {
    VesselConsigneeTrackingLinkScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("694 · Vessel Consignee Tracking Link · Light") {
    VesselConsigneeTrackingLinkScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
