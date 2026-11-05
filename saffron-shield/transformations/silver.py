from pyspark import pipelines as dp
from pyspark.sql import functions as F

CATALOG = spark.conf.get("catalog_name", "claims")


def _title_case(col: str):
    """Trim and title-case a string column."""
    return F.initcap(F.trim(F.col(col)))


@dp.table(
    name=f"{CATALOG}.silver.members",
    comment="Cleaned and standardized member dimension",
)
def silver_members():
    return (
        spark.readStream.table(f"{CATALOG}.bronze.members")
        .select(
            F.upper(F.trim(F.col("member_id"))).alias("member_id"),
            _title_case("name").alias("name"),
            F.to_date(F.trim(F.col("dob")), "yyyy-MM-dd").alias("dob"),
            F.when(F.upper(F.trim(F.col("gender"))).isin("FEMALE", "F"), "F")
            .when(F.upper(F.trim(F.col("gender"))).isin("MALE", "M"), "M")
            .otherwise(F.upper(F.trim(F.col("gender"))))
            .alias("gender"),
            _title_case("city").alias("city"),
            _title_case("state").alias("state"),
            F.trim(F.col("national_id")).alias("national_id"),
            F.trim(F.col("phone")).alias("phone"),
            F.lower(F.trim(F.col("email"))).alias("email"),
            F.col("file_name"),
            F.col("ingestion_ts"),
        ).dropDuplicates(["member_id"])
        .filter(F.col("member_id").isNotNull() & (F.trim(F.col("member_id")) != ""))
    )




@dp.table(
    name=f"{CATALOG}.silver.hospitals",
    comment="Cleaned and standardized hospital dimension",
)
def silver_hospitals():
    return (
        spark.readStream.table(f"{CATALOG}.bronze.hospitals")
        .select(
            F.upper(F.trim(F.col("hospital_id"))).alias("hospital_id"),
            _title_case("name").alias("name"),
            _title_case("city").alias("city"),
            F.lower(F.trim(F.col("city_tier"))).alias("city_tier"),
            _title_case("state").alias("state"),
            F.col("file_name"),
            F.col("ingestion_ts"),
        ).dropDuplicates(["hospital_id"])
        .filter(F.col("hospital_id").isNotNull() & (F.trim(F.col("hospital_id")) != ""))
    )



# 1. Main Silver Table (Valid Records Only)
@dp.table(
    name=f"{CATALOG}.silver.hospital_network_history",
    comment="Cleaned network history, referentially valid against silver.hospitals",
)
def silver_hospital_network_history():
    history = (
        spark.readStream.table(f"{CATALOG}.bronze.hospital_network_history")
        .select(
            F.upper(F.trim(F.col("hospital_id"))).alias("hospital_id"),
            F.expr("try_cast(nullif(trim(network_from), '') AS DATE)").alias("network_from"),
            F.expr("try_cast(nullif(trim(network_to), '') AS DATE)").alias("network_to"),
            F.col("file_name"),
            F.col("ingestion_ts"),
        )
        .dropDuplicates(["hospital_id", "network_from"])
        .filter(F.col("hospital_id").isNotNull() & (F.trim(F.col("hospital_id")) != ""))
    )
    hospitals = spark.read.table(f"{CATALOG}.silver.hospitals").select("hospital_id")
    
    # Sirf valid foreign keys wale records silver mein jayenge
    return history.join(hospitals, "hospital_id", "left_semi")


# 2. Quarantine Table (Orphan Records with Error Reason)
@dp.table(
    name=f"{CATALOG}.silver.hospital_network_history_quarantine",
    comment="Quarantine table for records failing FK check against silver.hospitals",
)
def hospital_network_history_quarantine():
    history = (
        spark.readStream.table(f"{CATALOG}.bronze.hospital_network_history")
        .select(
            F.upper(F.trim(F.col("hospital_id"))).alias("hospital_id"),
            F.expr("try_cast(nullif(trim(network_from), '') AS DATE)").alias("network_from"),
            F.expr("try_cast(nullif(trim(network_to), '') AS DATE)").alias("network_to"),
            F.col("file_name"),
            F.col("ingestion_ts"),
        )
        .dropDuplicates(["hospital_id", "network_from"])
        .filter(F.col("hospital_id").isNotNull() & (F.trim(F.col("hospital_id")) != ""))
    )
    hospitals = spark.read.table(f"{CATALOG}.silver.hospitals").select("hospital_id")
    
    # Left Anti: Jo hospitals table mein match nahi hue, unhe yahan pakdo
    return (
        history.join(hospitals, "hospital_id", "left_anti")
        .withColumn("error_reason", F.lit("INVALID_FK_MISSING_HOSPITAL"))
        .withColumn("quarantine_ts", F.current_timestamp())
    )



@dp.table(
    name=f"{CATALOG}.silver.plans",
    comment="Cleaned and typed insurance plans",
)
def silver_plans():
    return (
        spark.readStream.table(f"{CATALOG}.bronze.plans")
        .select(
            F.upper(F.trim(F.col("plan_code"))).alias("plan_code"),
            F.lower(F.trim(F.col("plan_family"))).alias("plan_family"),
            F.expr("try_cast(nullif(trim(sum_insured), '') AS DECIMAL(15,2))").alias("sum_insured"),
            F.expr("try_cast(nullif(trim(room_rent_cap_per_day), '') AS DECIMAL(10,2))").alias("room_rent_cap_per_day"),    
            F.expr("try_cast(nullif(trim(copay_pct), '') AS DECIMAL(5,2))").alias("copay_pct"),
            F.expr("try_cast(nullif(trim(ped_waiting_months), '') AS INT)").alias("ped_waiting_months"),
            F.expr("try_cast(nullif(trim(initial_waiting_days), '') AS INT)").alias("initial_waiting_days"),
            F.expr("try_cast(nullif(trim(annual_premium), '') AS DECIMAL(12,2))").alias("annual_premium"),
            F.col("file_name"),
            F.col("ingestion_ts"),
        ).dropDuplicates(["plan_code"])
        .filter(F.col("plan_code").isNotNull() & (F.trim(F.col("plan_code")) != ""))
    )


# ------------------------------------------------------------------
# Policy dimension: SCD Type 2 via Auto CDC on the bronze CDC stream
# ------------------------------------------------------------------
@dp.temporary_view()
def policy_cdc_clean():
    # Clean/standardize CDC events before Auto CDC; op drives delete handling.
    return (
        spark.readStream.table(f"{CATALOG}.bronze.policy")
        .select(
            F.upper(F.trim(F.col("policy_id"))).alias("policy_id"),
            F.upper(F.trim(F.col("member_id"))).alias("member_id"),
            F.upper(F.trim(F.col("plan_code"))).alias("plan_code"),
            F.expr("try_cast(nullif(trim(effective_from), '') AS DATE)").alias("effective_from"),
            F.expr("try_cast(nullif(trim(op_ts), '') AS TIMESTAMP)").alias("op_ts"),
            F.col("op"),
        )
        .filter(F.col("policy_id").isNotNull() & (F.trim(F.col("policy_id")) != ""))
    )


dp.create_streaming_table(
    name=f"{CATALOG}.silver.dim_policy_scd2",
    comment="Policy dimension with full change history (SCD Type 2); __END_AT empty = current",
)


dp.create_auto_cdc_flow(
    target=f"{CATALOG}.silver.dim_policy_scd2",
    source="policy_cdc_clean",
    keys=["policy_id"],
    sequence_by="op_ts",
    apply_as_deletes=F.expr("op = 'DELETE'"),
    stored_as_scd_type=2,
)


# ------------------------------------------------------------------
# Claims layer: rule-based validation (Q-A..Q-E), clean + quarantine
# ------------------------------------------------------------------
@dp.temporary_view()
def claims_std():
    # Standardized claim facts: ids upper-trimmed, dates/timestamps typed.
    # ALL versions flow through; claims_scd1 keeps only the latest per claim_id.
    return (
        spark.readStream.table(f"{CATALOG}.bronze.claims")
        .select(
            F.upper(F.trim(F.col("claim_id"))).alias("claim_id"),
            F.upper(F.trim(F.col("member_id"))).alias("member_id"),
            F.upper(F.trim(F.col("policy_id"))).alias("policy_id"),
            F.upper(F.trim(F.col("hospital_id"))).alias("hospital_id"),
            F.expr("try_cast(nullif(trim(admission_date), '') AS DATE)").alias("admission_date"),
            F.expr("try_cast(nullif(trim(discharge_date), '') AS DATE)").alias("discharge_date"),
            F.expr("try_cast(nullif(trim(submitted_ts), '') AS TIMESTAMP)").alias("submitted_ts"),
            F.expr("try_cast(nullif(trim(settled_ts), '') AS TIMESTAMP)").alias("settled_ts"),
            F.lower(F.trim(F.col("status"))).alias("status"),
            F.lower(F.trim(F.col("claim_type"))).alias("claim_type"),
            F.lower(F.trim(F.col("channel"))).alias("channel"),
            F.trim(F.col("diagnosis_code")).alias("diagnosis_code"),
            F.trim(F.col("procedure_code")).alias("procedure_code"),
            F.trim(F.col("pre_auth_id")).alias("pre_auth_id"),
            F.expr("nullif(trim(rejection_code), '')").alias("rejection_code"),
            F.col("billed_amount"),
            F.col("approved_amount"),
            F.col("room_days"),
            F.col("room_rent_per_day"),
            F.col("is_pre_existing"),
            F.col("_rescued_data"),
            F.col("file_name"),
            F.col("ingestion_ts"),
        )
        .filter(F.col("claim_id").isNotNull() & (F.trim(F.col("claim_id")) != ""))
    )


dp.create_streaming_table(
    name=f"{CATALOG}.silver.claims_scd1",
    comment="Latest version per claim (SCD Type 1); resubmissions overwrite earlier drafts",
)


dp.create_auto_cdc_flow(
    target=f"{CATALOG}.silver.claims_scd1",
    source="claims_std",
    keys=["claim_id"],
    sequence_by=F.struct("submitted_ts", "ingestion_ts"),
    stored_as_scd_type=1,
)


@dp.materialized_view(
    name=f"{CATALOG}.silver.claims_flagged",
    comment="All claims (latest version) with per-rule Q-A..Q-E flags",
)
@dp.expect("Q-A referential integrity", "passes_q_a")
@dp.expect("Q-B date ordering", "passes_q_b")
@dp.expect("Q-C amount sanity", "passes_q_c")
@dp.expect("Q-D status consistency", "passes_q_d")
@dp.expect("Q-E room math", "passes_q_e")
def claims_flagged():
    # Materialized view over the latest claim versions (SCD1): adds one
    # warn-only pass flag per rule plus a failed_rules array. Recomputed
    # every run, so a corrected claim is re-judged on its latest version.
    # The warn-level Q-E expectation surfaces room-math violations in the
    # pipeline's data-quality metrics without dropping any rows.
    claims = spark.read.table(f"{CATALOG}.silver.claims_scd1")
    members = spark.read.table(f"{CATALOG}.silver.members").select(
        "member_id", F.lit(True).alias("member_found")
    )
    hospitals = spark.read.table(f"{CATALOG}.silver.hospitals").select(
        "hospital_id", F.lit(True).alias("hospital_found")
    )
    policy_members = (
        spark.read.table(f"{CATALOG}.silver.dim_policy_scd2")
        .groupBy("policy_id")
        .agg(F.collect_set("member_id").alias("policy_member_ids"))
    )

    joined = (
        claims
        .join(members, "member_id", "left")
        .join(hospitals, "hospital_id", "left")
        .join(policy_members, "policy_id", "left")
    )

    # Q-A referential integrity: member, hospital and policy exist, and the
    # claim's member belongs to the referenced policy.
    member_ok = F.coalesce(F.col("member_found"), F.lit(False))
    hospital_ok = F.coalesce(F.col("hospital_found"), F.lit(False))
    policy_ok = F.col("policy_member_ids").isNotNull() & F.coalesce(
        F.array_contains("policy_member_ids", F.col("member_id")), F.lit(False)
    )
    passes_q_a = member_ok & hospital_ok & policy_ok

    # Q-B date ordering: admission/discharge/submitted are mandatory (missing
    # fails, consistent with Q-C/Q-E); admission <= discharge; settled >=
    # submitted when settled_ts is present (state-dependent).
    passes_q_b = (
        F.col("admission_date").isNotNull()
        & F.col("discharge_date").isNotNull()
        & F.col("submitted_ts").isNotNull()
        & (F.col("admission_date") <= F.col("discharge_date"))
        & (
            F.col("settled_ts").isNull()
            | (F.col("settled_ts") >= F.col("submitted_ts"))
        )
    )

    # Q-C amount sanity: billed is mandatory -> missing billed fails; approved
    # is state-dependent (submitted/rejected claims have none) -> missing
    # approved passes, but a present approved must be >= 0 and <= billed.
    passes_q_c = (
        F.col("billed_amount").isNotNull() & (F.col("billed_amount") > 0)
    ) & (
        F.col("approved_amount").isNull()
        | (
            (F.col("approved_amount") >= 0)
            & (F.col("approved_amount") <= F.col("billed_amount"))
        )
    )

    # Q-D status consistency: rejected -> rejection code and no approval;
    # settled -> settled ts and approved amount; open statuses -> neither.
    status_c = F.coalesce(F.col("status"), F.lit(""))

    passes_q_d = (
    F.when(
        status_c == "rejected",
        F.col("rejection_code").isNotNull()
        & F.col("approved_amount").isNull()
    )
    .when(
        status_c == "settled",
        F.col("settled_ts").isNotNull()
        & F.col("approved_amount").isNotNull()
    )
    .when(
        status_c == "approved",
        F.col("approved_amount").isNotNull()
        & F.col("settled_ts").isNull()
        & F.col("rejection_code").isNull()
    )
    .when(
        status_c == "submitted",
        F.col("approved_amount").isNull()
        & F.col("settled_ts").isNull()
        & F.col("rejection_code").isNull()
    )
    .otherwise(False)
)

    # Q-E room math, scenario by scenario:
    #   1. mandatory fields missing (room rent, room days, billed, admission)
    #      -> fail;
    #   2. discharge IS NULL (patient still admitted, stay in progress) ->
    #      stay length cannot be verified yet, so the stay check is skipped
    #      and only billed-days >= 1 + money math apply;
    #   3. discharge present: must be >= admission (reversed dates fail,
    #      also caught by Q-B), and billed days must match the actual stay:
    #      room_days == datediff(discharge, admission), except a same-day
    #      stay (datediff = 0) counts as 1 billed day - 288 legit same-day
    #      claims in the source use that convention, so bare datediff
    #      equality would falsely quarantine them;
    #   4. always: room rent component cannot exceed the billed amount.
    passes_q_e = (
        F.col("room_rent_per_day").isNotNull()
        & F.col("room_days").isNotNull()
        & F.col("billed_amount").isNotNull()
        & F.col("admission_date").isNotNull()
        & (F.col("room_days") >= 1)
        & (F.col("room_rent_per_day") * F.col("room_days") <= F.col("billed_amount"))
        & (
            F.col("discharge_date").isNull()
            | (
                (F.col("discharge_date") >= F.col("admission_date"))
                & (
                    (F.col("room_days") == F.datediff("discharge_date", "admission_date"))
                    | (
                        (F.col("room_days") == 1)
                        & (F.datediff("discharge_date", "admission_date") == 0)
                    )
                )
            )
        )
    )

    failed_rules = F.array_compact(
        F.array(
            F.when(~passes_q_a, F.lit("Q-A")),
            F.when(~passes_q_b, F.lit("Q-B")),
            F.when(~passes_q_c, F.lit("Q-C")),
            F.when(~passes_q_d, F.lit("Q-D")),
            F.when(~passes_q_e, F.lit("Q-E")),
        )
    )

    return joined.select(
        "*",
        passes_q_a.alias("passes_q_a"),
        passes_q_b.alias("passes_q_b"),
        passes_q_c.alias("passes_q_c"),
        passes_q_d.alias("passes_q_d"),
        passes_q_e.alias("passes_q_e"),
        failed_rules.alias("failed_rules"),
    ).drop("member_found", "hospital_found", "policy_member_ids")


@dp.materialized_view(
    name=f"{CATALOG}.silver.claims_clean",
    comment="Clean claims passing all Q-A..Q-E rules, one row per claim (latest judgment)",
)
def claims_clean():
    # Materialized view (not append-only ST): each refresh re-judges every
    # claim on its latest version, so a corrected claim leaves quarantine and
    # appears here exactly once.
    return (
        spark.read.table(f"{CATALOG}.silver.claims_flagged")
        .filter(F.size("failed_rules") == 0)
        .drop("failed_rules")
    )


@dp.materialized_view(
    name=f"{CATALOG}.silver.claims_quarantine",
    comment="Quarantined claims with failed_rules (any of Q-A..Q-E); current judgment only",
)
def claims_quarantine():
    # Materialized view (not append-only ST): holds only claims failing on
    # their LATEST version; corrected claims drop out on the next refresh.
    return (
        spark.read.table(f"{CATALOG}.silver.claims_flagged")
        .filter(F.size("failed_rules") > 0)
        .withColumn("quarantine_ts", F.current_timestamp())
    )




    







