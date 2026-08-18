/* LandBank v2 scoring engine
 * Transparent, auditable scores. No black-box AI required.
 * Every score is 0-100 and can be reweighted as real conversion data accumulates.
 */
(function(root, factory){
  if(typeof module === 'object' && module.exports) module.exports = factory();
  else root.LandBankScoring = factory();
})(typeof self !== 'undefined' ? self : this, function(){
  'use strict';

  function clamp(n, min, max){
    n = Number(n);
    if(!Number.isFinite(n)) return 0;
    return Math.max(min, Math.min(max, n));
  }
  function pct(n){ return clamp(n, 0, 100); }
  function weighted(parts){
    var totalWeight = 0, total = 0;
    Object.keys(parts).forEach(function(k){
      var p = parts[k];
      // Missing intelligence is unknown, not zero. Exclude it until evidence exists.
      if(p && p.score !== null && p.score !== undefined && p.score !== '' &&
         Number.isFinite(Number(p.score)) && Number.isFinite(Number(p.weight))){
        totalWeight += Number(p.weight);
        total += pct(p.score) * Number(p.weight);
      }
    });
    return totalWeight ? Math.round((total / totalWeight) * 10) / 10 : null;
  }

  // Feasibility: can this realistically become a useful solar project?
  function siteFeasibility(input){
    input = input || {};
    return weighted({
      grid:        {score: input.grid_score,          weight: 25},
      land:        {score: input.land_score,          weight: 20},
      planning:    {score: input.planning_score,      weight: 15},
      agricultural:{score: input.agricultural_score,  weight: 10},
      topography:  {score: input.topography_score,    weight: 10},
      solar:       {score: input.solar_score,         weight: 10},
      ownership:   {score: input.ownership_score,     weight: 10}
    });
  }

  // Sales readiness: how close are we to being able to progress this opportunity?
  function salesReadiness(input){
    input = input || {};
    var score = 0;
    if(input.owner_confirmed) score += 20;
    if(input.decision_maker_identified) score += 15;
    if(input.verified_direct_phone) score += 15;
    if(input.verified_email) score += 10;
    if(input.domain_verified) score += 5;
    if(input.connected) score += 10;
    if(input.interest_established) score += 10;
    if(input.acreage_confirmed) score += 5;
    if(input.consumption_data_obtained) score += 5;
    if(input.next_action_booked) score += 5;
    return pct(score);
  }

  // Ownership confidence: deliberately conservative because director/operator != owner.
  function ownershipConfidence(input){
    input = input || {};
    if(input.title_owner_confirmed) return 100;
    if(input.corporate_title_relationship_confirmed) return 85;
    if(input.registered_address_and_company_match) return 65;
    if(input.probable_operator_match) return 45;
    if(input.speculative_match) return 20;
    return 0;
  }

  function contactability(input){
    input = input || {};
    return weighted({
      phone: {score: input.phone_verified ? 100 : input.phone_present ? 55 : null, weight: 35},
      email: {score: input.email_verified ? 100 : input.email_present ? 45 : null, weight: 25},
      person:{score: input.decision_maker_identified ? 100 : input.director_identified ? 65 : null, weight: 25},
      source:{score: input.source_confidence == null ? null : input.source_confidence, weight: 15}
    });
  }

  // Commercial score is deliberately parameterised; finance assumptions live elsewhere.
  function commercialScore(input){
    input = input || {};
    var mwpScore = input.potential_mwp == null ? null : pct((Number(input.potential_mwp) / Number(input.target_mwp || 10)) * 100);
    var consumptionScore = input.self_consumption_pct == null ? null : pct(Number(input.self_consumption_pct));
    var valueScore = input.estimated_personal_25y_commission == null ? null : pct((Number(input.estimated_personal_25y_commission) / Number(input.target_personal_25y_commission || 250000)) * 100);
    var paybackYears = input.estimated_repayment_years == null ? null : Number(input.estimated_repayment_years);
    var paybackScore = paybackYears && paybackYears > 0 ? pct(100 - Math.max(0, paybackYears - 3) * 12.5) : null;
    return weighted({
      mwp:         {score:mwpScore,          weight:30},
      consumption: {score:consumptionScore,  weight:20},
      value:       {score:valueScore,        weight:35},
      payback:     {score:paybackScore,      weight:15}
    });
  }

  // Priority answers: where should the next hour go?
  function priorityScore(input){
    input = input || {};
    return weighted({
      site:       {score:input.site_score,        weight:35},
      commercial: {score:input.commercial_score,  weight:30},
      sales:      {score:input.sales_score,        weight:20},
      contact:    {score:input.contact_score,      weight:10},
      ownership:  {score:input.ownership_score,    weight:5}
    });
  }

  function probabilityWeightedValue(value, probabilityPct){
    return Math.round(Number(value || 0) * pct(probabilityPct) / 100 * 100) / 100;
  }

  function stageProbability(stage){
    var map = {
      identified: 3,
      researching: 5,
      contact_ready: 8,
      outreach_started: 10,
      connected: 15,
      qualified_interest: 25,
      site_data_requested: 30,
      site_prescreen: 35,
      commercial_assessment: 45,
      proposal: 55,
      site_visit: 60,
      heads_of_terms: 70,
      technical_dd: 75,
      grid_planning: 80,
      finance_approval: 88,
      contracted: 95,
      construction: 98,
      commissioned: 100,
      live: 100,
      closed_lost: 0
    };
    return map[stage] == null ? 0 : map[stage];
  }

  function nextBestAction(record){
    record = record || {};
    if(!record.owner_confidence || record.owner_confidence < 60) return 'Confirm legal/beneficial ownership';
    if(!record.decision_maker_identified) return 'Identify decision maker';
    if(!record.phone_present && !record.email_present) return 'Enrich contact details';
    if(!record.connected) return 'Make first contact';
    if(!record.interest_established) return 'Qualify interest and decision process';
    if(!record.acreage_confirmed) return 'Confirm usable acreage';
    if(!record.consumption_data_obtained) return 'Obtain electricity consumption / bill data';
    if(!record.site_prescreen_complete) return 'Run site/grid/planning pre-screen';
    if(!record.financial_scenario_complete) return 'Build commercial scenario';
    if(!record.proposal_sent) return 'Prepare and send proposal / indicative terms';
    if(!record.next_action_at) return 'Book next action';
    return record.next_action || 'Follow next scheduled action';
  }

  return {
    siteFeasibility: siteFeasibility,
    salesReadiness: salesReadiness,
    ownershipConfidence: ownershipConfidence,
    contactability: contactability,
    commercialScore: commercialScore,
    priorityScore: priorityScore,
    probabilityWeightedValue: probabilityWeightedValue,
    stageProbability: stageProbability,
    nextBestAction: nextBestAction
  };
});
