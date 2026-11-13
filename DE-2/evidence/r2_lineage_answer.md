# R2 — Lineage Answer

**Question:** which tables read `claims.raw.members.phone`?

**Note on names:** the `claims.raw` schema holds only the landing volume in this workspace; the members table lives at **`claims.bronze.members`**. All names below are full three-part names.

**Answer (column-level lineage, Unity Catalog, confirmed 2026-11-05):**

| # | Table reading `claims.bronze.members.phone` | What it is |
| --- | --- | --- |
| 1 | `claims.silver.members` | Pipeline streaming table built by `silver.py` in pipeline `5ddb66c6-98d4-48ef-b11f-9a9b0bb4d1ea`; `bronze.members.phone` maps 1:1 to `silver.members.phone`. |
| 2 | `claims.gov.proof_members_admin` | R1 governance proof table — admin view of raw member PII (built by the R1 notebook). |
| 3 | `claims.gov.proof_members_masked` | R1 governance proof table — masked (`****<last4>`) view of member PII (built by the R1 notebook). |

## Lineage chain

```
claims.bronze.members (phone)
        |  (pipeline 5ddb66c6-98d4-48ef-b11f-9a9b0bb4d1ea, silver.py)
        v
claims.silver.members (phone)
        |  (pipeline gold.sql reads members for enrichment)
        v
claims.gold.claims_enriched  <- reads member ATTRIBUTES only; phone does NOT propagate to gold

claims.gov.proof_members_admin  (R1 notebook — direct read of bronze.members)
claims.gov.proof_members_masked (R1 notebook — direct read of bronze.members)
```

## Why no gold table appears for `phone`

`claims.gold.claims_enriched` joins members only to enrich claims with member attributes (`member_id` etc.). The `phone` column stops at `claims.silver.members` — no gold table carries it. The only other readers are the R1 proof tables, which deliberately sample `bronze.members` PII to demonstrate the `claims.gov.mask_last4` column mask.

## Verification method

Unity Catalog column-level lineage was queried for `claims.bronze.members.phone`; the downstream column set returned `claims.silver.members.phone`, `claims.gov.proof_members_admin.phone`, and `claims.gov.proof_members_masked.phone`.
