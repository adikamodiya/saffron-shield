source: lakebase

R8 source route evidence
========================

Source line (per requirement): source: lakebase

- Provider directory data lives in Lakebase Postgres as table `provider_directory`
  (database `claims_provider`, loaded from the local provider_directory.sql script).
- The Lakebase database is registered in Unity Catalog as catalog `claims_lakebase`,
  and is read directly through the registered catalog:
  `claims_lakebase.public.provider_directory` (40 rows, 40 distinct hospital_ids,
  all matching claims.analytics.dim_hospital.hospital_id).
- Routes NOT used: federation (no Lakehouse Federation foreign catalog was created)
  and csv (no direct CSV read - the data was loaded into Postgres first, then read
  via the registered catalog).

Downstream object: claims.analytics.r8_provider_join
- Columns: hospital_id (STRING), hospital_name (STRING), city_tier (STRING),
  accreditation (STRING), accredited_until (DATE), claims_after_lapse (INT).
- claims_after_lapse = claims admitted after accredited_until; 0 when accredited_until
  is empty (NULL - accreditation NONE in the directory).
- Verified: 40 rows; lapse hospitals HOS-005=8, HOS-009=33, HOS-024=43, HOS-035=34,
  total 118 - matches an independent recompute via a different join path.

Screenshot (to be added by user): evidence/screenshots/r8_lakebase_catalog.png
(catalog claims_lakebase visible in Catalog Explorer).
