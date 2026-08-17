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

## Current foundation added

- `supabase/migrations/001_landbank_v2.sql`
  - Sites
  - Parcels/titles
  - Organisations
  - People/directors
  - Site-party/ownership relationships
  - Contact points + verification/provenance
  - Opportunities
  - Tasks / next actions
  - Site assessments
  - Financial scenarios
  - Enrichment events
  - Pipeline summary / needs-attention views

- `lib/scoring.js`
  - Site feasibility score
  - Sales readiness score
  - Ownership confidence score
  - Contactability score
  - Commercial score
  - Overall priority score
  - Probability weighted value
  - Stage probabilities
  - Next-best-action rules

## Build sequence

### 1 — CRM workflow upgrade
Replace the broad legacy sales statuses with an opportunity pipeline:

`identified` → `researching` → `contact_ready` → `outreach_started` → `connected` → `qualified_interest` → `site_data_requested` → `site_prescreen` → `commercial_assessment` → `proposal` → `site_visit` → `heads_of_terms` → `technical_dd` → `grid_planning` → `finance_approval` → `contracted` → `construction` → `commissioned` → `live`

Every open opportunity must have:
- owner
- next action
- next-action date
- stage
- probability
- loss reason if closed

### 2 — Existing data migration
Import the existing `farms.json` and `contacts.json` records into the v2 relational structure without deleting the current source data.

Match:
- company number → organisation
- farm/company/location → site
- directors → people + organisation_people
- phones/emails/websites → contact_points
- current pipeline metadata → opportunity

### 3 — Contact enrichment waterfall
Proposed provider order:

1. Companies House — directors/company status/address
2. Google Places — phone/domain/location confirmation
3. Website crawl — published phone/email/contact/team/legal pages
4. Hunter — domain search / named email / verification
5. Clay fallback — only for high-value unresolved prospects
6. Human verification queue for ambiguous matches

Each discovered datum records:
- provider
- source URL/reference
- discovery method
- confidence
- verification status
- timestamp

### 4 — Ownership intelligence
Build a confidence ladder rather than assuming `director = landowner`:

- 100: title owner confirmed
- 85: corporate/title relationship confirmed
- 65: registered-address/company relationship
- 45: probable operator/occupier
- 20: speculative match

Data sources can include HM Land Registry/INSPIRE plus the existing company/title matching inputs.

### 5 — Site feasibility enrichment
Add provider adapters for:

- Grid / DNO capacity
- Planning Data API
- MAGIC / environmental constraints
- Agricultural Land Classification
- PVGIS solar yield
- Parcel geometry / usable acreage
- Topography when a suitable dataset/provider is selected

Persist raw responses plus a compact normalized assessment. Never overwrite source evidence with only a score.

### 6 — Site scoring
Current starting weights:

- Grid: 25%
- Land: 20%
- Planning: 15%
- Agricultural quality/suitability: 10%
- Topography: 10%
- Solar resource: 10%
- Ownership confidence: 10%

Weights are deliberately configurable. They should be calibrated later from real project outcomes.

### 7 — Commercial / finance engine
Exact formulas must be agreed from the PE finance arrangement before being treated as production calculations.

Target inputs:
- usable acres
- system MWp
- expected annual generation MWh
- site demand / annual consumption
- self-consumption percentage
- export percentage/value
- system capex
- finance rate/fees
- repayment allocation (e.g. 100% vs 50%)
- degradation
- power price assumptions
- 10% participation pool
- Sam's contractual share of pool

Target outputs:
- estimated repayment period
- farmer income from commissioning
- farmer 25-year economics
- project 25-year economics
- personal annual commission
- personal 25-year commission
- probability-weighted value

### 8 — Dashboard
Primary dashboard should show action/value, not vanity counts:

- weighted 25-year pipeline
- potential MWp
- qualified opportunities
- callbacks/tasks due
- stale opportunities
- high-feasibility sites with missing contacts
- high-value sites missing technical data
- top opportunities by priority score
- opportunities by stage
- expected commission by stage / commissioning period

### 9 — Map modes
Extend the current Leaflet map with switchable overlays/modes:

- Sales stage
- Site feasibility
- Grid
- Planning/environment
- Commercial value
- Ownership confidence
- Contactability

### 10 — AI assistant layer
Only after structured data is reliable.

Examples:
- “Top 20 Lincolnshire opportunities not contacted.”
- “High grid score sites missing a verified decision maker.”
- “Show opportunities with >£250k estimated personal 25-year value.”
- “What should I do today?”

AI should query structured data and explain why records were prioritised; it should not invent technical assessments.

## What needs external credentials/data access

The code and integrations can be built in this repo, but live provider execution will require the relevant credentials/terms where applicable:

- Companies House API key
- Google Places API key
- Hunter API key (if selected)
- Clay account/API or webhook workflow (if selected)
- Supabase project access for migrations/Edge Functions
- Any DNO/grid data access chosen beyond open datasets

PVGIS and several government/open datasets may not require private credentials.

## Principle
Do not build a generic CRM clone. Keep LandBank's advantage: land + ownership + grid/planning + solar economics + sales execution in one record.
