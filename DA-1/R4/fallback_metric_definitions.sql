-- R4 Fallback: claims.analytics.metric_definitions — the metric dictionary.
-- Exactly 5 rows: the four contested claim KPIs + loss_ratio, each with its exact
-- expression and source, so any tool can re-derive the number the governed way.
CREATE OR REPLACE TABLE claims.analytics.metric_definitions AS
SELECT * FROM VALUES
  ('claim_count',
   'COUNT(*)',
   'claims.analytics.fact_claims',
   'Number of claims, all statuses; groupable by plan_code, city_tier, hospital_id, claim_type, admission_month'),
  ('approved_amount',
   'SUM(approved_amount)',
   'claims.analytics.fact_claims',
   'Sum of approved amounts (set on approved and settled claims)'),
  ('rejection_rate',
   'COUNT(*) FILTER (WHERE status = ''rejected'') / COUNT(*) FILTER (WHERE status IN (''approved'', ''settled'', ''rejected''))',
   'claims.analytics.fact_claims',
   'Rejected claims over DECIDED claims; submitted (awaiting decision) claims are excluded from both sides'),
  ('avg_turnaround_days',
   'AVG(turnaround_days)',
   'claims.analytics.fact_claims',
   'Mean submission-to-decision days; submitted claims carry no turnaround and are ignored'),
  ('loss_ratio',
   'SUM(paid_amount) / SUM(earned_premium)',
   'claims.analytics.mv_loss_ratio (R3 w01 monthly figures: paid = settled approved_amount; earned = annual_premium/12 per active policy version)',
   'Paid claims over earned premium; groupable by plan_code and month_start')
AS t(metric_name, expression, source, description);
