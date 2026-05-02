# Uber Freight — Feature Catalog (Public Sources, May 2026)

Reference catalog of publicly documented Uber Freight features for shipper-side and carrier/driver-side use, prepared for parity gap-analysis against EusoTrip. This is a factual extract from Uber Freight's own marketing pages, help center, app store listings, press releases, and trade-press coverage. Anything not documented in public sources is flagged "no public information."

---

# Shipper-side phases

## 1. Tendering & posting (instant rates, contract rates, lane RFP, Power Lane)

- **Instant spot quotes.** Algorithmically generated quote, valid for 15 minutes; "the rate you book is the rate you pay" — no post-book changes to the rate.
- **Quote/compare for FTL and LTL** in the same shipper UI; quotes also returned for dry van, reefer, flatbed, hazmat (LTL).
- **Instant contract rate.** Brokerage can issue an instant contract rate on a new lane for shippers needing committed capacity quickly.
- **Rate lock up to 90 days** — shippers can lock in spot rates for a 90-day window when booking.
- **Lane Explorer.** Forward-looking, ML-based predictive pricing that previews market-based rates for lanes up to 2 weeks in advance and lets shippers build loads that lock in those rates.
- **Uber Freight Exchange (contract / RFP).** Shippers run contract bid events end-to-end: create bid events in minutes, track live bid progress and carrier engagement, centralize all carrier rates in one tool, and download pre-configured routing guides + rates back into their TMS.
- **Mini-bids / mini-RFPs.** Exchange supports mini-bid events on a quarterly or monthly cadence in addition to annual RFPs.
- **Exchange: Spot.** Combined book-it-now pricing + bid-only auctions + automated tendering for spot loads. "Book-it-Now" price can be set by shipper or by Uber Freight's proprietary pricing model.
- **Advanced Scenario Analysis (Exchange).** Side-by-side cost/service/carrier-mix comparisons of multiple bid award strategies before finalizing procurement.
- **Powerloop (Power Lane equivalent).** Drop-and-hook program with Uber Freight–owned trailer pool. Powerloop dedicated tours (launched March 2025) are 2-week minimum commitments; pre-loaded trailers; combines contracted freight, drop-trailer locations, and the broader network into optimized routes. Trailer pool grew 40% YoY in 2024; >10,000 carriers serviced >220,000 loads to date.
- **Dedicated fleets.** Shippers can establish dedicated fleets of any size with carriers committing full-time under long-term contracts; >1,000 dedicated lanes available.

### Notes / limits
- Instant quote validity: 15 minutes.
- Lane Explorer forward window: up to 14 days (some shipper-side sources reference 90-day rate lock at booking time, which is a separate feature).
- Multi-stop FTL hard cap: 10 stops.
- Powerloop dedicated tour minimum commitment: 2 weeks.

---

## 2. Carrier discovery & vetting (network, ratings, scorecards, exclusivity)

- **Network scale.** Documented as 121K+ carriers; 150+ LTL carriers and 95K+ FTL carriers in separate counts.
- **Carrier Performance Program / Scorecard.** Three categories — reliability, tracking, performance — visible to carriers in app and to shippers in TMS. Account status driven by lowest of reliability and tracking scores.
- **Carrier Scorecard metrics.** On-time pickup, on-time delivery, tracking automation %, late cancellations, tender acceptance rate.
- **Top Carrier status.** Tier with payment perks (free 2-day pay) and presumably preferential load surfacing.
- **Booking rules and fraud screening.** Public material says network performance "ensured through carrier scorecards, booking rules, and fraud screenings."
- **Facility Ratings (carrier-side, surfaced to shippers).** 1–5 scale with written reviews; visible to all Uber Freight users; shippers see facility-level driver feedback (top driver pain point: wait time, then staff interaction).
- **Insurance Verification.** Vetting includes contract execution, validation that all carrier units are covered, workers' comp / occupational hazard verification, and a SAFER Web safety review.
- **Annual Carrier Awards.** Quantitative-metric–based recognition program (most recent: 2025 Carrier Award winners).
- **Exclusivity / dedicated capacity.** "Committed capacity" feature lets carriers lock in loads across 1,000+ dedicated lanes up to 3 months in advance.

### Notes / limits
- No public documentation of a "carrier exclusivity flag" enforced at the load level beyond dedicated/Powerloop tours.
- No public documentation of a public shipper-facing safety-tier (e.g., gold/silver/bronze) beyond Top Carrier status.

---

## 3. Booking confirmation (auto-tender, fallback)

- **Automated tendering** via Exchange: Spot — proprietary algorithms and scalable workflows handle tender automation.
- **First Tender Acceptance (FTA)** documented as a focus KPI; Uber Freight states a target of 100% tender acceptance regardless of market conditions.
- **Carrier Bidding API (3PL loads).** Carriers can submit/manage bids, receive instant counter-offers, accept, and have load details flow into their TMS without leaving it.
- **Conditional Bidding.** Carriers may submit bids for alternative pickup dates on eligible auctions; if accepted, shipper tenders at the carrier's rate and pickup time.
- **Rate confirmation issuance.** RateCon emailed to carrier primary contact + dispatcher/driver who booked the load shortly after the booking action.

### Notes / limits
- No public document explicitly lays out a "waterfall fallback" sequence for declined tenders. Tender acceptance is referred to in aggregate as an FTA KPI.

---

## 4. Tracking visibility (geofence-based status, ETA, exception flags)

- **Control Tower** — module within the Uber Freight TMS; 24/7, 360-degree shipment visibility; consolidates data, tools, protocols.
- **Real-time location on map.** Shipments visualized on a map; filterable by mode; "zero in on shipments needing attention."
- **Cross-mode visibility.** Truck, rail, ocean, and air shipments in a single view.
- **Ocean visibility.** 99% ocean shipment coverage via 40+ data sources; updates as frequently as every 15 minutes.
- **Predictive ETA.** Driven by real-time inputs + historical performance; service-risk predictions feed exception management.
- **Exception management.** Automated routing and service-risk predictions; "fast and easy access to relevant, accurate, actionable shipment exceptions."
- **Tracking sources.** Uber Freight app, web portal, ELD integration (Motive, Samsara, Transflo/Geotab), carrier EDI, and 3rd-party aggregators (project44, MacroPoint).
- **LTL tracking.** Status-update flow specific to LTL via the same TMS; carrier-EDI fed.

### Notes / limits
- No explicit public mention of "geofence" terminology as a shipper-configurable feature; geofencing is implicit in arrival/departure detection from app + ELD signal sources.
- Ocean tracking refresh cadence: ~15 min.
- Tracking automation requirement (carrier side, surfaces to shipper): 85%+ automated for Top Carrier; <50% automated puts the carrier at risk of suspension.

---

## 5. POD / proof-of-delivery (digital BOL, photo capture, dispute window)

- **In-app POD upload** by carrier; submission triggers shipper invoice processing.
- **BOL download** from the load page in shipper dashboard once a driver is assigned.
- **POD availability to shipper.** Located under Documents on the shipment dashboard, typically 5–7 business days post-delivery.
- **Photo POD + signed BOL** are both accepted; signed BOL with documented in/out times is required for accessorial validation.

### Notes / limits
- Public docs describe shipper POD turnaround as 5–7 business days — that's slower than the carrier's 2-day or same-day pay milestones, suggesting downstream review/validation steps.
- No public documentation of a formal shipper-side POD dispute workflow with a stated dispute-window SLA (claims docs are oriented to carrier accessorial disputes — see phase 8 carrier-side).

---

## 6. Settlement / invoicing (NET terms, EDI 210)

- **Standard shipper invoicing terms.** NET 30 via ACH bank wire transfer.
- **Invoice arrival.** 1–2 weeks after shipment delivery; payment terms start at receipt of invoice.
- **Credit card billing.** Charged at carrier pickup; accessorials charged at invoicing.
- **Late fees.** $10/invoice flat plus 1.5%/month interest if not paid within 15 days of invoice due date.
- **EDI 210 (Motor Carrier Freight Details and Invoice).** Documented as a Transplace/Uber Freight transaction set on Orderful's network — Uber Freight uses EDI 210 to send freight invoices to shippers; ITD segment carries payment terms.
- **TMS Financials (launched 2025).** Single view of AR + AP for procurement teams; bulk dispute tools cut dispute resolution times by up to 20%.

### Notes / limits
- No public document explicitly published NET 60 / NET 90 enterprise contract terms; standard is NET 30.

---

## 7. Analytics (spend, on-time %, lane benchmarks)

- **Freight Insights dashboard** (free, included with shipper platform). Real-time per-load + long-term aggregate; customizable.
- **Load metrics.** Tender acceptance rate, average lead time.
- **Facility metrics.** Load volume by facility, average time spent per facility (dwell), driver wait time.
- **Lane Explorer.** Real-time market rate baseline per lane (also analytics input).
- **Insights AI (generative).** Natural-language queries against shipper data; auto-generated KPI dashboards; ranks insights by ROI; correlation/regression and SQL synthesis behind the scenes; documented 98% accuracy.
- **Proactive Recommendations.** Auto-surfaces optimization opportunities (lane underperformance, mini-bid candidates, carrier-selection moves) without prompting.
- **Industry benchmarks.** Insights AI compares shipper variables against industry baselines.

### Notes / limits
- No public document of a formal "spend cube" by commodity/region beyond what Insights AI exposes in NL queries.
- No published list of out-of-the-box KPI report templates.

---

## 8. Multi-stop & complex loads (drop-trail, reload, intermodal)

- **Multi-stop FTL.** Up to 10 stops per shipment; flat rate; real-time visibility; 24/7 support.
- **Drop and hook.** Reduces live load/unload dwell.
- **Powerloop drop-trailer pool.** Pre-loaded trailers, drop-trailer locations stitched into route plans.
- **Powerloop trailer telematics.** GPS, cargo sensors, door sensors, on-trailer cameras (24/7 location + capacity monitoring).
- **Intermodal.** Available via dedicated account support — quotes for intermodal, international, hazmat, multi-stop, expedited.
- **LTL.** FTL + LTL quotes side-by-side in the shipper platform; LTL supports hazmat (requires emergency contact, UN#, proper shipping name, hazard class, packing group at load build).
- **Reloads/backhauls.** Auto-suggested at booking time on the carrier side (improves complex-load reuse for shippers' lanes).
- **Final mile.** Expanded final-mile offerings announced in 2024 platform update.

### Notes / limits
- Intermodal and international are documented as account-managed (broker-assisted) rather than fully self-serve.

---

## 9. Compliance (insurance verification, FMCSA tier)

- **Carrier authority requirement.** Active DOT number with interstate authority + valid MC; active Common or Contract Authority.
- **Safety Rating requirement.** Satisfactory or None.
- **Auto liability minimum.** ≥$1,000,000 per occurrence.
- **Cargo insurance minimum.** ≥$100,000 (US); ≥$150,000 (Canada).
- **Vetting steps.** Contract execution, unit-level coverage validation, workers' comp / occupational hazard, SAFER Web safety review.
- **Compliance monitoring.** General audit cadence is implied; not explicitly documented as a continuous-monitoring feed in public material.
- **Hazmat compliance support.** Required hazmat fields enforced at load build (UN#, hazard class, packing group, emergency contact).

### Notes / limits
- No public FMCSA-tier badge surfaced to shippers in the platform UI (e.g., "Tier A/B/C carrier").
- No documented C-TPAT / FAST / SmartWay certification surfacing.

---

## 10. API / TMS integration

- **Direct TMS integrations.** BluJay, Oracle, SAP — instant pricing + capacity into shipper's existing TMS.
- **Pricing API.** New-lane load requests can hit instant pricing API and be tendered automatically.
- **Scheduling API (SSC standard).** First production implementation of Scheduling Standards Consortium technical standard; pilot rolled GA in H2 2024. Live across 1,500 facilities for 10 Fortune 500 CPG shippers; loads cleared for coverage up to 75% faster vs. manual scheduling.
- **NetSuite integration.** Uber Freight TMS for NetSuite (SuiteApp).
- **Sign-up.** Public SSC/scheduling API request flow at uberfreight.com/ssc-api-signup.
- **Carrier Bidding API.** TMS-to-Exchange path so carriers bid without leaving their TMS.
- **EDI.** EDI 210 (carrier-to-shipper invoice) confirmed via Orderful. EDI 997 functional acks per spec.

### Notes / limits
- Detailed REST/GraphQL public docs are not openly published; access requires direct outreach.
- Public docs do not list every EDI transaction set supported beyond 210/997 references.

---

# Driver / carrier-side phases

## 1. Load discovery & search (price, lane, equipment filters)

- **Load board** — 24/7 access in app and web portal.
- **Map view.** Loads near current location; pickup-area drag/expand; type-in pickup search.
- **Sort options.** Weight, deadhead, rate per mile, price.
- **Smart load recommendations** + personalized recommendations.
- **Upfront facility details.** Ratings, reviews, amenities exposed before booking.
- **Dedicated lanes** discoverable in the app.
- **Reloads / backhauls.** Auto-previewed at the bottom of each load detail screen.
- **Equipment scope.** Dry van, reefer, flatbed (FTL), hazmat (LTL).

### Notes / limits
- No public mention of length-of-haul, hazmat-only, or team-required filters as first-class facets (recommendation engine handles match implicitly).

---

## 2. Booking (instant book, bid, hold)

- **Instant book.** "Tap a button" no-negotiation booking; upfront price.
- **Bidding.** In-app bidding for shipper auctions (Exchange: Spot path).
- **Conditional Bidding.** Submit bids tied to alternative pickup dates on eligible auctions.
- **Carrier Bidding API** (TMS-side bidding).
- **Reload preview at book time** — backhaul recommendation shown before commitment.

### Notes / limits
- No public documentation of a formal "hold" / "save for later" status; flow is bid → counter → accept, or instant book.

---

## 3. Pre-trip docs (rate confirmation, BOL, contracted carrier addendum)

- **Instant RateCon.** Issued in-app and emailed to primary contact + dispatcher/driver post-booking.
- **BOL.** Downloadable from the load detail page once driver is assigned.
- **Fleet mode dispatcher RateCon.** Both dispatcher and assigned driver receive the rate confirmation in fleet mode bookings.

### Notes / limits
- No public document of a self-serve "contracted carrier addendum" download path beyond the broker–carrier master agreement signed at onboarding.

---

## 4. Dispatch & assignment (broker contact, dispatcher tools)

- **Fleet Mode.** Dispatcher books and assigns to a driver from a fleet roster.
- **Driver acceptance window.** Drivers have 30 minutes to reject the dispatch.
- **Self-dispatch.** Driver can dispatch themselves in-app via the "Heading to Pickup" notification (appears 3 hours before scheduled pickup) or via in-app support.
- **Dispatcher tools.** Dispatchers manage drivers within the fleet, see dispatch state across the fleet, and book on driver's behalf.
- **24/7 customer support.** Live broker contact via the app's headset icon.

### Notes / limits
- No public documentation of a real-time chat thread per load between broker and driver; support is documented as headset/phone-driven plus push notifications.

---

## 5. En-route navigation (in-app turn-by-turn? truck routing? fuel stops?)

- **No native in-app turn-by-turn navigation** documented in public Uber Freight materials.
- **Fuel finder.** Map-based tool inside the carrier app with real-time pricing + participating discounted truck stops.
- **Automatic location updates.** Keep the app open and the driver gets continuous tracking data feeds.
- **ELD-derived location.** If Motive/Samsara/Transflo/Geotab integrated, ELD provides location through the trip without app foregrounding.

### Notes / limits
- Truck-specific routing (height/weight/HAZMAT-restricted) is **not** documented as an in-app Uber Freight feature; carriers reportedly use third-party truck GPS apps.

---

## 6. Pickup operations (check-in, dock door, weight ticket)

- **Pickup verification methods (Uber Deliveries API context — proof of pickup):** Barcode, Photo, Signature.
- **Status-update prompts.** Driver confirms in-app at each stage (heading to pickup, at pickup, in transit, at delivery).
- **Detention timer activation.** Driver should keep app running within 5 miles of approach/depart so accessorial validation has GPS context.
- **Scheduling API integration.** For shippers on SSC API, dock appointments flow back to the carrier with less manual back-and-forth.

### Notes / limits
- No public documentation of an explicit "dock door assignment" UI inside the carrier app.
- No public documentation of in-app weight ticket capture (separate from BOL/POD photo upload).

---

## 7. POD capture (photo, signature, scan)

- **In-app POD submission.** Photo upload of signed BOL via the carrier app.
- **Signature capture (Uber Deliveries platform).** Timestamped, GPS-tied signature; legally treated as equivalent to wet ink.
- **Pincode / ID Check / Barcode.** Surfaced as dropoff verification options in Uber's broader Deliveries API; Uber Freight POD flow is documented as photo + signature (Pincode/ID Check are not specifically listed for freight loads in public Uber Freight docs).

### Notes / limits
- No public documentation of OCR-based BOL parsing in the carrier-facing POD flow (OCR-style features sit on the shipper side via Insights AI's email/data correction agents).

---

## 8. Detention / accessorial claims (in-app billing)

- **In-app accessorial request.** Headset icon → submit claim against the load.
- **Detention coverage window.** Hours starting 2 hours after scheduled appointment, ending 7 hours after — capped at 5 hours of paid detention.
- **On-time eligibility.** Carrier must arrive on time to scheduled appointment to qualify.
- **Submission deadline.** Within 24 hours of delivery; late submissions are not honored.
- **Required documentation.** Signed BOL with documented in/out times for all completed stops.
- **Pre-detention notice.** Carrier must share location data or notify Uber Freight 30 minutes prior to entering detention.
- **Validation sources.** App location + ELD + 3rd-party aggregator data used to validate.

### Notes / limits
- Hard 24-hour submission window.
- Capped at 5 hours paid detention regardless of actual dwell.

---

## 9. Settlement / payment speed (QuickPay tiers, factoring, ACH timing)

- **Standard payment.** 7 days post-acceptable POD via ACH.
- **2-Day Pay.** 2 business days post valid POD; 2.5% fee; requires ACH direct deposit (factoring companies excluded).
- **Free 2-Day Pay.** Top Carriers get 2-day pay with no fee.
- **Same-Day Pay.** Available via the Uber Freight Carrier Card for carriers meeting spend threshold ($3,500/month per truck).
- **Factoring.** Uber Freight pays the carrier's contracted factoring company via ACH. Factoring carriers ineligible for the 2.5% 2-day option.
- **EDI 210 outbound** to shippers triggers AR-side flow.

### Notes / limits
- No 1-day non-card option below the 2-day tier outside the Carrier Card.
- Carriers on factoring lose access to the discounted 2-day pay tier.

---

## 10. Fuel card / fuel program (Discount network)

- **Uber Freight Carrier Card** (powered by AtoB).
- **Fuel discounts.** Up to 84¢/gallon at partner stations (TA, Petro highlighted).
- **Coverage scope.** Fuel, tires, tolls, roadside assistance — no fees, no minimums per published material.
- **Fuel finder.** Map-based; real-time pricing; flags participating discount truck stops.
- **Card economics.** No setup, card, software, annual, or maintenance fees.
- **Acceptance.** Any US truck stop that accepts Visa.
- **Same-day pay** triggered when monthly spend threshold is met ($3,500/month per truck).
- **Tire discounts.** Bundled with the rewards program.
- **Eligibility.** Must book ≥1 load per month to keep fuel/tire discount privileges active.

### Notes / limits
- Suspension trigger: <1 booked load/month → discount privileges suspended.

---

## 11. Insurance & compliance (yard ops)

- **Authority.** Active DOT (interstate) + valid MC; active Common or Contract Authority.
- **Safety rating.** Satisfactory or None.
- **Auto liability.** ≥$1M per occurrence.
- **Cargo.** ≥$100K (US) / ≥$150K (Canada).
- **Workers' comp / occupational hazard.** Verified.
- **Onboarding.** Carrier signs contract for carriage; insurance certificates validated; SAFER Web safety review.
- **Continuous compliance.** Uber Freight references "fraud screening" and ongoing scorecard monitoring; specific re-verification cadence is not publicly documented.
- **Tracking compliance threshold.** ≥85% automated tracking for Top Carrier; <50% triggers suspension/deactivation risk.
- **Hazmat.** Carriers handling LTL hazmat must support shipper-supplied UN#, hazard class, packing group at load build.

### Notes / limits
- No public documentation of yard-ops-specific compliance tooling (yard check-in, gate pass) inside the carrier app.
- No public mention of CDL / medical card storage or expiration tracking inside the Uber Freight app.

---

# Sources

- [Deliver 2025: Unveiling new platform features — Uber Freight](https://www.uberfreight.com/blog/deliver-2025-unveiling-new-platform-features/)
- [Powering carrier success: New tools and enhancements from Uber Freight in 2025 — Uber Freight](https://www.uberfreight.com/en-US/blog/powering-carrier-success-new-tools-and-enhancements-from-uber-freight-in-2025)
- [Uber Freight Exchange — Uber Freight](https://www.uberfreight.com/en-US/tech/exchange)
- [Uber Freight Exchange: Envisioning a freight marketplace for all](https://www.uberfreight.com/en-US/blog/uber-freight-exchange-a-freight-marketplace-for-all)
- [Uber Freight Exchange for carriers](https://www.uberfreight.com/en-US/carrier-services/freight-bidding-exchange)
- [Introducing Uber Freight Exchange: a reimagined procurement solution](https://www.uberfreight.com/en-US/blog/introducing-uber-freight-exchange)
- [Uber Freight Advances Vision for Industry-Wide Procurement Platform with Uber Freight Exchange: Spot — GlobeNewswire (2024)](https://www.globenewswire.com/news-release/2024/05/16/2883256/0/en/Uber-Freight-Advances-Vision-for-Industry-Wide-Procurement-Platform-with-Uber-Freight-Exchange-Spot.html)
- [Reliable freight shipping solutions — Uber Freight](https://www.uberfreight.com/en-US/technology/freight-shipping)
- [Transportation management system — Uber Freight](https://www.uberfreight.com/en-US/technology/tms)
- [Uber Freight TMS: next generation visibility, foresight, and control](https://www.uberfreight.com/blog/introducing-the-upgraded-uber-freight-tms/)
- [Delivering real-time visibility for ocean transportation on Uber Freight TMS](https://www.uberfreight.com/en-US/blog/delivering-real-time-ocean-visibility-on-uber-freight-tms)
- [Uber Freight Insights AI — Uber Freight](https://www.uberfreight.com/blog/uber-freight-insights-ai/)
- [Enter the era of logistics AI with Uber Freight](https://www.uberfreight.com/en-US/blog/the-era-of-logistics-ai-with-uber-freight)
- [Uber Freight Launches Industry-First AI Logistics Network at Scale](https://www.uberfreight.com/en-US/newsroom/uber-freight-launches-industry-first-ai-logistics-network-at-scale-ushering)
- [The new era of intelligent supply chains is here and Uber Freight is leading the way](https://www.uberfreight.com/en-US/blog/new-era)
- [Uber Freight rolls out integrated AI to simplify shipper operations — Digital Commerce 360](https://www.digitalcommerce360.com/2025/09/16/uber-freight-agentic-ai/)
- [Uber Freight bets big on AI tools to grow its business — TechCrunch](https://techcrunch.com/2025/05/21/uber-freight-bets-big-on-ai-tools-to-grow-its-business/)
- [Uber Freight releases pilot for scheduling API, a first under new industry standards](https://www.uberfreight.com/en-US/blog/uber-freight-releases-pilot-for-scheduling-api)
- [Uber Freight pilots scheduling API — IoT M2M Council](https://www.iotm2mcouncil.org/iot-library/news/smart-logistics-news/uber-freight-pilots-scheduling-api/)
- [Uber Freight Launches Scheduling API with Pilot Program — Heavy Duty Trucking](https://www.truckinginfo.com/news/uber-freight-launches-scheduling-api-with-pilot-program)
- [API benefits for Uber Freight shippers](https://www.uberfreight.com/en-US/blog/uber-freight-api-benefits)
- [Uber Freight TMS for NetSuite — SuiteApp](https://www.suiteapp.com/suiteappcom/docs/Uber-Freight-TMS-for-NetSuite/NetSuite%20API%20Two-Pager_%20Uber%20Freight.pdf)
- [Uber Freight Shipping FAQ — Uber Help (Shipper)](https://help.uber.com/en/freight/shipper/article/shipper-platform-faq?nodeId=96a90c95-32ad-40f5-8953-164c818a2dde)
- [Uber Freight Shipping Invoice and Payment Information — Uber Help (Shipper)](https://help.uber.com/freight/shipper/article/uber-freight-shipping-invoice-and-payment-information?nodeId=01f20258-542e-4e23-b6c4-f6d69604c84f)
- [x12 210 — Motor Carrier Freight Details and Invoice for Transplace (an Uber Freight company) — Orderful](https://www.orderful.com/network/transplace-an-uber-freight-company/192/x12-210-motor-carrier-freight-details-and-invoice)
- [TMS Terms of Use — Uber Freight](https://www.uberfreight.com/en-US/legal/tms-terms-of-use)
- [How freight insights gives shippers a data edge](https://www.uberfreight.com/en-US/blog/shipper-insights-dashboard-uber-freight)
- [How lane explorer lets shippers lock in rates up to 14 days in advance — Uber Freight](https://www.uberfreight.com/blog/how-to-use-uber-freight-lane-explorer/)
- [Lane Explorer Sets a New Standard For Price Transparency — Uber Freight](https://www.uberfreight.com/blog/lane-explorer-sets-a-new-standard-for-price-transparency/)
- [Uber Freight's facility ratings will drive industry-wide collaboration](https://www.uberfreight.com/en-US/blog/facility-ratings)
- [Facility ratings reveal new data to inform shippers](https://www.uberfreight.com/en-US/blog/lessons-learned-from-facility-ratings)
- [How LTL freight tracking works and how Uber Freight does it better](https://www.uberfreight.com/en-US/blog/ltl-tracking)
- [What is Less Than Truckload (LTL) Freight — Uber Freight](https://www.uberfreight.com/en-US/what-is-less-than-truckload-freight)
- [What is Dedicated Freight — Uber Freight](https://www.uberfreight.com/en-US/what-is-dedicated-freight)
- [Dedicated fleets — capacity and value — Uber Freight](https://www.uberfreight.com/en-US/blog/dedicated-fleets-capacity-and-value)
- [Power up with Drop and Hook Loads with Powerloop](https://www.uberfreight.com/drop-and-hook-loads)
- [Power only and dedicated fleet — Uber Freight](https://www.uberfreight.com/en-US/carriers/carrier-programs/dedicated-fleet)
- [Uber Freight rolls out tech upgrades in Powerloop trailer pool — DC Velocity](https://www.dcvelocity.com/articles/60293-uber-freight-rolls-out-tech-upgrades-in-powerloop-trailer-pool)
- [Uber Freight's Powerloop begins offering dedicated tours to carriers — FreightWaves](https://www.freightwaves.com/news/uber-freights-powerloop-begins-offering-dedicated-tours-to-carriers)
- [Uber Freight's Powerloop dedicated tours unlock more growth for carriers](https://www.uberfreight.com/en-US/blog/powerloop-dedicated-tours-unlock-more-growth-for-carriers)
- [Using Powerloop — Uber Help (Carrier)](https://help.uber.com/freight/carrier/article/using-powerloop?nodeId=28edc291-d1ac-4a9f-a1bc-7b50b0591801)
- [Carrier Marketplace — Uber Freight](https://www.uberfreight.com/en-US/carriers)
- [Become a carrier — Uber Freight](https://www.uberfreight.com/en-US/carriers/app)
- [Uber Freight — App Store (iOS)](https://apps.apple.com/us/app/uber-freight/id1183931851)
- [Uber Freight — Google Play](https://play.google.com/store/apps/details?id=com.ubercab.freight&hl=en_US)
- [Using the Uber Freight App to Search and Book Loads — Uber Help](https://help.uber.com/en/freight/carrier/article/using-the-uber-freight-app-to-search-and-book-loads?nodeId=dfe69814-ea0d-43e8-ad16-f77621cd2e0c)
- [Using the Uber Freight App During and After Delivery — Uber Help](https://help.uber.com/en/freight/carrier/article/using-the-uber-freight-app-during-and-after-delivery?nodeId=37bbed18-dd0a-47aa-86eb-15b5f73bd0b8)
- [Using Uber Freight for Dispatchers — Uber Help](https://help.uber.com/freight/carrier/article/using-uber-freight-for-dispatchers?nodeId=17fa1fd2-6765-4f74-b03e-a1aa9c7eee95)
- [Using Fleet Mode — Uber Help](https://help.uber.com/freight/carrier/article/using-fleet-mode?nodeId=0bcbf15c-b4ff-4c9b-8d29-d2c9514de3bb)
- [How to Access the Uber Freight App — Uber Help](https://help.uber.com/freight/carrier/article/how-to-access-the-uber-freight-app?nodeId=4e902db4-efa0-4899-9613-bff3b04926c8)
- [Carrier Performance Program — Uber Help](https://help.uber.com/en/freight/carrier/article/carrier-performance-program?nodeId=609e5cff-5b9b-455a-8050-1caed66c16b7)
- [Carrier Performance — Tracking — Uber Help](https://help.uber.com/freight/carrier/article/carrier-performance---tracking?nodeId=4505018e-3f84-4b62-9ebb-6d8541daefa7)
- [What Automated Tracking Sources Does Uber Freight Use? — Uber Help](https://help.uber.com/freight/carrier/article/what-automated-tracking-sources-does-uber-freight-use?nodeId=f7bdeccb-83d1-422c-88cf-12daa7d3c3eb)
- [How Does Automated Tracking Impact My Tracking Automation Score? — Uber Help](https://help.uber.com/en/freight/carrier/article/how-does-automated-tracking-impact-my-tracking-automation-score?nodeId=6da1335f-ddfe-405f-81a6-adcd9cfddfe8)
- [What is Uber Freight's Tracking Policy? — Uber Help](https://help.uber.com/freight/carrier/article/what-is-uber-freight%E2%80%99s-tracking-policy?nodeId=9e4ef3c8-bc34-4f2e-9a01-8c0989281c80)
- [Tracking and Location Data-Sharing — Uber Freight Support](https://uberfreight.zendesk.com/hc/en-us/articles/360048580214-Tracking-and-Location-Data-Sharing)
- [Carrier Insurance Requirements — Uber Help](https://help.uber.com/freight/carrier/article/carrier-insurance-requirements?nodeId=a45379b0-cb0a-4802-89be-11771be0cc95)
- [Are Carriers Required to Have Cargo Liability Insurance? — Uber Help (Shipper)](https://help.uber.com/en/freight/shipper/article/are-carriers-required-to-have-cargo-liability-insurance?nodeId=74e7b294-282c-446c-8eb7-0d375a05d81e)
- [Thank you for your interest in becoming an approved carrier — Uber Freight RMIS](https://uberfreightcarriers.rmissecure.com/_s/reg/GeneralRequirementsV2.aspx)
- [Uber Freight Equipment Requirements — Uber Help](https://help.uber.com/en/freight/carrier/article/uber-freight-equipment-requirements?nodeId=309bae3d-2969-480f-b7be-38eeb1b6b2f1)
- [How Do Uber Freight Payments Work? — Uber Help](https://help.uber.com/freight/carrier/article/how-do-uber-freight-payments-work?nodeId=b671ed28-ba0a-4794-a424-8b4b99ae00d7)
- [Carrier Payment and Accessorials Guide — Uber Freight Support](https://uberfreight.zendesk.com/hc/en-us/articles/360042493834-Carrier-Payment-and-Accessorials-Guide)
- [Uber Freight Quick Pay Terms and Conditions (PDF)](https://www.uberfreight.com/wp-content/uploads/2023/10/Uber_Freight-Quick_Pay_Agreement.pdf)
- [Uber Freight Quick Pay Terms and Conditions — Uber Legal](https://www.uber.com/legal/te/document/?name=uber-freight-quick-pay-terms-and-conditions&country=united-states&lang=en)
- [Uber Freight enhances fuel savings with new carrier card](https://www.uberfreight.com/blog/uber-freight-enhances-fuel-savings-with-new-carrier-card/)
- [Uber Freight card](https://www.uberfreight.com/carrier/carrier-card)
- [Uber Freight, AtoB partnership launches fuel card — FreightWaves](https://www.freightwaves.com/news/uber-freight-atob-partnership-launches-fuel-card)
- [Uber Freight Launches New Carrier Fuel Card — Transport Topics](https://www.ttnews.com/articles/uber-freight-fuel-card)
- [Uber Freight Fuel Card Review: Features, Pros & Cons — Expert Market](https://www.expertmarket.com/fleet-cards/uber-freight-fuel-card-review)
- [How Uber Freight helps carriers fuel success on and off the road](https://www.uberfreight.com/blog/how-uber-freight-helps-carriers/)
- [What is Uber Freight's Accessorial Policy for Carriers? — Uber Help](https://help.uber.com/freight/carrier/article/what-is-uber-freight%E2%80%99s-accessorial-policy-for-carriers?nodeId=993f6166-3606-40af-bdbd-ab27905c0567)
- [What is Uber Freight's Accessorial Policy for Shippers? — Uber Help](https://help.uber.com/freight/shipper/article/what-is-uber-freight%E2%80%99s-accessorial-policy?nodeId=87452ee8-b391-417f-ae21-2585595475fc)
- [Requesting detention has never been easier: a how-to guide — Uber Freight](https://www.uberfreight.com/blog/how-to-request-detention-on-uber-freight/)
- [Payment and accessorials FAQ — Uber Freight Support](https://uberfreight.zendesk.com/hc/en-us/articles/360042493834-Payment-and-accessorials-FAQ)
- [Building a Better App Experience For Carriers — Uber Freight](https://www.uberfreight.com/blog/building-a-better-app-experience-for-carriers/)
- [Introducing an improved web portal for carriers and dispatchers — Uber Freight](https://www.uberfreight.com/blog/how-to-use-the-uber-freight-web-portal/)
- [Find your perfect load in less time with Uber Freight](https://www.uber.com/gb/en/blog/find-your-perfect-load-in-less-time-with-uber-freight/)
- [Why "backhaul" rates are a thing of the past — Uber Freight](https://www.uberfreight.com/en-US/blog/uber-freight-transparent-rates)
- [Uber Freight announces in-app bidding for carriers](https://www.uberfreight.com/blog/does-uber-freight-allow-bidding/)
- [Uber Freight Adds Spot Loads to Exchange Platform — Heavy Duty Trucking](https://www.truckinginfo.com/news/uber-freight-adds-spot-loads-to-exchange-platform)
- [Uber Freight honors 2025 Carrier Award winners](https://www.uberfreight.com/en-US/blog/uber-freight-honors-2025-carrier-award-winners)
- [Latest Uber Freight launch combines marketplace and managed services networks — FreightWaves](https://www.freightwaves.com/news/latest-uber-freight-launch-combines-marketplace-and-managed-services-networks)
- [Proof of Delivery — Uber Developer (Deliveries)](https://developer.uber.com/docs/deliveries/guides/proof-of-delivery)
- [New Feature: Upload proof of delivery documents on Uber Freight app](https://www.uberfreight.com/en-US/blog/new-feature-upload-proof-of-delivery-documents-on-uber-freight-app)
- [Uber Freight Advances End-to-End Logistics with Platform Enhancements, Generative AI-Powered Tech and Expanded Final Mile Offerings (2024) — GlobeNewswire](https://www.globenewswire.com/news-release/2024/09/10/2943797/0/en/Uber-Freight-Advances-End-to-End-Logistics-with-Platform-Enhancements-Generative-AI-Powered-Tech-and-Expanded-Final-Mile-Offerings.html)
- [Q1 2026 freight market update: What shippers should be watching](https://www.uberfreight.com/en-US/blog/freight-market-update)
- [Ask the experts: 2026 Predictions and priorities for supply chain professionals](https://www.uberfreight.com/en-US/blog/2026-predictions-priorities)
- [How Does Uber Freight Work: Complete 2026 Guide — ParcelPath](https://parcelpath.com/how-does-uber-freight-work/)
- [Uber Freight 2026 Pricing, Features, Reviews & Alternatives — GetApp](https://www.getapp.com/operations-management-software/a/uber-freight/)
- [Uber Freight Reviews, Ratings & Features 2026 — Gartner Peer Insights](https://www.gartner.com/reviews/market/third-party-logistics/vendor/uber-freight)
- [Uber Freight Load Board Review 2025 — OI Engine](https://oiengine.com/uber-freight-load-board-review/)
