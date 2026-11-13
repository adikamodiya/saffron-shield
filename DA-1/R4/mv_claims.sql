-- R4: metric view claims.analytics.mv_claims — single source of truth for the
-- four contested claim KPIs, groupable by plan_code, city_tier, hospital_id,
-- claim_type, admission_month.
-- REJECTION RULE (spec): rejected ÷ decided. Decided = approved + settled + rejected.
-- 'submitted' claims await a decision and belong on NEITHER side of the fraction.
-- Sample queries (dashboard / Genie / one-off all read the same measures):
--   SELECT `plan_code`, MEASURE(`claim_count`) AS claim_count,
--          MEASURE(`rejection_rate`) AS rejection_rate
--   FROM claims.analytics.mv_claims GROUP BY ALL;
--   SELECT date_trunc('MONTH', `admission_month`) AS month, MEASURE(`approved_amount`) AS approved_amount
--   FROM claims.analytics.mv_claims GROUP BY ALL ORDER BY month;
CREATE OR REPLACE VIEW claims.analytics.mv_claims
WITH METRICS
LANGUAGE YAML
AS $$
  version: 1.1
  comment: >
    Claim KPIs defined exactly once: claim_count, approved_amount, rejection_rate,
    avg_turnaround_days — groupable by plan, city tier, hospital, claim type and
    admission month. rejection_rate = rejected / decided, where decided =
    approved + settled + rejected; submitted claims belong on neither side.
  source: claims.analytics.fact_claims
  joins:
    - name: dim_plan
      source: claims.analytics.dim_plan
      on: source.plan_sk = dim_plan.plan_sk
      cardinality: many_to_one
      rely:
        at_most_one_match: true
    - name: dim_hospital
      source: claims.analytics.dim_hospital
      on: source.hospital_sk = dim_hospital.hospital_sk
      cardinality: many_to_one
      rely:
        at_most_one_match: true
    - name: dim_date
      source: claims.analytics.dim_date
      on: source.admission_date_key = dim_date.date_key
      cardinality: many_to_one
      rely:
        at_most_one_match: true
  dimensions:
    - name: plan_code
      expr: dim_plan.plan_code
    - name: city_tier
      expr: dim_hospital.city_tier
    - name: hospital_id
      expr: dim_hospital.hospital_id
    - name: claim_type
      expr: source.claim_type
    - name: admission_month
      expr: date_trunc('MONTH', dim_date.full_date)
      format:
        type: date
        date_format: year_month_day
  measures:
    - name: claim_count
      expr: COUNT(1)
    - name: approved_amount
      expr: SUM(source.approved_amount)
      comment: Sum of approved amounts (approved_amount is set on approved/settled claims)
    - name: rejection_rate
      expr: COUNT(1) FILTER (WHERE source.status = 'rejected') /
            NULLIF(COUNT(1) FILTER (WHERE source.status IN ('approved', 'settled', 'rejected')), 0)
      comment: >
        rejected claims / decided claims (approved + settled + rejected).
        Submitted (awaiting decision) claims are excluded from BOTH sides.
      format:
        type: percentage
        decimal_places:
          type: exact
          places: 2
    - name: avg_turnaround_days
      expr: AVG(source.turnaround_days)
      comment: Mean submission-to-decision days; submitted claims carry no turnaround yet and are ignored by AVG
      format:
        type: number
        decimal_places:
          type: exact
          places: 2
$$;
