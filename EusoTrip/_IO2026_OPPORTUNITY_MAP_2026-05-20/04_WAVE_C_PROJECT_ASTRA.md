# Wave C — Project Astra (Live Visual + Memory)
**Agent #3 deliverable** | 6 use cases + audit/trust model

## What Astra brings to freight
- Live visual data + conversation concurrent
- Spots objects in field of view, reasons over them
- Remembers locations (spatial memory)
- Answers contextual questions on what's visible
- Helps finish tasks in real time (multi-step)
- Integrated across XR glasses, phones, smart-home

## Use case A — Driver Pre-Trip DVIR (P0)
- **Astra sees:** Real-time tread depth analysis, brake pad wear, heat cracks, brake fluid seepage, missing hubcaps, valve stem condition
- **Astra remembers:** Tire rotation history, prior DVIR dates, manufacturer specs, axle load limits
- **Acts autonomously:** Pre-populates DVIR form with severity codes (green/yellow/red); queues work orders if red; raises dispatch alert; fills immutable record in blockchain audit log with photo + confidence scores
- **Files:** `Views/Driver/DVIRCaptureController.swift`, `Services/VehicleInspectionService.swift`, `Services/PhotoCaptureService.swift`, `Data/hazmat_metadata.json`
- **Compliance unlock:** 49 CFR 396 (maintenance), FMCSA out-of-service criteria — visual evidence replaces subjective inspection
- **Trust + audit:** Each DVIR photo + metadata (timestamp, GPS, IoT sync) signed with driver public key. Hash of vision output committed to ledger. Insurers accept as prima facie evidence.
- **Effort:** M

## Use case B — Hazmat Placard + ERG hands-free (P0)
- **Astra sees:** OCR placard (UN1075), hazard class (2.1), subsidiary classes; cross-references 49 CFR 172.101 → commodity, shipping name, ERG guide; detects placard damage/fading
- **Acts autonomously:** Queries ERG microservice "UN1075 class 2.1" → returns guide 115; streams to voice "Propane. Flammable gas. Isolate 1,600 feet, evacuate downwind."; auto-populates shipping paper fields; flags segregation violations
- **Files:** `Services/HazmatMetadataService.swift`, `Views/Driver/HazmatPlaycardScanController.swift`, `Data/49_cfr_172_101_seed.json`, `Services/EmergencyResponseGuideClient.ts`
- **Compliance unlock:** 49 CFR 172.201 (shipping papers — Astra eliminates transcription errors), DOT HM-181 (hazmat training — hands-free ERG counts as real-time decision support)
- **Trust:** OCR confidence + placard photo timestamped + signed. Cross-reference to manifest: Astra warns if placard ≠ manifest. Low confidence triggers manual review.
- **Effort:** M

## Use case C — POD Photo with auto-seal/placard/damage detection (P1)
- **Astra sees:** Tamper-evident seal numbers via OCR, physical damage (tears, crushed corners, water stains, missing goods), placards still affixed, damage spatial position
- **Acts autonomously:** Auto-populates POD form (seal #, condition code, damage description, photo count); compares seal # to manifest (flag mismatch); generates OS&D exception if visual ≠ manifest; routes to cargo insurance intake
- **Files:** `Views/Receiver/PODPhotoController.swift`, `Services/ReceiptService.swift`, `Services/OCRService.swift`, `Services/ClaimInitiationService.ts`
- **Compliance unlock:** FMC Rule 1 (bill of lading — Astra-signed photo admissible), 49 CFR 380 Appendix B (cargo inspection — replaces subjective notes)
- **Trust:** Each POD photo cryptographically linked to load ID + receiver signature. Damage classification (Astra-suggested vs. manual override) both logged.
- **Effort:** M

## Use case D — Reefer Temp-Log Reading (P1)
- **Astra sees:** Reads analog or LCD reefer display, extracts min/max temps from past 24h if visible, unit serial # from nameplate, GPS at time of read
- **Acts autonomously:** Converts display reading to FSMA-compliant temp log entry (21 CFR 1.908); checks for excursions; populates telemetry sync log; raises alert if violations
- **Files:** `Services/ReeferTelemetryService.swift`, `Views/Driver/ReeferStatusController.swift`, `Data/fsma_compliance_rules.json`
- **Compliance unlock:** FSMA 21 CFR 1.908 — real-time temp log with Astra photo evidence satisfies "continuous temperature monitoring" without IoT hardware dependency
- **Trust:** Display photo + extracted temp signed with driver public key. Cross-checked against telematics if IoT present; discrepancies flagged.
- **Effort:** S

## Use case E — Receiver OS&D Detection from cargo visual diff (P1)
- **Astra sees:** Reads manifest barcode → loads expected SKU list, pallet count, weight, color/label; captures actual cargo photo; compares visual signatures (label, color, shrink-wrap, stacking pattern)
- **Astra remembers:** Prior deliveries from same shipper (learns expected variance)
- **Acts autonomously:** Detects missing pallets ("manifest 15, camera shows 13"); flags SKU mismatch; generates OS&D exception with type/quantity/reason; auto-notifies shipper + dispatcher; routes to freight claim intake
- **Files:** `Views/Receiver/InboundManifestController.swift`, `Views/Receiver/DockSurface.swift`, `Services/CargoComparisonService.ts`, `Services/OSandDService.swift`
- **Compliance unlock:** Intra-company claims reconciliation (eliminates 48-hr manual count delays). Carrier accountability: timestamped photo + count is binding.
- **Trust:** Expected manifest + actual cargo photo both retained immutably. Astra pallet/SKU count + confidence logged. Receiver can override (manual recount); override reason + photo stored.
- **Effort:** M

## Use case F — Livestock 28-hr Law Arming (P2)
- **Astra sees:** Detects animal presence + species (cattle, swine, poultry) via thermal signature + motion; counts animals (cross-references manifest); remembers load departure time, route, next unload
- **Acts autonomously:** Auto-calculates rest/feed deadline (load time + 28 hours); sets recurring voice reminder ("Livestock deadline in 4 hours. Route to staging area"); flags route if no unload facility within remaining time; prevents new livestock load dispatch if previous still in trailer
- **Files:** `Services/LivestockComplianceService.swift`, `Views/Driver/TrailerScanController.swift`, `Data/livestock_regulations.json`
- **Compliance unlock:** 49 CFR 173 — Astra-verified load + animal detection = irrefutable evidence of load time for 28-hr timer. USDA Animal Welfare Act compliance.
- **Trust:** Initial detection photo + count timestamped at load. Ledger records load time, species, headcount, calculated deadline, actual unload time. If deadline exceeded: photo evidence supports violation claim.
- **Effort:** L (thermal animal detection model, species classification, 28-hr state machine across lifecycle)

---

## AUDIT + TRUST MODEL — Astra observations → admissible evidence

### 1. Observation Capture
- Astra captures photo/video + extracts structured data (OCR, detection, measurement)
- Metadata: NTP-synced timestamp, GPS, device ID, operator public key, load ID, commodity type
- Confidence scores attached (e.g., "OCR 94%", "tire tread ±2mm")

### 2. Local Signing + Dual-Layer Hash
- Device immediately signs observation bundle (photo hash + metadata + confidence) with operator's private key
- **First hash:** SHA-256(Astra output + operator signature)
- **Second hash:** bundled with manual verification (dispatcher review or dock-worker confirmation)
  - Astra-only (remote DVIR): operator signature = acceptance
  - With manual override: BOTH Astra signature + verifier signature on chain (shows dispute or confirmation)

### 3. Blockchain Ledger Commitment
- Observation hash + load ID appended to immutable audit log
- Ledger entry: `{astra_hash, load_id, timestamp, operator_pk, confidence_scores, override_flag}`
- Double-entry accounting: OS&D claim links both receipt photo hash + delivery photo hash

### 4. Immutability + Transparency
- Once committed, cannot be deleted or modified
- Claim adjuster queries: "Show all DVIR records for LD-12345" → returns all observations + overrides + timestamps
- Cryptographic proof on request

### 5. Admissibility in Dispute Resolution
- Carrier defends with Astra POD photo + signature
- If Astra-captured damage at receipt ≠ condition at unload, both in ledger
- Astra is **programmatically neutral** (no incentive to lie); photo timestamp + dual signature = chain-of-custody

### 6. Rollback + Exception Handling
- Operator disputes Astra reading → files override + counter-evidence
- Override tagged: `{astra_observation_hash, override_reason, override_signature, original_confidence}`
- Pattern detection: repeated overrides by same operator → flag for retraining or device replacement
- **Showing all disputed readings (not hiding failures) actually strengthens carrier credibility**

### 7. Regulatory Reporting
- FMCSA violations: pull ledger records, generate compliance report with Astra attestation
- DOT audit: "How do you know you were compliant?" → blockchain ledger with timestamped DVIR hashes
- Insurance underwriting: Astra POD data shows actual vs. claimed damage trends (reduces fraud risk)

---

## Summary table

| Use case | Compliance win | Audit strength | Effort |
|----------|---------------|----------------|:------:|
| A. Pre-Trip DVIR | 49 CFR 396; FMCSA OOS criteria | Visual evidence eliminates subjective disputes | M |
| B. Hazmat Placard | 49 CFR 172.201; ERG hands-free | OCR + cross-ref prevents transcription errors | M |
| C. POD Photo | FMC Rule 1; cargo damage inspection | Timestamped photo + seal OCR = claim proof | M |
| D. Reefer Temp | FSMA 21 CFR 1.908 | Display read replaces IoT dependency | S |
| E. OS&D Detection | Carrier liability for short-ships | Image diff establishes facts without dispute | M |
| F. Livestock 28-hr | 49 CFR 173; USDA Animal Welfare Act | Countdown + animal detection = irrefutable timeline | L |

**Net impact:** Astra transforms EusoTrip from *declarative* compliance (driver fills form) to *observational* compliance (Astra verifies facts). Blockchain ledger makes every observation defensible in court or claims adjudication.
