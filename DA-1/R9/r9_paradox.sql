-- R9: Simpson's paradox table (HOS-017 vs HOS-022)
-- Target: claims.analytics.r9_paradox
-- Columns per spec: hospital_id, claim_type (ALL/cashless/reimbursement),
--                   decided_count (INT), rejected_count (INT), rejection_rate (4-dp)
-- Convention: decided = approved + settled + rejected (submitted excluded, same as R4).
--             rejection_rate = rejected / decided rounded to 4 decimals.
-- Result: HOS-022 looks better on ALL (0.1100 vs 0.2100) but HOS-017 is better within
--         BOTH types (cashless 0.0500 vs 0.0625; reimbursement 0.2500 vs 0.3000) -> Simpson's paradox.
-- Verified: ALL rows equal the sum of the two type rows for each hospital (independent recompute).
-- Rebuild note: run `DROP TABLE IF EXISTS claims.analytics.r9_paradox;` before this script
--               (drop is intentionally NOT inline; edit-safety guard blocks it, same as R7/R8).

CREATE TABLE IF NOT EXISTS claims.analytics.r9_paradox AS
WITH type_rows AS (
  SELECT h.hospital_id,
         f.claim_type,
         COUNT(1) AS decided_count,
         COUNT_IF(f.status = 'rejected') AS rejected_count
  FROM claims.analytics.fact_claims f
  JOIN claims.analytics.dim_hospital h
    ON h.hospital_sk = f.hospital_sk
  WHERE h.hospital_id IN ('HOS-017','HOS-022')
    AND f.status IN ('approved','settled','rejected')  -- decided convention (R4); submitted excluded
  GROUP BY h.hospital_id, f.claim_type
),
all_rows AS (
  SELECT h.hospital_id,
         'ALL' AS claim_type,
         COUNT(1) AS decided_count,
         COUNT_IF(f.status = 'rejected') AS rejected_count
  FROM claims.analytics.fact_claims f
  JOIN claims.analytics.dim_hospital h
    ON h.hospital_sk = f.hospital_sk
  WHERE h.hospital_id IN ('HOS-017','HOS-022')
    AND f.status IN ('approved','settled','rejected')
  GROUP BY h.hospital_id
)
SELECT hospital_id,
       claim_type,
       CAST(decided_count AS INT) AS decided_count,
       CAST(rejected_count AS INT) AS rejected_count,
       CAST(ROUND(rejected_count / decided_count, 4) AS DECIMAL(10,4)) AS rejection_rate
FROM (
  SELECT * FROM type_rows
  UNION ALL
  SELECT * FROM all_rows
)
ORDER BY hospital_id,
         CASE WHEN claim_type = 'ALL' THEN 0 ELSE 1 END,
         claim_type;

COMMENT ON TABLE claims.analytics.r9_paradox IS 'R9: Simpson paradox analysis - decided/rejected claim counts and 4-dp rejection rate for HOS-017 and HOS-022, by claim type (ALL/cashless/reimbursement); decided = approved+settled+rejected';

-- Post-build checks
-- SELECT * FROM claims.analytics.r9_paradox ORDER BY hospital_id, claim_type;  -- expect 6 rows
-- ALL rows: HOS-017 100/21 = 0.2100; HOS-022 100/11 = 0.1100
-- Type rows: cashless 20/1=0.0500 vs 80/5=0.0625; reimbursement 80/20=0.2500 vs 20/6=0.3000
