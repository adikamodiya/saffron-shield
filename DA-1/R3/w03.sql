-- R3 w03: hospitals ranked by total paid within city tier (ties share a rank)
-- Returns: hospital_id, city, tier, total_paid (2-dp), rank_in_tier (INT)
-- Saved query clone: claims.analytics.w03 (SQL editor)
-- Convention: total_paid = approved_amount of SETTLED claims (same basis as R2 q02);
--             RANK() = ties share a rank (gaps after ties), per the spec.
WITH hospital_paid AS (
  SELECT h.hospital_id,
         h.city,
         h.city_tier AS tier,
         CAST(ROUND(SUM(f.approved_amount), 2) AS DECIMAL(15,2)) AS total_paid
  FROM claims.analytics.fact_claims f
  JOIN claims.analytics.dim_hospital h ON h.hospital_sk = f.hospital_sk
  WHERE f.status = 'settled'
  GROUP BY h.hospital_id, h.city, h.city_tier
)
SELECT hospital_id,
       city,
       tier,
       total_paid,
       CAST(RANK() OVER (
         PARTITION BY tier
         ORDER BY total_paid DESC
       ) AS INT) AS rank_in_tier
FROM hospital_paid
ORDER BY tier, rank_in_tier, total_paid DESC;
