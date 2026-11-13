-- R2 q02: the 10 hospitals paid the most (approved amounts of settled claims)
-- Returns: hospital_id, hospital_name, total_paid (2-dp), settled_claims (INT)
-- Saved query clone: claims.analytics.q02 (SQL editor)
SELECT h.hospital_id, h.hospital_name,
       CAST(ROUND(SUM(f.approved_amount), 2) AS DECIMAL(15,2)) AS total_paid,
       CAST(COUNT(*) AS INT) AS settled_claims
FROM claims.analytics.fact_claims f
JOIN claims.analytics.dim_hospital h ON h.hospital_sk = f.hospital_sk
WHERE f.status = 'settled'
GROUP BY h.hospital_id, h.hospital_name
ORDER BY total_paid DESC
LIMIT 10;
