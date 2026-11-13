-- R7 Part 1: claims.analytics.weekly_rejection_rate — rejection rate at plan x week grain.
-- Same REJECTION RULE as R4 (single source of truth, claims.analytics.mv_claims):
--   rejection_rate = rejected / decided, decided = approved + settled + rejected.
-- 'submitted' claims await a decision and are excluded from BOTH sides of the fraction.
-- week_start = Monday-start week of the claim SUBMISSION date (date_trunc('WEEK',
-- CAST(submitted_ts AS DATE))). Basis verified against data: by admission week, every
-- claim admitted on/after 2026-06-20 is still 'submitted' (zero decided claims in alert
-- week 2026-06-22); by settled week, week 2026-06-22 has zero rejections (rate 0, alert
-- could never fire). Submission week is the only basis where the R7 alert week has
-- decided claims and can trigger above 0.18 (max plan rate that week = 0.4, SENIOR).
-- the alert week 2026-06-22 is the final full Monday-start week in the data.
-- Consumed by the R7 alert 'claims_week_rejection_alert' (threshold 0.18), whose query
-- reads this table BY FULL NAME for week_start = DATE'2026-06-22' and returns one value:
-- MAX(rejection_rate) across plans in that week.
-- NOTE: IF NOT EXISTS (non-destructive). To rebuild from scratch, DROP TABLE first.
CREATE TABLE IF NOT EXISTS claims.analytics.weekly_rejection_rate AS
SELECT
  plan_code_at_admission                            AS plan_code,
  CAST(date_trunc('WEEK', CAST(submitted_ts AS DATE)) AS DATE) AS week_start,
  CAST(COUNT_IF(status IN ('approved', 'settled', 'rejected')) AS INT) AS decided_count,
  CAST(COUNT_IF(status = 'rejected') AS INT)                           AS rejected_count,
  ROUND(
    CAST(COUNT_IF(status = 'rejected') AS DOUBLE)
    / NULLIF(CAST(COUNT_IF(status IN ('approved', 'settled', 'rejected')) AS INT), 0),
    4
  )                                                              AS rejection_rate
FROM claims.gold.claims_enriched
WHERE status IN ('approved', 'settled', 'rejected')
GROUP BY plan_code_at_admission, CAST(date_trunc('WEEK', CAST(submitted_ts AS DATE)) AS DATE);

COMMENT ON TABLE claims.analytics.weekly_rejection_rate IS
  'R7: rejection rate per plan per Monday-start submission week (week_start = Monday of submitted_ts date). decided = approved + settled + rejected; submitted excluded from both sides. rejection_rate rounded to 4 dp. Source: claims.gold.claims_enriched.';
