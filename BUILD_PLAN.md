# LandBank v2 — Implementation Plan

This branch is the safe build area for the next version of LandBank. `main` remains untouched until individual changes are tested and deliberately merged.

## Goal
Turn the current map-based prospecting CRM into a solar-land origination intelligence platform that answers:

1. Is this land technically attractive?
2. Who actually controls/owns it?
3. Can we reach the right person?
4. What information is missing?
5. What should Sam do next?
6. What is the opportunity likely to be worth over 25 years?

## Current live state

The V2 schema is live in Supabase and the existing source universe has been imported:

- 6,425 organisations
- 6,425 sites
- 6,425 opportunities
- 6,425 qualification records
- 654 contact-ready opportunities
- 5,771 identified / enrichment-needed opportunities
- 668 phone/mobile contact records
- 320 email records
- 335 website records
- 19,983 source land parcels represented

See `README_V2_STATUS.md` for the current operational checkpoint.

## Built and live

- `supabase/migrations/001_landbank_v2.sql` — relational V2 + PostGIS foundation
- `supabase/migrations/002_legacy_bridge_and_qualification.sql` — legacy bridge + qualification data
- `supabase/migrations/003_contact_uniqueness_fix.sql` — shared farm contact handling
- `supabase/migrations/004_upsert_keys.sql` — idempotent import keys
- `supabase/migrations/005_import_snapshots.sql` — source snapshot provenance
- `supabase/migrations/006_browser_permissions_and_workspace.sql` — browser workspace + reduced privileges
- `supabase/migrations/007_site_score_function.sql` — authoritative evidence-aware site scoring
- `lib/scoring.js` — transparent scoring engine; missing data is unknown, not zero
- `v2.html` — compatibility V2 interface
- `v2-live.html` — live Supabase-backed CRM interface
- `supabase/functions/import-legacy/index.ts` — idempotent source importer
- `supabase/functions/enrich-prospect/index.ts` — Companies House → Google Places → Hunter adapter
- `supabase/functions/assess-site/index.ts` — PVGIS + Planning Data point screening
- `.github/workflows/v2-smoke.yml` — JavaScript smoke checks

## CRM workflow

Opportunity pipeline:

`identified` → `researching` → `contact_ready` → `outreach_started` → `connected` → `qualified_interest` → `site_data_requested` → `site_prescreen` → `commercial_assessment` → `proposal` → `site_visit` → `heads_of_terms` → `technical_dd` → `grid_planning` → `finance_approval` → `contracted` → `construction` → `commissioned` → `live`

Every open opportunity is designed to have an owner, stage, probability, next action, next-action date and a loss reason when closed.

## Contact enrichment waterfall

1. Companies House — directors/company status/address
2. Google Places — phone/domain/location confirmation
3. Website crawl — published phone/email/contact/team/legal pages
4. Hunter — domain search / named email / verification
5. Clay fallback — only for high-value unresolved prospects
6. Human verification queue for ambiguous matches

Each discovered datum should retain provider, source URL/reference, discovery method, confidence, verification status and timestamp.

Provider credentials are not yet configured for live contact enrichment.

## Ownership intelligence

Use a confidence ladder rather than assuming `director = landowner`:

- 100: title owner confirmed
- 85: corporate/title relationship confirmed
- 65: registered-address/company relationship
- 45: probable operator/occupier
- 20: speculative match

Target source layers include HM Land Registry/INSPIRE plus existing company/title matching inputs.

## Technical enrichment

### Live now
- PVGIS solar yield via server-side Edge Function
- Planning Data point screening via server-side Edge Function

### Next
- bulk Planning Data/environmental spatial overlays in PostGIS for national portfolio screening
- DNO/grid-capacity normalization and Grid Score
- Agricultural Land Classification
- environmental/MAGIC-style layers
- parcel geometry / usable acreage
- topography

Point screening is triage only. Portfolio-scale constraint screening should use bulk datasets + PostGIS intersections rather than thousands of API calls.

## Site scoring

Starting component weights:

- Grid: 25%
- Land: 20%
- Planning: 15%
- Agricultural quality/suitability: 10%
- Topography: 10%
- Solar resource: 10%
- Ownership confidence: 10%

Missing components are excluded from the denominator until evidence exists. Partial scores must be treated as partial intelligence, not full due diligence.

## Commercial / finance engine

Exact formulas must be agreed from the PE finance arrangement before being treated as production calculations.

Target inputs include usable acres, system MWp, expected annual generation, site demand, self-consumption/export, capex, finance rate/fees, repayment allocation, degradation, power-price assumptions, participation-pool percentage and contractual share.

Target outputs include repayment period, farmer income, farmer/project 25-year economics, personal annual commission, personal 25-year commission and probability-weighted value.

## Dashboard / UI

The live V2 interface now contains live metrics, ranked opportunities, search/filtering, pipeline columns, intelligence map, data-gap queue and an editable opportunity workspace covering qualification and electricity-data fields.

Future dashboard additions include weighted 25-year pipeline, potential MWp, commissioning forecast, high-feasibility sites missing contacts, source/provider performance and stage-age analytics.

## AI assistant layer

Only after structured data is reliable. It should query evidence-backed structured data and explain prioritisation; it must not invent technical assessments.

## Principle

Do not build a generic CRM clone. Keep LandBank's advantage: land + ownership + grid/planning + solar economics + sales execution in one record.

## Merge status

Do not merge PR #1 yet. Continue development on `landbank-v2-foundation` while `main` remains untouched.
