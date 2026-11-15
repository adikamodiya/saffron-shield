%md
# R6 Genie prompting note - Saffron Shield Claims Analytics

Space: 01f1df20e1131371bdf0a038bc2c33a2
Benchmark runs: 01f1df2252931a719bb9738b657c6097 (pre-fix baseline),
01f1df242e671f838c5dab2d0c0cb2ab (final)
Result: 10/10 correct in both runs (agent mode, score 100 each) - bar was >= 8/10.

All fixes below were applied while configuring the space; each names the
benchmark ID(s) it was designed to satisfy. The first full run passed all 10,
so no post-failure fixes were needed; Fix 5 was a preventive hardening.

## Fix 1 - Rejection rate over decided claims (text instruction + trusted example)
Added the rule: rejection_rate = rejected / decided, decided = approved +
settled + rejected; 'submitted' excluded from BOTH sides (397/2,699 = 0.147),
plus a trusted example query showing the exact CASE WHEN pattern.
Addressed: B07 (overall rejection rate), B06 (metro vs non-metro rejection rates).

## Fix 2 - Loss ratio must use w01, not claim grain (new table + instruction)
Materialized the R3 w01 query as claims.analytics.w01 (48 rows, 4 plans x 12
months) and instructed: paid = approved_amount of SETTLED claims by ADMISSION
month; earned = annual_premium/12 per active policy version; loss_ratio =
paid/earned. Prevents Genie from recomputing loss ratio from fact_claims.
Addressed: B10 (GOLD_IND monthly loss ratio), B09 (plan with highest overall LR).

## Fix 3 - Turnaround only for decided claims (instruction + trusted example)
Documented that turnaround_days is NULL for submitted rows and gave a trusted
example filtering WHERE turnaround_days IS NOT NULL (avg = 15.69).
Addressed: B04 (average claim turnaround time).

## Fix 4 - KPI SSOT = mv_claims metric view (added as data source + instruction)
Attached claims.analytics.mv_claims and instructed Genie to prefer it for claim
KPIs grouped by plan/city tier/hospital/claim type/status/rejection code/month -
the KPI definitions live in exactly one place (R4).
Addressed: B01 (total approved 177,758,760.28), B05 (top-5 hospitals by rejected),
B03 (rejection counts by code), B08 (total claim count = 3,046), B02 (monthly
claim volume by admission month).

## Fix 5 - Check the metric view before computing any formula (instruction only)
Strengthened the instruction: "If you need ANY KPI formula, check
claims.analytics.mv_claims FIRST and query it with MEASURE(...) instead of
computing the formula yourself; fall back to fact_claims only if the metric
view cannot answer the grouping." Re-run after fix: 10/10 correct.
Addressed: B01, B06, B07 (all KPI-formula benchmarks).

## Benchmark ID map
B01 01f1df224dc4...e671 total approved | B02 01f1df224d861...457b monthly volume |
B03 01f1df224d481...3b96 rejected by code | B04 01f1df224d101...8af7d avg turnaround |
B05 01f1df224cd71...c81ae top-5 hospitals | B06 01f1df224c9c1...24309 metro vs non-metro |
B07 01f1df224c5b1...96d6d overall rejection rate | B08 01f1df224c221...4def total claims |
B09 01f1df224be71...b587 highest-loss-ratio plan | B10 01f1df224ba01...362e8 GOLD_IND LR