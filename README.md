# Saffron Shield — Insurance Claims Pipeline

A Lakeflow Spark Declarative Pipeline (SDP) that ingests insurance claims data from raw landing files and produces a governed, quality-checked gold layer for analytics.

- **Catalog / schema convention:** default `claims` catalog with `claims.bronze`, `claims.silver`, `claims.gold`; fully parameterized — the DAB bundle deploys the same code to `claims_dev` and `claims_prod` via the `target_catalog` variable (see the R6 section below)
- **Pipeline root:** `saffron-shield-1/transformations/` (`bronze.sql`, `silver.py`; `gold.sql` kept as a design reference only — gold is built by the `publish_gold` notebook since R4)
- **Bundle root:** `databricks.yml` + `resources/` (R6) at the repo root; the bundle packages the pipeline code, job chain, and notebooks as-is (no `src/` layout required)
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
        ▼  bronze.sql                (${target_catalog} / ${source_catalog} from pipeline conf)
claims.bronze.*    (raw streaming tables, one per source)
        │
        ▼  silver.py                 (conf target_catalog, default claims)
claims.silver.*    (cleaned dimensions, CDC dimensions, validated claims)
        │
        ▼  publish_gold notebook     (batch job task, R4+)
claims.gold.*      (analytics-ready fact + aggregates)
```

The same code serves all three catalogs: `claims` (default / legacy hand-built job), `claims_dev` (bundle target `dev`), `claims_prod` (bundle target `prod`) — the catalog name is injected, never hard-coded.

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

### Gold (publish_gold notebook) — requirements R5–R7

Since R4 the gold layer is **outside the SDP pipeline**: `gold.sql` remains as a design reference only, and the `publish_gold` notebook (a task in the `claims_daily` / bundle jobs) builds the gold tables as **batch tables** with `CREATE OR REPLACE` from the current silver, then re-attaches the R1 row filter for the main `claims` catalog.

| Dataset | Type | Notes |
| --- | --- | --- |
| `claims.gold.claims_enriched` | batch table, `CLUSTER BY (admission_month, hospital_id)` | one row per clean claim, enriched **as of the admission date** |
| `claims.gold.hospital_monthly` | batch table | monthly per-hospital aggregates |
| `claims.gold.hospital_monthly_designer` | batch table (main `claims` catalog only) | independent implementation; verified equal to `hospital_monthly` via `EXCEPT` (not rebuilt by the bundle's dev/prod runs) |

**State of the three environments (Nov 12, 2026):** `claims.gold` = 3,046 rows / 469 hospital-months (refreshed after the Q-B FY-window rule; it had gone stale because the R5 run skipped publish_gold at the dq gate); `claims_dev.gold` = identical, built by the bundle dev run; `claims_prod.gold` = built by the prod bundle run.

**`claims_enriched` enrichment logic:**

- `plan_code_at_admission` / `room_rent_cap_per_day` / `plan_family` — point-in-time lookup into `dim_policy_scd2` (`__START_AT <= admission_date < __END_AT`)
- `policy_start_date` — earliest `effective_from` across all policy versions; `policy_tenure_months` = months from policy start to admission
- `is_network_at_admission` — effective-dated lookup into network history; defaults to FALSE when no period covers the admission date (never NULL)
- `hospital_city` / `hospital_city_tier` — from the hospitals dimension
- `admission_month` — admission date truncated to month (DATE)
- `length_of_stay` — same-day stay counts as 1 day (Q-E convention); NULL while still admitted
- `turnaround_days` — settlement minus submission; NULL until settled
- `room_rent_over_cap` — room rate exceeds the plan's daily cap

Note: Q-B also enforces the FY2025-26 window — admission/discharge dates and submitted/settled timestamps must fall in `2025-07-01..2026-06-30` (typed bounds, end-of-day inclusive; `settled_ts` NULL-passes). This rule is what excluded 44 `batch_007` claims from the Nov 12 gold refresh.

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

## R6 — Deployable project (Declarative Automation Bundle)

The whole project ships as a DAB rooted at the repo root (no `src/` layout needed — only `databricks.yml` is mandatory, plus whatever files it references):

```
saffron-shield/                 <- bundle root
|-- databricks.yml              <- name, variables, targets (dev/prod)
|-- resources/
|   |-- pipeline.yml            <- claims_pipeline_bundle (serverless SDP)
|   `-- job.yml                 <- claims_daily_bundle (task chain)
|-- saffron-shield-1/transformations/   <- bronze.sql + silver.py (pipeline libraries)
|-- ingest, dq_check, publish_gold      <- job task notebooks (catalog-widget parameterized)
`-- saffron shield-2/evidence/cli/r6_bundle_log.txt   <- evidence log (validate -> dev -> prod)
```

**Variables & targets** (`databricks.yml`):

| Variable | dev | prod | Purpose |
| --- | --- | --- | --- |
| `target_catalog` | `claims_dev` | `claims_prod` | catalog the pipeline writes; the job's dq_check / publish_gold read it |
| `source_catalog` | `claims` | `claims` | shared raw landing volume source |
| `name_prefix` | (empty) | `prod_` | resource-name prefix (pipeline names must be unique workspace-wide) |

**Parameter flow:** bundle variable `target_catalog` -> resolved at deploy time -> job task `base_parameters: catalog` -> notebook widget `catalog` (default `claims`, so the legacy hand-built job is unaffected). The pipeline gets the same values via its `configuration` block, read in `bronze.sql` (`${target_catalog}`, `${source_catalog}`) and `silver.py` (`spark.conf.get("target_catalog", "claims")`). These are task-level parameters — visible under Tasks -> dq_check / publish_gold -> Base parameters, not in the "Job parameters" panel.

**Commands** (run from the bundle root):

```bash
databricks bundle validate -t dev                        # validity check (also -t prod)
databricks bundle deploy -t dev                          # dev auto-approves
databricks bundle run claims_daily_bundle -t dev
databricks bundle deploy -t prod --auto-approve          # prod REQUIRES --auto-approve
databricks bundle run claims_daily_bundle -t prod        # resource key, not display name
```

The bundle job mirrors the hand-built `claims_daily` chain — ingest -> pipeline -> dq_check (row-growth + duplicate checks, writes `dq_state`) -> dq_gate (condition task; skips publish_gold when dq_problems != 0) -> publish_gold. Resource names: dev = `claims_pipeline_bundle` / `claims_daily_bundle`, prod = `prod_claims_pipeline_bundle` / `prod_claims_daily_bundle`. Jobs are UI-locked (bundle-managed) — edit the YAML and redeploy, never edit in the UI.

## How to run

- **Validate code:** start a dry run from the pipeline editor (fast, no data written)
- **Build/refresh datasets:** run a pipeline update; use a selective refresh to rebuild only gold or a subset of datasets
- **Full refresh:** drops and rebuilds tables from scratch — use only when necessary (e.g. after changing a dataset type)
- **Deploy per environment:** use the bundle commands in the R6 section above (gold tables are batch-built by the job's `publish_gold` task, not by the pipeline)

## Operational notes

- Catalog is injected via the pipeline `configuration` key `target_catalog` (default `claims`; legacy `catalog_name` was dropped in R6), plus `source_catalog` for the landing-volume paths in bronze
- Batch reads of published pipeline datasets inside pipeline code use fully qualified names (bare names resolve to the default schema); temporary views resolve bare
- `CREATE OR REFRESH TEMPORARY VIEW` is not valid SDP syntax — use `CREATE TEMPORARY VIEW`
- Adding `dropDuplicates` to a streaming table can require a full refresh of that dataset (stateful operator state directory)
- `explorations/Testing` holds ad-hoc verification queries (not pipeline source)
