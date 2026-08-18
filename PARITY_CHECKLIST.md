# LandBank — Production vs V2 Feature Parity

This checklist prevents V2 replacing `main` until every useful production workflow is either reproduced or deliberately superseded by a better V2 workflow.

## Core access / data
- [x] PIN gate retained for current single-user workflow.
- [x] Existing farm/company universe retained.
- [x] Existing contact enrichment retained and migrated.
- [x] Supabase persistence retained and expanded.

## Prospect / opportunity list
- [x] Search by company/farm/location.
- [x] Contactability filtering.
- [x] Minimum land/parcel filtering.
- [x] Pipeline/stage filtering.
- [x] Priority ranking.
- [x] County filter in opportunity list.
- [x] User-selectable sort: priority / name / contact / land / stage / next action.

## Map
- [x] Leaflet map.
- [x] Marker clustering.
- [x] Click through from map to opportunity.
- [x] Land-size filtering.
- [x] County filtering.
- [x] V2 adds priority/contact/stage/land/technical map modes.
- [x] Detail-level location convenience retained via direct map/location link (supersedes the old mini-map without removing national Intelligence Map capability).

## Prospect / opportunity workspace
- [x] Company/farm/address/company number.
- [x] Decision-maker capture.
- [x] Phone/email/website visibility.
- [x] Land size / ownership / occupier capture.
- [x] Pipeline stage editing.
- [x] Next action + date.
- [x] Qualification and electricity/site fields.
- [x] Technical/commercial intelligence sections.
- [x] Direct tap-to-call.
- [x] Direct mailto.
- [x] Website link.
- [x] Companies House link.
- [x] Google/location search link.
- [x] Notes/call logging.
- [x] Callback creation.
- [x] Activity/history timeline including stage changes.

## Callback workflow
- [x] Dedicated callbacks screen.
- [x] Overdue/due-soon styling.
- [x] Open callback into opportunity.
- [x] Mark callback complete.
- [x] Dashboard actions-due metric includes opportunity actions and overdue callbacks.

## Existing data behaviour
- [x] Existing production CRM tables left untouched.
- [x] V2 keeps provenance snapshots of imported JSON data.
- [x] Browser cannot delete opportunities or mutate source site records.
- [x] Browser-role callback insert/update tested in a rolled-back database integration test.
- [x] V2 app candidate JavaScript passed automated GitHub smoke parsing.
- [ ] Final side-by-side human acceptance test before merge.

## V2-only improvements already present
- [x] Separate sites / organisations / contacts / opportunities / qualification model.
- [x] Expanded solar-origination pipeline.
- [x] Priority, ownership, technical and commercial scoring structure.
- [x] Data-gap queue / next-best-action logic.
- [x] PostGIS foundation.
- [x] PVGIS + Planning Data assessment function.
- [x] Contact-enrichment waterfall function.
- [x] Probability-weighted pipeline architecture.

**Step 1 engineering status: COMPLETE.** Final human acceptance remains intentionally deferred until the V2 build has progressed further and before any merge into `main`.

**Merge rule:** PR #1 stays open until the final acceptance test passes.
