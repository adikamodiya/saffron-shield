-- R2 q01: claim volume per status
-- Returns: status, claim_count (INT)
-- Saved query clone: claims.analytics.q01 (SQL editor)
SELECT status, CAST(COUNT(*) AS INT) AS claim_count
FROM claims.analytics.fact_claims
GROUP BY status
ORDER BY claim_count DESC;
