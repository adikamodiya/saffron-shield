-- R3 w01: monthly paid vs earned premium and loss ratio per plan
-- Returns: plan_code, month_start (DATE), paid_amount (2-dp), earned_premium (2-dp), loss_ratio (2-dp)
-- Saved query clone: claims.analytics.w01 (SQL editor)
-- Convention: paid_amount = approved_amount of SETTLED claims (admission month);
--             earned_premium = annual_premium/12 per policy version active in the month.
WITH months AS (
  SELECT DISTINCT month_start
  FROM claims.analytics.dim_date
),
earned AS (
  SELECT p.plan_code, m.month_start,
         SUM(p.annual_premium / 12.0) AS earned_premium
  FROM claims.analytics.dim_plan p
  JOIN months m
    ON p.valid_from <= last_day(m.month_start)
   AND (p.valid_to IS NULL OR p.valid_to >= m.month_start)
  GROUP BY p.plan_code, m.month_start
),
paid AS (
  SELECT p.plan_code, d.month_start,
         SUM(f.approved_amount) AS paid_amount
  FROM claims.analytics.fact_claims f
  JOIN claims.analytics.dim_plan p ON p.plan_sk = f.plan_sk
  JOIN claims.analytics.dim_date d ON d.date_key = f.admission_date_key
  WHERE f.status = 'settled'
  GROUP BY p.plan_code, d.month_start
)
SELECT e.plan_code,
       e.month_start,
       CAST(ROUND(paid.paid_amount, 2) AS DECIMAL(15,2)) AS paid_amount,
       CAST(ROUND(e.earned_premium, 2) AS DECIMAL(15,2)) AS earned_premium,
       CAST(ROUND(paid.paid_amount / e.earned_premium, 2) AS DECIMAL(10,2)) AS loss_ratio
FROM earned e
JOIN paid
  ON paid.plan_code = e.plan_code
 AND paid.month_start = e.month_start
ORDER BY e.plan_code, e.month_start;
