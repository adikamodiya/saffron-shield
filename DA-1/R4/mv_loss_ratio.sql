-- R4: metric view claims.analytics.mv_loss_ratio — loss-ratio KPIs defined once,
-- built FROM the R3 w01 monthly paid/earned figures (same monthly CTE), not recomputed
-- from claim grain. Groupable by plan_code and month_start.
-- Sample queries:
--   SELECT `plan_code`, MEASURE(`loss_ratio`) AS loss_ratio
--   FROM claims.analytics.mv_loss_ratio GROUP BY ALL;
--   SELECT `plan_code`, `month_start`, MEASURE(`paid_amount`), MEASURE(`earned_premium`), MEASURE(`loss_ratio`)
--   FROM claims.analytics.mv_loss_ratio GROUP BY ALL ORDER BY `month_start`;
CREATE OR REPLACE VIEW claims.analytics.mv_loss_ratio
WITH METRICS
LANGUAGE YAML
AS $$
  version: 1.1
  comment: >
    Loss ratio by plan and month, layered on the R3 w01 monthly figures
    (paid = approved_amount of settled claims; earned = annual_premium/12 per
    policy version active in the month).
  source: |-
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
    SELECT e.plan_code, e.month_start, paid.paid_amount, e.earned_premium
    FROM earned e
    JOIN paid
      ON paid.plan_code = e.plan_code
     AND paid.month_start = e.month_start
  dimensions:
    - name: plan_code
      expr: plan_code
    - name: month_start
      expr: month_start
      format:
        type: date
        date_format: year_month_day
  measures:
    - name: paid_amount
      expr: SUM(paid_amount)
      format:
        type: number
        decimal_places:
          type: exact
          places: 2
    - name: earned_premium
      expr: SUM(earned_premium)
      format:
        type: number
        decimal_places:
          type: exact
          places: 2
    - name: loss_ratio
      expr: MEASURE(paid_amount) / MEASURE(earned_premium)
      comment: paid_amount / earned_premium at the queried grouping level
      format:
        type: percentage
        decimal_places:
          type: exact
          places: 2
$$;
