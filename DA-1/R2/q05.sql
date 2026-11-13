-- R2 q05: rejection reasons and each code's share of all rejections
-- Returns: rejection_code, rejected_count (INT), share_of_rejections (4-dp)
-- Saved query clone: claims.analytics.q05 (SQL editor)
SELECT f.rejection_code,
       CAST(COUNT(*) AS INT) AS rejected_count,
       CAST(ROUND(COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (), 4) AS DECIMAL(10,4)) AS share_of_rejections
FROM claims.analytics.fact_claims f
WHERE f.status = 'rejected'
GROUP BY f.rejection_code
ORDER BY rejected_count DESC;
