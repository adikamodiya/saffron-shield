-- R2 q06: room-rent cap breaches per plan (plan at admission via dim_plan)
-- Returns: plan_code, claim_count (INT), over_cap_count (INT), over_cap_share (4-dp)
-- Saved query clone: claims.analytics.q06 (SQL editor)
SELECT p.plan_code,
       CAST(COUNT(*) AS INT) AS claim_count,
       CAST(COUNT(CASE WHEN f.room_rent_over_cap THEN 1 END) AS INT) AS over_cap_count,
       CAST(ROUND(COUNT(CASE WHEN f.room_rent_over_cap THEN 1 END) * 1.0 / COUNT(*), 4) AS DECIMAL(10,4)) AS over_cap_share
FROM claims.analytics.fact_claims f
JOIN claims.analytics.dim_plan p ON p.plan_sk = f.plan_sk
GROUP BY p.plan_code
ORDER BY over_cap_count DESC;
