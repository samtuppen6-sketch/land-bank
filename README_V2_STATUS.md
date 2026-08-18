# LandBank V2 — Live Build Status

## Live Supabase state

Project: `solar-canvass-proxy` (`xdoqclrwdduncjaxtixp`)

Current source universe:
- 6,425 organisations
- 6,425 sites
- 6,425 opportunities
- 6,425 qualification records
- 654 contact-ready opportunities
- 5,771 identified / enrichment-needed opportunities
- 668 phone/mobile records
- 320 email records
- 335 website records
- 19,983 source land parcels represented

Source snapshots are retained in `lb_import_snapshots` for provenance and are not browser-readable.

## Commercial model

The current solar proposition is **100% grid export for farm income**. The core financial model must not use self-consumption or electricity-bill-offset savings as project revenue.

The later financial engine will model:
`MWp -> annual MWh -> grid export price -> gross generation revenue -> finance repayment allocation -> farmer income -> long-term participation / commission`.

Export-price assumptions must remain adjustable scenarios, not guaranteed forecasts.

## Live V2 application layer

The V2 Supabase-backed CRM includes:
- dashboard metrics
- priority-ranked opportunities
- pipeline
- intelligence map
- callbacks and activity history
- data-gap workflow
- opportunity workspace
- stage / probability / next-action management
- decision-maker and qualification capture
- acreage and land notes
- technical scores and evidence coverage

The browser can read V2 workspace data and update intended CRM/qualification workflow records, but cannot delete opportunities, edit source site records or read raw import snapshots.

## Task 1 — CCOD / HMLR corporate ownership: COMPLETE

The August 2026 HMLR CCOD full file was screened against the LandBank universe and then exact-verified in Supabase using normalized Companies House number + farm postcode.

Permanent result:
- 1,159 sites with strong HMLR-backed corporate ownership relationship evidence
- 1,549 unique HMLR titles stored
- 1,549 ownership-evidence records
- 1,159 probable-owner site-party links
- ownership score 85/100 for the strong cohort
- remaining 5,266 sites remain provisional rather than being falsely upgraded

`85/100` means a strong corporate/title relationship. It is **not** the same as proving that the target solar field lies inside that exact registered title.

## Task 2 — HMLR spatial ownership: IN PROGRESS

LandBank now has a targeted HMLR INSPIRE spatial worker for the 1,159 strong CCOD sites.

Architecture:
1. Query the open HMLR INSPIRE WMS around the stored LandBank point.
2. Parse returned KML polygons.
3. Use PostGIS for exact point/polygon intersection.
4. Store the INSPIRE polygon geometry and identifier as supporting spatial evidence.
5. Keep ownership at 85 unless the INSPIRE identifier is separately resolved to a registered title number that matches the same CCOD corporate proprietor.
6. Only that full chain can promote a site to 100/100 ownership confidence.

Important limitation: the current LandBank coordinate can represent a farmhouse, office or company location. A point intersection therefore does **not** prove that every agricultural field represented by the aggregate farm record is owned by the same party or suitable for solar. The original source contains title/land counts and sample descriptions, not the underlying parcel geometries.

The automated INSPIRE queue is active in Supabase. After clean larger-batch testing it is currently scheduled at 10 strong-ownership sites per minute.

Frontend workspace data now exposes:
- ownership status
- CCOD title count
- INSPIRE point-hit count
- resolved spatial-title count
- HMLR title references
- INSPIRE identifiers

### Exact-title dependency

The open INSPIRE feed does not publish title numbers. The full HMLR National Polygon Service does, but is a paid licensed dataset. HMLR Business e-services / Business Gateway can return title numbers by property description for approved customers. LandBank already has `lb_inspire_title_resolution` and `lb_apply_inspire_title_resolutions()` ready so any legitimate title-resolution source can be plugged in without changing the ownership model.

A third-party address/title-boundary lookup should not automatically be treated as proof of the intended solar field if the stored LandBank point is only a farmhouse or office location.

## Ownership confidence ladder

- 45: provisional legacy farm/company relationship
- 70: supporting open INSPIRE point/polygon evidence (does not override stronger evidence)
- 85: strong HMLR CCOD company + property-postcode relationship
- 100: exact registered title + corporate proprietor + spatial polygon chain confirmed

## Technical screening status

LandBank has live workers / data structures for:
- PVGIS solar yield
- exact-point flood screening
- Planning Data bulk constraints
- DNO/grid normalization and multiple DNO adapters
- technical evidence completeness

Missing intelligence is **unknown**, not zero. A high partial score must be read with its evidence coverage rather than treated as complete due diligence.

## Contact enrichment

`enrich-prospect` provides a server-side waterfall for Companies House, Google Places and Hunter. Provider credentials still need to be configured before paid/provider enrichment is run at scale. Enrichment should be targeted at the best opportunities after technical ranking rather than blindly spent across all 6,425 sites.

## Remaining build order

1. Finish Task 2 open spatial screening and choose the pragmatic exact-title resolution route.
2. Complete national DNO/grid coverage.
3. Complete planning, Agricultural Land Classification, environmental and topography screening.
4. Re-score the full 6,425-site universe on populated evidence.
5. Targeted contact enrichment for the best opportunities.
6. Build the 100%-export Farmer Proposition / No-Brainer engine.
7. Build scenario-based financial forecasting and farmer/participation value.
8. Build farmer proposal output and risk/responsibility matrix.
9. Run a 50–100-farm sales pilot.
10. Final parity/acceptance test, then merge V2 deliberately.

## Merge status

Do not merge PR #1 yet. `main` remains untouched while V2 continues on `landbank-v2-foundation`.
