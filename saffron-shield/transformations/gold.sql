-- ============================================================================
-- GOLD LAYER (R5-R7)
-- R5: claims.gold.claims_enriched        - one row per claim, exact column contract
-- R5: forbidden columns                  - payable/eligible/waiting-period/copay logic
--                                          must NOT appear in claims_enriched
-- R5: claims.gold.hospital_monthly       - monthly per-hospital aggregates
-- R6: claims.gold.hospital_monthly_designer - independent build, rows must match exactly
-- R7: claims_enriched clustered by (admission_month, hospital_id)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Point-in-time policy version in force at each claim's admission date (SCD2
-- as-of join on __START_AT / __END_AT). Deduped defensively in case versions
-- ever overlap.
-- ---------------------------------------------------------------------------
CREATE TEMPORARY VIEW policy_at_admission AS
SELECT claim_id, plan_code
FROM (
  SELECT
    c.claim_id,
    pv.plan_code,
    ROW_NUMBER() OVER (
      PARTITION BY c.claim_id
      ORDER BY pv.effective_from DESC
    ) AS rn
  FROM claims.silver.claims_clean c
  JOIN claims.silver.dim_policy_scd2 pv
    ON c.policy_id = pv.policy_id
   AND pv.__START_AT <= c.admission_date
   AND (pv.__END_AT IS NULL OR pv.__END_AT > c.admission_date)
)
WHERE rn = 1;

-- ---------------------------------------------------------------------------
-- Original policy start date (earliest effective_from across all versions).
-- ---------------------------------------------------------------------------
CREATE TEMPORARY VIEW policy_start_dates AS
SELECT
  policy_id,
  MIN(effective_from) AS policy_start_date
FROM claims.silver.dim_policy_scd2
GROUP BY policy_id;

-- ---------------------------------------------------------------------------
-- Network status of the claim's hospital at the admission date. Claims with
-- no covering network period default to FALSE (R5: is_network_at_admission is
-- never empty).
-- ---------------------------------------------------------------------------
CREATE TEMPORARY VIEW network_at_admission AS
SELECT claim_id, TRUE AS is_network
FROM (
  SELECT
    c.claim_id,
    ROW_NUMBER() OVER (
      PARTITION BY c.claim_id
      ORDER BY nh.network_from DESC
    ) AS rn
  FROM claims.silver.claims_clean c
  JOIN claims.silver.hospital_network_history nh
    ON c.hospital_id = nh.hospital_id
   AND nh.network_from <= c.admission_date
   AND (nh.network_to IS NULL OR nh.network_to >= c.admission_date)
)
WHERE rn = 1;

-- ---------------------------------------------------------------------------
-- R5: claims_enriched - exact column list, no more, no fewer. No adjudication
-- columns (payable / eligible / waiting period / copay) by design.
-- R7: clustered by (admission_month, hospital_id).
-- ---------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW claims.gold.claims_enriched
COMMENT 'R5/R7: one row per claim, enriched with policy/plan/hospital/network attributes as of admission date'
CLUSTER BY (admission_month, hospital_id)
AS
SELECT
  c.claim_id,
  c.member_id,
  c.policy_id,
  c.hospital_id,
  c.admission_date,
  c.discharge_date,
  CAST(date_trunc('month', c.admission_date) AS DATE) AS admission_month,
  c.diagnosis_code,
  c.procedure_code,
  c.is_pre_existing,
  c.claim_type,
  c.billed_amount,
  c.room_rent_per_day,
  c.room_days,
  c.status,
  c.approved_amount,
  c.rejection_code,
  c.submitted_ts,
  c.settled_ts,
  c.channel,
  pa.plan_code AS plan_code_at_admission,
  pl.plan_family,
  pl.room_rent_cap_per_day,
  ps.policy_start_date,
  CAST(FLOOR(months_between(c.admission_date, ps.policy_start_date)) AS INT)
    AS policy_tenure_months,
  CASE
    WHEN c.discharge_date IS NULL THEN NULL
    ELSE GREATEST(datediff(c.discharge_date, c.admission_date), 1)  -- same-day stay = 1 day (Q-E convention)
  END AS length_of_stay,
  CASE
    WHEN pl.room_rent_cap_per_day IS NULL THEN NULL
    ELSE c.room_rent_per_day > pl.room_rent_cap_per_day
  END AS room_rent_over_cap,
  CASE
    WHEN c.settled_ts IS NOT NULL AND c.submitted_ts IS NOT NULL
      THEN datediff(c.settled_ts, c.submitted_ts)
  END AS turnaround_days,  -- empty until settled
  COALESCE(nw.is_network, FALSE) AS is_network_at_admission,  -- never empty (R5)
  h.city AS hospital_city,
  h.city_tier AS hospital_city_tier
FROM claims.silver.claims_clean c
LEFT JOIN policy_at_admission pa ON pa.claim_id = c.claim_id
LEFT JOIN claims.silver.plans pl ON pl.plan_code = pa.plan_code
LEFT JOIN policy_start_dates ps ON ps.policy_id = c.policy_id
LEFT JOIN network_at_admission nw ON nw.claim_id = c.claim_id
LEFT JOIN claims.silver.hospitals h ON h.hospital_id = c.hospital_id;

-- ---------------------------------------------------------------------------
-- R5: hospital_monthly - monthly per-hospital aggregates. Money as DECIMAL(2dp);
-- totals never empty (0 when no approved amounts); counts as INT.
-- ---------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW claims.gold.hospital_monthly
COMMENT 'R5: monthly claim volume and amounts per hospital'
AS
SELECT
  e.hospital_id,
  e.admission_month,
  CAST(COUNT(*) AS INT) AS claim_count,
  CAST(COALESCE(SUM(e.billed_amount), 0.0) AS DECIMAL(15,2)) AS total_billed,
  CAST(COALESCE(SUM(e.approved_amount), 0.0) AS DECIMAL(15,2)) AS total_approved,
  CAST(COUNT(CASE WHEN e.status = 'rejected' THEN 1 END) AS INT) AS rejected_count
FROM claims.gold.claims_enriched e
GROUP BY e.hospital_id, e.admission_month;


