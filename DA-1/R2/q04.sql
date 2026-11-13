-- R2 q04: settled claims and average turnaround by claim type and network status
-- Returns: claim_type, is_network_at_admission (BOOLEAN), settled_claims (INT), avg_turnaround_days (2-dp)
-- Saved query clone: claims.analytics.q04 (SQL editor)
SELECT f.claim_type, f.is_network_at_admission,
       CAST(COUNT(*) AS INT) AS settled_claims,
       CAST(ROUND(AVG(f.turnaround_days), 2) AS DECIMAL(10,2)) AS avg_turnaround_days
FROM claims.analytics.fact_claims f
WHERE f.status = 'settled'
GROUP BY f.claim_type, f.is_network_at_admission
ORDER BY f.claim_type, f.is_network_at_admission;
