-- Additive LandBank project-execution workbench: no changes to legacy lead, budget or outreach tables.
CREATE TABLE IF NOT EXISTS public.lb_project_execution (
  asset_id uuid PRIMARY KEY REFERENCES public.lb_acq_assets(id) ON DELETE RESTRICT,
  project_stage text NOT NULL DEFAULT 'screening'
    CHECK (project_stage IN ('screening','site_diligence','partner_shortlist','commercial_terms','documents','execution','closed','on_hold')),
  landowner_consent text NOT NULL DEFAULT 'unconfirmed'
    CHECK (landowner_consent IN ('unconfirmed','requested','documented','denied')),
  land_control text NOT NULL DEFAULT 'unconfirmed'
    CHECK (land_control IN ('unconfirmed','under_discussion','option_signed','lease_signed','purchase_signed')),
  introducer_rights_review text NOT NULL DEFAULT 'pending'
    CHECK (introducer_rights_review IN ('pending','cleared','restricted')),
  exclusivity_review text NOT NULL DEFAULT 'pending'
    CHECK (exclusivity_review IN ('pending','cleared','restricted')),
  financial_promotions_review text NOT NULL DEFAULT 'pending'
    CHECK (financial_promotions_review IN ('pending','cleared','restricted')),
  project_disclosure_approved boolean NOT NULL DEFAULT false,
  required_devex_gbp numeric(15,2) CHECK(required_devex_gbp IS NULL OR required_devex_gbp>=0),
  land_rights_evidence_ref text,
  permission_evidence_ref text,
  legal_review_ref text,
  planned_spv_structure text,
  originator_economics_status text NOT NULL DEFAULT 'unnegotiated'
    CHECK (originator_economics_status IN ('unnegotiated','under_discussion','heads_of_terms','signed')),
  originator_terms_ref text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lb_project_disclosure_gate CHECK (
    NOT project_disclosure_approved OR
    (landowner_consent='documented'
      AND introducer_rights_review='cleared'
      AND exclusivity_review='cleared'
      AND financial_promotions_review='cleared'
      AND permission_evidence_ref IS NOT NULL
      AND legal_review_ref IS NOT NULL)
  )
);
CREATE TABLE IF NOT EXISTS public.lb_project_partner_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id uuid NOT NULL REFERENCES public.lb_acq_assets(id) ON DELETE RESTRICT,
  organisation_id uuid NOT NULL REFERENCES public.lb_partner_organisations(id) ON DELETE RESTRICT,
  partner_lane text NOT NULL CHECK (partner_lane IN ('capital','delivery')),
  stage text NOT NULL DEFAULT 'researched'
    CHECK (stage IN ('researched','mandate_qualified','approved_to_contact','contacted','engaged','terms_discussion','contract_signed','declined')),
  partner_mandate_verified boolean NOT NULL DEFAULT false,
  counterparty_reply_verified boolean NOT NULL DEFAULT false,
  structure_under_discussion text,
  signed_document_ref text,
  contract_signed_at date,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT lb_project_partner_unique UNIQUE (asset_id,organisation_id,partner_lane),
  CONSTRAINT lb_partner_signed_document_gate CHECK(
    stage <> 'contract_signed' OR (signed_document_ref IS NOT NULL AND contract_signed_at IS NOT NULL)
  )
);
CREATE INDEX IF NOT EXISTS lb_partner_assignments_asset_idx ON public.lb_project_partner_assignments(asset_id);
CREATE INDEX IF NOT EXISTS lb_partner_assignments_org_idx ON public.lb_project_partner_assignments(organisation_id);
ALTER TABLE public.lb_project_execution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lb_project_partner_assignments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lb_project_execution FROM anon;
REVOKE ALL ON public.lb_project_partner_assignments FROM anon;
GRANT SELECT,INSERT,UPDATE ON public.lb_project_execution TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.lb_project_partner_assignments TO authenticated;
DROP POLICY IF EXISTS lb_project_execution_team ON public.lb_project_execution;
CREATE POLICY lb_project_execution_team ON public.lb_project_execution
  FOR ALL TO authenticated
  USING ((SELECT private.lb_access_allowed()))
  WITH CHECK ((SELECT private.lb_access_allowed()));
DROP POLICY IF EXISTS lb_project_partner_team ON public.lb_project_partner_assignments;
CREATE POLICY lb_project_partner_team ON public.lb_project_partner_assignments
  FOR ALL TO authenticated
  USING ((SELECT private.lb_access_allowed()))
  WITH CHECK ((SELECT private.lb_access_allowed()));
COMMENT ON TABLE public.lb_project_execution IS 'Independent development diligence and rights gates; never evidence of capital commitment';
COMMENT ON TABLE public.lb_project_partner_assignments IS 'Research and negotiation status only; contract_signed requires user-supplied evidence reference, never automatically verifies capital availability';

-- Restrict the new workbench to the existing LandBank authorised team; no table deletes.
REVOKE ALL ON public.lb_project_execution FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.lb_project_partner_assignments FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.lb_project_execution TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.lb_project_partner_assignments TO authenticated;
DROP POLICY IF EXISTS lb_project_execution_team ON public.lb_project_execution;
DROP POLICY IF EXISTS lb_project_partner_team ON public.lb_project_partner_assignments;
CREATE POLICY lb_project_execution_read ON public.lb_project_execution FOR SELECT TO authenticated
 USING ((SELECT private.lb_access_allowed()));
CREATE POLICY lb_project_execution_insert ON public.lb_project_execution FOR INSERT TO authenticated
 WITH CHECK ((SELECT private.lb_access_allowed()));
CREATE POLICY lb_project_execution_update ON public.lb_project_execution FOR UPDATE TO authenticated
 USING ((SELECT private.lb_access_allowed())) WITH CHECK ((SELECT private.lb_access_allowed()));
CREATE POLICY lb_project_partner_read ON public.lb_project_partner_assignments FOR SELECT TO authenticated
 USING ((SELECT private.lb_access_allowed()));
CREATE POLICY lb_project_partner_insert ON public.lb_project_partner_assignments FOR INSERT TO authenticated
 WITH CHECK ((SELECT private.lb_access_allowed()));
CREATE POLICY lb_project_partner_update ON public.lb_project_partner_assignments FOR UPDATE TO authenticated
 USING ((SELECT private.lb_access_allowed())) WITH CHECK ((SELECT private.lb_access_allowed()));
