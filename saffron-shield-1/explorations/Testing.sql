-- Databricks notebook source
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
WHERE status IN ('approved', 'settled', 'rejected') and  CAST(date_trunc('WEEK', CAST(submitted_ts AS DATE)) AS DATE) = DATE'2026-06-22'
GROUP BY plan_code_at_admission, CAST(date_trunc('WEEK', CAST(submitted_ts AS DATE)) AS DATE);


-- COMMAND ----------

select * from claims.silver.dim_policy_scd2 where policy_id='POL-0072';

-- COMMAND ----------

select * from claims.silver.claims_clean where claim_id = 'CLM-10001';

-- COMMAND ----------

show tables in claims.silver

-- COMMAND ----------

show tables in claims.silver;

-- COMMAND ----------

desc claims.bronze.members;

-- COMMAND ----------

select * from claims.bronze.claims;