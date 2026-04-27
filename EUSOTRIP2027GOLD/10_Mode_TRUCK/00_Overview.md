# 10 · Mode TRUCK — Overview

**What this covers.** The top-level map of the TRUCK mode on EusoTrip: the nine verticals (hazmat, reefer, flatbed, livestock, auto-hauler, LTL, tanker, intermodal, general), the three countries (US / CA / MX), the persona roster (Driver, Dispatch, Catalyst, Broker, Shipper, Escort, Carrier, Terminal, Admin), the canonical screen-number ranges, and the per-role files in this folder.

**When you need this.** When orienting a new engineer to where TRUCK lives, when a PM asks what TRUCK's scope looks like, when deciding which role-file to read for a given feature.

**Cross-links.** Full vertical × country deep dive: [50_Verticals_Reference.md](./../50_Verticals_Reference.md). Cross-border specifics: [40_Intermodal_and_Cross_Border.md](./../40_Intermodal_and_Cross_Border.md). Rail + Vessel: [20_Mode_RAIL/00_Overview.md](./../20_Mode_RAIL/00_Overview.md), [30_Mode_VESSEL/00_Overview.md](./../30_Mode_VESSEL/00_Overview.md).

---

## Screen-number ranges (TRUCK)

- **010 – 099** — Driver A→Z. See [01_Driver.md](./01_Driver.md).
- **200 – 299** — Shipper. See [05_Shipper.md](./05_Shipper.md).
- **300 – 399** — Dispatcher. See [02_Dispatch.md](./02_Dispatch.md).
- **400 – 499** — Broker. See [04_Broker.md](./04_Broker.md).
- **500 – 599** — Catalyst. See [03_Catalyst.md](./03_Catalyst.md).
- **600 – 699** — Escort. See [06_Escort.md](./06_Escort.md).
- **700 – 799** — Terminal / Yard. See [07_Carrier_Terminal_Admin.md](./07_Carrier_Terminal_Admin.md).
- **800 – 899** — Carrier Admin / Fleet Owner / Safety Officer / Compliance Officer. See [07_Carrier_Terminal_Admin.md](./07_Carrier_Terminal_Admin.md).

Always match the Figma id. A screen-number collision across roles is a doctrine bug.

---

## 9 verticals × 3 countries

| Vertical | USA (FMCSA, DOT, ELD) | Canada (Transport Canada, NSC, TDG) | Mexico (SCT / SICT, NOM-087, Carta Porte) |
|---|---|---|---|
| Hazmat | 49 CFR 172, PHMSA, HM-232 security plan, TWIC, HMSP permits | TDG Act, French/English shipping papers Quebec | NOM-087-SCT-2, Carta Porte hazmat complement |
| Reefer | FSMA 21 CFR 1 Subpart O, FDA | CFIA rules | SAGARPA / SENASICA, SAT CFDI |
| Flatbed | 49 CFR 392.9 + 393 Subpart I securement, oversize permits per state | Provincial weight/dimension regs | NOM-012-SCT-2 weights |
| Livestock | 28-hour law (49 USC 80502), USDA VS Form 1-27, CFIA for Canada border | CFIA conditional releases | SAGARPA inspection at border |
| Auto-hauler | VIN check digit validation, NHTSA tie-down best practices | Same inspection expectations | Same inspection expectations |
| LTL | NMFC class, NMFTA ClassIT | Same | Same |
| Tanker | Tank car specs, wash certs, SpectraMatch | TDG + provincial dangerous-goods | NOM-087 + SCT |
| Intermodal | ACE, ISF 10+2 (ocean), UIIC chassis, TWIC ports | ACI, PARS, Ports Halifax/Vancouver | ACE (into US), Carta Porte (MX-side) |
| General / Dry Van | Standard CVSA Level 1 | Standard | Standard |

Every combination is rendered by the same iOS binary. The data-driven `dispatchResolver.ts` produces the required screens, gates, rate multiplier, insurance tier, endorsement set.

**Maximum-complexity case** (hazmat reefer tanker carrying Class 6.1 pharmaceuticals on a Laredo → Monterrey → Calgary tri-country lane): **42 required screens, 31 compliance gates, rate multiplier 2.85, insurance tier "PLATINUM+"** ($15M pollution + $10M cargo + $5M liability), endorsement set `{H, N, X, TWIC, FAST, TDG, Licencia-Federal-E, C-TPAT}`.

**Minimum-complexity case** (one-way dry van Atlanta → Dallas): 8 screens, 4 gates, 1.00× multiplier, standard FMCSA minimums.

---

## Persona roster (TRUCK)

**Driver** — 7 sub-personas: Solo OTR, Team, Regional, Local / P&D, Owner-operator, Company driver, Hazmat-endorsed. CDL-A vs CDL-B gates surface differently. See [01_Driver.md](./01_Driver.md) for full persona engine.

**Dispatch** — 4 sub-personas: In-House, 3PL, Carrier, Broker. Web-heavy by design; mobile companion for triage + quick actions. See [02_Dispatch.md](./02_Dispatch.md).

**Catalyst** — independent freight matcher, commission-earning, co-brokered under a Broker. [03_Catalyst.md](./03_Catalyst.md).

**Broker** — licensed principal (MC + FF, bond, BOC-3, E&O). Portfolio-driven, desk-first. [04_Broker.md](./04_Broker.md).

**Shipper** — 6 sub-personas: Manufacturer, Retailer, CPG, Food Processor, Oil & Gas, Ag Co-op. Web-first, mobile for alerts + capture. [05_Shipper.md](./05_Shipper.md).

**Escort** — pilot-car driver, hazmat escort, oversize/overweight escort, heavy-haul convoy coordinator. State-by-state licensure. [06_Escort.md](./06_Escort.md).

**Carrier / Terminal / Admin** — fleet manager, safety officer, compliance officer, terminal manager, yard jockey, accountant, executive. [07_Carrier_Terminal_Admin.md](./07_Carrier_Terminal_Admin.md).

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
