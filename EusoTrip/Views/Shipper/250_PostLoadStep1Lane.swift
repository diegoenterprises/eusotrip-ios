//
//  250_PostLoadStep1Lane.swift
//  EusoTrip — Shipper · Post-a-Load · Step 1 LANE.
//
//  First step of the wizard. Origin + destination + pickup window.
//  Bound to the shared `PostLoadDraft`. "Continue" advances to 251
//  Equipment via NotificationCenter screen-swap.
//

import SwiftUI

struct PostLoadStep1LaneScreen: View {
    let theme: Theme.Palette
    @StateObject var draft = PostLoadDraft()

    var body: some View {
        Shell(theme: theme) {
            PostLoadStep1Body(draft: draft)
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct PostLoadStep1Body: View {
    @Environment(\.palette) private var palette
    @ObservedObject var draft: PostLoadDraft

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                fieldsCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("POST A LOAD · STEP 1 · LANE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("Where is the freight going?")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text("Enter origin, destination, and the pickup window.")
                .font(EType.body).foregroundStyle(palette.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.85)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard {
            // ── Mode picker (T-002 · 2026-05-20) ────────────────────
            // Drives the entire wizard. Picking Rail surfaces rail
            // equipment chips on Step 2 (251_PostLoadStep2Equipment.swift
            // already switches on draft.mode at line 24). Picking Vessel
            // does the same for vessel chips. Clearing equipmentType on
            // change prevents a stale truck selection from carrying into
            // a rail/vessel load — every mode has its own equipment list.
            //
            // Bound to `draft.mode` (PostLoadDraft.Mode, 3 cases:
            // truck/rail/vessel). The canonical `TransportMode` enum from
            // `Models/Multimodal/MultiModalCore.swift` adds a 4th case
            // (.barge); migrating `draft.mode` to the canonical type is
            // tracked separately so every existing exhaustive switch in
            // 251 / 253 / 257 stays valid.
            LifecycleSection(label: "MODE", icon: "shippingbox.and.arrow.backward")
            Picker("Mode", selection: $draft.mode) {
                ForEach(PostLoadDraft.Mode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: draft.mode) { oldMode, newMode in
                // T-031 · 2026-05-20 — Canonical cross-track auto-snap.
                // When the user flips truck → rail (or any combo), look
                // up the equivalent equipment in the new mode via
                // `EquipmentEquivalency.equivalent(of:in:)` from T-001's
                // foundation. The existing trailer (TrailerCode) is the
                // only structured source today; PostLoadDraft will grow
                // `railCar: RailCarKind?` and `vesselClass: VesselClassKind?`
                // in T-031b so the suggestion can actually be stored —
                // until then this surfaces the suggestion via the
                // existing `equipmentType: String` field as a label
                // hint, and clears `trailer` (TrailerCode is truck-only).
                guard let truckTrailer = draft.trailer else {
                    // No canonical trailer set yet → standard clear.
                    draft.equipmentType = ""
                    return
                }
                let source = AnyEquipment.truck(truckTrailer)
                let targetMode: TransportMode = {
                    switch newMode {
                    case .truck:  return .truck
                    case .rail:   return .rail
                    case .vessel: return .vessel
                    }
                }()
                let equivalent = EquipmentEquivalency.equivalent(of: source, in: targetMode)
                switch equivalent {
                case .truck(let t):
                    // truck → truck (no change really, but the equivalency
                    // map can return a same-mode result for completeness).
                    draft.trailer = t
                    draft.equipmentType = t.rawValue
                case .rail(let r):
                    // Rail-mode pick. Wizard doesn't yet have a railCar
                    // field, so we hint via equipmentType and clear
                    // trailer (canonically truck-only).
                    draft.trailer = nil
                    draft.equipmentType = r.rawValue
                case .vessel(let v):
                    draft.trailer = nil
                    draft.equipmentType = v.rawValue
                case .none:
                    // No canonical equivalent (e.g., livestock → rail/vessel
                    // has no match). Fall back to clearing so Step 2 surfaces
                    // its full mode list and the user picks fresh.
                    draft.trailer = nil
                    draft.equipmentType = ""
                }
                _ = oldMode    // silenced — oldMode reserved for future undo/redo
            }

            // ── Country picker (T-003 · 2026-05-20) ─────────────────
            // Origin + destination country drive customs / hazmat
            // regulatory dispatch. The canonical `Country` enum in
            // `Services/FeeMultiplierEngine.swift` has 3 cases (US/MX/CA)
            // — but `PostLoadDraft.Country` already supports 6 (adds
            // EU/UK/Asia). Bound to the broader draft enum so EU/UK/Asia
            // lanes still post; FeeMultiplierEngine.compute(...) clamps
            // unknown countries to the US multiplier until the fee
            // engine grows ROW coverage. USMCA chip lights up when
            // draft.isUSMCA is true (US-CA or US-MX or CA-MX, etc.).
            LifecycleSection(label: "COUNTRIES", icon: "globe")
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ORIGIN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Picker("Origin country", selection: $draft.originCountry) {
                        ForEach(PostLoadDraft.Country.allCases) { c in
                            Text("\(c.flag) \(c.rawValue)").tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("DESTINATION").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Picker("Destination country", selection: $draft.destinationCountry) {
                        ForEach(PostLoadDraft.Country.allCases) { c in
                            Text("\(c.flag) \(c.rawValue)").tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(palette.bgCard.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            if draft.isCrossBorder {
                HStack(spacing: 6) {
                    Image(systemName: draft.isUSMCA ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(draft.isUSMCA ? "USMCA lane — preferential treatment eligible" : "Cross-border lane — customs broker required")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(LinearGradient.diagonal.opacity(0.10))
                .clipShape(Capsule())
            }

            LifecycleSection(label: "LANE", icon: "map")
            // Origin / destination use HereAddressField so the user gets
            // typeahead suggestions from the HERE Geocoding API and can
            // also paste raw coordinates ("32.7767,-96.7970") — the way
            // truckers capture pickup/delivery for unaddressed sites
            // (oilfield pads, agricultural lots, port slips). Coords
            // ride along to `shippers.create` so distance + map render
            // without a second-pass server geocode.
            field(label: "Origin") {
                HereAddressField(
                    text: $draft.origin,
                    lat:  $draft.originLat,
                    lng:  $draft.originLng,
                    placeholder: "City, ST or lat,lng"
                )
            }
            field(label: "Destination") {
                HereAddressField(
                    text: $draft.destination,
                    lat:  $draft.destLat,
                    lng:  $draft.destLng,
                    placeholder: "City, ST or lat,lng"
                )
            }
            field(label: "Pickup window") {
                DatePicker("", selection: Binding(
                    get: { draft.pickupDate ?? Date() },
                    set: { draft.pickupDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            }
            field(label: "Delivery window (optional)") {
                DatePicker("", selection: Binding(
                    get: { draft.deliveryDate ?? Date().addingTimeInterval(86400) },
                    set: { draft.deliveryDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func field<Inner: View>(label: String, @ViewBuilder content: () -> Inner) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            content()
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                // T-004 · 2026-05-20: routed to 255 (MultiStop builder),
                // not 256 (AddressPicker). The audit caught a typo where
                // the multi-stop affordance was opening the single-address
                // picker, which had no multi-stop UX. Address-book lookup
                // stays available via the individual Origin/Destination
                // HereAddressField suggestions above.
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "255"])
            } label: {
                Text("Multi-stop builder").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(palette.tintNeutral).clipShape(Capsule())
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "251"])
            } label: {
                Text("Continue").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }
}

#Preview("250 · Lane · Night") {
    PostLoadStep1LaneScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("250 · Lane · Afternoon") {
    PostLoadStep1LaneScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
