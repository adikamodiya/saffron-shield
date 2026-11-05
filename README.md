# Saffron Shield — Insurance Claims Pipeline

A Lakeflow Spark Declarative Pipeline (SDP) that ingests insurance claims data from raw landing files and produces a governed, quality-checked gold layer for analytics.

- **Catalog / schema convention:** `claims` catalog; layers live in `claims.bronze`, `claims.silver`, `claims.gold`
- **Pipeline root:** `transformations/` (`bronze.sql`, `silver.py`, `gold.sql`)
- **Landing volume:** `/Volumes/claims/raw/landing/` with subfolders `claims`, `plans`, `hospitals`, `members`, `hospital_network_history`, `policy_changes_cdc`
- **Upstream setup:** the `setup` notebook creates the catalog, schemas, volume, and folder layout

## Setup (one-time bootstrap)

The `setup` notebook (workspace path `.../saffron-shield/setup`) prepares the environment before the pipeline runs:

1. **Catalog** — `CREATE CATALOG IF NOT EXISTS claims`
2. **Schemas** — `claims.raw`, `claims.bronze`, `claims.silver`, `claims.gold` (one per medallion layer)
3. **Volume** — `CREATE VOLUME IF NOT EXISTS claims.raw.landing` (UC-managed volume for raw landing files)
4. **Landing subfolders** — `claims/`, `plans/`, `hospitals/`, `members/`, `hospital_network_history/`, `policy_changes_cdc/` under `/Volumes/claims/raw/landing/`

Note: the policy CDC landing folder is named `policy_changes_cdc/` (the bronze table is still called `claims.bronze.policy`).

**Ingestion formats (bronze.sql, Auto Loader `read_files`):**

| Source folder | Format | Options |
| --- | --- | --- |
| `claims/` | JSON | multiLine, type inference on |
| `policy_changes_cdc/` | JSON | multiLine, type inference on |
| `plans/`, `hospitals/`, `members/`, `hospital_network_history/` | CSV | header, no type inference (typed in silver) |

All sources use `schemaEvolutionMode => 'addNewColumns'` and a `rescuedDataColumn => '_rescued_data'`, plus `_metadata.file_name` and an `ingestion_ts` audit column.

## Architecture (medallion)

```
/Volumes/claims/raw/landing/*        (Auto Loader sources)
        │
        ▼  bronze.sql
claims.bronze.*   (raw streaming tables, one per source)
        │
        ▼  silver.py
claims.silver.*   (cleaned dimensions, CDC dimensions, validated claims)
        │
        ▼  gold.sql
claims.gold.*     (analytics-ready fact + aggregates)
```

## Datasets

### Bronze (bronze.sql)

| Dataset | Source | Notes |
| --- | --- | --- |
| `claims.bronze.claims` | landing `claims/` | raw claim submissions, incl. resubmissions (multiple versions per claim) |
| `claims.bronze.members` | landing `members/` | member master |
| `claims.bronze.hospitals` | landing `hospitals/` | hospital master |
| `claims.bronze.plans` | landing `plans/` | plan catalog |
| `claims.bronze.policy` | landing `policy_changes_cdc/` | CDC stream (`op` = INSERT / UPDATE / DELETE, `op_ts` sequencing) |
| `claims.bronze.hospital_network_history` | landing `hospital_network_history/` | effective-dated in-network periods |

### Silver (silver.py)

| Dataset | Type | Notes |
| --- | --- | --- |
| `claims.silver.members` | streaming table | trimmed, typed, deduped by `member_id` |
| `claims.silver.hospitals` | streaming table | trimmed, typed, deduped by `hospital_id` |
| `claims.silver.plans` | streaming table | money/waiting fields typed to DECIMAL/INT |
| `claims.silver.hospital_network_history` | streaming table | FK-valid rows only (`left_semi` against hospitals) |
| `claims.silver.hospital_network_history_quarantine` | streaming table | orphan rows (`left_anti`) with `error_reason` |
| `claims.silver.dim_policy_scd2` | streaming table | SCD Type 2 policy dimension via Auto CDC on the CDC stream; deletes applied as `op = 'DELETE'`; `__END_AT` NULL = current version |
| `claims.silver.claims_scd1` | streaming table | latest version per claim via Auto CDC (SCD1), sequenced by `(submitted_ts, ingestion_ts)` |
| `claims.silver.claims_flagged` | materialized view | all claims + per-rule pass flags `passes_q_a`..`passes_q_e` and `failed_rules` array |
| `claims.silver.claims_clean` | materialized view | claims passing all Q-A..Q-E rules (one row per claim) |
| `claims.silver.claims_quarantine` | materialized view | claims failing ≥1 rule on their latest version, with `failed_rules` |

**Data-quality rules (warn-only, judged per rule):**

- **Q-A** referential integrity: member, hospital, and policy exist; claim's member belongs to the policy
- **Q-B** date ordering: admission/discharge/submitted mandatory; admission ≤ discharge; settled ≥ submitted when settled
- **Q-C** amount sanity: billed mandatory and > 0; approved (when present) 0 ≤ approved ≤ billed
- **Q-D** status consistency: rejected → code + no approval; settled → settled_ts + approved; approved → approved only; submitted → neither
- **Q-E** room math: room rent × days ≤ billed; `room_days` matches stay length (same-day stay counts as 1 day)

Mandatory-field NULLs fail a rule; state-dependent fields (approved amount, settled_ts) NULL-pass.

### Gold (gold.sql) — requirements R5–R7

| Dataset | Type | Notes |
| --- | --- | --- |
| `claims.gold.claims_enriched` | materialized view, `CLUSTER BY (admission_month, hospital_id)` | one row per clean claim, enriched **as of the admission date** |
| `claims.gold.hospital_monthly` | materialized view | monthly per-hospital aggregates |
| `claims.gold.hospital_monthly_designer` | materialized view | independent implementation; rows must match `hospital_monthly` exactly (verified via `EXCEPT`) |

**`claims_enriched` enrichment logic:**

- `plan_code_at_admission` / `room_rent_cap_per_day` / `plan_family` — point-in-time lookup into `dim_policy_scd2` (`__START_AT <= admission_date < __END_AT`)
- `policy_start_date` — earliest `effective_from` across all policy versions; `policy_tenure_months` = months from policy start to admission
- `is_network_at_admission` — effective-dated lookup into network history; defaults to FALSE when no period covers the admission date (never NULL)
- `hospital_city` / `hospital_city_tier` — from the hospitals dimension
- `admission_month` — admission date truncated to month (DATE)
- `length_of_stay` — same-day stay counts as 1 day (Q-E convention); NULL while still admitted
- `turnaround_days` — settlement minus submission; NULL until settled
- `room_rent_over_cap` — room rate exceeds the plan's daily cap

**Forbidden columns:** `payable`, `is_payable`, `payable_amount`, `eligible`, `is_eligible`, `waiting_period_ok`, `copay_pct`, `paid_waiting_months`, `initial_waiting_days` must **not** appear in `claims_enriched`. The gold fact layer is factual enrichment only — adjudication logic (eligibility, copay, waiting periods, payable amounts) belongs to a separate layer.

**`hospital_monthly` / `hospital_monthly_designer` columns:** `hospital_id`, `admission_month` (DATE), `claim_count` (INT), `total_billed` / `total_approved` (DECIMAL, 2dp, never NULL — 0 when none), `rejected_count` (INT).

## Delta internals

The pipeline's outputs are Delta tables, and several Delta features do the heavy lifting:

**Transaction log & ACID** — every bronze/silver/gold dataset is a Delta table with a `_delta_log` transaction log. Pipeline updates commit atomically, so consumers never see partial states.

**Liquid clustering (R7)** — `claims_enriched` uses `CLUSTER BY (admission_month, hospital_id)`: Delta incrementally clusters rows by those keys without fixed partitions, so time-range and per-hospital queries do file pruning. Preferred over `PARTITIONED BY` for tables of this size. `hospital_monthly` is small enough to skip clustering.

**Streaming checkpoints & state** — Auto Loader sources track ingested files in a pipeline-managed checkpoint (exactly-once per file); stateful operators (Auto CDC, dedup) persist state between runs. Resetting a checkpoint or changing stateful logic can require a full refresh of that dataset.

**SCD1/SCD2 via MERGE** — `claims_scd1` (Auto CDC SCD1) and `dim_policy_scd2` (Auto CDC SCD2) are implemented with Delta MERGE under the hood; the SCD2 table's `__START_AT`/`__END_AT` validity windows are what gold's as-of joins key on.

**Schema enforcement & evolution** — Delta enforces the schema on every write; the bronze layer additionally opts into `addNewColumns` evolution and captures unexpected fields in `_rescued_data` instead of failing.

**Incremental-refresh support** — materialized views refresh incrementally when sources have row tracking / deletion vectors enabled; MV maintenance (OPTIMIZE, VACUUM) is handled by the pipeline automatically — never run OPTIMIZE/VACUUM by hand on pipeline-managed tables.

**Time travel** — all tables are versioned; `DESCRIBE HISTORY` and version/time-snapshot reads work on every dataset for debugging or rewind (the pipeline's rewind points are built on Delta versioning).

## How to run

- **Validate code:** start a dry run from the pipeline editor (fast, no data written)
- **Build/refresh datasets:** run a pipeline update; use a selective refresh to rebuild only gold or a subset of datasets
- **Full refresh:** drops and rebuilds tables from scratch — use only when necessary (e.g. after changing a dataset type)

## Operational notes

- Catalog is injected via the pipeline `configuration` key `catalog_name` (default `claims`)
- Batch reads of published pipeline datasets inside pipeline code use fully qualified names (bare names resolve to the default schema); temporary views resolve bare
- `CREATE OR REFRESH TEMPORARY VIEW` is not valid SDP syntax — use `CREATE TEMPORARY VIEW`
- Adding `dropDuplicates` to a streaming table can require a full refresh of that dataset (stateful operator state directory)
- `explorations/Testing` holds ad-hoc verification queries (not pipeline source)
