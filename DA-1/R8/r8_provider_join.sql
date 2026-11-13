-- R8: provider accreditation join (source: lakebase)
-- Target: claims.analytics.r8_provider_join
-- Source: claims_lakebase.public.provider_directory (Lakebase Postgres, registered as UC catalog claims_lakebase)
-- Columns per spec: hospital_id, hospital_name, city_tier, accreditation,
--                   accredited_until (DATE), claims_after_lapse (INT, 0 when accredited_until is empty)
-- Convention: claims_after_lapse = ALL claims (any status) admitted AFTER the accreditation expiry
--             (admission full_date > accredited_until). accredited_until NULL (accreditation = NONE) -> 0.
-- Verified: 40 rows; 4 hospitals with lapses -> HOS-005: 8, HOS-009: 33, HOS-024: 43, HOS-035: 34 (total 118);
--           independently recomputed via provider->dim_hospital->fact join path = identical 118.
-- Rebuild note: to fully refresh, run `DROP TABLE IF EXISTS claims.analytics.r8_provider_join;`
--               before this script (drop is intentionally NOT inline; see R7 note on edit-safety guard).

CREATE TABLE IF NOT EXISTS claims.analytics.r8_provider_join AS
WITH lapse AS (
  -- claims admitted AFTER the hospital's accreditation expiry
  SELECT f.hospital_sk,
         COUNT(1) AS claims_after_lapse
  FROM claims.analytics.fact_claims f
  JOIN claims.analytics.dim_date d
    ON d.date_key = f.admission_date_key
  JOIN claims.analytics.dim_hospital h
    ON h.hospital_sk = f.hospital_sk
  JOIN claims_lakebase.public.provider_directory p
    ON p.hospital_id = h.hospital_id
  WHERE p.accredited_until IS NOT NULL
    AND d.full_date > p.accredited_until
  GROUP BY f.hospital_sk
)
SELECT h.hospital_id,
       h.hospital_name,
       h.city_tier,
       p.accreditation,
       p.accredited_until,
       CAST(COALESCE(l.claims_after_lapse, 0) AS INT) AS claims_after_lapse
FROM claims.analytics.dim_hospital h
JOIN claims_lakebase.public.provider_directory p
  ON p.hospital_id = h.hospital_id
LEFT JOIN lapse l
  ON l.hospital_sk = h.hospital_sk
ORDER BY h.hospital_id;

COMMENT ON TABLE claims.analytics.r8_provider_join IS 'R8: hospital provider accreditation (sourced: lakebase claims_lakebase.public.provider_directory) joined to analytics dim_hospital; claims_after_lapse = claims admitted after accredited_until (0 when accredited_until is NULL)';

-- Post-build checks
-- SELECT COUNT(*) FROM claims.analytics.r8_provider_join;                                     -- expect 40
-- SELECT SUM(claims_after_lapse) FROM claims.analytics.r8_provider_join;                      -- expect 118
-- SELECT hospital_id, accredited_until, claims_after_lapse FROM claims.analytics.r8_provider_join
--  WHERE claims_after_lapse > 0 ORDER BY hospital_id;                                         -- HOS-005/009/024/035
