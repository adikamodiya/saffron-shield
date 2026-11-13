-- R4 Fallback: claims.analytics.v_metrics_by_plan — plain SQL view proving the
-- fallback path works end-to-end: one row per plan_code with all five metrics,
-- same conventions as the metric views (rejected ÷ decided; settled approved = paid;
-- earned = annual_premium/12 per active policy version per FY month).
-- Returns: plan_code, claim_count (INT), approved_amount (2-dp), rejection_rate (4-dp),
--          avg_turnaround_days (2-dp), loss_ratio (2-dp)
CREATE OR REPLACE VIEW claims.analytics.v_metrics_by_plan AS
WITH months AS (
  SELECT DISTINCT month_start
  FROM claims.analytics.dim_date
),
earned AS (
  SELECT p.plan_code,
         SUM(p.annual_premium / 12.0) AS earned_premium
  FROM claims.analytics.dim_plan p
  JOIN months m
    ON p.valid_from <= last_day(m.month_start)
   AND (p.valid_to IS NULL OR p.valid_to >= m.month_start)
  GROUP BY p.plan_code
),
claims AS (
  SELECT p.plan_code,
         COUNT(*) AS claim_count,
         SUM(f.approved_amount) AS approved_amount,
         COUNT(CASE WHEN f.status = 'rejected' THEN 1 END) AS rejected_n,
         COUNT(CASE WHEN f.status IN ('approved', 'settled', 'rejected') THEN 1 END) AS decided_n,
         AVG(f.turnaround_days) AS avg_turnaround,
         SUM(CASE WHEN f.status = 'settled' THEN f.approved_amount ELSE 0 END) AS paid_amount
  FROM claims.analytics.fact_claims f
  JOIN claims.analytics.dim_plan p ON p.plan_sk = f.plan_sk
  GROUP BY p.plan_code
)
SELECT c.plan_code,
       CAST(c.claim_count AS INT) AS claim_count,
       CAST(ROUND(c.approved_amount, 2) AS DECIMAL(15,2)) AS approved_amount,
       CAST(ROUND(c.rejected_n / c.decided_n, 4) AS DECIMAL(10,4)) AS rejection_rate,
       CAST(ROUND(c.avg_turnaround, 2) AS DECIMAL(10,2)) AS avg_turnaround_days,
       CAST(ROUND(c.paid_amount / e.earned_premium, 2) AS DECIMAL(10,2)) AS loss_ratio
FROM claims c
JOIN earned e ON e.plan_code = c.plan_code
ORDER BY c.plan_code;
