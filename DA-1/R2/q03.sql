-- R2 q03: monthly claim volume and billed amounts (admission month via dim_date)
-- Returns: month_start (DATE), claim_count (INT), total_billed (2-dp)
-- Saved query clone: claims.analytics.q03 (SQL editor)
SELECT CAST(date_trunc('month', d.full_date) AS DATE) AS month_start,
       CAST(COUNT(*) AS INT) AS claim_count,
       CAST(ROUND(SUM(f.billed_amount), 2) AS DECIMAL(15,2)) AS total_billed
FROM claims.analytics.fact_claims f
JOIN claims.analytics.dim_date d ON d.date_key = f.admission_date_key
GROUP BY date_trunc('month', d.full_date)
ORDER BY month_start;
