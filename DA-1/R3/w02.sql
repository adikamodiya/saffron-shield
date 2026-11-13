-- R3 w02: monthly loss ratio per plan + rolling 3-month loss ratio
-- Returns: plan_code, month_start (DATE), loss_ratio (2-dp), rolling_3m_loss_ratio (2-dp)
-- Saved query clone: claims.analytics.w02 (SQL editor)
-- Convention: rolling_3m = SUM(paid over 3 months) / SUM(earned over 3 months),
--             frame = current month + 2 preceding (per plan, ordered by month_start).
WITH monthly AS (
  -- w01 result, kept at paid/earned grain so the rolling window sums amounts (not ratios)
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
  SELECT e.plan_code, e.month_start,
         paid.paid_amount, e.earned_premium,
         CAST(ROUND(paid.paid_amount / e.earned_premium, 2) AS DECIMAL(10,2)) AS loss_ratio
  FROM earned e
  JOIN paid
    ON paid.plan_code = e.plan_code
   AND paid.month_start = e.month_start
)
SELECT plan_code,
       month_start,
       loss_ratio,
       CAST(ROUND(SUM(paid_amount) OVER w / SUM(earned_premium) OVER w, 2) AS DECIMAL(10,2)) AS rolling_3m_loss_ratio
FROM monthly
WINDOW w AS (
  PARTITION BY plan_code
  ORDER BY month_start
  ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
)
ORDER BY plan_code, month_start;
