# CloudTrucks Feature Catalog

Reference catalog of CloudTrucks' publicly documented product surface, captured for parity / gap analysis against EusoTrip's shipper↔driver interaction surface.

CloudTrucks targets owner-operators and small fleets. Its product taxonomy in 2026 centers on three programs (Virtual Carrier, Flex, Road to Independence), one freight marketplace (Exchange), and a fintech stack (CT Cash, CT Credit, CT Fuel). There is no shipper-facing posting / TMS surface comparable to EusoTrip's shipper persona — shipper-side coverage is thin and brokerage-mediated.

Compiled from public sources only (cloudtrucks.com, FreightWaves, BusinessWire, Help Center / Zendesk, App Store, Google Play, G2). Last updated 2026-05.

---

## 1. Load Discovery / Matching

- **300k+ loads aggregated in-app** — sourced from broker load boards plus exclusive shipper contracts; new loads added daily from "thousands of sources."
- **Multi-broker integrations** — JBHunt, Uber Freight, Coyote, Convoy, Loadsmart, DAT, and "many others" surfaced through a single in-app feed when running under CloudTrucks authority (Virtual Carrier).
- **123Loadboard partnership** — embedded marketplace lets members search, bid, book inside CloudTrucks; carries through 123Loadboard's rates, mileage, routing, credit ratings.
- **CT Exchange** — proprietary brokered loads from the acquired Shipwell brokerage division (acquired Feb 2024). Direct-from-shipper contract freight + dedicated lanes available to Virtual Carrier customers.
- **Schedule Optimizer (Dispatch Assistant)** — combs 1,000+ loads in ~3 minutes; takes inputs (current location, target end-of-week location, max deadhead, preferences) and returns a revenue-maximizing chained schedule.
- **ML-driven recommendations** — system learns from past behavior to suggest loads matching driver preferences.
- **CT Rate Estimate** — fair-rate estimate displayed inline before booking.
- **Mileage-based revenue guarantees (CT Exchange)** — e.g., $4,500/wk for drivers averaging 2,000 loaded miles ($2.25/mi) over 2-week window; $3,250/wk for 1,500-mile averages ($2.16/mi).

### Notes / limits
- Optimizer maximizes revenue without weighting deadhead/mileage cost — documented limitation, future-roadmap item per CloudTrucks blog.
- Direct-shipper feed only flows to Virtual Carrier (lease-on) drivers; Flex (own-authority) drivers see broker-board content.
- Some app-store reviews flag "loads sourced from other apps" with broker-side confusion around the carrier MC# at booking — surface is curated but not always primary.

---

## 2. Driver App Surface — Book, Dispatch, Navigate, Doc Capture

- **Search & book** — load search, recommendations, one-tap book without phoning a broker.
- **Dispatch Assistant** — pre-plans high-earning route chains.
- **POD capture** — driver uploads signed Bill of Lading photo in-app; verification typically within 12 hours.
- **Fuel receipt capture** — uploaded fuel receipts auto-feed IFTA filing pipeline.
- **Expense + revenue tracking** — job payments, pending invoices, fuel costs, business expenses unified.
- **Insurance handled in-app** — for Virtual Carrier drivers, auto liability/cargo runs through the platform; deductions visible.
- **24/7 support** — in-app + phone support marketed as "world-class."
- **Card management** — virtual CT Cash card sits in Apple Wallet; physical card disable + virtual fallback if lost.
- **Available on iOS + Android** — App Store id 1523676447, Play Store `com.cloudtrucks.cloudtrucksapp.production`. Google Play rating 4.6 (~200 reviews).

### Notes / limits
- **No documented turn-by-turn truck-routed navigation built in.** App handles booking + comms but does not appear in lists of truck-GPS apps; drivers presumably use Google Maps / Trucker Path / Hammer alongside it.
- **No documented in-app messaging thread with shippers** — communication is mediated through brokers / dispatch.
- Deductions tier system was reworked recently (per app-store update notes): tiers now calculated monthly with lowered max deduction rates.

---

## 3. Pricing & Rates Intelligence

- **Business Intelligence Dashboard** — revenue per week, dollars per mile, expense breakdown, goal-setting for revenue growth.
- **CT Cash Card expense ingestion** — categorized purchases roll into the BI dashboard.
- **CT Rate Estimate** — pre-book fair-rate display inline with each load.
- **Revenue guarantees in CT Exchange** — published $/mi floors for participating Virtual Carrier drivers.
- **Tech stack signals** — public profiles cite Looker + Google AI in their analytics layer.

### Notes / limits
- **No public "CT One" product** — that name does not appear in any indexed CloudTrucks property as of May 2026.
- **No publicly documented lane-level rate-per-mile heatmap or forward-curve pricing intelligence** for end-users — BI surface focuses on personal P&L, not market lane analytics.
- Profit-projection tooling is implicit (BI + Optimizer + Rate Estimate), not a packaged forward simulator.

---

## 4. Banking / Payments — CT Cash

- **CT Cash card** — Visa-branded debit/cash card co-developed with Visa; usable anywhere Visa is accepted (fuel, food, lodging, anything).
- **Instant pay on POD** — funds released within ~2 hours of POD verification; advertised as "free quick pay on all loads" for Virtual Carrier.
- **Cash advance** — on-the-job advances at 1.5% per payment fee (vs. 3–5% typical factoring).
- **Virtual card** — provisioned to Apple Wallet; survives physical-card disable.
- **Free ACH out** — funds transferable from CT Cash to any external bank account at no cost.
- **Pickup Pay** — in-app request flow for advances at pickup (Help Center documents this).
- **Real-time eligibility checks** for advances; funding in minutes.
- **30-day exit clause** documented for the program.

### Notes / limits
- **No interest-bearing savings account / yield product** documented — CT Cash is a spending account, not a treasury product.
- CT Cash factoring (for non-Virtual-Carrier authority holders) was discontinued as a standalone in 2024 — CloudTrucks exited the factoring business to focus on Virtual Carrier + Flex. CT Cash remains for Virtual Carrier customers only.
- 1.5% advance fee applies per payment, not flat-rate monthly.

---

## 5. Factoring & Invoicing — CT Suite

- **Historical CT Cash non-recourse factoring** — was offered for own-authority carriers; sunset in 2024.
- **Embedded settlement for Virtual Carrier** — drivers under CloudTrucks authority get instant pay direct from the platform; no third-party factoring needed because CloudTrucks is the carrier of record.
- **Invoice/expense visibility** — pending invoices + job payments tracked inside the BI dashboard.

### Notes / limits
- **CloudTrucks is no longer in the standalone factoring business** as of 2024 (FreightWaves, Yahoo Finance coverage). "CT Suite" is not currently a marketed line; the public taxonomy is Virtual Carrier / Flex / CT Cash / CT Credit / CT Exchange / Road to Independence.
- Drivers running their own authority via Flex who want third-party factoring must source it externally.
- No documented invoice-generation tool for own-authority owner-ops on the platform.

---

## 6. Fuel Cards / Fuel Discounts — CT Fuel

- **CT Fuel card** — standard issue to all Virtual Carrier fleets.
- **CloudTrucks Fuel Network** — discounted in-network fueling; cash-back capped at $20 max per transaction.
- **Pilot Flying J integration via CT Cash** — 3% cash back on fuel paid with CT Cash, up to $0.15/gal credited to CT Cash balance (authorization can take a few days).
- **CT Credit cash-back partners** — Road Ranger, Pilot Flying J, Love's Maintenance.
- **Fuel-receipt scan** — receipts auto-feed IFTA; in-network purchases recorded automatically.

### Notes / limits
- CT Cash fuel discount cannot be combined with other discount cards/programs.
- **No documented direct TA / Petro discount** in the indexed sources (Pilot Flying J + Love's are the named partners).
- Per-transaction cash-back ceiling ($20) limits big-fill economics for heavy haulers.

---

## 7. Insurance

- **Auto liability + cargo** — included for Virtual Carrier drivers as part of the platform fee.
- **General liability** — included under CloudTrucks DOT/MC authority (Virtual Carrier).
- **Non-Trucking Liability + Occupational Accident** — CloudTrucks "helps drivers acquire" these via partner network rather than carrying them directly.
- **Insurance fee structure** — to be on auto liability + cargo, drivers pay the greater of $150/week or 5% of gross load value, collected as part of the lease-on fee (not paid up front).
- **Physical damage** — driver responsibility, sourced through partner brokers.

### Notes / limits
- Insurance bundle is **only** part of Virtual Carrier; Flex (own-authority) drivers carry their own complete policy stack.
- No documented in-app claims FNOL / accident-handling workflow surfaced beyond the standard "coverage included" descriptor — accident handling is external.
- Cargo insurance limit details not published.

---

## 8. Compliance & Docs

- **DOT + MC authority provided** under Virtual Carrier — drivers do not need their own.
- **IFTA permit + stickers** — temporary permit valid 30 days issued at onboarding; physical stickers mailed within 14 days.
- **IFTA filing** — quarterly Distance Summary reports (total distance, total fuel, jurisdictions); fuel purchases auto-recorded via CT Fuel Network.
- **TCS fuel records** — quarterly external fuel records can be forwarded to CloudTrucks for inclusion.
- **FMCSA exemption activity** — CloudTrucks has filed for FMCSA exemptions related to its driver-hiring process (per FreightWaves).

### Notes / limits
- **BOC-3 + IRP filing as a paid line item is not publicly broken out as a CloudTrucks product** — guidance content exists on the blog but no productized filing service is documented.
- IFTA service tied to using CT Fuel + CT Cash data; manual receipt forwarding is supported but is the fallback path.
- Drivers running Flex (own authority) remain solely responsible for their own DOT/MC compliance, UCR, IRP, BOC-3.

---

## 9. Tax Services

- **ATBS partnership** — CloudTrucks partners with American Truck Business Services (the largest US tax/accounting firm for owner-operators) for tax prep + bookkeeping referrals.
- **1099 documentation** — CloudTrucks issues drivers 1099-equivalent records reflecting Virtual Carrier earnings.
- **IFTA quarterly reports** — feed driver tax filings.
- **Mileage / distance summaries** — generated on request; commonly used by IRP offices and tax preparers.

### Notes / limits
- **No in-house CPA or tax-filing product** — CloudTrucks routes drivers to ATBS for actual tax filing.
- No documented self-serve mileage tracker independent of dispatched loads (mileage comes from booked-load history + fuel-card data).
- No documented tax estimator inside the BI dashboard.

---

## 10. Mentorship / Coaching / Community

- **Road to Independence** — multi-month onboarding program for first-time owner-operators; "dedicated business consultant, dedicated dispatcher, 24/7 support."
- **Dedicated dispatcher** — in-program drivers get 1:1 dispatch contact to hit earnings goals.
- **Podcast** — monthly CloudTrucks-hosted show with industry insight + owner-operator stories; secondary podcast series with peer owner-op narratives.
- **Blog + educational library** — extensive operator-focused content (tax tips, becoming an owner-op, expense management, MC authority playbook).
- **Community forums / TruckersReport thread presence** — CloudTrucks engages on TruckersReport, G2.

### Notes / limits
- **No in-app peer-to-peer driver community / forum / messaging** documented.
- **No gamification, leaderboard, missions, or rewards engine** documented (no equivalent of EusoTrip's "The Haul").
- Mentorship is service-style (consultant + dispatcher) rather than peer-network style.

---

## 11. Shipper-Direct Features

- **CT Exchange (shipper view)** — shippers can tap the Virtual Carrier fleet (~300+ direct-access owner-operators) for prioritized capacity, plus broader Exchange carrier network.
- **Shipper services** — API/EDI integrations, end-to-end shipment tracking, exception management via ELD integrations, 24/7 dedicated account team.
- **Shipper Referral Program** — published referral incentive (Help Center).
- **Brokers page** — separate "For Brokers" surface advertising 600+ vetted owner-operators, instant load matching, TMS integration, data-driven coverage.

### Notes / limits
- **Shipper surface is brokerage-mediated** — CloudTrucks runs as an asset-light carrier/brokerage, so the "shipper product" is essentially "tender freight to our brokerage" — there is no documented self-serve shipper portal for posting loads, comparing carrier bids, viewing scorecards, or running RFP cycles.
- **No shipper-facing TMS** (rate management, lane planning, accessorial governance, BOL templating, OS&D claims, vendor scorecards) — these are not CloudTrucks territory.
- **No shipper-managed driver chat / live shipment portal** documented at parity with what EusoTrip ships for shippers.
- The Exchange shipper page emphasizes capacity access + tracking, not pricing/rate-management self-service.

---

## 12. Maintenance + Roadside (Zeun-equivalent)

- **Discount partners** — Love's Maintenance is a published CT Credit cash-back partner; CT Cash unlocks "exclusive benefits and discounts for gas, maintenance, tires, and more."
- **Maintenance reserve in lease-to-own** — Road to Independence weekly economics include a maintenance reserve payment.

### Notes / limits
- **No documented in-app roadside-assistance / breakdown dispatch product**.
- **No documented mechanic / service-provider network or DVIR workflow** comparable to EusoTrip's Zeun.
- **No documented preventive-maintenance scheduling, PM intervals, or inspection-tracking feature**.
- **No documented accident / FNOL workflow** in-app.
- This is a major gap vs EusoTrip's Zeun branded surface.

---

## 13. ELD / HOS Integration

- **Motive (formerly KeepTruckin) integration** — listed in Motive Marketplace; fleet admin authenticates and authorizes CloudTrucks read access to ELD data during onboarding.
- **Used by both Flex and CT Cash products** — Motive linkage is part of fleet onboarding checklist.
- **ELD data feeds shipment tracking** — referenced in the Exchange shipper-services description ("proactive exception management through ELD integrations").

### Notes / limits
- **Only Motive is publicly named.** No documented Samsara, Geotab, Omnitracs, or Verizon Connect direct integration.
- **No documented native ELD / hardware product** from CloudTrucks itself.
- HOS visibility surfaces appear to be carrier-admin facing (compliance + dispatch), not packaged as a driver-facing HOS coach inside the CloudTrucks app.

---

## 14. Subscription Tiers + Public Pricing

- **Virtual Carrier (lease-on under CloudTrucks authority)** — 18% per-load fee (13% service + 5% group auto-liability/cargo insurance enrollment). Compared in marketing to 30–35% at "most mega-carriers."
- **Flex (own authority)** — published rate of $30 per user for fleets of 1–3 trucks. Custom pricing for fleets of 4+ trucks.
- **Road to Independence Service Package** — 21% per-load fee, bundled with dedicated dispatch + insurance + IFTA + instant pay + load access. 1-year commitment minimum.
- **Lease-to-own truck terms (FleetFirst, Road to Independence)** — $0 down for qualifying drivers; weekly truck payments $550–$950; end-of-lease buyout $5,000–$10,000 with security deposit credit.
- **CT Cash** — no monthly subscription; 1.5% per advance.
- **CT Credit** — no fees, no interest, no late fees; 2-week revolving cycle (auto-paid 1st and 16th); custom underwriting per applicant.

### Notes / limits
- Flex public price ($30/user) appears narrowly published; some sources reference it without a date stamp.
- Per-load percentage fees (18% / 21%) are gross-revenue based, not net.
- No public price discovery for CT Exchange shipper customers (sales-led).

---

## What CloudTrucks Does NOT Cover (Findings vs EusoTrip)

These are documented absences in CloudTrucks' public product surface as of May 2026 — useful as positive signal for EusoTrip differentiation, not as criticism:

- **Self-serve shipper portal** — no shipper can log in, post loads, compare carrier bids, manage tenders, run RFPs, or score carriers. (CloudTrucks shippers tender into the brokerage.)
- **Shipper-side pricing intelligence** — no lane heatmap, fuel surcharge schedule, accessorial benchmark, or rate-comparison tool surfaced to shippers.
- **In-app turn-by-turn truck navigation** — driver app does not appear to ship a routed truck-aware GPS layer.
- **Native in-app driver↔shipper messaging** — communication is mediated through brokers / CloudTrucks dispatch.
- **Maintenance / breakdown / roadside / mechanic-network product** — no Zeun-equivalent surface.
- **DVIR / inspection / PM scheduling** — no documented driver-facing inspection workflow.
- **Accident FNOL / freight-claims workflow** — no documented in-app claims surface.
- **Standalone factoring** — exited 2024; not a current line.
- **Multi-modal** — no rail, vessel, intermodal, or cross-border (US-MX-CA) coverage. Pure US over-the-road.
- **Hazmat-specialized workflow** — no documented hazmat checklist, ADR/IMDG/NOM compliance, escort coordination.
- **Escort / heavy-haul / oversize coordination** — not present.
- **Terminal manager / yard-management** surface — not present.
- **Rail roles, vessel roles, port master, customs broker** — not present.
- **Compliance-officer / safety-manager dashboards** — not productized for those personas.
- **Gamification / missions / leaderboards / rewards** — no Haul equivalent.
- **Voice assistant / AI co-pilot in-cab** — no ESANG-equivalent surface documented.
- **BOC-3 / IRP filing as productized service** — content exists, not a sold service.
- **Yield / interest savings product** — CT Cash is spending-only.
- **Self-serve invoicing for own-authority Flex carriers** — no documented invoice generator.
- **Direct-named ELD integrations beyond Motive** — only Motive in public materials.

---

## Sources

- [CloudTrucks homepage](https://www.cloudtrucks.com/)
- [Virtual Carrier for Truck Drivers](https://www.cloudtrucks.com/virtual-carrier)
- [Virtual Carrier FAQ](https://www.cloudtrucks.com/faq)
- [Pricing for Drivers & Fleets](https://www.cloudtrucks.com/pricing)
- [CloudTrucks Exchange (Shipper page)](https://www.cloudtrucks.com/exchange)
- [For Brokers](https://www.cloudtrucks.com/brokers)
- [Lease-to-Own Truck Program / Road to Independence](https://www.cloudtrucks.com/road-to-independence)
- [Fuel Card Terms](https://www.cloudtrucks.com/fuel-card-terms)
- [Podcasts](https://www.cloudtrucks.com/podcasts)
- [CT Hacks blog](https://www.cloudtrucks.com/blog-post/ct-hacks-celebrating-innovation-teamwork)
- [Building a Business Intelligence Backend (blog)](https://www.cloudtrucks.com/blog-post/building-a-business-intelligence-backend)
- [Introducing CloudTrucks Exchange (blog)](https://www.cloudtrucks.com/blog-post/introducing-ct-exchange)
- [Dispatch and Loads for Owner Operators (blog)](https://www.cloudtrucks.com/blog-post/dispatch-and-loads-for-owner-operators)
- [CloudTrucks Launches Schedule Optimizer (blog)](https://www.cloudtrucks.com/blog-post/cloudtrucks-launches-schedule-optimizer)
- [Road to Independence: Equipping First-Time Owner Operators (blog)](https://www.cloudtrucks.com/blog-post/cloudtrucks-road-to-independence)
- [Unlock Independence with FleetFirst (blog)](https://www.cloudtrucks.com/blog-post/unlock-independence-with-fleetfirst-leasing-partner-exclusive-cloudtrucks)
- [Driving Broker Success: The CloudTrucks Advantage (blog)](https://www.cloudtrucks.com/blog-post/driving-broker-success-the-cloudtrucks-advantage)
- [Tax Tips for Owner-Operator Truck Drivers (blog)](https://www.cloudtrucks.com/blog-post/tax-tips-for-owner-operators)
- [Embracing Change: New Year Updates (blog)](https://www.cloudtrucks.com/blog-post/embracing-change-exciting-new-year-updates)
- [CT Cash FAQs (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/13976395244823-CT-Cash-FAQs)
- [CT Cash + Pilot Flying J (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/13975518307095-CloudTrucks-Pilot-Flying-J)
- [CloudTrucks Fuel Network (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/14485144366871-CloudTrucks-Fuel-Network)
- [Virtual CT Cash Card setup (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/13976043382295-Your-Virtual-CT-Cash-Card-Set-Up-Steps-and-Benefits)
- [Insurance Coverage FAQ (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/13976195134871-CloudTrucks-insurance-coverage-FAQ)
- [Trailer Lease Agreement (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/14199303088279-CloudTrucks-trailer-lease-agreement)
- [Contract Freight & Dedicated Lanes FAQ (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/13975991063191-Contract-Freight-Dedicated-Lanes-FAQ)
- [Road to Independence Program FAQ (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/23398736875799-CloudTrucks-Road-to-Independence-Program-FAQ)
- [IFTA, Fuel Receipts, and Fuel Reports (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/22402363292311-IFTA-Fuel-Receipts-and-Fuel-Reports)
- [Pickup Pay In-app Request (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/13975842594071-How-to-request-Pickup-Pay-in-app)
- [Lumper Fees (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/24006646198295-Lumper-Fees)
- [Toll Billing at CloudTrucks (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/16193818345495-Toll-Billing-at-CloudTrucks)
- [Shipper Referral Program (Help Center)](https://cloudtrucks.zendesk.com/hc/en-us/articles/30378775990935-CloudTrucks-Shipper-Referral-Program)
- [CT Credit FAQ (Your-Authority Help Center)](https://your-authority.help.cloudtrucks.com/hc/en-us/articles/13946810906391-CT-Credit-FAQ)
- [What is CT Credit & how to apply](https://your-authority.help.cloudtrucks.com/hc/en-us/articles/13946777543959-What-is-CT-Credit-how-to-apply)
- [Schedule Optimizer how-to](https://your-authority.help.cloudtrucks.com/hc/en-us/articles/16999052617111-How-to-use-Schedule-Optimizer)
- [CT Cash (intercom Help Center)](https://help.cloudtrucks.com/en/articles/5053564-ct-cash)
- [CT Cash Virtual Card](https://help.cloudtrucks.com/en/articles/5371337-ct-cash-virtual-card)
- [CloudTrucks – Apple App Store](https://apps.apple.com/us/app/cloudtrucks/id1523676447)
- [CloudTrucks – Google Play](https://play.google.com/store/apps/details?id=com.cloudtrucks.cloudtrucksapp.production)
- [CloudTrucks Reviews – G2](https://www.g2.com/products/cloudtrucks/reviews)
- [CloudTrucks Alternatives – G2](https://www.g2.com/products/cloudtrucks/competitors/alternatives)
- [CloudTrucks Reviews – TruckersReport](https://www.thetruckersreport.com/co/cloudtrucks.4124/reviews)
- [Motive Marketplace – CloudTrucks](https://marketplace.gomotive.com/app/cloudtrucks)
- [123Loadboard Partners with CloudTrucks (press)](https://www.123loadboard.com/press-releases/123loadboard-partners-with-cloudtrucks/)
- [CloudTrucks acquires Shipwell brokerage – FreightWaves](https://www.freightwaves.com/news/cloudtrucks-launches-new-offerings-acquires-shipwells-brokerage)
- [CloudTrucks acquires Shipwell brokerage – Journal of Commerce](https://www.joc.com/article/cloudtrucks-acquires-shipwell-brokerage-division-amid-truckload-market-shakeout-5222356)
- [Shipwell Sells Brokerage Division to CloudTrucks – Shipwell](https://www.shipwell.com/blog/strategic-power-move-shipwell-sharpens-saas-cloud-supply-chain-focus-sells-brokerage-arm-to-cloudtrucks)
- [VC-backed CloudTrucks exits factoring – FreightWaves](https://www.freightwaves.com/news/vc-backed-cloudtrucks-exits-factoring-business-to-focus-on-core-offerings)
- [CloudTrucks expands Road to Independence with FleetFirst – FreightWaves](https://www.freightwaves.com/news/cloudtrucks-empowers-drivers-with-fleetfirst-ownership)
- [CloudTrucks launches scheduling tool – FreightWaves](https://www.freightwaves.com/news/cloudtrucks-launches-scheduling-tool-for-drivers)
- [CloudTrucks new offerings for owner-operators – FreightWaves](https://www.freightwaves.com/news/cloudtrucks-new-offerings-available-to-all-owner-operators)
- [CloudTrucks launches CT Credit – FreightWaves](https://www.freightwaves.com/news/cloudtrucks-launches-new-fintech-offering-ct-credit)
- [CloudTrucks Road to Independence – FreightWaves](https://www.freightwaves.com/news/cloudtrucks-offers-drivers-road-to-independence)
- [CloudTrucks seeks FMCSA exemption – FreightWaves](https://www.freightwaves.com/news/cloudtrucks-seeks-exemption-for-its-driver-hiring-process)
- [Virtual trucking carrier startup snags $6.1M – FreightWaves](https://www.freightwaves.com/news/virtual-trucking-carrier-startup-snags-6-1m)
- [CloudTrucks Series A $20.5M – PR Newswire](https://www.prnewswire.com/news-releases/cloudtrucks-raises-20-5-million-series-a-launches-instant-payments-to-help-truckers-manage-cash-flow-301193716.html)
- [CloudTrucks Series B $115M – BusinessWire](https://www.businesswire.com/news/home/20211130005269/en/CloudTrucks-Raises-115-Million-at-850-Million-Valuation-in-Series-B-Funding-Led-by-Tiger-Global)
- [CloudTrucks Series B – TechCrunch](https://techcrunch.com/2021/11/30/cloudtrucks-raised-115m-series-b-to-help-truck-entrepreneurs-manage-their-business/amp)
- [CloudTrucks launches CT Credit – BusinessWire](https://www.businesswire.com/news/home/20220706005222/en/CloudTrucks-Launches-CT-Credit-to-Unlock-Cash-Flow-for-Owner-Operators-and-Small-Fleets)
- [CloudTrucks debuts Visa Card – PYMNTS](https://www.pymnts.com/news/b2b-payments/2022/trucking-management-firm-cloudtrucks-debuts-visa-card/)
- [CloudTrucks new credit card – Overdrive](https://www.overdriveonline.com/business/article/15294011/cloudtrucks-launches-new-credit-card-for-ownerops-small-fleets)
- [CloudTrucks launches CT Credit – Commercial Carrier Journal](https://www.ccjdigital.com/technology/article/15293937/cloudtrucks-launches-ct-credit)
- [Menlo Ventures investment in CloudTrucks](https://menlovc.com/perspective/our-investment-in-cloudtrucks-bringing-critical-solutions-to-truckers-powering-the-supply-chain/)
- [CloudTrucks – PitchBook profile (2026)](https://pitchbook.com/profiles/company/399472-66)
- [CloudTrucks – Crunchbase](https://www.crunchbase.com/organization/cloudtrucks)
- [CloudTrucks – CB Insights](https://www.cbinsights.com/company/cloudtrucks)
- [CloudTrucks – AllTruckJobs profile](https://www.alltruckjobs.com/trucking-companies/cloudtrucks)
- [CloudTrucks Flex Review – EMPWR Trucking](https://staging.empwrtrucking.com/freight-technology/cloudtrucks-flex-review-is-it-the-best-tms-for-you/)
- [Trucking Opportunities w/ Uber Freight, COOP & CloudTrucks – Infiniti Workforce](https://infinitiworkforce.com/2025/08/11/new-trucking-opportunities/)
- [Shipwell Sells Brokerage – FreightCaviar](https://www.freightcaviar.com/shipwell-sells-brokerage-division-to-cloudtrucks/)
