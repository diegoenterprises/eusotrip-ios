# HERE Technologies — Discovery Call Script
## With Alexandra Frackowiak, SDR · HERE Technologies

> **Goal of this call:** convert an SDR triage into a strategic enterprise relationship, anchor pricing on volume + data-marketplace participation, and walk out with a named Account Executive + a follow-up meeting.

> **What you're NOT here to do:** sound like a startup begging for a discount. You're a paying customer at scale who is offering HERE something they can't get elsewhere — a directly-instrumented, anonymized data feedback loop from professional drivers across truck/rail/vessel modes.

---

## 0 — Pre-call prep (do these in the 15 minutes before)

- [ ] LinkedIn-stalk Alexandra. SDR at HERE, likely in Chicago, Frankfurt, or Eindhoven. Note her tenure. If <12 months, she's hungry to qualify and book.
- [ ] Pull up the HERE platform billing dashboard. Note your current tier + month-to-date API calls.
- [ ] Have ready: the EusoTrip 1-pager + the Trillion-Dollar Doctrine cover note (just §0 + §1) + a screenshot of the Hot Zones heatmap on Driver Home.
- [ ] Camera on. Headset working. Quiet room.
- [ ] Notebook. Pen. Two questions you intend to leave the call having asked, even if she dodges:
   1. *What does HERE's data marketplace pay for high-fidelity professional-driver ground truth?*
   2. *Who is the right AE for a customer driving 20M+ API calls/month projected by Q4?*

---

## 1 — Opener (90 seconds)

> "Alexandra, thanks for reaching out — twice. Sorry I missed the first one, head down on a build week. Mike Usoro, founder of Eusorone Technologies. We make EusoTrip — it's the operating system for freight: trucking, rail, ocean. We've been using the HERE platform for about six months now — routing, geocoding, traffic, the truck-attributes API, the JS Maps SDK for our Hot Zones heatmap, and we just finished migrating from API key to OAuth2 client credentials with bearer tokens. Latest commit landed last week.
>
> The reason this is a real relationship and not a 'kicking-tires' call is two things. One — we're already in production. Build 55 of our iOS app went up to App Store Connect this week and HERE is wired into the driver-facing experience. Two — we have a feedback loop you don't have anywhere else in your customer base, and that's what I want to talk about.
>
> What's the best way to do this? Do you want me to walk you through what we've built first, or do you have a discovery template you usually run through?"

**Why this works:** you've signaled paying customer + production scale + technical specificity (OAuth2 migration is non-trivial — every HERE engineer respects it) + a tease of a unique offer. You've also given Alexandra control of the call structure, which puts her at ease.

---

## 2 — Discovery — what she'll ask + how you answer

### "What are you building?"

> "EusoTrip is a 24-role freight operating system. Driver-first by design. We have an iOS + watchOS companion app — that's our flagship — and a web platform for dispatchers, brokers, shippers, captains, port agents. The core thesis is that the trucker on I-40 at 3 a.m. and the captain at the Houston ship channel are using the same brand, the same data, the same identity. One platform. Three modes. Three countries — US, Canada, Mexico — all of USMCA, Carta Porte, ACE/ACI built in.
>
> HERE is the spatial layer. Routing for load-acceptance, geocoding for address fields, truck attributes for bridge-clearance and hazmat-restricted lanes, traffic for ETA, and the JS Maps SDK powers our heatmap of high-margin freight zones."

### "How many users?"

> "Active beta with 2,100 drivers across 60 fleets. Treaty pilots in Texas and Louisiana. Onboarding cadence is 5,000 new drivers a quarter through Q4. Twelve-month projection puts us at ~25,000 monthly actives. Each driver triggers ~80 HERE API calls per active day — routing, geocoding, geofence checks, traffic, isolines. That's our trajectory."

### "What's your timeline?"

> "We're shipping weekly to TestFlight. Public launch on App Store is Q3. The HERE relationship is a launch dependency — if anything breaks at the rate-limit ceiling on launch day, we eat it. So we have a six-week window where the right pricing tier is the difference between a smooth launch and a fire drill."

### "Tell me about your team."

> "Founder-led. I'm Mike Usoro — broker background, oil and gas, Texas. CFO and VP Eng round out the executive layer. Engineering is small but disciplined — we run TDD, the iOS app is at 99.5% crash-free users in TestFlight."

### "What problems are you running into with HERE?"

This is your money question. Give the answer that sets up the asks.

> "Three things, in order of size. First — we've outgrown the freemium tier for routing v8 and traffic v7. Volume's been doubling month over month. Second — we want to participate in the HERE data marketplace as a contributor, not just a consumer. That's where the strategic conversation gets interesting. Third — the JS Maps SDK doesn't accept OAuth bearer tokens, so we're running two key types in parallel, which is operationally annoying. Has that changed?"

---

## 3 — The Pitch — the data-feedback-loop monetization angle (this is the hook)

This is the section that turns an SDR call into an enterprise conversation.

> "Alexandra, here's the part most HERE customers don't bring to you. We have something called The Haul. It's the professional driver community + recognition layer inside our app. Drivers complete real loads, and the system layers Mission completion, Standing tiers, and a lane-scoped community on top of the work. PSO-inspired loop, professionally restated.
>
> What that means for HERE: every active driver on EusoTrip is a high-fidelity ground-truth sensor. They tell us when a truck stop's amenity tier is wrong. They tell us when a HERE-routed bridge clearance is off. They confirm when a hot zone has surged or cooled. They photo-verify POI accuracy at the moment of arrival.
>
> That data — anonymized, consent-walled, professionally attributed — is gold for HERE's map quality team. Right now we keep it. We could pipe it back to you. The question is: does HERE have a marketplace, a revenue share program, a data partnership tier — anything that compensates a customer for being a data contributor at scale?
>
> Our drivers do this work. Today they do it inside The Haul for recognition. Tomorrow, if we structure it right, they do it for a HERE-funded micropayment that we pass through. Net effect: HERE gets ground truth no map-data competitor can buy, drivers get paid for their time, and EusoTrip gets a more durable HERE relationship.
>
> Is there an existing program for this? If not, who would I talk to inside HERE to scope it?"

**What this does:**
- Reframes you from a customer extracting value → a partner contributing it.
- Creates an opening for revenue share, data-marketplace participation, or strategic-investment-in-kind (HERE invests in EusoTrip via API credit or marketing co-fund).
- Forces Alexandra to escalate. She can't answer this herself. She'll need to bring in an AE, a Channel Partner Manager, or a HERE Workspace Marketplace contact. That's the goal.

---

## 4 — The Three Strategic Asks (don't leave the call without all three)

State each one cleanly. Pause for response. Don't hedge.

### Ask 1 — Volume tier optimization

> "Based on our trajectory — ~80 calls per driver per active day, 25,000 monthly actives projected by Q4 — we're looking at 60 to 100 million API calls per month by year-end. What does that pricing tier look like, what's the volume commit, and is there a startup-stage discount or a co-marketing arrangement that ladders us up to enterprise pricing?"

Acceptable answer: she sends pricing. Better answer: she introduces an AE same week.

### Ask 2 — Data marketplace + revenue share

> "On the partnership angle I just raised — who at HERE owns the contributor side of the data marketplace? Is there a revenue-share or data-license program where a high-fidelity contributor gets paid? If yes, I want a meeting with that team. If no, I want a meeting with whoever could greenlight a pilot."

Acceptable answer: she points you to a Channel Partner Manager. Better answer: she emails an intro within 24 hours.

### Ask 3 — JS SDK Bearer token roadmap

> "Last technical thing. JS Maps SDK still requires API key, not OAuth Bearer. We've worked around it but it's a security smell to ship two credential systems. What's the roadmap on Bearer-supported JS SDK?"

Acceptable answer: she takes it to Product. Better answer: she confirms a beta exists.

---

## 5 — Closing the call (60 seconds)

> "Alexandra, this was useful. Let me make sure I have the next steps clear.
>
> One — you're going to send me current pricing for ~60 to 100M calls/month with the OAuth Bearer surface. Two — you're going to put me in front of the right person on the data marketplace + contributor side, this week if possible. Three — you're going to flag the JS SDK Bearer-token question to your product team and come back with what you hear.
>
> On my side — I'll send you a one-pager on EusoTrip and a slide on The Haul + the data feedback loop, so when you brief your AE you have ammunition. You'll have it in your inbox within an hour of this call ending.
>
> Anything I'm missing on next steps?"

Listen. Confirm. Get her direct cell or scheduling link. Hang up.

---

## 6 — Post-call (within 60 minutes)

### Follow-up email — copy-paste this

```
Subject: EusoTrip ↔ HERE — recap from today's call

Alexandra —

Thanks for the time today. Quick recap of what we discussed and committed
to, so we're aligned:

What you're sending me:
1. Pricing tiers for the OAuth Bearer surface at 60M-100M API calls/month
   (Routing v8, Geocoding v7, Truck Attributes, Traffic v7, Isolines).
2. An introduction to the HERE Workspace Marketplace / contributor team —
   we want to discuss data partnership for our anonymized professional-
   driver feedback stream (POI accuracy, route ground truth, hot zones).
3. Update from your product team on the JS Maps SDK Bearer token roadmap
   so we can retire our parallel JS apiKey.

What I'm sending you (attached):
1. EusoTrip one-pager (the executive view).
2. The Haul + Data Feedback Loop concept brief (1 page) — what we'd be
   contributing to HERE if we structure a partnership.
3. A 30-second screen capture of HERE-powered surfaces inside the
   EusoTrip iOS app — Hot Zones heatmap, routing for load acceptance,
   geofenced boss missions.

For your AE briefing, three numbers worth flagging:
- Currently in production — Build 55 shipped this week.
- Trajectory: 25K monthly actives by Q4 = ~60M+ HERE API calls/month.
- We are the only customer in your book that has consented professional
  drivers contributing real-time ground truth at scale via a community
  recognition system.

Looking forward to the next conversation.

— Mike Usoro
   Founder & CEO, Eusorone Technologies, Inc.
   diego@eusorone.com
   www.eusorone.com
```

### Attach (have these ready before the call so you can send within 60 minutes)

1. **EusoTrip one-pager PDF** — pull from `EUSOTRIP2027GOLD/` brand pack. If not finalized, generate a quick one-pager: company, mission, traction (60 fleets, 2,100 drivers, 25K projected), HERE integration scope, ask.
2. **The Haul + Data Feedback Loop one-pager** — write today. Use the language in §3 of this script. Anonymized. Consent-walled. Professionally attributed. Ground truth. Cover the four data streams: POI accuracy, traffic confirmations, road condition updates, hot zone validation.
3. **30-second screen capture** — record on your iPhone of the HERE-powered surfaces. No audio. Just clean visuals: Driver Home → Hot Zones heatmap → Load detail with route → Pulse watch with HERE truck attributes triggering hazmat alert.

---

## 7 — What HERE's monetization actually looks like (so you know what you're negotiating)

For internal context — what to expect when the AE comes back:

**HERE Platform tiers (pricing as of 2026):**
- Freemium: 30K transactions/month per service, free
- Pay-as-you-go: $0.50–$1.50 per 1K transactions depending on service (routing cheaper, isolines more expensive)
- Volume tier: $X/month commit, included transactions, overage pricing — discounts kick in at ~10M txns/month
- Enterprise: custom contract, often includes co-marketing, technical-account-management, and roadmap influence — typical floor for inclusion is 50M+ txns/month or $250K+ ARR commit. **You qualify.**

**HERE Workspace Marketplace:**
- HERE has a marketplace where data buyers (insurance companies, retailers, governments, OEMs) buy anonymized location data
- Contributors get a revenue share — typical splits we've seen industry-wide are 30–50% to the contributor for "high-fidelity verified" data, lower for raw bulk
- The contributor side is run out of HERE's "Open Location Platform" team (sometimes branded HERE Workspace)
- The strategic angle: HERE's mapping competitor moat is data freshness; consented professional-driver ground truth is exactly what they need

**Data partnership precedents:**
- HERE has done revenue-share with OEMs (BMW, Audi, Daimler are HERE's owners — connected-car data is the precedent).
- Less precedent for software-platform contributors, but the model exists.
- We are pioneering this for freight. That's a feature, not a bug.

**What "good" looks like coming out of this call:**
- 30 days: pricing + AE introduction in hand, NDA signed for marketplace conversation.
- 60 days: marketplace pilot scoped — what data, what compensation per record, what attribution.
- 90 days: signed agreement that includes (a) volume commit pricing, (b) data marketplace contributor enrollment, (c) HERE-funded micropayment to drivers passing through The Haul.
- 12 months: HERE writes a co-marketing case study about EusoTrip's data feedback loop. Worth more than the cash.

---

## 8 — If she pushes back on the partnership ask (handle these)

### "We don't have a contributor program for software platforms."

> "Then we'd be your first. The model exists for OEMs. We're a comparable contribution profile — high-volume, high-fidelity, consented. I'd be happy to be the first software-platform pilot. Who would I talk to about scoping that?"

### "That's above my pay grade."

> "Understood. Who at HERE owns partnerships of this shape — Channel Partner Manager? Strategic Alliances? I'd rather get pointed to the right person than have you carry water you can't carry."

### "What's your funding situation?"

> "Founder-funded. Profitable on a monthly basis since Q1. We're not raising a Series A right now — we're growing on customer revenue. I mention that because the relationship I'm proposing isn't a 'we need credits' conversation. It's a 'we want to bring HERE something HERE doesn't have' conversation. Pricing is one half of it. Partnership is the other."

### "Send me a deck and we'll review internally."

> "Happy to. Can I send it to you and your AE simultaneously, so the conversation moves at the same pace as the email chain? You said you'd loop in an AE on the volume side — if we can include that person on the deck send, we save a round-trip."

---

## 9 — Voice and tone

- Calm. Never excited. Never apologetic.
- Slow down on the partnership ask in §3 — that's the moment of the call. Let the silence after "Is there an existing program for this?" do its work.
- Don't say "synergy," "leverage," "empower," or "ecosystem" — even with a HERE SDR.
- Mention specific HERE product names — Routing v8, Truck Attributes, JS Maps SDK, OAuth Bearer, HERE Workspace. It signals you're a real customer, not a tire-kicker.
- Mention real numbers — 80 calls/driver/day, 60M-100M/month. Numbers force them to escalate.
- If she compliments you, accept it briefly and move on. ("Thanks. Worth doing.") Don't preen.

---

## 10 — Risks to manage

- **Don't oversell.** If she asks for production traffic numbers, give the real ones. Lying gets caught at the AE diligence stage and burns the relationship.
- **Don't commit to volumes you can't hit.** Forecast at 60M; commit at 30M with overage; let actual usage reveal the real curve.
- **Don't trade IP or roadmap details.** EusoTrip's secret sauce is The Haul + the design DNA + the doctrine — none of that needs to be on this call. The Haul is mentioned by name; the playbook is not.
- **Don't agree to be a HERE reference customer until pricing + partnership is signed.** Reference status is leverage. Hold it.
- **Don't take "we'll get back to you" as a closing.** Make Alexandra commit to a specific next step (intro within 48h, pricing within 5 days). If she dodges, ask "what's a reasonable timeline so I can plan around it?" Anchor a date.

---

## 11 — Mike's two-line cheat sheet (for the moment of the call when you blank)

> "We have what HERE wants — anonymized, consented, professional ground truth at scale through The Haul. We need pricing and a partnership conversation. Who do I talk to?"

That's the call. Everything else is decoration.

---

*Last updated: 2026-04-27. Mirrored to `EUSOTRIP2027GOLD/the_haul/` in both the web platform repo and the iOS repo. Update after the call with the AE name + next-meeting date.*
