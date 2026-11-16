-- R8 - LLM claims adjudication via the Databricks SQL ai_query() function.
-- Endpoint = Paper 4 CHAT_MODEL (databricks-meta-llama-3-3-70b-instruct), temperature = 0.0 for determinism.
-- responseFormat (json_object) enforces JSON output; from_json(REGEXP_EXTRACT(...)) lands the
-- reply in typed columns. Generated and executed by GenAi-1/R8; this file is the code-needle artifact.
CREATE OR REPLACE TABLE claims.genai.adjudications AS
WITH facts AS (
  SELECT
    p.claim_id,
    c.plan_family,
    c.plan_code_at_admission,
    c.is_pre_existing,
    c.policy_tenure_months,
    DATEDIFF(c.admission_date, c.policy_start_date) AS days_since_policy_start,
    c.is_network_at_admission,
    c.room_rent_per_day,
    c.room_rent_cap_per_day
  FROM claims.genai.adjudication_probes AS p
  INNER JOIN claims.gold.claims_enriched AS c
    ON p.claim_id = c.claim_id
),
prompts AS (
  SELECT
    f.*,
    CONCAT(
      'You are a Saffron Shield claims adjudicator. Apply ONLY the rules below to the claim facts and decide the claim. RULE 1 - waiting periods. Individual plans (SILVER_IND and GOLD_IND) have a 30 day initial waiting period and a 36 month pre-existing disease waiting period. The SENIOR plan has a 30 day initial waiting period, a 24 month pre-existing disease waiting period and a 10 percent plan copay. CORP_GROUP has no initial waiting period (0 days) and a 12 month pre-existing disease waiting period. Months are completed months of policy tenure at admission. If the admission date is within the initial waiting period the claim is not payable and the reason is INITIAL_WAITING. Otherwise, if the claim is for a pre-existing disease and the policy tenure is below the PED waiting period, the claim is not payable and the reason is PED_WAITING. Compare the policy tenure months directly with the PED waiting months; for CORP_GROUP a pre-existing disease claim with tenure below 12 months is not payable with reason PED_WAITING, even if the tenure is more than half of the waiting period. RULE 2 - network. A claim at a non-network hospital is still payable but carries a 20 percent copayment added to the plan copay. The Senior plan copay is 10 percent; all other plans have a 0 percent plan copay. RULE 3 - room rent cap. The room rent deduction depends ONLY on room rent per day versus the plan cap. When room rent per day is above the plan cap, the whole bill is reduced by (1 minus cap divided by room rent per day) times 100, rounded to 2 decimals, and the reason becomes PAYABLE_WITH_DEDUCTION. When room rent is at or below the cap, the deduction is exactly 0 and the deduction reason must not be used. A non-network hospital never creates a deduction; it only adds 20 percent to copay_pct. room_rent_deduction_pct is a PERCENTAGE between 0 and 100: a 25 percent deduction is written 25.00, never 0.25. Example: room rent per day 4000 with a cap of 3000 gives room_rent_deduction_pct 25.00; room rent 6500 with a cap of 6000 gives 7.69. ALWAYS compute room_rent_deduction_pct from the room rent rule, even when the claim is NOT payable: a claim refused for a waiting period still reports the deduction its room rent would cause (example: a not-payable claim with room rent 4000 and cap 3000 reports room_rent_deduction_pct 25.00 and reason PED_WAITING or INITIAL_WAITING). RULE 4 - reason codes. A claim that fails a waiting period is not payable, with reason INITIAL_WAITING or PED_WAITING as set by rule 1. A payable claim with a room rent deduction above zero has reason PAYABLE_WITH_DEDUCTION. A payable claim with zero deduction has reason PAYABLE_IN_FULL, even when the hospital is non-network. Use these reason codes only: INITIAL_WAITING, PED_WAITING, PAYABLE_WITH_DEDUCTION, PAYABLE_IN_FULL. A claim that fails a waiting period MUST have payable=false and waiting_period_ok=false. Reply with ONLY a JSON object, no markdown and no extra text, with exactly these keys IN THIS ORDER: reasoning FIRST (work out the decision step by step here: check the initial waiting period, then the PED waiting period, then the network copay, then the room rent cap and its deduction in every case), THEN payable (boolean), waiting_period_ok (boolean), network_at_admission (boolean), room_rent_deduction_pct (number with 2 decimals), copay_pct (integer), reason_code (one of the four codes above). The decision fields MUST agree with your own reasoning. ',
      'CLAIM FACTS: claim_id=',
      f.claim_id,
      '; plan=',
      f.plan_code_at_admission,
      '; plan_family=',
      f.plan_family,
      '; is_pre_existing=',
      CAST(f.is_pre_existing AS STRING),
      '; policy_tenure_months=',
      CAST(f.policy_tenure_months AS STRING),
      '; days_since_policy_start=',
      CAST(f.days_since_policy_start AS STRING),
      '; is_network_at_admission=',
      CAST(f.is_network_at_admission AS STRING),
      '; room_rent_per_day=',
      CAST(f.room_rent_per_day AS STRING),
      '; room_rent_cap_per_day=',
      CAST(f.room_rent_cap_per_day AS STRING)
    ) AS prompt
  FROM facts AS f
),
replies AS (
  SELECT
    pr.*,
    AI_QUERY(
      'databricks-meta-llama-3-3-70b-instruct',
      pr.prompt,
      modelParameters => named_struct('temperature', 0.0),
      responseFormat => '{"type": "json_object"}',
      failOnError => true
    ) AS reply
  FROM prompts AS pr
)
SELECT
  claim_id,
  CAST(j.payable AS BOOLEAN) AS payable,
  CAST(j.waiting_period_ok AS BOOLEAN) AS waiting_period_ok,
  CAST(j.network_at_admission AS BOOLEAN) AS network_at_admission,
  ROUND(CAST(j.room_rent_deduction_pct AS DOUBLE), 2) AS room_rent_deduction_pct,
  CAST(j.copay_pct AS INT) AS copay_pct,
  UPPER(TRIM(CAST(j.reason_code AS STRING))) AS reason_code,
  CAST(j.reasoning AS STRING) AS reasoning
FROM (
  SELECT
    claim_id,
    FROM_JSON(REGEXP_EXTRACT(reply, '(?s)[{].*[}]', 0), 'payable BOOLEAN, waiting_period_ok BOOLEAN, network_at_admission BOOLEAN, room_rent_deduction_pct DOUBLE, copay_pct INT, reason_code STRING, reasoning STRING') AS j
  FROM replies
)
