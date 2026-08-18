# LandBank V2 — Live Build Status

## Product goal
LandBank is a lean solar-origination sales system: identify the highest-value farms, find the right decision maker, qualify genuine interest, capture the required land/commercial information, and hand a clean opportunity to the downstream project company. Contracting, formal grid applications, survey/design, planning due diligence and title/legal due diligence sit downstream.

The commercial proposition is 100% grid-export solar for income, not onsite self-consumption.

## Live portfolio
- 6,425 sites / organisations / opportunities.
- Solar PVGIS screening: 6,425 / 6,425.
- Flood screening: 6,425 / 6,425.
- Usable grid intelligence: 6,392 / 6,425 (99.49%).
  - 4,099 sites have published capacity/headroom-style numeric evidence.
  - 2,293 have explicitly lower-confidence same-DNO/high-voltage proximity evidence.
  - 33 remain without meaningful grid evidence.
- HMLR CCOD strong ownership relationship: 1,159 sites at 85/100, backed by 1,549 unique titles.
- Remaining ownership relationships stay provisional rather than being overstated.

## Live screeners
England planning/environment point screening is active against Planning Data datasets including Green Belt, SSSI, SPA, SAC, Ramsar, ancient woodland, scheduled monuments, National Landscapes/AONB, National Parks, NNR/LNR, battlefield, listed building, conservation area and heritage coast. Results are labelled origination point screens, not parcel-level planning due diligence.

Agricultural Land Classification is populated from the complete 585-feature Planning Data England layer and the Welsh Government predictive ALC layer.

Welsh environmental screening uses DataMapWales / NRW / Cadw data for protected environmental and heritage constraints.

Topography screening is active using official Environment Agency 2m LIDAR DTM in England and Welsh Government 1m national LIDAR DTM in Wales. The score uses a 200m terrain window around the stored farm pin and records median slope, p90 slope and local relief. It is an origination ranking signal, not array design.

## Origination scoring
LandBank now separates:
- Site Potential
- Contactability
- Call Priority
- Enrichment Priority
- evidence completeness / confidence

Lower-confidence grid proximity evidence is deliberately weakened and cannot masquerade as published headroom.

Views include:
- `lb_top_100_to_call`
- `lb_enrichment_queue`
- `lb_grid_evidence`
- `lb_sales_workspace`
- `lb_sales_dashboard_metrics`
- `lb_handover_queue`

Each opportunity carries a human-readable `why_calling` evidence list.

## Sales workflow
`sales.html` is the lean sales desk. It provides:
- Today / Top 100 to call
- all-farm ranked search
- targeted enrichment queue
- qualified handover queue
- direct call / email / website / Companies House / map links
- Site Potential / Call Priority / Contactability / Ownership scores
- grid / solar / flood / planning / ALC / terrain evidence
- short origination qualification capture
- call / note / callback logging
- next-action capture
- gated `Qualify & Hand Over` action

A lead becomes handover-ready only when genuine solar-income interest, an authorised decision maker, available land and consent to share are captured.

## Export-only value model
The export model activates once available/usable acreage is captured. It uses:
- 4 acres/MW conservative capacity density
- 3 acres/MW base
- 2 acres/MW high-density
- the site's own PVGIS annual yield
- illustrative £50 / £70 / £90 per MWh export-value scenarios
- 25-year constant-price gross illustration
- provisional 10% participation pool and 20% personal share of that pool

These are origination illustrations only and not a PPA, CfD, finance, farmer-income or contractual quote. Exact finance/waterfall logic will replace assumptions when definitive terms are supplied.

## Targeted enrichment
The top 1,000 enrichment opportunities are queued in `lb_enrichment_queue_jobs`. The persistence worker is deployed but is intentionally not scheduled until provider credentials exist. It supports Companies House, Google Places and Hunter, records provenance, updates directors/company data, and promotes stronger contact points without blindly overwriting existing contacts.

Required provider secrets (not configured yet):
- `COMPANIES_HOUSE_API_KEY`
- `GOOGLE_PLACES_API_KEY`
- `HUNTER_API_KEY`

## CI / merge
Both LandBank V2 and LandBank Sales JavaScript smoke checks pass on the current development branch.

PR #1 remains deliberately unmerged. `main` stays untouched until the national screeners have matured, enrichment has run on the selected portfolio, the sales desk has been acceptance-tested and the final parity/launch check is complete.
