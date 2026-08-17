# LandBank V2 — Live Build Status

## Live Supabase state

Project: `solar-canvass-proxy` (`xdoqclrwdduncjaxtixp`)

Current imported source universe:
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

Source snapshots are retained in `lb_import_snapshots` for provenance and are not browser-readable.

## Live application layer

`v2-live.html` is the Supabase-backed V2 CRM interface. It supports:
- live dashboard metrics
- priority-ranked opportunity list
- pipeline view
- intelligence map
- data-gap queue
- opportunity workspace
- stage/probability updates
- next-action + next-action date
- decision maker and qualification capture
- acreage / usable acreage / ownership confirmation
- electricity consumption, annual cost, tariff, MPAN, peak demand and three-phase fields
- farmer objective and repayment-preference capture
- evidence flags for bills, HH data, LOA, terms and heads of terms
- stage-history logging

The browser can read the V2 workspace and update CRM/qualification workflow records but cannot delete opportunities, edit source site records or read raw import snapshots.

## Live enrichment functions

### `enrich-prospect`
Server-side contact enrichment adapter for:
1. Companies House
2. Google Places
3. Hunter

Provider credentials still need to be configured before those providers can run live.

### `assess-site`
Open-data technical screening for:
1. PVGIS 5.3 solar yield
2. Planning Data point constraints

The first live test was run on A L LEE FARMING COMPANY, Cambridgeshire:
- 108 source parcels
- PVGIS annual yield: 1,035.37 kWh/kWp/year
- PVGIS prioritisation score: 81.5
- Planning point-screen score: 100 (no queried point constraints returned)
- Partial technical site score: 92.6

Important: the planning result is a point screen, not parcel-level due diligence. An absence of returned entities is not proof that a whole site is constraint-free.

## Scoring rule

Missing intelligence is **unknown**, not zero. Weighted scores use only components with actual evidence and become more complete as grid, planning, land, agricultural, topography, solar and ownership layers are populated.

## Next technical blocks

1. Bulk Planning Data / environmental spatial overlays in PostGIS for national screening.
2. DNO/grid-capacity data normalization and Grid Score.
3. Agricultural Land Classification + environmental/MAGIC-style overlays.
4. Ownership/title confidence using HMLR/INSPIRE source layers.
5. Configure contact-enrichment API credentials and process high-priority unresolved prospects.
6. Commercial/finance engine after exact funding waterfall and contractual revenue definitions are confirmed.

## Merge status

Do not merge PR #1 yet. `main` remains the current production version while V2 is developed and tested on `landbank-v2-foundation`.
