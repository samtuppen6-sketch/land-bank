#!/usr/bin/env python3
import json
import math
import os
import re
import sys
import urllib.parse
import urllib.request
from urllib.parse import urlparse

import duckdb

SUPABASE_URL = os.environ.get('SUPABASE_URL', '').rstrip('/')
SUPABASE_KEY = os.environ.get('SUPABASE_PUBLISHABLE_KEY', '').strip()
FSQ_TOKEN = os.environ.get('FOURSQUARE_OS_ACCESS_TOKEN', '').strip()
CATALOG_ENDPOINT = 'https://catalog.h3-hub.foursquare.com/iceberg'
BATCH_SIZE = int(os.environ.get('FSQ_BATCH_SIZE', '100'))
MAX_BATCHES = int(os.environ.get('FSQ_MAX_BATCHES', '2'))

STOP = {
    'LIMITED','LTD','LLP','PLC','COMPANY','CO','FARM','FARMS','FARMING','AGRICULTURE',
    'AGRICULTURAL','HOLDINGS','HOLDING','SOLAR','OPPORTUNITY','THE','AND','OF','UK'
}


def norm_pc(value):
    return re.sub(r'[^A-Z0-9]', '', (value or '').upper())


def outward_pc(value):
    p = norm_pc(value)
    return p[:-3] if len(p) > 3 else p


def norm_name(value):
    words = re.sub(r'[^A-Z0-9 ]', ' ', (value or '').upper()).split()
    return ' '.join(w for w in words if w not in STOP)


def tokens(value):
    return {w for w in norm_name(value).split() if len(w) >= 3}


def overlap(a, b):
    aa, bb = tokens(a), tokens(b)
    if not aa or not bb:
        return 0.0
    return len(aa & bb) / max(len(aa), len(bb))


def host(value):
    if not value:
        return ''
    raw = value.strip()
    if not re.match(r'^https?://', raw, re.I):
        raw = 'https://' + raw
    try:
        return (urlparse(raw).hostname or '').lower().removeprefix('www.')
    except Exception:
        return ''


def haversine_km(lat1, lon1, lat2, lon2):
    if None in (lat1, lon1, lat2, lon2):
        return None
    r = 6371.0088
    p1, p2 = math.radians(float(lat1)), math.radians(float(lat2))
    dp = math.radians(float(lat2) - float(lat1))
    dl = math.radians(float(lon2) - float(lon1))
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2*r*math.atan2(math.sqrt(a), math.sqrt(1-a))


def api(path, method='GET', payload=None):
    url = SUPABASE_URL + path
    headers = {
        'apikey': SUPABASE_KEY,
        'Authorization': 'Bearer ' + SUPABASE_KEY,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
    }
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=120) as resp:
        raw = resp.read().decode()
        return json.loads(raw) if raw else None


def fetch_jobs(limit):
    fields = ','.join([
        'job_id','opportunity_id','site_id','organisation_id','priority_score',
        'opportunity_name','organisation_name','domain','website','site_name',
        'address_line','town','county','postcode','lat','lng','decision_makers'
    ])
    query = urllib.parse.urlencode({
        'select': fields,
        'order': 'priority_score.desc.nullslast',
        'limit': str(limit),
    })
    return api('/rest/v1/lb_foursquare_work_queue?' + query) or []


def record_results(results):
    if not results:
        return None
    return api('/rest/v1/rpc/lb_record_foursquare_results', 'POST', {'p_results': results})


def attach_catalog():
    con = duckdb.connect()
    con.execute('INSTALL httpfs; LOAD httpfs;')
    con.execute('INSTALL iceberg; LOAD iceberg;')
    token_sql = FSQ_TOKEN.replace("'", "''")
    con.execute(f"CREATE OR REPLACE SECRET iceberg_secret (TYPE ICEBERG, TOKEN '{token_sql}');")
    con.execute(
        "ATTACH 'places' AS places (TYPE iceberg, SECRET iceberg_secret, "
        f"ENDPOINT '{CATALOG_ENDPOINT}');"
    )
    # Fast fail if auth/catalog/table access is wrong.
    con.execute('SELECT fsq_place_id FROM places.datasets.places_os LIMIT 1').fetchone()
    return con


def rows_for_postcodes(con, jobs):
    pcs = sorted({norm_pc(j.get('postcode')) for j in jobs if norm_pc(j.get('postcode'))})
    if not pcs:
        return []
    placeholders = ','.join(['?'] * len(pcs))
    sql = f"""
        SELECT fsq_place_id,name,latitude,longitude,address,locality,region,postcode,country,
               tel,website,email,placemaker_url,date_refreshed,unresolved_flags
        FROM places.datasets.places_os
        WHERE country='GB'
          AND date_closed IS NULL
          AND regexp_replace(upper(coalesce(postcode,'')), '[^A-Z0-9]', '', 'g') IN ({placeholders})
    """
    cur = con.execute(sql, pcs)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def rows_near_job(con, job):
    lat, lng = job.get('lat'), job.get('lng')
    if lat is None or lng is None:
        return []
    # Roughly a 3–4 km box in Great Britain. This is fallback only.
    dlat, dlng = 0.035, 0.055
    sql = """
        SELECT fsq_place_id,name,latitude,longitude,address,locality,region,postcode,country,
               tel,website,email,placemaker_url,date_refreshed,unresolved_flags
        FROM places.datasets.places_os
        WHERE country='GB' AND date_closed IS NULL
          AND latitude BETWEEN ? AND ?
          AND longitude BETWEEN ? AND ?
        LIMIT 200
    """
    cur = con.execute(sql, [float(lat)-dlat, float(lat)+dlat, float(lng)-dlng, float(lng)+dlng])
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def candidate_score(job, cand):
    flags = {str(x).lower() for x in (cand.get('unresolved_flags') or [])}
    if flags & {'closed','delete','doesnt_exist','privatevenue'}:
        return -1, None, 0.0

    target_names = [job.get('organisation_name'), job.get('site_name'), job.get('opportunity_name')]
    ov = max((overlap(n, cand.get('name')) for n in target_names if n), default=0.0)
    exact_name = any(norm_name(n) and norm_name(n) == norm_name(cand.get('name')) for n in target_names if n)
    pc = norm_pc(job.get('postcode'))
    cpc = norm_pc(cand.get('postcode'))
    dist = haversine_km(job.get('lat'), job.get('lng'), cand.get('latitude'), cand.get('longitude'))
    domain_match = bool(job.get('domain') and host(job.get('domain')) and host(job.get('domain')) == host(cand.get('website')))

    # Require identity evidence; rural postcodes often contain several unrelated POIs.
    if not (exact_name or ov >= 0.34 or domain_match):
        return -1, dist, ov

    score = 0.0
    if pc and cpc == pc:
        score += 45
    elif pc and outward_pc(cpc) == outward_pc(pc):
        score += 15
    score += ov * 35
    if exact_name:
        score += 20
    if domain_match:
        score += 25
    if dist is not None:
        if dist <= 0.5:
            score += 15
        elif dist <= 2.0:
            score += 10
        elif dist <= 5.0:
            score += 5
    return min(100, round(score, 1)), dist, ov


def match_job(job, candidates):
    scored = []
    for c in candidates:
        score, dist, ov = candidate_score(job, c)
        if score >= 0:
            scored.append((score, dist if dist is not None else 9999, ov, c))
    scored.sort(key=lambda x: (-x[0], x[1]))
    if not scored:
        return None
    best = scored[0]
    second = scored[1][0] if len(scored) > 1 else -1
    if best[0] < 72:
        return None
    if best[0] < 90 and second >= 0 and best[0] - second < 8:
        return None
    return best


def build_result(job, match):
    if not match:
        return {
            'opportunity_id': job['opportunity_id'],
            'status': 'no_contact',
            'contacts': [],
            'match_score': None,
        }
    score, dist, _ov, c = match
    source = c.get('placemaker_url') or f"https://foursquare.com/placemakers/review-place/{c.get('fsq_place_id')}"
    contacts = []
    confidence = max(70, min(95, int(round(score))))
    for typ, field in [('phone','tel'),('email','email'),('website','website')]:
        value = (c.get(field) or '').strip() if isinstance(c.get(field), str) else c.get(field)
        if value:
            contacts.append({'type': typ, 'value': str(value), 'confidence': confidence, 'source_url': source})
    return {
        'opportunity_id': job['opportunity_id'],
        'status': 'completed' if contacts else 'no_contact',
        'contacts': contacts,
        'fsq_place_id': c.get('fsq_place_id'),
        'match_score': score,
        'matched_name': c.get('name'),
        'matched_postcode': c.get('postcode'),
        'distance_km': None if dist is None else round(dist, 3),
        'source_url': source,
    }


def process_batch(con, jobs):
    postcode_rows = rows_for_postcodes(con, jobs)
    by_pc = {}
    for row in postcode_rows:
        by_pc.setdefault(norm_pc(row.get('postcode')), []).append(row)

    results = []
    spatial_fallbacks = 0
    for job in jobs:
        cands = by_pc.get(norm_pc(job.get('postcode')), [])
        match = match_job(job, cands)
        if not match and spatial_fallbacks < 20:
            spatial_fallbacks += 1
            match = match_job(job, rows_near_job(con, job))
        results.append(build_result(job, match))
    return results


def main():
    if not FSQ_TOKEN:
        print('FOURSQUARE_OS_ACCESS_TOKEN is not configured in GitHub Actions; skipping Foursquare enrichment.')
        return 0
    if not SUPABASE_URL or not SUPABASE_KEY:
        raise RuntimeError('SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY missing')

    print('Connecting to Foursquare OS Places Iceberg catalog…')
    con = attach_catalog()
    total_jobs = total_contacts = 0
    for n in range(MAX_BATCHES):
        jobs = fetch_jobs(BATCH_SIZE)
        if not jobs:
            print('No queued Foursquare jobs remain.')
            break
        print(f'Batch {n+1}: matching {len(jobs)} LandBank targets.')
        results = process_batch(con, jobs)
        matched = sum(1 for r in results if r.get('fsq_place_id'))
        contacts = sum(len(r.get('contacts') or []) for r in results)
        outcome = record_results(results)
        total_jobs += len(results)
        total_contacts += contacts
        print(f'Batch {n+1}: matched={matched}, contacts_submitted={contacts}, database={outcome}')
    print(f'Foursquare enrichment complete: jobs={total_jobs}, contacts_submitted={total_contacts}.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print(f'Foursquare enrichment failed: {type(exc).__name__}: {exc}', file=sys.stderr)
        sys.exit(1)
