# iOS production audit — remediation plan
**Date:** 2026-05-22 · **Scope:** `EusoTrip/Views/` · **Author:** session-handoff doc

This report enumerates two doctrine violations found in the existing
iOS production views and proposes a wiring strategy for each. **No code
edits were made** — this is an implementation plan for follow-up
sessions.

Both doctrines come from `MEMORY.md`:
1. **Zero stubs / no dead buttons** — every Button must fire a real
   action (mutation, navigation, or local state change with downstream
   effect). `Button { } label: { ... }` is an anti-pattern.
2. **Fully dynamic** — every visible value must bind to a tRPC read.
   Canonical scenario literals (`CEL`, `M-04`, `JR Reyes`, `$1,489`,
   `Aurora Freight`, `Michael Eusorone`, `Eusotrans LLC`, etc.) are
   wireframe-illustration artifacts that must be replaced with bindings
   to whichever load / driver / carrier the user is actually viewing.

---

## §1 · DEAD BUTTONS

19 confirmed `Button { } label: { … }` instances across 7 files
(plus the `DriverNavController` doctrine comment that flags
"60 remaining dead Button{}label" — the author is already aware
the regex misses some multi-line variants).

### §1.1 · Confirmed dead-button inventory

| File | Lines | Count | Vantage |
|---|---|---:|---|
| `Dispatch/Dpch720_DispatcherSVGTrio.swift` | 173 · 178 · 184 · 558 · 566 | **5** | Dispatcher SVG trio (403/405/411) |
| `Dispatch/Dpch730_DispatcherOpsQuartet.swift` | 346 · 355 · 552 · 706 · 714 | **5** | Dispatcher ops (406/407/408/414) |
| `Dispatch/Dpch734_DispatcherControlQuartet.swift` | 286 · 294 · 464 · 641 · 650 | **5** | Dispatcher control (409/413/416/417) |
| `Dispatch/Dpch724_DispatcherExceptionQuartet.swift` | 789 · 797 | **2** | Dispatcher exception (412/415/418/419) |
| `Shipper/248_ShipperPODReceipt.swift` | 181 | **1** | Shipper POD receipt |
| `Catalyst/302_CatalystProfile.swift` | 94 | **1** | Catalyst profile |
| `Driver/DriverNavController.swift` | 195 | **1** (comment) | doctrine reference |

### §1.2 · Proposed wiring per file

#### `Dispatch/Dpch720_DispatcherSVGTrio.swift` — 403/405/411 trio
Tender Queue · Comms Hub · BOL Mismatch surfaces.
- **L173, 178, 184** — likely "Accept tender / Decline / Counter" row
  buttons on the 403 Tender Queue card. Wire to:
  - Accept → `dispatchRole.acceptLoad({ loadId })` (exists,
    `dispatchRole.ts`)
  - Decline → `dispatchRole.declineLoad({ loadId })` (exists)
  - Counter → open a counter sheet → `bidReview.counterOffer({ loadId,
    counterRate })`
- **L558, 566** — read after open; likely "Mark Read / Reply" on the
  405 Comms Hub. Wire to:
  - Mark Read → `messages.markRead({ conversationId })`
  - Reply → push a `MessagesComposeSheet`

#### `Dispatch/Dpch730_DispatcherOpsQuartet.swift` — 406/407/408/414
Yard Slots · Reassignment · Quick-Tender · Escort Republish.
- **L346, 355** — Yard Slots action row. Wire to a `dispatch.assignYard`
  proc (CHECK: may not exist; if missing, propose new proc:
  `dispatchRole.assignYardSlot({ loadId, slot })`).
- **L552** — Reassignment commit. Wire to existing
  `dispatchRole.reassignLoad({ loadId, newCarrierId })`.
- **L706, 714** — Quick-Tender accept / decline (same as Dpch720).

#### `Dispatch/Dpch734_DispatcherControlQuartet.swift` — 409/413/416/417
Settings · Weather Reroute · Reload Offer · Fuel Policy.
- **L286, 294** — Settings toggle row commits. Wire to a
  `dispatchSettings.*` family OR fold into existing user-prefs surface.
- **L464** — Weather-driven reroute "Approve" button. Propose:
  `dispatch.applyRecommendedReroute({ loadId, polyline })`.
- **L641, 650** — Reload offer accept / fuel policy override commit.
  Both need new procs OR fold into `dispatchRole.acceptLoad` variants.

#### `Dispatch/Dpch724_DispatcherExceptionQuartet.swift` — 412/415/418/419
HOS Reassign · Cancel Load · Late Pickup · Dock Mismatch. Two of these
were partially wired in commit `5fd8847` (Cancel Load) and `cebc906`
(Late Pickup extend/release) — the **L789, L797** dead buttons are the
last two members of the quartet.
- **L789** — likely HOS Reassign commit. Wire to a `dispatch.reassign
  HOS` proc OR reuse `dispatchRole.reassignLoad` with HOS reason code.
- **L797** — Dock Mismatch resolution. Wire to
  `dispatchRole.resolveException({ loadId, exceptionType: "dock_mismatch", note })`.

#### `Shipper/248_ShipperPODReceipt.swift` — POD receipt
- **L181** — likely "Download POD / Share" button. Wire to:
  - `loads.getPODUrl({ loadId })` → present native share sheet via
    `UIActivityViewController`.

#### `Catalyst/302_CatalystProfile.swift` — Catalyst profile
- **L94** — likely "Edit profile" or "Verify" CTA. Wire to:
  - `catalysts.updateProfile({ … })` mutation if it exists, OR push
    a profile-edit sheet.

### §1.3 · The "60 remaining dead buttons" (per `DriverNavController:195`)

Author comment says 60+ more exist that this regex doesn't catch.
**Recommended next pass:** broaden the grep to multi-line patterns:

```bash
# Catches Button { /* whitespace + comments only */ } label:
grep -rPzo 'Button\s*\{\s*([^a-zA-Z_/]|//[^\n]*|/\*[\s\S]*?\*/)*\s*\}\s*label:' Views/
```

Or simpler: scan for `Button {` followed by a body that contains
no identifier characters. Best done as a dedicated audit pass in a
fresh session.

---

## §2 · HARDCODED SCENARIO DATA

49 production view files contain canonical scenario tokens (`CEL`,
`M-04`, `JR Reyes`, `Diego Usoro`, `Aurora Freight`, `Michael Eusorone`,
`Eusotrans LLC`, `LD-M-04`, `MC-712 944`, `UN1203`, `Houston→Dallas`,
`Atlanta→Charlotte`, `$1,489`, etc.).

### §2.1 · Top hotspots by hit count

| Hits | File | Strategy |
|---:|---|---|
| **27** | `Shipper/SH261_ShipperM04ObservedNonet.swift` | Refactor whole bundle to bind `loads.getById` + party-resolver helper |
| **20** | `Driver/DL141_DriverCELM04CloseOctet.swift` | Same refactor pattern as Driver 149 audit (this session) |
| **19** | `Driver/DL126_DriverCELM04Septet.swift` | Same — 149 audit pattern |
| **19** | `Catalyst/CV369_CatalystM04BiddingSextet.swift` | Same |
| **6** | `Dispatch/Dpch820_DispatcherM04KanbanQuintet.swift` | Same |
| **6** | `Catalyst/CV320B_CatalystDriverBVariantOctet.swift` | Same |
| **5** | `Dispatch/Dpch790_DispatcherLaneRFPSextet.swift` | Same |
| **5** | `Components/EusoTicketCanvas.swift` | Make rendering data-driven (EusoTicket DTO) |
| **5** | `Catalyst/CV375_CatalystM04FleetTrackPair.swift` | Same as DL141 pattern |
| **5** | `Catalyst/CV330B_CatalystVehicleBVariantOctet.swift` | Same |
| 4 | `Shipper/229_ShipperBOLUpload.swift` | bind to `loads.getById` |
| 4 | `Driver/DL133_DriverCELM04DVIRContinuationOctet.swift` | DL141 pattern |
| 4 | `Catalyst/313_CatalystEusoTicketRenderer.swift` | EusoTicket DTO |
| 3 | `Shipper/208_ShipperPaymentMethods.swift` | bind to `users.getProfile` / `wallet.*` |
| 3 | `Catalyst/CV330_CatalystVehicleScorecardSeptet.swift` | DL141 pattern |
| 2 × many | Long tail of single/double-hit files | Targeted per-line replacements |

### §2.2 · The replacement pattern (proven by Driver 149 audit this session)

1. Drop scenario constants (`"CEL"`, `"M-04"`, `"JR"`, `"$1,489"`,
   `"245 mi"`, `"I-85 SE"`).
2. Bind to `loads.getById`-driven state: `loadNumberDisplay`,
   `rateDisplay`, `laneDisplay`, `distanceDisplay`, `equipmentDisplay`,
   `settleDateDisplay` (computed from `deliveryDate + 30d`).
3. Use `"—"` as the "unresolved" placeholder, **not** a scenario value.
4. For driver/dispatch/shipper **names**: today's `loads.getById`
   returns only `driverId`/`catalystId`/`shipperId`. Add a server-side
   **party resolver**:
   - Either extend `loads.getById` to return `driver`, `catalyst`,
     `shipper` resolved objects with `{ name, initials, companyName,
     mcNumber }`.
   - Or add `loads.getPartyContext({ id })` returning the resolved
     parties without bloating the existing endpoint.

### §2.3 · Required server-side additions for the doctrine

| New piece | Why | Where |
|---|---|---|
| `loads.getById` returns `driver`/`catalyst`/`shipper` resolved | Most screens need driver name + carrier MC — currently only IDs | `frontend/server/routers/loads.ts:1266` |
| Or: `loads.getPartyContext({ id })` | Alternative to bloating `getById` | new in `loads.ts` |
| `companies` MC lookup helper | Driver screens want carrier MC# | resolver alongside party context |

Without one of these, scenario refactoring stalls — every screen can
display load fields but every screen falls back to `"—"` for names.

---

## §3 · PRIORITIZATION (recommended order)

Highest leverage first — these are the screens with most hits or most
user-visible impact.

### Tier 1 — high-value rewires
1. **`SH261_ShipperM04ObservedNonet`** (27 hits) — shipper nonet,
   highest concentration. Single file pass.
2. **`DL141_DriverCELM04CloseOctet`** (20 hits) — driver close octet,
   user-facing 8-screen bundle. Apply Driver 149 audit pattern.
3. **`DL126_DriverCELM04Septet`** (19 hits) — driver CEL M04 septet.
   Same pattern.
4. **`CV369_CatalystM04BiddingSextet`** (19 hits) — catalyst bidding.
   Same pattern.

### Tier 2 — dead-button cleanup
5. **`Dpch720_DispatcherSVGTrio`** (5 dead buttons) — wire to
   `dispatchRole.acceptLoad`/`declineLoad` + counter-offer.
6. **`Dpch730_DispatcherOpsQuartet`** (5 dead buttons) — yard / reassign
   / quick-tender / escort.
7. **`Dpch734_DispatcherControlQuartet`** (5 dead buttons) — settings /
   reroute / fuel policy.
8. **`Dpch724_DispatcherExceptionQuartet`** (2 dead buttons) — last
   2 members of the quartet (HOS reassign + dock mismatch).

### Tier 3 — single-hit cleanups + server-side
9. `Shipper/248_ShipperPODReceipt:181` — wire POD share.
10. `Catalyst/302_CatalystProfile:94` — wire profile edit.
11. **Server-side: add party resolver** (`loads.getPartyContext` or
    extend `getById`) — unblocks the scenario-data refactor for every
    screen that needs driver/carrier names.

### Tier 4 — long-tail
12. Remaining ~35 files with 1-4 hits each — single-line replacements
    once the party resolver lands.

---

## §4 · ESTIMATED EFFORT

| Tier | Files | Effort (focused engineering) |
|---|---:|---|
| Tier 1 (top 4 hotspots) | 4 | ~3-4 hours each → 12-16 hours |
| Tier 2 (Dispatch dead buttons) | 4 | ~1-2 hours each → 4-8 hours |
| Tier 3 (single fixes + server resolver) | 3 | ~4-6 hours total |
| Tier 4 (long tail) | ~35 | ~15 minutes each → 8-10 hours |
| **Total** | **~46 files** | **~28-40 hours** |

This is 4-5 focused engineering days. Realistically a multi-session
sprint with the party-resolver server change shipping first (Tier 3
item #11) so every screen rewire below it has the data to bind.

---

## §5 · WHAT NOT TO TOUCH

Per `MEMORY.md` doctrines:
- **Driver bottom-nav** (frozen; `feedback_bottom_nav_frozen.md`).
  Several "dead buttons" may turn out to be intentional non-action
  affordances per the bottom-nav freeze — verify each before wiring.
- **Pulse Watch app** — Watch surfaces have their own doctrine; not in
  this audit scope.

---

## §6 · NEXT STEP

Start with the **server-side party resolver** (Tier 3 #11). It unblocks
the scenario refactor for everything below. Then attack Tier 1 in
order. Each rewire follows the proven pattern from this session's
Driver 149 audit (commit `7470d75`):
- `private struct …Load: Decodable` projecting `loads.getById`
- Computed `…Display` properties with `"—"` fallback
- Bind every `Text(...)` to a display property
- Light + Dark `#Preview` blocks

Done.
