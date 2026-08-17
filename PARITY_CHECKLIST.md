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
- [ ] County filter in opportunity list.
- [ ] User-selectable sort (priority/name/contact/land/stage/next action).

## Map
- [x] Leaflet map.
- [x] Marker clustering.
- [x] Click through from map to opportunity.
- [x] Land-size filtering.
- [x] County filtering.
- [x] V2 adds priority/contact/stage/land map modes.
- [ ] Detail-level map/location convenience link.

## Prospect / opportunity workspace
- [x] Company/farm/address/company number.
- [x] Decision-maker capture.
- [x] Phone/email/website visibility.
- [x] Land size / ownership / occupier capture.
- [x] Pipeline stage editing.
- [x] Next action + date.
- [x] Qualification and electricity/site fields.
- [x] Technical/commercial intelligence sections.
- [ ] Direct tap-to-call.
- [ ] Direct mailto.
- [ ] Website link.
- [ ] Companies House link.
- [ ] Google/location search link.
- [ ] Notes/call logging.
- [ ] Callback creation.
- [ ] Activity/history timeline.

## Callback workflow
- [ ] Dedicated callbacks screen.
- [ ] Overdue/due-soon styling.
- [ ] Open callback into opportunity.
- [ ] Mark callback complete.
- [x] Dashboard already has actions-due metric.

## Existing data behaviour
- [x] Existing production CRM tables left untouched.
- [x] V2 keeps provenance snapshots of imported JSON data.
- [x] Browser cannot delete opportunities or mutate source site records.
- [ ] Final side-by-side manual acceptance test before merge.

## V2-only improvements already present
- [x] Separate sites / organisations / contacts / opportunities / qualification model.
- [x] Expanded solar-origination pipeline.
- [x] Priority, ownership, technical and commercial scoring structure.
- [x] Data-gap queue / next-best-action logic.
- [x] PostGIS foundation.
- [x] PVGIS + Planning Data assessment function.
- [x] Contact-enrichment waterfall function.
- [x] Probability-weighted pipeline architecture.

**Merge rule:** PR #1 stays open until all unchecked production-parity items are completed or explicitly marked as superseded and the final acceptance test passes.
