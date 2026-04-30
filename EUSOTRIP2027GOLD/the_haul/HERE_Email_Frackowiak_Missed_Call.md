# HERE Technologies — Missed Call Recovery Email
## To Alexandra Frackowiak, SDR · HERE Technologies
## From Mike Usoro, Founder · Eusorone Technologies, Inc.

> **Purpose:** Recover the missed call by putting the substance in writing. State wants and needs across mapping, traffic, monetization, and the recognition layer (The Haul). Anchor the four asks. Reschedule.

---

## Subject line options (pick one)

1. **EusoTrip ↔ HERE — sorry I missed today's call. Here's what I would have asked.**
2. **HERE platform — production customer needs (mapping, traffic, marketplace, support)**
3. **EusoTrip @ Build 55 — wants and needs ahead of our reschedule**

Recommended: **#1.** It's honest, signals real substance, and the parenthetical earns the open.

---

## Email body — copy-paste ready

```
Subject: EusoTrip ↔ HERE — sorry I missed today's call. Here's what I would have asked.

Alexandra,

Apologies for missing today. Head down on a build week — Build 55 of our
iOS app went up to App Store Connect and I lost the hour. Rather than
make you wait for the reschedule to learn what's on the table, here's
the substance, in writing, so you can pre-brief the right people on your
side before we talk.

Quick context. I'm Mike Usoro, founder of Eusorone Technologies. We make
EusoTrip — a 24-role freight operating system covering trucking, rail,
and ocean across the US, Canada, and Mexico. We're a paying HERE
customer, mid-rollout. Last week we finished migrating from API key to
OAuth2 client credentials with bearer tokens (HEREAuthService.swift, for
your engineering folks if they care to look). We're in active beta with
2,100 drivers across 60 fleets, projecting ~25,000 monthly actives and
60M-100M API calls per month by Q4.

Here is what we are building on top of HERE, and what we need from you.

──────────────────────────────────────────────────────────────────
1. MAPPING
──────────────────────────────────────────────────────────────────

What we use today:
  - HERE Geocoding & Search v7 (every address field in the app)
  - HERE Maps API for JavaScript v3.1 (the Hot Zones heatmap that drivers
    see on Driver Home — high-margin freight zones rendered as a live
    overlay)
  - HERE Raster Tile API v3 (basemap tiles for Hot Zones and the loadboard
    map view)
  - HERE Truck Attributes (bridge clearance, hazmat-restricted lanes,
    weight-restricted segments — surfaced in route warnings before a
    driver accepts a load)

What we need:
  - Confirmation that we're on the current plan tier appropriate to our
    volume trajectory (we transitioned past the Limited Plan; please
    confirm Base Plan or better is reflected on our account).
  - Pricing visibility for 60M-100M API calls per month across the
    surfaces above.
  - JS Maps SDK roadmap question: when does the JS SDK accept OAuth
    Bearer tokens natively? We're running two credential types in
    parallel today (server-side Bearer + JS apiKey) and would like to
    retire the apiKey when the SDK supports it.

──────────────────────────────────────────────────────────────────
2. ROUTING & TRAFFIC
──────────────────────────────────────────────────────────────────

What we use today:
  - HERE Routing v8 (load-acceptance routing, ETA computation, escort
    convoy routing)
  - HERE Traffic v7 (real-time traffic on driver routes, ETA refresh,
    Hot Zone temperature)
  - HERE Isolines API (driver availability radius for dispatch matching)

What we need:
  - Volume commit pricing for the routing + traffic surface at our Q4
    projection.
  - Confirmation that Routing v8 + Truck Attributes cover all 50 US
    states, all Canadian provinces, and Mexico (Carta Porte routes
    through MX customs corridors specifically).
  - SLA detail. We're a launch-day-sensitive customer. If the routing
    surface degrades at 2 a.m. on a launch night, we need to know
    where to call.

──────────────────────────────────────────────────────────────────
3. MONETIZATION — THE HAUL & THE DATA FEEDBACK LOOP
──────────────────────────────────────────────────────────────────

This is the part most HERE customers don't bring you, and it's the
strategic conversation I want to have.

Inside EusoTrip, drivers participate in a recognition system we call
The Haul. It's a professional community + standing layer — drivers
complete real loads, earn recognition tiers (Rookie → Pro → Veteran →
Legend), and contribute to a lane-scoped community. PSO-inspired loop,
professionally restated. Driver-facing copy never uses the word
"gamification" — internally that is the design substrate; externally
it is a community + recognition system.

What this means for HERE: every active driver on EusoTrip is, by
construction, a high-fidelity ground-truth sensor. Through The Haul we
already capture (with explicit driver consent and full anonymization at
the contribution layer):

  - POI accuracy verifications at moment of arrival (truck stop tier,
    fuel availability, parking count, amenity correctness)
  - Bridge clearance & weight-restriction confirmations or corrections
  - Hot zone validation (does the predicted high-margin lane match
    real on-road conditions in the last 4 hours?)
  - Route ground-truth (was the HERE-routed path the path actually
    driven, and if not, what was the deviation reason)

Today this data lives inside The Haul as recognition-tier inputs. We
keep it. We could pipe it back to HERE.

What we need:

  - A conversation with whoever at HERE owns the Workspace Marketplace /
    contributor side. Is there a contributor program where a customer
    that produces high-fidelity ground truth at scale gets compensated
    via revenue share or data license fee?
  - If a software-platform contributor program does not exist yet, we
    are willing to be the first pilot. The model already exists for
    OEMs (BMW / Audi / Daimler are HERE owners; connected-car data is
    the precedent). We are the comparable contribution profile for
    professional fleet drivers.
  - The structural ask: HERE-funded micropayments to contributing
    drivers, passed through EusoTrip's payment rails. Net effect — HERE
    gets ground truth no map-data competitor can buy, drivers get paid
    for time they're already spending, EusoTrip gets a durable HERE
    relationship.

──────────────────────────────────────────────────────────────────
4. ENTERPRISE SUPPORT — LAUNCH WEEK
──────────────────────────────────────────────────────────────────

Public launch on the App Store is Q3 2026. We need a named technical
support contact and a guaranteed response SLA for the launch window.
Standard support portal coverage is fine 51 weeks of the year; week 52
is the one we're sensitive about.

  - What does enterprise support look like at our trajectory?
  - Who is the launch-week point of contact?
  - Is there a HERE-side dry-run we can do together in the two weeks
    before launch?

──────────────────────────────────────────────────────────────────
SUMMARY OF ASKS
──────────────────────────────────────────────────────────────────

Compactly, we need:

  1. Confirmation of current plan tier on our account, plus pricing
     visibility for 60M-100M API calls per month (mapping + routing +
     traffic + truck attributes + isolines).
  2. Introduction to the Account Executive who owns customers at our
     volume trajectory.
  3. Introduction to the HERE Workspace Marketplace / contributor
     team so we can scope the data-feedback-loop partnership.
  4. JS Maps SDK Bearer token roadmap update so we can retire the
     parallel JS apiKey.
  5. Enterprise support tier scoping for our Q3 launch week.

──────────────────────────────────────────────────────────────────
WHAT I'LL SEND YOU NEXT
──────────────────────────────────────────────────────────────────

  - EusoTrip one-pager (executive view of the company)
  - The Haul + Data Feedback Loop one-pager (what we'd be contributing
    to HERE if we structure a partnership)
  - 30-second screen capture of HERE-powered surfaces inside the iOS
    app (Hot Zones heatmap, routing for load acceptance, geofenced
    Mission alerts, Pulse watch with HERE truck attributes triggering a
    hazmat warning)

I'll send those within 48 hours. If you want them earlier, reply and I
will prioritize.

──────────────────────────────────────────────────────────────────
RESCHEDULE
──────────────────────────────────────────────────────────────────

I'm available for the reschedule any of the following — pick whatever
works on your calendar and I'll confirm:

  - Thursday May 1, 10:00 a.m. – 12:00 p.m. CT
  - Thursday May 1, 2:00 p.m. – 4:00 p.m. CT
  - Friday May 2, 9:00 a.m. – 11:00 a.m. CT
  - Monday May 5, any block before 3:00 p.m. CT

If you have a Calendly link or scheduling tool you prefer, send it and
I'll book directly. If it's faster to loop in your AE on the same call,
even better — I'd rather move at the speed of one meeting than three.

Looking forward.

— Mike Usoro
   Founder & CEO, Eusorone Technologies, Inc.
   diego@eusorone.com
   www.eusorone.com
   m. [your cell]
```

---

## Pre-send checklist

Before you hit send:

- [ ] Confirm your actual current plan tier — pull `platform.here.com` → Account → Billing — and revise the Mapping section if the answer is something other than "transitioned past Limited."
- [ ] Confirm Maps JS version string in the iOS WebView (should be `v3.1` — search the iOS repo for `js.api.here.com`).
- [ ] Confirm Raster Tile v3 (not legacy Map Image API). Search for `raster.api.here.com` or `tile.api.here.com`.
- [ ] Replace the four reschedule slots with whatever's actually open on your calendar in the next 5 business days. Don't promise hours you can't hold.
- [ ] Replace `[your cell]` with your real number. SDRs and AEs always escalate faster when there's a phone number, even if they don't use it.
- [ ] CC anyone internally you want looped in (CFO if the conversation might land at $250K+ ARR commit; VP Eng if she might come back with a technical-fit question).
- [ ] Attach the three documents listed in the "What I'll send you next" section, OR send the email today and follow up with the attachments inside 48 hours as promised. Don't let the 48-hour promise slip; it's a credibility cost you don't need.

---

## Voice & tone notes

- The email is long because the substance is real. Don't apologize for the length — long, specific emails outperform short, vague ones at the SDR-to-AE handoff. Alexandra will forward this to her AE verbatim, and the AE will read every word.
- The opening apology is one sentence. Don't grovel. "Apologies for missing today. Head down on a build week" is enough.
- The technical name-drops (`HEREAuthService.swift`, Maps API for JS v3.1, Raster Tile API v3, Routing v8, Truck Attributes, Carta Porte) are deliberate. They tell HERE engineering this isn't a tire-kicker email.
- The Haul section is the strategic content. Don't shorten it. The word "gamification" must NOT appear in driver-facing copy or in any HERE-facing materials we publish — but the design substrate IS that, and that fact stays internal. The email uses "recognition system" and "community + standing layer" externally, which is correct.
- The Asks section is numbered for a reason. Alexandra will check off each one when she replies. Don't make her hunt for what we want.
- Closing line is "Looking forward." Not "Looking forward to chatting" or "Looking forward to our next conversation." Two words. Calm. Done.

---

## After it sends

1. Watch your inbox for 48 hours. SDRs at HERE typically reply same-day or next-day on a substantive email. If no reply by Friday May 1 EOD, send a one-line bump: *"Alexandra — circling back. Did the email below come through clean?"*
2. The moment you get a reschedule confirmation, update `HERE_Call_Script_Frackowiak.md` § Pre-call prep with the new date.
3. The moment Alexandra introduces an AE, add the AE's name + title to the script's footer line ("Update after the call with the AE name + next-meeting date") — and CC them on every subsequent message in the thread.

---

*Last updated: 2026-04-29. Mirrored to `EUSOTRIP2027GOLD/the_haul/` in both repos. Send-ready.*
